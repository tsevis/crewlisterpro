import Foundation
import Observation

/// Observable application state. Every mutation goes through this type so the
/// encrypted store sees exactly one writer.
@MainActor @Observable
final class CrewStore {
    private let secureStore: SecureStore?
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
        do { secureStore = try SecureStore() }
        catch {
            secureStore = nil
            storageFailure = error.localizedDescription
            return
        }
        Task { await load() }
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
        guard secureStore != nil else { return }
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
        guard let secureStore else { return }
        do {
            data = try await secureStore.load()
            hasLoaded = true
            // Open on the work in hand rather than on two empty columns: the
            // first trip, and within it the first document still needing review.
            selectedTripID = selectedTripID ?? data.trips.first?.id
            let documents = selectedTripDocuments
            selectedDocumentID = selectedDocumentID
                ?? documents.first { !$0.canExport() }?.id
                ?? documents.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Trips and boats

    @discardableResult
    func createTrip() -> UUID {
        let boat = Boat(name: Boat.placeholderName)
        let departure = Calendar.current.startOfDay(for: .now)
        let trip = Trip(boatID: boat.id, departureDate: departure, returnDate: Calendar.current.date(byAdding: .day, value: 7, to: departure) ?? departure)
        data.boats.append(boat)
        data.trips.append(trip)
        selectedTripID = trip.id
        selectedDocumentID = nil
        persist()
        return trip.id
    }

    func updateBoat(_ boat: Boat) {
        guard let index = data.boats.firstIndex(where: { $0.id == boat.id }) else { return }
        var updated = boat
        // A blank name is never a value anyone means, in the same way a return
        // before departure never is: the yacht's name is printed in the crew
        // list's header box, and an empty one clears port as "Untitled yacht".
        // The trip editor saves as you type, so an emptied field would
        // otherwise overwrite a real name the moment it lost focus.
        if updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.name = data.boats[index].name
        }
        data.boats[index] = updated
        persist()
    }

    func updateTrip(_ trip: Trip) {
        guard let index = data.trips.firstIndex(where: { $0.id == trip.id }) else { return }
        var updated = trip
        // A return before departure is always a typo; clamp rather than export it.
        if updated.returnDate < updated.departureDate { updated.returnDate = updated.departureDate }
        data.trips[index] = updated
        persist()
    }

    /// Removes a trip with its documents, assignments, people and the encrypted
    /// originals on disk. Nothing else in the app can delete stored identity
    /// documents, which an operator holding passport scans has to be able to do.
    func deleteTrip(_ id: UUID) {
        let documents = data.documents.filter { $0.tripID == id }
        for document in documents { discardFiles(of: document) }
        let personIDs = Set(documents.map(\.personID))
        let boatID = data.trips.first { $0.id == id }?.boatID

        data.documents.removeAll { $0.tripID == id }
        data.assignments.removeAll { $0.tripID == id }
        data.people.removeAll { personIDs.contains($0.id) }
        data.trips.removeAll { $0.id == id }
        if let boatID, !data.trips.contains(where: { $0.boatID == boatID }) {
            data.boats.removeAll { $0.id == boatID }
        }
        if selectedTripID == id {
            selectedTripID = data.trips.first?.id
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

    func setField(_ field: CrewField, to value: String, on documentID: UUID) {
        guard let index = data.documents.firstIndex(where: { $0.id == documentID }) else { return }
        data.documents[index][field] = value
        syncPerson(from: data.documents[index])
        persist()
    }

    func setVerified(_ verified: Bool, field: CrewField, on documentID: UUID) {
        guard let index = data.documents.firstIndex(where: { $0.id == documentID }) else { return }
        // A field that fails validation cannot be marked correct.
        if verified, data.documents[index].validation(of: field).isBlocking { return }
        if verified { data.documents[index].verifiedFields.insert(field.rawValue) }
        else { data.documents[index].verifiedFields.remove(field.rawValue) }
        refreshRisk(at: index)
        persist()
    }

    /// Confirms every field that currently passes validation.
    func verifyAllValidFields(on documentID: UUID) {
        guard let index = data.documents.firstIndex(where: { $0.id == documentID }) else { return }
        for field in CrewField.allCases where !data.documents[index].validation(of: field).isBlocking {
            guard !data.documents[index][field].isEmpty || !field.isRequiredForExport else { continue }
            data.documents[index].verifiedFields.insert(field.rawValue)
        }
        refreshRisk(at: index)
        persist()
    }

    func rejectDocument(_ documentID: UUID, reason: String) {
        guard let index = data.documents.firstIndex(where: { $0.id == documentID }) else { return }
        data.documents[index].risk = .high
        data.documents[index].verifiedFields = []
        data.documents[index].riskReasons = [reason]
        if let person = data.people.firstIndex(where: { $0.id == data.documents[index].personID }) {
            data.people[person].verification = .rejected
        }
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

    func setRole(_ role: CrewRole, forPersonID personID: UUID) {
        guard let tripID = selectedTripID else { return }
        if role == .skipper {
            for index in data.assignments.indices where data.assignments[index].tripID == tripID {
                data.assignments[index].role = data.assignments[index].personID == personID ? .skipper : .passenger
            }
        } else if let index = data.assignments.firstIndex(where: { $0.tripID == tripID && $0.personID == personID }) {
            data.assignments[index].role = .passenger
        }
        persist()
    }

    func role(forPersonID personID: UUID) -> CrewRole {
        data.assignments.first { $0.tripID == selectedTripID && $0.personID == personID }?.role ?? .passenger
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
            selectedTripID = data.trips.first?.id
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
        Task {
            defer { activity = nil }
            do {
                let original = try await secureStore.readOriginal(named: document.encryptedFileName)
                let suggested = try await LlamaVisionRescuer().extract(imageData: original)
                guard let index = data.documents.firstIndex(where: { $0.id == id }) else { return }
                for (key, value) in suggested where data.documents[index].fields[key, default: ""].isEmpty {
                    data.documents[index].fields[key] = value
                }
                data.documents[index].riskReasons.append("Local AI suggestions added; all remain unverified.")
                refreshRisk(at: index)
                persist()
            } catch { errorMessage = Self.explain(error) }
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
                return CrewListRow(document: document, role: assigned?.role ?? .passenger)
            }
            .sorted { lhs, rhs in
                if lhs.role != rhs.role { return lhs.role == .skipper }
                return lhs.fullName < rhs.fullName
            }
    }

    func exportSelectedTrip(to directory: URL) throws {
        guard let trip = selectedTrip, let boat = selectedBoat else { throw ExportError.noTripSelected }
        guard selectedTripCanExport else { throw ExportError.blocked(exportBlockers) }
        let rows = crewRows(forTripID: trip.id)
        let base = ExportService.fileNameStem(boat: boat, trip: trip)
        try ExportService.exportCSV(to: directory.appending(path: "\(base).csv"), trip: trip, boat: boat, rows: rows)
        try ExportService.exportPDF(to: directory.appending(path: "\(base).pdf"), trip: trip, boat: boat, rows: rows)
    }

    // MARK: - Internals

    /// Keeps the person registry in step with the document that identifies them.
    private func syncPerson(from document: CrewDocument) {
        guard let index = data.people.firstIndex(where: { $0.id == document.personID }) else { return }
        data.people[index].fullName = document[.fullName]
        data.people[index].nationality = document[.nationality]
        data.people[index].birthDate = CrewFieldValidator.isoDate(document[.birthDate])
        data.people[index].verification = document.canExport() ? .verified : .pending
    }

    private func refreshRisk(at index: Int) {
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

    private func persist() {
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
