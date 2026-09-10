import Foundation
import Observation

/// Observable application state. Every mutation goes through this type so the
/// encrypted store sees exactly one writer.
@MainActor @Observable
final class CrewStore {
    private var secureStore: SecureStore?
    var data = AppData()
    var selectedTripID: UUID?
    var selectedDocumentID: UUID?
    var errorMessage: String?
    /// The long-running operation in flight, if any, described well enough to
    /// draw a determinate bar where the work can actually be measured.
    var activity: Activity?

    /// Kept so existing callers keep compiling while the UI adopts `activity`.
    var busyMessage: String? {
        get {
            guard let activity else { return nil }
            guard let detail = activity.detail else { return activity.title }
            return "\(activity.title) — \(detail)"
        }
        set { activity = newValue.map { .indeterminate($0) } }
    }

    /// The task behind a cancellable activity, so the operator can stop it.
    private var cancellableWork: Task<Void, Never>?

    func cancelActivity() {
        cancellableWork?.cancel()
        cancellableWork = nil
        activity = nil
    }
    /// Set when the encrypted store could not be opened. The UI shows this
    /// instead of the app dying: a failed Keychain or disk is recoverable.
    private(set) var storageFailure: String?

    /// Serialises persistence so a stale snapshot can never overwrite a newer
    /// one. Unstructured `Task {}` per save gave no ordering guarantee.
    private var persistChain: Task<Void, Never> = Task {}

    /// Opens the operator's encrypted store on this Mac. The app's entry point,
    /// and the ONLY initialiser that touches their real data.
    init() {
        // Deliberately does no work. Opening the store touches the Keychain,
        // and macOS may put an authorisation prompt in front of that — which it
        // does on every rebuild, because an ad-hoc signature changes the code
        // identity the key's ACL was granted to.
        //
        // This used to happen here, inside `App.init()`, before any window
        // existed. The result was an app that was a Dock icon with nothing
        // behind it, no error and nothing in the logs, for as long as the
        // prompt went unanswered — indistinguishable from a hang, and it cost
        // three debugging sessions before anyone sampled the process and found
        // it parked in SecKeychainItemCopyContent.
        Task { await openStore() }
    }

    /// True while the encrypted store is being opened, so the window can say so
    /// rather than showing an empty workspace that looks like lost data.
    private(set) var isOpening = true

    private func openStore() async {
        // Off the main actor: both the Keychain call and the SQLCipher open are
        // blocking, and the window has to be able to draw while they run.
        let opened = await Task.detached(priority: .userInitiated) { () -> Result<SecureStore, any Error> in
            do { return .success(try SecureStore()) } catch { return .failure(error) }
        }.value

        switch opened {
        case .success(let store):
            secureStore = store
            await load()
        case .failure(let error):
            // A locked Keychain or a full disk is a condition to explain, not a
            // crash and not an empty window. RootView shows StorageFailureView.
            storageFailure = error.localizedDescription
        }
        isOpening = false
    }

    /// A store backed by an explicitly supplied database, or by nothing at all.
    ///
    /// `CrewStore(secureStore: nil)` never touches disk: `persist()` has nowhere to
    /// write and returns immediately. This exists because the previous shape —
    /// `init(secureStore: SecureStore? = nil)` — read as "no store" but silently
    /// constructed a live `SecureStore` against the operator's real database, so
    /// a test that set `data` and called any mutating method overwrote their
    /// trips. Tests wanting persistence must pass a `SecureStore(fileManager:)`
    /// pointed at a temporary directory.
    init(secureStore: SecureStore?) {
        self.secureStore = secureStore
        guard secureStore != nil else { isOpening = false; return }
        Task { await load() }
    }

    /// False until `load()` has read the store off disk.
    ///
    /// `data` starts empty and is filled asynchronously, so between `init` and
    /// the end of `load()` the in-memory state is an empty `AppData` that does
    /// not describe anything. A `persist()` in that window writes that emptiness
    /// over the real database — every trip, every person, every confirmation —
    /// and the encrypted document files are left orphaned on disk with nothing
    /// pointing at them. `persist()` refuses to run until this is true.
    private(set) var hasLoaded = false

