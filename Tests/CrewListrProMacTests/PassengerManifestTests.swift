import Foundation
import XCTest
@testable import CrewListrProMac

/// The passenger manifest a port authority imports: the nine columns of its
/// own template, every value text, nationality as one of its codes.
final class PassengerManifestTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/dev/null")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "crewlistr-manifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fixtures

    private let boat = Boat(name: "S/Y ELPIDA", flag: "GRC", registrationPort: "PIRAEUS", registrationNumber: "GR-1187-P")

    private var trip: Trip {
        var trip = Trip(boatID: boat.id,
                        departureDate: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1))!,
                        returnDate: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 8))!)
        trip.embarkationTime = "08:00"
        trip.embarkationPort = "LAVRIO"
        return trip
    }

    private func row(_ name: String, nationality: String = "ITALIAN", sex: String = "F",
                     role: CrewRole = .passenger, notes: String = "") -> CrewListRow {
        var document = CrewDocument(tripID: UUID(), personID: UUID(), originalName: "a.jpeg", encryptedFileName: "a.bin")
        document[.fullName] = name
        document[.documentNumber] = "IT987654"
        document[.nationality] = nationality
        document[.birthDate] = "1990-03-22"
        document[.sex] = sex
        return CrewListRow(document: document, role: role, notes: notes)
    }

    private func unzip(_ member: String, from url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, member]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(member) is not readable from the archive")
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Nationality

    func testNationalityResolvesEveryWayTheAppHoldsIt() {
        XCTAssertEqual(ManifestNationality.code(for: "GREEK"), "GRC")
        XCTAssertEqual(ManifestNationality.code(for: "grc"), "GRC")
        XCTAssertEqual(ManifestNationality.code(for: " Ελληνική "), "GRC")
        XCTAssertEqual(ManifestNationality.code(for: "HELLENIC"), "GRC")
        XCTAssertEqual(ManifestNationality.code(for: "Congolese (DRC)"), "COD")
    }

    func testMachineReadableZoneCodesBecomeTheTemplatesOwn() {
        // Germany writes D in the MRZ, and the template has its own code for
        // Palestine and Kosovo rather than ISO's.
        XCTAssertEqual(ManifestNationality.code(for: "D"), "DEU")
        XCTAssertEqual(ManifestNationality.code(for: "PSE"), "TPO")
        XCTAssertEqual(ManifestNationality.code(for: "RKS"), "XKX")
        XCTAssertEqual(ManifestNationality.code(for: "GBD"), "GBR")
    }

    func testAnUnknownNationalityIsNotGuessed() {
        XCTAssertNil(ManifestNationality.code(for: "UTO"))
        XCTAssertNil(ManifestNationality.code(for: ""))
    }

    // MARK: - Embarkation time

    func testEmbarkationTimeIsHeldAsTwoDigitHoursAndMinutes() {
        XCTAssertEqual(EmbarkationTime.normalised("8:00"), "08:00")
        XCTAssertEqual(EmbarkationTime.normalised("0830"), "08:30")
        XCTAssertEqual(EmbarkationTime.normalised("14.15"), "14:15")
        XCTAssertEqual(EmbarkationTime.normalised(""), "")
        XCTAssertNil(EmbarkationTime.normalised("25:00"))
        XCTAssertNil(EmbarkationTime.normalised("12:60"))
        XCTAssertNil(EmbarkationTime.normalised("noon"))
    }

    // MARK: - Rows

    func testRowsFollowTheTemplatesColumnOrder() {
        let lines = PassengerManifest.lines(trip: trip, rows: [row("MARIA ROSSI", notes: "VIP guest")])
        XCTAssertEqual(lines.first, [
            "Full Name / Ονοματεπώνυμο", "ID/Passport No / Αρ. Ταυτότητας/Διαβατηρίου",
            "Sex (M/F) / Φύλο (Α/Θ)", "Nationality / Ιθαγένεια", "Date of Birth / Ημ. Γέννησης",
            "Embarkation Date / Ημ. Επιβίβασης", "Embarkation Time / Ώρα Επιβίβασης",
            "Embarkation Port / Λιμένας Επιβίβασης", "Notes / Σημειώσεις",
        ])
        XCTAssertEqual(lines[1], ["MARIA ROSSI", "IT987654", "F", "ITA", "1990-03-22",
                                  "2026-07-01", "08:00", "LAVRIO", "VIP guest"])
    }

    func testTheSkipperIsMarkedInNotes() {
        let lines = PassengerManifest.lines(trip: trip, rows: [row("ANNA ERIKSSON", role: .skipper, notes: "Owner")])
        XCTAssertEqual(lines[1].last, "Skipper · Owner")
    }

    func testAnUnresolvedNationalityIsWrittenAsReadNotDropped() {
        let lines = PassengerManifest.lines(trip: trip, rows: [row("X", nationality: "UTO")])
        XCTAssertEqual(lines[1][3], "UTO")
    }

    // MARK: - Workbook

    func testWorkbookIsAValidArchiveWithEveryCellAsText() throws {
        let url = directory.appending(path: "manifest.xlsx")
        try PassengerManifest.export(to: url, trip: trip, rows: [row("O'BRIEN & <SONS>")])

        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        check.arguments = ["-tq", url.path]
        check.standardOutput = Pipe()
        try check.run()
        check.waitUntilExit()
        XCTAssertEqual(check.terminationStatus, 0, "the archive fails its own CRC check")

        let workbook = try unzip("xl/workbook.xml", from: url)
        XCTAssertTrue(workbook.contains("name=\"Passengers\""))

        let sheet = try unzip("xl/worksheets/sheet1.xml", from: url)
        XCTAssertTrue(sheet.contains("O&apos;BRIEN &amp; &lt;SONS&gt;"), "names must be escaped, not break the XML")
        XCTAssertTrue(sheet.contains("<t xml:space=\"preserve\">2026-07-01</t>"))
        XCTAssertFalse(sheet.contains("<v>"), "a numeric cell is one Excel will turn into a serial date")
    }

    // MARK: - Persistence

    func testATripSavedBeforeEmbarkationExistedStillOpens() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","boatID":"\(UUID().uuidString)","departureDate":0,"returnDate":0,"status":"draft"}
        """
        let decoded = try JSONDecoder().decode(Trip.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.embarkationTime, "")
        XCTAssertEqual(decoded.embarkationPort, "")
    }

    func testSettingsSavedBeforeTheManifestExistedWriteIt() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"writesCSV":true,"writesPDF":true}"#.utf8))
        XCTAssertTrue(decoded.writesManifest)
    }
}
