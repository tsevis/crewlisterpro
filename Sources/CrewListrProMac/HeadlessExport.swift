import Foundation

/// Scriptable export: the app writes a crew list without opening a window.
///
///     CrewListrProMac --export <directory> [--trip <yacht name>]
///     CrewListrProMac --list
///     CrewListrProMac --snapshot
///     CrewListrProMac --backups
///     CrewListrProMac --restore <snapshot-id>
///
/// It runs the same store, the same export gate and the same `ExportService` the
/// Crew List sheet uses, so a file produced this way is the file the sheet would
/// have produced. Useful for automation, for a machine with no display, and for
/// checking readiness from a script.
enum HeadlessExport {

    struct Request: Equatable {
        var directory: URL?
        var tripName: String?
        var listOnly = false
        var listBackups = false
        var takeSnapshot = false
        var restoreIdentifier: String?
    }

    enum Failure: LocalizedError {
        case noTrips
        case unknownTrip(String)
        case ambiguousTrip(Int)
        case orphanedTrip
        case notReady([String])

        var errorDescription: String? {
            switch self {
            case .noTrips: "this Mac has no trips."
            case .unknownTrip(let name): "no trip for a yacht named \(name)."
            case .ambiguousTrip(let count): "this Mac has \(count) trips; name one with --trip."
            case .orphanedTrip: "that trip has no yacht."
            case .notReady(let reasons): "the crew list is not ready:\n  • " + reasons.joined(separator: "\n  • ")
            }
        }
    }

    // MARK: - Arguments

    /// What the command line asked for.
    ///
    /// The window used to be the fallback for anything unrecognised, which made
    /// a typo indistinguishable from a double-click: `--exprot /tmp/out` opened
    /// a window and wrote nothing, and on a machine with no display, or under a
    /// script, that is a hang. `--help` did the same — the one thing a person
    /// types to find out how this works was the one thing that told them
    /// nothing.
    enum Intent: Equatable {
        case headless(Request)
        case usage(exitCode: Int32)
        case presentWindow
    }

    static func intent(_ arguments: [String] = Swift.CommandLine.arguments) -> Intent {
        if arguments.dropFirst().contains(where: { $0 == "--help" || $0 == "-h" }) {
            return .usage(exitCode: 0)
        }
        // Checked BEFORE parsing, not after. `parse` skips what it does not
        // recognise, so `--list --nonsense` parsed cleanly as `--list` and the
        // misspelling went unmentioned — the operator would have got a
        // successful-looking run of something they did not ask for.
        //
        // Only double-dashed arguments are judged. macOS itself passes
        // `-psn_0_123456` and `-NSDocumentRevisionsDebugMode YES` when the app
        // is opened from the Finder or Xcode; refusing those would stop the app
        // opening at all.
        let usedAFlag = arguments.dropFirst().contains { $0.hasPrefix("--") }
        let unknown = arguments.dropFirst().contains { argument in
            argument.hasPrefix("--") && !Self.knownFlags.contains(argument)
        }
        if unknown { return .usage(exitCode: 2) }
        if let request = parse(arguments) { return .headless(request) }
        // A recognised flag that did not amount to a request — `--trip` with no
        // verb, or `--export` with no directory — is also a mistake, not a
        // double-click.
        return usedAFlag ? .usage(exitCode: 2) : .presentWindow
    }

    private static let knownFlags: Set<String> = ["--export", "--trip", "--list", "--backups", "--snapshot", "--restore"]

    static let usage = """
        CrewListr Pro — offline crew-list preparation.

        Usage:
          CrewListrProMac                          Open the window.
          CrewListrProMac --list                   List the trips on this Mac.
          CrewListrProMac --export <directory>     Write the crew list files.
                          [--trip <yacht name>]    Which trip, when there is more than one.
          CrewListrProMac --backups                List the earlier versions kept.
          CrewListrProMac --snapshot               Save a version now.
          CrewListrProMac --restore <id>           Make an earlier version current.
          CrewListrProMac --help                   This text.

        Everything runs against the encrypted store on this Mac. Export writes
        the same files, through the same review gate, as the Crew List screen.
        """

