import Foundation
import PDFKit
import XCTest
@testable import CrewListrProMac

/// What the client, the skipper's email and the three-letter month look like on
/// the two files a port authority is handed.
///
/// The split of formats is deliberate and is tested as such: the PDF is read by
/// a person, so dates are printed the way the passport beside it prints them;
/// the CSV is read by software, so dates stay ISO-8601.
final class ExportClientTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/dev/null")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "crewlistr-client-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let boat = Boat(name: "S/Y ELPIDA", flag: "GRC", registrationPort: "PIRAEUS", registrationNumber: "GR-1187-P")

    /// Built from local calendar components, because that is what the picker
    /// hands the store and what the exporter now has to write back.
    private var trip: Trip {
        let calendar = Calendar.current
        return Trip(boatID: boat.id,
                    departureDate: calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!,
                    returnDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!)
    }

    private func row(_ name: String, number: String = "W1357924D", birth: String = "1984-12-16",
                     role: CrewRole = .passenger, isClient: Bool = false) -> CrewListRow {
        var document = CrewDocument(tripID: UUID(), personID: UUID(), originalName: "\(number).jpeg", encryptedFileName: "\(number).bin")
        document[.fullName] = name
        document[.documentNumber] = number
        document[.nationality] = "UKRAINIAN"
        document[.birthDate] = birth
        document[.sex] = "F"
        document[.expiryDate] = "2027-07-22"
        return CrewListRow(document: document, role: role, isClient: isClient)
    }

    private func csv(_ rows: [CrewListRow], skipperEmail: String = "") throws -> String {
        let url = directory.appending(path: "list.csv")
        try ExportService.exportCSV(to: url, trip: trip, boat: boat, rows: rows, skipperEmail: skipperEmail)
        return String(decoding: try Data(contentsOf: url).dropFirst(3), as: UTF8.self)
    }

    private func pdfText(_ rows: [CrewListRow], skipperEmail: String = "", name: String = "list.pdf") throws -> String {
        let url = directory.appending(path: name)
        try ExportService.exportPDF(to: url, trip: trip, boat: boat, rows: rows, skipperEmail: skipperEmail)
        let document = try XCTUnwrap(PDFDocument(url: url))
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    // MARK: - The picked day

    func testThePDFPrintsTheDayThatWasPicked() throws {
        let text = try pdfText([row("A", role: .skipper)], name: "dates.pdf")
        XCTAssertTrue(text.contains("29 AUG 2026"), "departure wrong or missing:\n\(text)")
        XCTAssertTrue(text.contains("05 SEP 2026"), "return wrong or missing:\n\(text)")
        XCTAssertFalse(text.contains("28 AUG 2026"), "the departure lost a day:\n\(text)")
    }

    func testTheCSVKeepsVoyageDatesMachineReadable() throws {
        let text = try csv([row("A", role: .skipper)])
        XCTAssertTrue(text.contains("2026-08-29"), text)
        XCTAssertTrue(text.contains("2026-09-05"), text)
    }

    // MARK: - Three-letter months

    func testThePDFPrintsBirthDatesTheWayAPassportDoes() throws {
        let text = try pdfText([row("YUKI NAKAMURA", birth: "1984-12-16", role: .skipper)], name: "birth.pdf")
        XCTAssertTrue(text.contains("16 DEC 1984"), "birth date not printed as on the document:\n\(text)")
    }

    func testTheCSVKeepsBirthDatesISO() throws {
        let text = try csv([row("YUKI NAKAMURA", birth: "1984-12-16")])
        XCTAssertTrue(text.contains("1984-12-16"), text)
        XCTAssertFalse(text.contains("16 DEC 1984"), "the CSV must stay machine-readable:\n\(text)")
    }

    // MARK: - The client

    func testTheCSVRecordsWhichCrewMemberIsTheClient() throws {
        let text = try csv([row("ANNA ERIKSSON", role: .skipper),
                            row("YUKI NAKAMURA", number: "Y2", isClient: true)])
        let lines = text.components(separatedBy: "\r\n")

        XCTAssertEqual(lines[0].components(separatedBy: ",").last, "is_client")
        XCTAssertEqual(lines[1].components(separatedBy: ",").last, "\"no\"", "the skipper is not the client here")
        XCTAssertEqual(lines[2].components(separatedBy: ",").last, "\"yes\"")
    }

    /// Something out there already reads this file by column position. Both new
    /// columns are appended, so every column that existed before keeps its
    /// index — inserting `is_client` second would have handed a reader a role
    /// where it expected a name.
    func testTheColumnsThatExistedBeforeKeepTheirPositions() throws {
        let text = try csv([row("ANNA ERIKSSON", role: .skipper)], skipperEmail: "anna@example.com")
        let header = text.components(separatedBy: "\r\n")[0].components(separatedBy: ",")

        XCTAssertEqual(Array(header.prefix(13)),
                       ["role", "full_name", "document_number", "nationality", "birth_date", "sex",
                        "expiry_date", "yacht", "flag", "registry_port", "registration_number",
                        "departure_date", "return_date"])
        XCTAssertEqual(Array(header.dropFirst(13)), ["skipper_email", "is_client"])
    }

    func testThePDFNamesTheClientOnASignatureLine() throws {
        let text = try pdfText([row("ANNA ERIKSSON", role: .skipper),
                                row("YUKI NAKAMURA", number: "Y2", isClient: true)], name: "client.pdf")
        XCTAssertTrue(text.contains("CLIENT"), "no client block:\n\(text)")
        let clientHeading = try XCTUnwrap(text.range(of: "CLIENT")).lowerBound
        let name = try XCTUnwrap(text.range(of: "YUKI NAKAMURA", range: clientHeading..<text.endIndex))
        XCTAssertGreaterThan(name.lowerBound, clientHeading, "the client is not named under the client heading")
    }

    /// A trip nobody has named a client on still prints the block, with the
    /// line blank — the same reasoning as the always-present skipper section.
    func testThePDFPrintsAnEmptyClientLineWhenNobodyIsNamed() throws {
        let text = try pdfText([row("ANNA ERIKSSON", role: .skipper)], name: "noclient.pdf")
        XCTAssertTrue(text.contains("CLIENT"), "the signature block must be on the form regardless:\n\(text)")
    }

    // MARK: - The skipper's email

    /// The blank case, which is what most trips look like before anyone fills
    /// these in: no client named and no address given. The block still has to
    /// be on the form and the gap under the header boxes has to stay the same,
    /// or a port official is handed a form that is a different shape each time.
    func testThePDFWithNoClientAndNoEmailIsStillAWholeForm() throws {
        let url = directory.appending(path: "bare.pdf")
        try ExportService.exportPDF(to: url, trip: trip, boat: boat,
                                    rows: [row("ANNA ERIKSSON", role: .skipper), row("YUKI NAKAMURA", number: "Y2")],
                                    skipperEmail: "")
        let document = try XCTUnwrap(PDFDocument(url: url))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")

        XCTAssertTrue(text.contains("SKIPPER"), text)
        XCTAssertTrue(text.contains("PASSENGERS"), text)
        XCTAssertTrue(text.contains("CLIENT"), "the signature block must be on every form")
        XCTAssertTrue(text.contains("SIGNATURE"))
        XCTAssertFalse(text.contains("SKIPPER EMAIL"), "no address was given, so no label for one")
        XCTAssertEqual(document.pageCount, 1)
    }

    func testThePDFPrintsTheSkippersEmail() throws {
        let text = try pdfText([row("ANNA ERIKSSON", role: .skipper)], skipperEmail: "anna@example.com", name: "email.pdf")
        XCTAssertTrue(text.contains("anna@example.com"), "skipper email missing:\n\(text)")
    }

    func testTheCSVCarriesTheSkippersEmailOnEveryRow() throws {
        let text = try csv([row("ANNA ERIKSSON", role: .skipper), row("YUKI NAKAMURA", number: "Y2")],
                           skipperEmail: "anna@example.com")
        XCTAssertTrue(text.components(separatedBy: "\r\n")[0].contains("skipper_email"))
        XCTAssertEqual(text.components(separatedBy: "anna@example.com").count - 1, 2)
    }

    func testAnAbsentSkipperEmailLeavesTheColumnEmptyRatherThanMissing() throws {
        let text = try csv([row("ANNA ERIKSSON", role: .skipper)])
        let lines = text.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0].components(separatedBy: ",").count,
                       lines[1].components(separatedBy: ",").count,
                       "header and row disagree on column count")
    }
}
