import AppKit
import SwiftUI
import XCTest
@testable import CrewListrProMac

/// Renders each screen of the real window to a PNG, so a layout can be looked
/// at rather than reasoned about.
///
/// Opt-in, like every other test here that produces a file: set
/// CREWLISTR_SCREENSHOT_OUT to a directory. Nothing appears on screen — the
/// view is hosted in an `NSHostingView` that is never attached to a window, so
/// a full test run stays silent and nothing lands in front of whatever the
/// operator is doing.
///
/// The store is `CrewStore(secureStore: nil)`, which never touches disk. The
/// real encrypted database is not opened, read or written by any of this.
@MainActor
final class ScreenshotTests: XCTestCase {

    private func outputDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["CREWLISTR_SCREENSHOT_OUT"] else {
            throw XCTSkip("Set CREWLISTR_SCREENSHOT_OUT to render the screens.")
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - A fleet and a charter worth looking at

    private func seededStore() -> CrewStore {
        let store = CrewStore(secureStore: nil)

        let elpida = Boat(name: "S/Y ELPIDA", flag: "GRC", registrationPort: "PIRAEUS", registrationNumber: "GR-1187-P")
        let aurora = Boat(name: "M/Y AURORA", flag: "GRC", registrationPort: "LAVRIO", registrationNumber: "GR-4471-P")
        var zephyros = Boat(name: "S/Y ZEPHYROS", flag: "GRC", registrationPort: "RHODES", registrationNumber: "GR-2210-P")
        zephyros.isRetired = true

        let calendar = Calendar.current
        let departure = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let arrival = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let elpidaTrip = Trip(boatID: elpida.id, departureDate: departure, returnDate: arrival)
        let auroraTrip = Trip(boatID: aurora.id,
                              departureDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!,
                              returnDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 19))!)

        let skipper = person("ANNA MARIA ERIKSSON")
        let client = person("NIKOLAOS PAPADOPOULOS")
        let guest = person("GIULIA ROSSI")

        var skipperDocument = document(trip: elpidaTrip.id, person: skipper.id, name: "ANNA MARIA ERIKSSON",
                                       number: "L898902C3", nationality: "UTOPIAN", birth: "1974-08-12",
                                       sex: "F", expiry: "2032-04-15", confirmed: true)
        skipperDocument.riskReasons = ["Machine-readable zone read; document number, birth date and expiry all checksum-valid."]

        var clientDocument = document(trip: elpidaTrip.id, person: client.id, name: "NIKOLAOS PAPADOPOULOS",
                                      number: "AB1234567", nationality: "GREEK", birth: "1983-02-19",
                                      sex: "M", expiry: "2031-06-30", confirmed: true)
        clientDocument.riskReasons = ["Machine-readable zone read; document number, birth date and expiry all checksum-valid."]

        // One still being worked on, so the review pane shows real progress
        // rather than a finished document.
        var pending = document(trip: elpidaTrip.id, person: guest.id, name: "GIULIA ROSSI",
                               number: "YA9876543", nationality: "ITALIAN", birth: "1995-07-04",
                               sex: "F", expiry: "2029-09-13", confirmed: false)
        pending.verifiedFields = [CrewField.fullName.rawValue, CrewField.documentNumber.rawValue]
        pending.markSuggested(.documentNumber)
        pending.riskReasons = ["Machine-readable zone unreadable; values below were read from the page."]