    /// Parsed separately from the work so the argument handling is testable.
    static func parse(_ arguments: [String]) -> Request? {
        var request = Request()
        var sawVerb = false
        var index = 1   // skip the executable
        while index < arguments.count {
            switch arguments[index] {
            case "--export":
                sawVerb = true
                guard index + 1 < arguments.count else { return nil }
                index += 1
                request.directory = URL(fileURLWithPath: arguments[index])
            case "--trip":
                guard index + 1 < arguments.count else { return nil }
                index += 1
                request.tripName = arguments[index]
            case "--list":
                sawVerb = true
                request.listOnly = true
            case "--backups":
                sawVerb = true
                request.listBackups = true
            case "--snapshot":
                sawVerb = true
                request.takeSnapshot = true
            case "--restore":
                sawVerb = true
                guard index + 1 < arguments.count else { return nil }
                index += 1
                request.restoreIdentifier = arguments[index]
            default:
                break
            }
            index += 1
        }
        guard sawVerb else { return nil }
        guard request.listOnly || request.listBackups || request.takeSnapshot
                || request.restoreIdentifier != nil || request.directory != nil else { return nil }
        return request
    }

    // MARK: - Entry point

    /// Called before the window scene is built. Returns only when the process
    /// should carry on and present the UI.
    // `Swift.` qualified: a UI type in this module is also called CommandLine,
    // and unqualified it resolves to that one.
    static func runIfRequested(_ arguments: [String] = Swift.CommandLine.arguments) {
        switch intent(arguments) {
        case .presentWindow:
            return
        case .usage(let code):
            if code == 0 { log(usage) } else { FileHandle.standardError.write(Data((usage + "\n").utf8)) }
            exit(code)
        case .headless(let request):
            exit(run(request))
        }
    }

