import Foundation
import PDFKit
import XCTest
@testable import CrewListrProMac

/// Tests for the crew-list deliverables handed to a port authority.
final class ExportServiceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/dev/null")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "crewlistr-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fixtures

    private let boat = Boat(name: "S/Y ELPIDA", flag: "GRC", registrationPort: "PIRAEUS", registrationNumber: "GR-1187-P")

    /// Built from local calendar components rather than from an epoch offset.
    /// A voyage date is a day on the operator's calendar, so the fixture has to
    /// be the same kind of thing the picker hands the store — an instant fixed
    /// in UTC lands on the previous day for anyone west of Greenwich.
    private var trip: Trip {
        let calendar = Calendar.current
        return Trip(boatID: boat.id,
                    departureDate: calendar.date(from: DateComponents(year: 2025, month: 9, day: 1))!,
                    returnDate: calendar.date(from: DateComponents(year: 2025, month: 9, day: 8))!)
    }

    private func row(_ name: String, number: String = "W1357924D", nationality: String = "UKRAINIAN",
                     birth: String = "1984-12-16", sex: String = "F", expiry: String = "2027-07-22",
                     role: CrewRole = .passenger) -> CrewListRow {
        var document = CrewDocument(tripID: UUID(), personID: UUID(), originalName: "\(number).jpeg", encryptedFileName: "\(number).bin")
        document[.fullName] = name
        document[.documentNumber] = number
        document[.nationality] = nationality
        document[.birthDate] = birth
        document[.sex] = sex
        document[.expiryDate] = expiry
        return CrewListRow(document: document, role: role)
    }

    private func exportCSV(_ rows: [CrewListRow], boat: Boat? = nil) throws -> String {
        let url = directory.appending(path: "list.csv")
        try ExportService.exportCSV(to: url, trip: trip, boat: boat ?? self.boat, rows: rows)
        let data = try Data(contentsOf: url)
        return String(decoding: data.dropFirst(3), as: UTF8.self)   // strip the UTF-8 BOM
    }

    // MARK: - File naming

    func testFileNameIncludesTheYachtAndTheDepartureDate() {
        let stem = ExportService.fileNameStem(boat: boat, trip: trip)
        XCTAssertEqual(stem, "crew-list-S-Y-ELPIDA-2025-09-01")
    }

    func testTwoYachtsDepartingTheSameDayGetDifferentFileNames() {
        let other = Boat(name: "MY AURORA")
        let mine = ExportService.fileNameStem(boat: boat, trip: trip)
        let theirs = ExportService.fileNameStem(boat: other, trip: Trip(boatID: other.id, departureDate: trip.departureDate, returnDate: trip.returnDate))
        XCTAssertNotEqual(mine, theirs, "same-day departures would overwrite each other")
    }

    func testFileNameHasNoPathSeparators() {
        let hostile = Boat(name: "../../etc/passwd")
        let stem = ExportService.fileNameStem(boat: hostile, trip: trip)
        XCTAssertFalse(stem.contains("/"))
        XCTAssertFalse(stem.contains(".."))
    }

    // MARK: - CSV content

    func testCSVHasAHeaderAndOneRowPerCrewMember() throws {
        let text = try exportCSV([row("YUKI NAKAMURA"), row("SOFIA MARCHETTI", number: "Y7654321B", sex: "M")])
        let lines = text.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("role,full_name,document_number,nationality,birth_date,sex,expiry_date"))
    }

    func testCSVCarriesTheBirthDate() throws {
        let text = try exportCSV([row("YUKI NAKAMURA", birth: "1984-12-16")])
        XCTAssertTrue(text.contains("1984-12-16"), "birth date missing:\n\(text)")
    }

    func testCSVCarriesTheExpiryDate() throws {
        let text = try exportCSV([row("SOFIA MARCHETTI", expiry: "2035-07-03")])
        XCTAssertTrue(text.contains("2035-07-03"), "expiry missing:\n\(text)")
    }

    func testCSVCarriesTheRole() throws {
        let text = try exportCSV([row("SOFIA MARCHETTI", role: .skipper)])
        XCTAssertTrue(text.contains("\"skipper\""), text)
    }

    func testCSVCarriesTheYachtRegistrationOnEveryRow() throws {
        let text = try exportCSV([row("A"), row("B", number: "X2")])
        XCTAssertEqual(text.components(separatedBy: "PIRAEUS").count - 1, 2)
        XCTAssertTrue(text.contains("GR-1187-P"))
    }

    func testCSVUsesCRLFLineEndings() throws {
        XCTAssertTrue(try exportCSV([row("A")]).contains("\r\n"))
    }

    func testCSVStartsWithAUTF8ByteOrderMark() throws {
        let url = directory.appending(path: "bom.csv")
        try ExportService.exportCSV(to: url, trip: trip, boat: boat, rows: [row("A")])
        XCTAssertEqual(Array(try Data(contentsOf: url).prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testCSVQuotesEmbeddedQuotesAndCommas() throws {
        let text = try exportCSV([row("O'BRIEN, \"SEAN\"")])
        XCTAssertTrue(text.contains("\"O'BRIEN, \"\"SEAN\"\"\""), text)
    }

    func testCSVNeutralisesAFormulaComingFromAScannedDocument() throws {
        for hostile in ["=HYPERLINK(evil)", "+1+1", "-2+3", "@SUM(A1)"] {
            let text = try exportCSV([row(hostile)])
            XCTAssertTrue(text.contains("\"'\(hostile)\""), "formula not neutralised: \(text)")
            XCTAssertFalse(text.contains("\"\(hostile)\""), "raw formula still present: \(text)")
        }
    }

    func testCSVSurvivesAnEmptyCrew() throws {
        let text = try exportCSV([])
        XCTAssertEqual(text.components(separatedBy: "\r\n").count, 1)
    }

    func testCSVHandlesTwoDocumentsForTheSamePersonWithoutTrapping() throws {
        // The old exporter built Dictionary(uniqueKeysWithValues:) keyed by
        // personID and trapped here. Rows are independent now.
        var document = CrewDocument(tripID: UUID(), personID: UUID(), originalName: "a", encryptedFileName: "a")
        document[.fullName] = "YUKI NAKAMURA"
        let passport = CrewListRow(document: document, role: .passenger)
        let idCard = CrewListRow(document: document, role: .passenger)
        XCTAssertNoThrow(try exportCSV([passport, idCard]))
    }

    // MARK: - PDF

    private func pdf(_ rows: [CrewListRow], name: String = "list.pdf") throws -> CGPDFDocument {
        let url = directory.appending(path: name)
        try ExportService.exportPDF(to: url, trip: trip, boat: boat, rows: rows)
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)), "not a PDF")
        return try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
    }

    func testPDFIsAValidDocument() throws {
        XCTAssertEqual(try pdf([row("YUKI NAKAMURA", role: .skipper)]).numberOfPages, 1)
    }

    func testPDFPaginatesALargeCrew() throws {
        let crew = (1...60).map { row("CREW MEMBER \($0)", number: "P\($0)") }
        let document = try pdf(crew, name: "big.pdf")
        XCTAssertGreaterThan(document.numberOfPages, 1, "60 crew were written onto one page")
    }

    /// Reads the rendered text back out of the PDF rather than grepping the raw
    /// bytes: CGContext writes glyphs, not literal ASCII.
    private func pdfText(_ rows: [CrewListRow], name: String) throws -> String {
        let url = directory.appending(path: name)
        try ExportService.exportPDF(to: url, trip: trip, boat: boat, rows: rows)
        let document = try XCTUnwrap(PDFDocument(url: url))
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    func testEveryCrewMemberOfALargeCrewReachesThePDF() throws {
        let crew = (1...60).map { row("CREW\($0)", number: "P\($0)") }
        let text = try pdfText(crew, name: "all.pdf")
        for index in 1...60 {
            XCTAssertTrue(text.contains("CREW\(index)"), "crew member \(index) was dropped from the PDF")
        }
    }

    func testPDFIncludesTheYachtRegistrationDetails() throws {
        let text = try pdfText([row("A", role: .skipper)], name: "reg.pdf")
        XCTAssertTrue(text.contains("PIRAEUS"), "port of registry missing:\n\(text)")
        XCTAssertTrue(text.contains("GR-1187-P"), "registration number missing:\n\(text)")
        XCTAssertTrue(text.contains("GRC"), "flag missing")
        XCTAssertTrue(text.contains("S/Y ELPIDA"), "yacht name missing")
    }

    /// Printed the way the passport dates beside them are printed. The CSV
    /// keeps the ISO form — see `ExportClientTests`.
    func testPDFIncludesTheVoyageDates() throws {
        let text = try pdfText([row("A", role: .skipper)], name: "dates.pdf")
        XCTAssertTrue(text.contains("01 SEP 2025"), text)
        XCTAssertTrue(text.contains("08 SEP 2025"), text)
    }

    func testPDFSeparatesSkipperFromPassengers() throws {
        let text = try pdfText([row("SKIP PER", role: .skipper), row("PASS ENGER", number: "X2")], name: "sections.pdf")
        let skipperIndex = try XCTUnwrap(text.range(of: "SKIPPER")).lowerBound
        let passengersIndex = try XCTUnwrap(text.range(of: "PASSENGERS")).lowerBound
        XCTAssertLessThan(skipperIndex, passengersIndex, "the skipper section must come first")
    }

    func testPDFAlwaysPrintsASkipperSectionEvenWithNoSkipper() throws {
        let text = try pdfText([row("A")], name: "noskipper.pdf")
        XCTAssertTrue(text.contains("SKIPPER"), "the printed form must still show the skipper section")
    }

    func testPDFSurvivesAnEmptyCrew() throws {
        XCTAssertEqual(try pdf([], name: "empty.pdf").numberOfPages, 1)
    }

    func testPDFSurvivesAVeryLongName() throws {
        let long = String(repeating: "ANASTASIOPOULOS ", count: 12)
        XCTAssertEqual(try pdf([row(long, role: .skipper)], name: "long.pdf").numberOfPages, 1)
    }
}