    func load() async {
        guard let secureStore else { isOpening = false; return }
        // Cleared here rather than only in `openStore`, so an injected store
        // reaches the same state — otherwise the window sits on the opening
        // screen forever for anything that did not come through `init()`.
        defer { isOpening = false }
        do {
            data = try await secureStore.load()
            #if DEBUG
            // Only ever onto an empty store, and only when asked. See DebugSeed.
            if let seeded = DebugSeed.seeded(onto: data) { data = seeded }
            #endif
            hasLoaded = true
            applyStorageSettings()
            reportDecodingLosses()
            // Open on the work in hand rather than on two empty columns: the
            // first trip, and within it the first document still needing review.
            // An archived trip is not work in hand, so it is never what the app
            // opens on — reaching one is always a deliberate act.
            selectedTripID = selectedTripID ?? activeTrips.first?.id
            let documents = selectedTripDocuments
            selectedDocumentID = selectedDocumentID
                ?? documents.first { !$0.canExport() }?.id
                ?? documents.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Tells the operator when a read salvaged what it could.
    ///
    /// `AppData` now decodes record by record, so one malformed row costs one
    /// row instead of the whole database. That is the right trade only if the
    /// dropped row is announced: a document that fails to decode is a passport
    /// scan that has quietly left a trip, and an operator who is not told will
    /// discover it when a port authority counts heads.
    func reportDecodingLosses() {
        guard !data.decodingLosses.isEmpty else { return }
        errorMessage = ([
            "Some stored records could not be read and were left out.",
        ] + data.decodingLosses + [
            "The rest of your data opened normally. An earlier version may be available under Earlier versions.",
        ]).joined(separator: "\n")
    }

    // MARK: - Settings

    /// The operator's defaults. Read freely; write through `updateSettings`,
    /// which is where they are brought back into range.
    var settings: AppSettings { data.settings }

    /// Takes a whole new value rather than mutating in place, so a caller
    /// always builds the settings it wants and this stays the single point
    /// where they are checked.
    func updateSettings(_ settings: AppSettings) {
        let normalised = settings.normalised()
        guard normalised != data.settings else { return }
        data.settings = normalised
        applyStorageSettings()
        persist()
    }

    /// Pushes the settings the encrypted store itself obeys down to it.
    private func applyStorageSettings() {
        guard let secureStore else { return }
        let depth = data.settings.versionsKept
        Task { await secureStore.setBackupDepth(depth) }
    }

    // MARK: - Trips and boats

    /// The trips the picker offers: everything not put away.
    var activeTrips: [Trip] { data.trips.filter { !$0.isArchived } }

    /// Every charter gathered into the day it sails on, earliest first.
    ///
    /// Archived trips included: they keep their place in the strip, or their
    /// documents could be neither restored nor erased. `TripDay.isArchived`
    /// is how a day of nothing but put-away charters says so.
    var tripDays: [TripDay] { TripCalendar.days(of: data.trips) }

    /// Finished charters, kept for the record. Listed separately rather than
    /// hidden outright — a trip nothing can reach is a trip whose documents can
    /// never be restored or erased.
    var archivedTrips: [Trip] { data.trips.filter(\.isArchived) }

    /// Charters a yacht.
    ///
    /// The yacht is the one named, or the fleet's default, or the only one in
    /// the fleet — and if the operator has not built a fleet yet, a fresh
    /// placeholder, so a first run still produces a working trip.
    @discardableResult
    func createTrip(boatID: UUID? = nil) -> UUID {
        // Validated rather than trusted: a caller holding an id for a yacht
        // that has since been deleted would otherwise make a charter pointing
        // at nothing, which no screen can show and no export can name.
        let named: UUID? = boatID.flatMap { id in data.boats.contains { $0.id == id } ? id : nil }
        let chartered = named ?? chosenBoatForNewTrip()
        // Saturday to Saturday unless this fleet says otherwise. Any other pair
        // of dates is one the operator picked on purpose.
        let week = VoyageDate.charterWeek(startingOn: settings.charterStartWeekday,
                                          lastingDays: settings.charterLengthDays)
        let trip = Trip(boatID: chartered, departureDate: week.departure, returnDate: week.arrival)
        data.trips.append(trip)
        selectedTripID = trip.id
        selectedDocumentID = nil
        persist()
        return trip.id
    }

    /// Which yacht an unnamed new trip is for.
    ///
    /// The one most recently chartered, then the first in the fleet — and a
    /// placeholder ONLY when the fleet is empty. That last rule is the
    /// important one: minting a "NEW YACHT" while three real ones sit in the
    /// fleet gave the operator a charter for a vessel they do not own and a
    /// fourth row in their fleet list, once per ⌘N, and nothing could remove it
    /// while the trip existed.
    ///
    /// There is deliberately no default yacht to consult first. It was a
    /// setting, a checkbox in the Fleet, a context-menu item and a badge, all
    /// to answer a question the last charter already answers better.
    ///
    /// Appends to the fleet as a side effect in that last case, which is why
    /// this is not a computed property.
    private func chosenBoatForNewTrip() -> UUID {
        // The yacht this operator was last working with is a far better guess
        // than the alphabetically first one.
        if let recent = data.trips.last?.boatID, let boat = boat(withID: recent), !boat.isRetired {
            return recent
        }
        if let first = fleet.first { return first.id }
        let placeholder = Boat(name: Boat.placeholderName)
        data.boats.append(placeholder)
        return placeholder.id
    }

    func updateTrip(_ trip: Trip) {
        guard let index = data.trips.firstIndex(where: { $0.id == trip.id }) else { return }
        var updated = trip
        // Stripped to the start of the day in the operator's own calendar. A
        // voyage date is a day, not an instant, and one stored at 14:37 crosses
        // a day boundary as soon as anything reads it from another time zone.
        updated.departureDate = VoyageDate.day(updated.departureDate)
        updated.returnDate = VoyageDate.day(updated.returnDate)
        // A return before departure is always a typo; clamp rather than export it.
        if updated.returnDate < updated.departureDate { updated.returnDate = updated.departureDate }
        data.trips[index] = updated
        persist()
    }

    /// Moves the departure, and the return with it.
    ///
    /// The charter keeps its length: an operator shifting a week-long trip by a
    /// fortnight means a week starting a fortnight later, not a three-week
    /// voyage. Picking the return afterwards overrides that, which is what
    /// `setReturnDate` is for.
    func setDepartureDate(_ date: Date, onTripWith id: UUID) {
        guard let trip = data.trips.first(where: { $0.id == id }) else { return }
        let departure = VoyageDate.day(date)
        let length = Calendar.current.dateComponents([.day], from: VoyageDate.day(trip.departureDate),
                                                     to: VoyageDate.day(trip.returnDate)).day ?? 0
        var updated = trip
        updated.departureDate = departure
        updated.returnDate = Calendar.current.date(byAdding: .day, value: length, to: departure) ?? departure
        updateTrip(updated)
    }

    func setReturnDate(_ date: Date, onTripWith id: UUID) {
        guard var trip = data.trips.first(where: { $0.id == id }) else { return }
        trip.returnDate = VoyageDate.day(date)
        updateTrip(trip)
    }

    /// Puts a finished charter away. Destroys nothing.
    ///
    /// The trip, its documents, its people and the encrypted originals all stay
    /// exactly where they are; only the picker stops offering it. This is the
    /// non-destructive half of the pair — `deleteTrip` is the other half, and
    /// the two must never be confused at the call site.
    func archiveTrip(_ id: UUID) {
        setStatus(.archived, onTripWith: id)
    }

    /// Brings an archived charter back into the working list.
    func restoreTrip(_ id: UUID) {
        setStatus(.draft, onTripWith: id)
    }

    private func setStatus(_ status: TripStatus, onTripWith id: UUID) {
        guard let index = data.trips.firstIndex(where: { $0.id == id }),
              data.trips[index].status != status else { return }
        data.trips[index].status = status
        // Only when the operator archived the trip they were looking at: the
        // review pane must never sit on a trip the picker no longer offers,
        // and the stale document behind it must go with it.
        if status == .archived, selectedTripID == id {
            selectedTripID = activeTrips.first?.id
            selectedDocumentID = nil
        }
        persist()
    }

    /// Removes a trip with its documents, assignments, people and the encrypted
    /// originals on disk. Nothing else in the app can delete stored identity
    /// documents, which an operator holding passport scans has to be able to do.
    ///
    /// Reachable for an archived trip too, deliberately: archiving must not be
    /// a one-way door that strands passport scans out of the operator's reach.
    func deleteTrip(_ id: UUID) {
        let documents = data.documents.filter { $0.tripID == id }
        for document in documents { discardFiles(of: document) }
        let personIDs = Set(documents.map(\.personID))

        data.documents.removeAll { $0.tripID == id }
        data.assignments.removeAll { $0.tripID == id }
        data.people.removeAll { personIDs.contains($0.id) }
        data.trips.removeAll { $0.id == id }
        // The yacht stays. It used to be deleted along with its last trip,
        // which was right when a yacht existed only for one charter and is
        // wrong now that the fleet is a list the operator keeps: erasing a
        // vessel because this season's booking was cancelled is not something
        // deleting a trip should do. `deleteBoat` is how a yacht leaves.
        if selectedTripID == id {
            selectedTripID = activeTrips.first?.id
            selectedDocumentID = nil
        }
        persist()
    }

    // MARK: - Documents

    func importDocuments(_ sources: [URL]) async {
        guard let tripID = selectedTripID else {
            errorMessage = "Create or select a trip before importing a document."
            return
        }
        guard let secureStore else { return }
        defer { activity = nil }

        for (index, source) in sources.enumerated() {
            activity = .step("Reading documents", completed: index, total: sources.count,
                             detail: source.lastPathComponent)
            do {
                // Vision is synchronous and slow enough to freeze the window;
                // run it off the main actor.
                let result = try await Task.detached(priority: .userInitiated) {
                    try OCRService.extract(from: source)
                }.value

                var person = CrewPerson(fullName: result.fields[CrewField.fullName.rawValue] ?? "",
                                        nationality: result.fields[CrewField.nationality.rawValue] ?? "")
                person.birthDate = (result.fields[CrewField.birthDate.rawValue]).flatMap(CrewFieldValidator.isoDate)

                var document = CrewDocument(
                    tripID: tripID,
                    personID: person.id,
                    originalName: source.lastPathComponent,
                    encryptedFileName: "",
                    documentNumber: result.fields[CrewField.documentNumber.rawValue] ?? "",
                    documentType: result.fields[CrewField.documentType.rawValue] ?? "unknown",
                    risk: result.risk,
                    riskReasons: result.reasons,
                    fields: result.fields
                )
                document.encryptedFileName = try await secureStore.importOriginal(from: source, documentID: document.id)

                data.people.append(person)
                data.documents.append(document)
                data.assignments.append(CrewAssignment(tripID: tripID, personID: person.id, role: data.assignments.contains { $0.tripID == tripID && $0.role == .skipper } ? .passenger : .skipper))
                selectedDocumentID = document.id
            } catch {
                errorMessage = "Could not import \(source.lastPathComponent): \(error.localizedDescription)"
            }
        }
        persist()
    }

    func updateDocument(_ document: CrewDocument) {
        guard let index = data.documents.firstIndex(where: { $0.id == document.id }) else { return }
        data.documents[index] = document
        syncPerson(from: document)
        persist()
    }

    func deleteDocument(_ documentID: UUID) {
        guard let index = data.documents.firstIndex(where: { $0.id == documentID }) else { return }
        let document = data.documents[index]
        discardFiles(of: document)
        data.documents.remove(at: index)
        if !data.documents.contains(where: { $0.personID == document.personID }) {
            data.people.removeAll { $0.id == document.personID }
            data.assignments.removeAll { $0.personID == document.personID && $0.tripID == document.tripID }
        }
        if selectedDocumentID == documentID { selectedDocumentID = selectedTripDocuments.first?.id }
        persist()
    }

    // MARK: - Original image

    func originalImageData(for document: CrewDocument) async -> Data? {
        guard let secureStore, !document.encryptedFileName.isEmpty else { return nil }
        return try? await secureStore.readOriginal(named: document.encryptedFileName)
    }

    func editSelectedDocument(_ transform: @escaping @Sendable (Data) throws -> Data) {
        guard let id = selectedDocumentID, let document = data.documents.first(where: { $0.id == id }), let secureStore else { return }
        activity = .indeterminate("Applying image edit")
        Task {
            defer { activity = nil }
            do {
                let original = try await secureStore.readOriginal(named: document.encryptedFileName)
                // Image work is CPU-bound; keep it off the main actor.
                let edited = try await Task.detached(priority: .userInitiated) { try transform(original) }.value
                let revision = try await secureStore.replaceOriginal(named: document.encryptedFileName, with: edited)
                guard let index = data.documents.firstIndex(where: { $0.id == id }) else { return }
                data.documents[index].imageRevisions.append(revision)
                data.documents[index].verifiedFields = []
                data.documents[index].risk = .review
                data.documents[index].riskReasons = ["Image changed; review the extraction again before export."]
                persist()
            } catch { errorMessage = "Image edit failed: \(error.localizedDescription)" }
        }
    }

    /// Re-runs extraction on the currently stored image, keeping any value the
    /// operator has already verified.
    func reanalyseSelectedDocument() {
        guard let id = selectedDocumentID, let document = data.documents.first(where: { $0.id == id }), let secureStore else { return }
        activity = .indeterminate("Re-reading document", detail: document.originalName)
        Task {
            defer { activity = nil }
            do {
                let original = try await secureStore.readOriginal(named: document.encryptedFileName)
                let result = try await Task.detached(priority: .userInitiated) { try OCRService.extract(from: original) }.value
                guard let index = data.documents.firstIndex(where: { $0.id == id }) else { return }
                for (key, value) in result.fields where !value.isEmpty {
                    guard !data.documents[index].verifiedFields.contains(key) else { continue }
                    data.documents[index].fields[key] = value
                }
                data.documents[index].riskReasons = result.reasons
                refreshRisk(at: index)
                syncPerson(from: data.documents[index])
                persist()
            } catch { errorMessage = "Re-analysis failed: \(error.localizedDescription)" }
        }
    }

    // MARK: - Snapshots
    //
    // The store keeps the state it replaces on every save. Surfacing that is
    // the difference between a recovery path an operator has and one only
    // someone reading release notes with a terminal open has.

    private(set) var backups: [SecureStore.Backup] = []

    func refreshBackups() async {
        guard let secureStore else { return }
        backups = await secureStore.backups()
    }

    /// A deliberate checkpoint, before something the operator expects to be
    /// risky. Returns whether a new version was written: it is skipped when
    /// nothing has changed since the last one, and a button that silently does
    /// nothing reads as broken to the person who just pressed it.
    @discardableResult
    func takeSnapshot() async -> Bool {
        guard let secureStore else { return false }
        let written = await secureStore.snapshot()
        await refreshBackups()
        return written
    }

    /// Makes a snapshot current and reloads. The state it replaces is itself
    /// snapshotted first, so this is undoable.
    func restoreBackup(_ identifier: String) async {
        guard let secureStore else { return }
        activity = .indeterminate("Restoring an earlier version")
        defer { activity = nil }
        do {
            data = try await secureStore.restore(identifier)
            // The restored payload carries its own settings, and the store
            // obeys one of them. The other two write paths into `data.settings`
            // — `load` and `updateSettings` — both do this; this is the third.
            applyStorageSettings()
            // A snapshot is older than the live store by definition, so it is
            // likelier than anything to hold a record this build salvages.
            reportDecodingLosses()
            selectedTripID = activeTrips.first?.id
            selectedDocumentID = selectedTripDocuments.first?.id
            await refreshBackups()
        } catch {
            errorMessage = Self.explain(error)
        }
    }

    /// What a snapshot would restore, phrased for a list row.
    nonisolated static func describe(_ backup: SecureStore.Backup) -> String {
        let trips = "\(backup.trips) trip\(backup.trips == 1 ? "" : "s")"
        let documents = "\(backup.documents) document\(backup.documents == 1 ? "" : "s")"
        return "\(trips), \(documents)"
    }

    /// Whether the local vision model is on this Mac. Stored here rather than
    /// in the extension that manages it, because an extension cannot hold
    /// state — see `CrewStoreLocalModel.swift` for everything that reads it.
    // MARK: - The optional local model

    /// Whether the local vision model is on this Mac. The rescue action offers
    /// nothing when it is not, and there was no way to install it at all — the
    /// menu item threw "The file doesn't exist." with no route forward.
    private(set) var localModelIsInstalled = false

    func refreshLocalModelState() async {
        guard let manager = try? ModelManager() else { return }
        localModelIsInstalled = await manager.isReady(.qwen3VL8BQ4)
    }

    /// What the local model would cost to install, for the confirmation the UI
    /// must show before starting a multi-gigabyte download.
    var localModelDescription: String {
        "\(ModelManifest.qwen3VL8BQ4.displayName) · \(ModelManifest.qwen3VL8BQ4.approximateSizeDescription)"
    }

    /// Call only after the operator has seen the size and agreed.
    ///
    /// Reports real byte progress and can be stopped: several gigabytes with no
    /// percentage and no way out is worse than no feature.
    func downloadLocalModel() async {
        guard !localModelIsInstalled else { return }
        let work = Task { [weak self] in
            guard let self else { return }
            do {
                let manager = try ModelManager()
                try await manager.download(.qwen3VL8BQ4) { received, expected in
                    Task { @MainActor in
                        self.activity = .bytes("Downloading the local AI model", received: received, expected: expected)
                    }
                }
                let ready = await manager.isReady(.qwen3VL8BQ4)
                await MainActor.run { self.localModelIsInstalled = ready }
            } catch is CancellationError {
                // Stopping is a choice, not a failure.
            } catch {
                await MainActor.run { self.errorMessage = Self.explain(error) }
            }
        }
        cancellableWork = work
        activity = .bytes("Downloading the local AI model", received: 0,
                          expected: ModelManifest.qwen3VL8BQ4.totalBytes)
        await work.value
        cancellableWork = nil
        activity = nil
    }

    /// Removes this app's copy of the local model.
    ///
    /// Only its own copy: `ModelManager.removeDownload` will not touch a model
    /// found in the HuggingFace cache, which belongs to whatever else on this
    /// Mac downloaded it. So this can leave `localModelIsInstalled` true, which
    /// is the honest answer — the model really is still available.
    func removeLocalModel() async {
        guard let manager = try? ModelManager() else { return }
        let removed = await manager.removeDownload(.qwen3VL8BQ4)
        await refreshLocalModelState()
        if !removed || localModelIsInstalled {
            errorMessage = localModelIsInstalled
                ? "This app's copy was removed, but the model is still on this Mac — another program downloaded it into the shared model cache, and erasing that is not this app's to do."
                : "There was no downloaded copy to remove."
        }
    }

    /// Errors reach the operator with their recovery suggestion attached; an
    /// `errorDescription` alone often says what failed but not what to do.
    nonisolated static func explain(_ error: Error) -> String {
        guard let local = error as? LocalizedError, let description = local.errorDescription else {
            return error.localizedDescription
        }
        guard let suggestion = local.recoverySuggestion else { return description }
        return "\(description)\n\n\(suggestion)"
    }

    func rescueSelectedDocumentWithLocalAI() {
        guard let id = selectedDocumentID, let document = data.documents.first(where: { $0.id == id }), let secureStore else { return }
        activity = .indeterminate("Asking the local model", detail: document.originalName)
        let work = Task { [weak self] in
            guard let self else { return }
            defer { activity = nil }
            do {
                let original = try await secureStore.readOriginal(named: document.encryptedFileName)
                let name = document.originalName
                let suggested = try await LlamaVisionRescuer().extract(imageData: original) { phase in
                    Task { @MainActor [weak self] in self?.report(phase, document: name) }
                }
                guard let index = data.documents.firstIndex(where: { $0.id == id }) else { return }
                for (key, value) in suggested where data.documents[index].fields[key, default: ""].isEmpty {
                    data.documents[index].fields[key] = value
                    // Marked, not merged silently. A value with no check digits
                    // behind it must not be indistinguishable from one that has.
                    data.documents[index].markSuggested(rawField: key)
                }
                data.documents[index].riskReasons.append("Local AI suggestions added; all remain unverified.")
                refreshRisk(at: index)
                persist()
            } catch is CancellationError {
                // Backing out of a ten-minute load is a choice, not a failure.
            } catch { errorMessage = Self.explain(error) }
        }
        cancellableWork = work
    }

    /// The first rescue on a machine loads an 8B model, which takes minutes.
    /// Reported as sustained so it lands in the strip with a way out — a
    /// spinner for ten minutes is indistinguishable from a hang, and the
    /// operator deserves to know which one they are looking at.
    private func report(_ phase: LlamaVisionRescuer.Phase, document: String) {
        switch phase {
        case .startingRuntime:
            activity = Activity(title: "Starting the local AI model",
                                detail: "First use since launch",
                                fraction: nil, isCancellable: true, style: .sustained)
        case .loadingModel(let elapsed):
            activity = Activity(title: "Loading the local AI model",
                                detail: "\(Int(elapsed))s · about 8 GB into memory, several minutes on first use",
                                fraction: nil, isCancellable: true, style: .sustained)
        case .reading:
            activity = .indeterminate("Reading the document with the local model", detail: document)
        }
    }

    // MARK: - Derived state

    var selectedTrip: Trip? { data.trips.first { $0.id == selectedTripID } }
    var selectedBoat: Boat? { selectedTrip.flatMap { trip in data.boats.first { $0.id == trip.boatID } } }
    var selectedTripDocuments: [CrewDocument] { data.documents.filter { $0.tripID == selectedTripID } }
    var selectedDocument: CrewDocument? { data.documents.first { $0.id == selectedDocumentID } }

    func boat(for trip: Trip) -> Boat? { data.boats.first { $0.id == trip.boatID } }

    /// Everything standing between the selected trip and a crew list, phrased
    /// for the operator rather than as a boolean.
    var exportBlockers: [String] {
        var blockers: [String] = []
        guard let trip = selectedTrip else { return ["Select a trip."] }
        guard let boat = data.boats.first(where: { $0.id == trip.boatID }) else { return ["This trip has no yacht."] }
        if !boat.isComplete { blockers.append("Name the yacht.") }
        if boat.flag.trimmingCharacters(in: .whitespaces).isEmpty { blockers.append("Set the yacht's flag.") }
        let documents = selectedTripDocuments
        if documents.isEmpty { blockers.append("Import at least one document.") }
        for document in documents {
            let pending = document.blockingFields()
            if document.risk == .high {
                blockers.append("\(document.originalName) is rejected.")
            } else if !pending.isEmpty {
                blockers.append("\(document.originalName): \(pending.map(\.label).joined(separator: ", ")) still unconfirmed.")
            }
        }
        if !documents.isEmpty, !data.assignments.contains(where: { $0.tripID == trip.id && $0.role == .skipper }) {
            blockers.append("Nominate a skipper.")
        }
        return blockers
    }

    var selectedTripCanExport: Bool { exportBlockers.isEmpty }

    func crewRows(forTripID tripID: UUID) -> [CrewListRow] {
        data.documents
            .filter { $0.tripID == tripID }
            .map { document in
                let assigned = data.assignments.first { $0.tripID == tripID && $0.personID == document.personID }
                return CrewListRow(document: document,
                                   role: assigned?.role ?? .passenger,
                                   isClient: assigned?.isClient ?? false)
            }
            .sorted { lhs, rhs in
                if lhs.role != rhs.role { return lhs.role == .skipper }
                return lhs.fullName < rhs.fullName
            }
    }

    /// Writes the crew list, and says what it wrote.
    ///
    /// Which files depends on the settings; `AppSettings.normalised()`
    /// guarantees at least one, so this can never succeed having written
    /// nothing.
    @discardableResult
    func exportSelectedTrip(to directory: URL) throws -> [URL] {
        guard let trip = selectedTrip, let boat = selectedBoat else { throw ExportError.noTripSelected }
        guard selectedTripCanExport else { throw ExportError.blocked(exportBlockers) }
        let rows = crewRows(forTripID: trip.id)
        let base = ExportService.fileNameStem(boat: boat, trip: trip, prefix: settings.fileNamePrefix)
        let email = skipperEmail(forTripID: trip.id)

        var written: [URL] = []
        if settings.writesCSV {
            let url = directory.appending(path: "\(base).csv")
            try ExportService.exportCSV(to: url, trip: trip, boat: boat, rows: rows, skipperEmail: email)
            written.append(url)
        }
        if settings.writesPDF {
            let url = directory.appending(path: "\(base).pdf")
            try ExportService.exportPDF(to: url, trip: trip, boat: boat, rows: rows, skipperEmail: email)
            written.append(url)
        }
        return written
    }

    /// The folder the operator chose to export into, if it is still a folder
    /// they can write to.
    ///
    /// Checked rather than trusted: it is a path typed into a setting weeks
    /// ago, and an unplugged drive or a renamed folder must send the export
    /// back to asking rather than fail at the write.
    var standingExportFolder: URL? {
        let path = settings.exportFolderPath
        guard !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Internals

    /// Keeps the person registry in step with the document that identifies them.
    ///
    /// Internal rather than private only because `CrewStore`'s own extensions
    /// live in other files; nothing outside this type calls it.
    func syncPerson(from document: CrewDocument) {
        guard let index = data.people.firstIndex(where: { $0.id == document.personID }) else { return }
        data.people[index].fullName = document[.fullName]
        data.people[index].nationality = document[.nationality]
        data.people[index].birthDate = CrewFieldValidator.isoDate(document[.birthDate])
        data.people[index].verification = document.canExport() ? .verified : .pending
    }

    /// Internal for the same reason as `syncPerson`.
    func refreshRisk(at index: Int) {
        guard data.documents[index].risk != .high else { return }
        data.documents[index].risk = data.documents[index].canExport() ? .low : .review
        syncPerson(from: data.documents[index])
    }

    private func discardFiles(of document: CrewDocument) {
        guard let secureStore else { return }
        let names = [document.encryptedFileName] + document.imageRevisions
        Task { await secureStore.deleteOriginals(named: names.filter { !$0.isEmpty }) }
    }

    /// Waits for any in-flight save to reach disk. Tests only: the UI never
    /// needs it, because `persistChain` already serialises writes.
    func flushForTesting() async { _ = await persistChain.value }

    /// Internal rather than private only because `CrewStore`'s own extensions
    /// live in other files. Nothing outside this type may call it: every
    /// mutation is expected to persist itself, and a caller reaching for this
    /// is a caller that has changed `data` from outside.
    func persist() {
        guard let secureStore else { return }
        // Never write over a store that has not been read yet. See `hasLoaded`.
        // Refusing rather than trapping: losing an edit is recoverable, and a
        // failed load leaves this false permanently on purpose — an app that
        // could not read the database must not be allowed to overwrite it.
        guard hasLoaded else { return }
        let snapshot = data
        let previous = persistChain
        persistChain = Task { [weak self] in
            _ = await previous.value
            do { try await secureStore.save(snapshot) }
            catch { await MainActor.run { self?.errorMessage = error.localizedDescription } }
        }
    }
}

enum ExportError: LocalizedError {
    case noTripSelected
    case blocked([String])

    var errorDescription: String? {
        switch self {
        case .noTripSelected: "Select a trip before exporting."
        case .blocked(let reasons): "The crew list is not ready:\n• " + reasons.joined(separator: "\n• ")
        }
    }
}