    private static func run(_ request: Request) -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var status: Int32 = 1
        Task {
            status = await execute(request)
            semaphore.signal()
        }
        semaphore.wait()
        return status
    }

    private static func execute(_ request: Request) async -> Int32 {
        do {
            let store = try SecureStore()

            if request.takeSnapshot {
                let taken = await store.snapshot()
                log(taken
                    ? "Snapshot taken."
                    : "Nothing to snapshot: this state is already the newest one kept.")
                return 0
            }

            if request.listBackups {
                let backups = await store.backups()
                guard !backups.isEmpty else {
                    log("No snapshots yet. One is taken each time the store changes.")
                    return 0
                }
                let stamp = DateFormatter()
                stamp.dateStyle = .medium
                stamp.timeStyle = .medium
                for backup in backups {
                    log("\(backup.id)  \(stamp.string(from: backup.created))  \(backup.trips) trip\(backup.trips == 1 ? "" : "s"), \(backup.documents) document\(backup.documents == 1 ? "" : "s")")
                }
                return 0
            }

            if let identifier = request.restoreIdentifier {
                let recovered = try await store.restore(identifier)
                log("Restored \(recovered.trips.count) trip(s) and \(recovered.documents.count) document(s) from \(identifier).")
                log("The state this replaced was snapshotted first, so this is undoable.")
                return 0
            }

            let data = try await store.load()
            if request.listOnly {
                printSummary(of: data)
                return 0
            }
            let (trip, boat) = try resolveTrip(in: data, named: request.tripName)
            let rows = try crewRows(in: data, for: trip, boat: boat)
            let email = data.assignments.first { $0.tripID == trip.id && $0.role == .skipper }?.email ?? ""
            let written = try write(rows, trip: trip, boat: boat, skipperEmail: email, into: request.directory!)
            log("Exported \(rows.count) crew for \(boat.name):")
            for url in written { log("  " + url.path(percentEncoded: false)) }
            return 0
        } catch {
            return fail(error.localizedDescription)
        }
    }

    // MARK: - Steps

    private static func printSummary(of data: AppData) {
        for trip in data.trips {
            let boat = data.boats.first { $0.id == trip.boatID }
            let documents = data.documents.filter { $0.tripID == trip.id }
            let cleared = documents.filter { $0.canExport() }.count
            let dates = "\(VoyageDate.iso(trip.departureDate)) → \(VoyageDate.iso(trip.returnDate))"
            // Marked, so `--list` does not present a put-away charter as though
            // it were still being worked on.
            let archived = trip.isArchived ? "  [archived]" : ""
            log("\(boat?.displayName ?? "Untitled yacht")  \(dates)  \(cleared)/\(documents.count) cleared\(archived)")
        }
    }

    /// Naming a trip searches every trip, archived included — a port authority
    /// asking about last season has to be answerable. Omitting the name means
    /// "the only trip there is", and there archived trips are skipped: putting
    /// finished charters away is precisely what keeps that unambiguous.
    static func resolveTrip(in data: AppData, named name: String?) throws -> (Trip, Boat) {
        guard !data.trips.isEmpty else { throw Failure.noTrips }
        let trip: Trip
        if let name {
            let match = data.trips.first { candidate in
                let boat = data.boats.first { $0.id == candidate.boatID }
                return boat?.name.caseInsensitiveCompare(name) == .orderedSame
            }
            guard let match else { throw Failure.unknownTrip(name) }
            trip = match
        } else {
            let candidates = data.trips.filter { !$0.isArchived }
            guard !candidates.isEmpty else { throw Failure.noTrips }
            guard candidates.count == 1 else { throw Failure.ambiguousTrip(candidates.count) }
            trip = candidates[0]
        }
        guard let boat = data.boats.first(where: { $0.id == trip.boatID }) else { throw Failure.orphanedTrip }
        return (trip, boat)
    }

    /// The same gate the Crew List sheet applies, phrased the same way.
    static func blockers(in data: AppData, for trip: Trip, boat: Boat) -> [String] {
        var blockers: [String] = []
        if !boat.isComplete { blockers.append("Name the yacht.") }
        if boat.flag.trimmingCharacters(in: .whitespaces).isEmpty { blockers.append("Set the yacht's flag.") }
        let documents = data.documents.filter { $0.tripID == trip.id }
        if documents.isEmpty { blockers.append("Import at least one document.") }
        for document in documents {
            let pending = document.blockingFields()
            if document.risk == .high {
                blockers.append("\(document.originalName) is rejected.")
            } else if !pending.isEmpty {
                blockers.append("\(document.originalName): \(pending.map(\.label).joined(separator: ", ")) unconfirmed.")
            }
        }
        if !documents.isEmpty, !data.assignments.contains(where: { $0.tripID == trip.id && $0.role == .skipper }) {
            blockers.append("Nominate a skipper.")
        }
        return blockers
    }

    private static func crewRows(in data: AppData, for trip: Trip, boat: Boat) throws -> [CrewListRow] {
        let reasons = blockers(in: data, for: trip, boat: boat)
        guard reasons.isEmpty else { throw Failure.notReady(reasons) }
        let documents = data.documents.filter { $0.tripID == trip.id }
        let rows = documents.map { document -> CrewListRow in
            let assignment = data.assignments.first { $0.tripID == trip.id && $0.personID == document.personID }
            return CrewListRow(document: document,
                               role: assignment?.role ?? .passenger,
                               isClient: assignment?.isClient ?? false)
        }
        return rows.sorted { lhs, rhs in
            lhs.role == rhs.role ? lhs.fullName < rhs.fullName : lhs.role == .skipper
        }
    }

    private static func write(_ rows: [CrewListRow], trip: Trip, boat: Boat, skipperEmail: String, into directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = ExportService.fileNameStem(boat: boat, trip: trip)
        let csv = directory.appending(path: "\(base).csv")
        let pdf = directory.appending(path: "\(base).pdf")
        try ExportService.exportCSV(to: csv, trip: trip, boat: boat, rows: rows, skipperEmail: skipperEmail)
        try ExportService.exportPDF(to: pdf, trip: trip, boat: boat, rows: rows, skipperEmail: skipperEmail)
        return [csv, pdf]
    }

    // MARK: - Output

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data(("crewlistr: " + message + "\n").utf8))
        return 1
    }
}