        store.data = AppData(
            boats: [elpida, aurora, zephyros],
            trips: [elpidaTrip, auroraTrip],
            people: [skipper, client, guest],
            documents: [skipperDocument, clientDocument, pending],
            assignments: [
                CrewAssignment(tripID: elpidaTrip.id, personID: skipper.id, role: .skipper,
                               isClient: false, email: "anna.eriksson@example.com"),
                CrewAssignment(tripID: elpidaTrip.id, personID: client.id, role: .passenger, isClient: true),
                CrewAssignment(tripID: elpidaTrip.id, personID: guest.id, role: .passenger),
            ],
            settings: AppSettings()
        )
        store.selectedTripID = elpidaTrip.id
        store.selectedDocumentID = pending.id
        return store
    }

    private func person(_ name: String) -> CrewPerson {
        CrewPerson(fullName: name)
    }

    private func document(trip: UUID, person: UUID, name: String, number: String, nationality: String,
                          birth: String, sex: String, expiry: String, confirmed: Bool) -> CrewDocument {
        var document = CrewDocument(tripID: trip, personID: person,
                                    originalName: "IMG-2026\(number).jpg", encryptedFileName: "")
        document[.fullName] = name
        document[.documentNumber] = number
        document[.documentType] = "passport"
        document[.nationality] = nationality
        document[.birthDate] = birth
        document[.sex] = sex
        document[.expiryDate] = expiry
        if confirmed {
            for field in CrewField.allCases { document.verifiedFields.insert(field.rawValue) }
            document.risk = .low
        }
        return document
    }

    // MARK: - Rendering

    /// Hosted in a window that is never shown, laid out, and cached to a
    /// bitmap.
    ///
    /// Two simpler approaches were tried and both lie about the app. A bare
    /// `NSHostingView.cacheDisplay` with no window draws a SwiftUI `List` as an
    /// empty box — the Fleet panel came out as a "2 yachts" header over
    /// nothing, and the document list as status marks with no names beside
    /// them, because an `NSTableView` outside a window never draws its rows.
    /// `ImageRenderer` refuses AppKit-backed views outright and stamps a
    /// yellow no-entry sign where the list should be. A screenshot harness that
    /// invents defects is worse than none, so the view gets a real window.
    ///
    /// The window is created far offscreen and never ordered front, and the
    /// process is set `.prohibited`, so nothing appears on the operator's
    /// screen and nothing lands in the Dock.
    private func render(_ view: some View, size: CGSize, to url: URL) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)

        let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
        host.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }

        host.layoutSubtreeIfNeeded()
        // Turns of the run loop so SwiftUI settles its first layout pass and the
        // table views load their rows before the bitmap is taken.
        for _ in 0..<3 { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        host.layoutSubtreeIfNeeded()

        let bounds = host.bounds
        guard let representation = host.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw XCTSkip("This machine cannot render offscreen.")
        }
        host.cacheDisplay(in: bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw XCTSkip("PNG encoding failed.")
        }
        try png.write(to: url)
    }

    func testRendersEveryScreen() throws {
        let output = try outputDirectory()
        let store = seededStore()
        let size = CGSize(width: 1440, height: 900)

        for screen in Screen.allCases {
            // RootView reads the screen from AppStorage, so this drives the
            // real window rather than a hand-assembled imitation of it.
            UserDefaults.standard.set(screen.rawValue, forKey: "crewlistr.screen")
            try render(RootView().environment(store).tint(Theme.accentText),
                       size: size,
                       to: output.appending(path: "\(screen.rawValue).png"))
        }

        // Settings is taller than any window, so it is also rendered at a height
        // that fits it — the local model and storage sections are below the
        // fold at 900 and would never be looked at otherwise.
        UserDefaults.standard.set(Screen.settings.rawValue, forKey: "crewlistr.screen")
        try render(RootView().environment(store).tint(Theme.accentText),
                   size: CGSize(width: 1440, height: 1750),
                   to: output.appending(path: "settings-full.png"))

        // The skipper's pane, which is the only place the email field appears.
        let skipperSelected = seededStore()
        skipperSelected.selectedDocumentID = skipperSelected.data.documents.first { document in
            skipperSelected.data.assignments.contains { $0.personID == document.personID && $0.role == .skipper }
        }?.id
        UserDefaults.standard.set(Screen.people.rawValue, forKey: "crewlistr.screen")
        try render(RootView().environment(skipperSelected).tint(Theme.accentText),
                   size: size, to: output.appending(path: "people-skipper.png"))

        // And the crew list once nothing is blocking it, which is the only way
        // to see the table, the client column and the metrics at all.
        let ready = seededStore()
        for index in ready.data.documents.indices {
            for field in CrewField.allCases { ready.data.documents[index].verifiedFields.insert(field.rawValue) }
            ready.data.documents[index].risk = .low
            ready.data.documents[index].suggestedFields = nil
        }
        UserDefaults.standard.set(Screen.crewList.rawValue, forKey: "crewlistr.screen")
        try render(RootView().environment(ready).tint(Theme.accentText),
                   size: size, to: output.appending(path: "crewList-ready.png"))

        // A fleet nobody has built yet: the first thing a new operator sees.
        let empty = CrewStore(secureStore: nil)
        UserDefaults.standard.set(Screen.fleet.rawValue, forKey: "crewlistr.screen")
        try render(RootView().environment(empty).tint(Theme.accentText),
                   size: size, to: output.appending(path: "fleet-empty.png"))

        // The deliverable itself, from the same seeded trip, so the screens and
        // the paper can be checked against each other.
        let boat = try XCTUnwrap(ready.selectedBoat)
        let trip = try XCTUnwrap(ready.selectedTrip)
        _ = try ready.exportSelectedTrip(to: output)

        for screen in Screen.allCases {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: output.appending(path: "\(screen.rawValue).png").path(percentEncoded: false)))
        }

        let stem = ExportService.fileNameStem(boat: boat, trip: trip, prefix: ready.settings.fileNamePrefix)
        XCTAssertEqual(stem, "crew-list-S-Y-ELPIDA-2026-08-29",
                       "the departure picked as 29/08 must survive into the file name")
        for suffix in ["csv", "pdf"] {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: output.appending(path: "\(stem).\(suffix)").path(percentEncoded: false)))
        }
    }
}
