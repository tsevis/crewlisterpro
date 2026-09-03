import Foundation
import XCTest
@testable import CrewListrProMac

/// Tests for the app's scriptable export entry point.
final class HeadlessExportTests: XCTestCase {

    private func intent(_ arguments: String...) -> HeadlessExport.Intent {
        HeadlessExport.intent(["CrewListrProMac"] + arguments)
    }

    // MARK: - What an unrecognised flag does
    //
    // It used to open a window. On a machine with no display, or in a script,
    // that is a hang — and `--help` did it too, so the one thing a person types
    // to find out how to use this was the one thing that told them nothing.

    func testHelpPrintsUsageRatherThanOpeningAWindow() {
        XCTAssertEqual(intent("--help"), .usage(exitCode: 0))
        XCTAssertEqual(intent("-h"), .usage(exitCode: 0))
    }

    func testAnUnrecognisedLongFlagIsRefusedRatherThanOpeningAWindow() {
        XCTAssertEqual(intent("--exprot", "/tmp/out"), .usage(exitCode: 2))
        XCTAssertEqual(intent("--list", "--nonsense"), .usage(exitCode: 2))
    }

    /// macOS passes these when the app is launched from the Finder or Xcode.
    /// They are not typos, and refusing them would stop the app opening at all.
    func testTheArgumentsMacOSAddsStillOpenTheWindow() {
        XCTAssertEqual(intent(), .presentWindow)
        XCTAssertEqual(intent("-psn_0_123456"), .presentWindow)
        XCTAssertEqual(intent("-NSDocumentRevisionsDebugMode", "YES"), .presentWindow)
    }

    private func parse(_ arguments: String...) -> HeadlessExport.Request? {
        HeadlessExport.parse(["CrewListrProMac"] + arguments)
    }

    // MARK: - Arguments

    func testNoArgumentsMeansShowTheWindow() {
        XCTAssertNil(HeadlessExport.parse(["CrewListrProMac"]))
    }

    /// Launch Services passes arguments of its own; none may be mistaken for a
    /// request to export, or double-clicking the app would exit silently.
    func testLaunchServicesArgumentsAreIgnored() {
        XCTAssertNil(parse("-psn_0_123456"))
        XCTAssertNil(parse("-NSDocumentRevisionsDebugMode", "YES"))
    }

    func testExportRequiresADirectory() {
        XCTAssertNil(parse("--export"))
    }

    func testExportParsesADirectory() {
        XCTAssertEqual(parse("--export", "/tmp/out")?.directory, URL(fileURLWithPath: "/tmp/out"))
    }

    func testTripNameIsOptional() {
        XCTAssertNil(parse("--export", "/tmp/out")?.tripName)
        XCTAssertEqual(parse("--export", "/tmp/out", "--trip", "S/Y ANEMOS")?.tripName, "S/Y ANEMOS")
    }

    func testTripAloneIsNotAVerb() {
        XCTAssertNil(parse("--trip", "S/Y ANEMOS"))
    }

    func testBackupsNeedsNoDirectory() {
        let request = parse("--backups")
        XCTAssertEqual(request?.listBackups, true)
        XCTAssertNil(request?.directory)
    }

    func testRestoreTakesASnapshotIdentifier() {
        XCTAssertEqual(parse("--restore", "2026-08-21T121122000Z")?.restoreIdentifier, "2026-08-21T121122000Z")
    }

    func testRestoreWithoutAnIdentifierIsRejected() {
        XCTAssertNil(parse("--restore"))
    }

    func testListNeedsNoDirectory() {
        let request = parse("--list")
        XCTAssertEqual(request?.listOnly, true)
        XCTAssertNil(request?.directory)
    }

    // MARK: - The gate

    private func makeReadyData() -> (AppData, Trip, Boat) {
        let boat = Boat(name: "S/Y ANEMOS", flag: "GRC", registrationPort: "LAVRIO", registrationNumber: "GR-4471-P")
        let trip = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        var document = CrewDocument(tripID: trip.id, personID: UUID(), originalName: "a.jpeg", encryptedFileName: "a.bin")
        document[.fullName] = "ERIK LINDQVIST"
        document[.documentNumber] = "X1234567A"
        document[.nationality] = "UKRAINIAN"
        document[.birthDate] = "1980-11-20"
        document[.sex] = "M"
        for field in CrewField.requiredForExport { document.verifiedFields.insert(field.rawValue) }
        let data = AppData(boats: [boat], trips: [trip], documents: [document],
                           assignments: [CrewAssignment(tripID: trip.id, personID: document.personID, role: .skipper)])
        return (data, trip, boat)
    }

    func testAFullyReviewedTripHasNoBlockers() {
        let (data, trip, boat) = makeReadyData()
        XCTAssertEqual(HeadlessExport.blockers(in: data, for: trip, boat: boat), [])
    }

    func testAnUnnamedYachtBlocks() {
        var (data, trip, _) = makeReadyData()
        data.boats[0].name = Boat.placeholderName
        XCTAssertTrue(HeadlessExport.blockers(in: data, for: trip, boat: data.boats[0]).contains("Name the yacht."))
        _ = trip
    }

    func testAMissingFlagBlocks() {
        var (data, trip, _) = makeReadyData()
        data.boats[0].flag = ""
        XCTAssertTrue(HeadlessExport.blockers(in: data, for: trip, boat: data.boats[0]).contains("Set the yacht's flag."))
    }

    func testAnUnconfirmedFieldBlocks() {
        var (data, trip, boat) = makeReadyData()
        data.documents[0].verifiedFields.remove(CrewField.sex.rawValue)
        let blockers = HeadlessExport.blockers(in: data, for: trip, boat: boat)
        XCTAssertTrue(blockers.contains { $0.contains("Sex") }, "\(blockers)")
    }

    func testAMissingSkipperBlocks() {
        var (data, trip, boat) = makeReadyData()
        data.assignments[0].role = .passenger
        XCTAssertTrue(HeadlessExport.blockers(in: data, for: trip, boat: boat).contains("Nominate a skipper."))
    }

    func testARejectedDocumentBlocks() {
        var (data, trip, boat) = makeReadyData()
        data.documents[0].risk = .high
        XCTAssertTrue(HeadlessExport.blockers(in: data, for: trip, boat: boat).contains { $0.contains("rejected") })
    }

    func testTheGateMatchesTheCrewListSheet() async throws {
        let (data, _, _) = makeReadyData()
        // A throwaway store: `secureStore: nil` opens the user's real database.
        var homes: [URL] = []
        defer { for home in homes { try? FileManager.default.removeItem(at: home) } }
        let store = await CrewStore(secureStore: try TemporaryStore.make(in: &homes))
        await MainActor.run {
            store.data = data
            store.selectedTripID = data.trips[0].id
            // Both paths must agree; the sheet and the script share a rulebook.
            XCTAssertEqual(store.exportBlockers,
                           HeadlessExport.blockers(in: data, for: data.trips[0], boat: data.boats[0]))
        }
    }
}
