import Foundation

/// Scriptable export: the app writes a crew list without opening a window.
///
///     CrewListrProMac --export <directory> [--trip <yacht name>]
///     CrewListrProMac --list
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
            default:
                break
            }
            index += 1
        }
        guard sawVerb else { return nil }
        guard request.listOnly || request.directory != nil else { return nil }
        return request
    }

    // MARK: - Entry point

    /// Called before the window scene is built. Returns only when the process
    /// should carry on and present the UI.
    // `Swift.` qualified: a UI type in this module is also called CommandLine,
    // and unqualified it resolves to that one.
    static func runIfRequested(_ arguments: [String] = Swift.CommandLine.arguments) {
        guard let request = parse(arguments) else { return }
        exit(run(request))
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
            let data = try await store.load()
            if request.listOnly {
                printSummary(of: data)
                return 0
            }
            let (trip, boat) = try resolveTrip(in: data, named: request.tripName)
            let rows = try crewRows(in: data, for: trip, boat: boat)
            let written = try write(rows, trip: trip, boat: boat, into: request.directory!)
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
            let dates = "\(CrewFieldValidator.iso8601String(trip.departureDate)) → \(CrewFieldValidator.iso8601String(trip.returnDate))"
            log("\(boat?.name ?? "Untitled yacht")  \(dates)  \(cleared)/\(documents.count) cleared")
        }
    }

    private static func resolveTrip(in data: AppData, named name: String?) throws -> (Trip, Boat) {
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
            guard data.trips.count == 1 else { throw Failure.ambiguousTrip(data.trips.count) }
            trip = data.trips[0]
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
            return CrewListRow(document: document, role: assignment?.role ?? .passenger)
        }
        return rows.sorted { lhs, rhs in
            lhs.role == rhs.role ? lhs.fullName < rhs.fullName : lhs.role == .skipper
        }
    }

    private static func write(_ rows: [CrewListRow], trip: Trip, boat: Boat, into directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = ExportService.fileNameStem(boat: boat, trip: trip)
        let csv = directory.appending(path: "\(base).csv")
        let pdf = directory.appending(path: "\(base).pdf")
        try ExportService.exportCSV(to: csv, trip: trip, boat: boat, rows: rows)
        try ExportService.exportPDF(to: pdf, trip: trip, boat: boat, rows: rows)
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
