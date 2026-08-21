import Foundation
import XCTest
@testable import CrewListrProMac

/// End-to-end exercise of the shipping pipeline — OCRService → CrewDocument →
/// review → ExportService — against real identity documents.
///
/// Opt-in. Set CREWLISTR_FIXTURES to a directory of documents and, optionally,
/// CREWLISTR_OUTPUT to where the crew list should be written. The test never
/// touches the operator's live SQLCipher store or Keychain-held key.
final class CrewListGenerationTests: XCTestCase {

    private struct Extraction {
        let file: URL
        let result: OCRResult
        var document: CrewDocument
    }

    private func fixtures() throws -> [URL] {
        guard let dir = ProcessInfo.processInfo.environment["CREWLISTR_FIXTURES"] else {
            throw XCTSkip("Set CREWLISTR_FIXTURES to a directory of identity documents.")
        }
        // Only identity documents. A directory an operator has also exported
        // into contains crew lists, and a crew-list PDF is still a PDF — so
        // exclude by name as well as by type, or the harness tries to read a
        // machine-readable zone off its own output and reports the fixture set
        // as broken.
        let readable: Set<String> = ["jpg", "jpeg", "png", "heic", "tif", "tiff", "pdf"]
        return try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .filter { readable.contains($0.pathExtension.lowercased()) }
            .filter { !$0.lastPathComponent.hasPrefix("crew-list-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func outputDirectory() throws -> URL {
        let path = ProcessInfo.processInfo.environment["CREWLISTR_OUTPUT"]
            ?? FileManager.default.temporaryDirectory.appending(path: "crewlistr-output").path(percentEncoded: false)
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Operator corrections, keyed by document number, read from the JSON file
    /// named by CREWLISTR_CORRECTIONS. This is the review pane's typing step in
    /// batch form: a name the camera destroyed is typed from the image beside it.
    /// Kept in an external file so no real name is ever committed to this repo.
    ///
    ///     { "X1234567A": { "full_name": "..." } }
    private func corrections() throws -> [String: [String: String]] {
        guard let path = ProcessInfo.processInfo.environment["CREWLISTR_CORRECTIONS"] else { return [:] }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
            XCTFail("CREWLISTR_CORRECTIONS must be {document_number: {field: value}}")
            return [:]
        }
        return object
    }

    /// The voyage the crew list is for, read from the JSON file named by
    /// CREWLISTR_VOYAGE. Kept external for the same reason as the corrections:
    /// a real charter's registration details do not belong in this repository.
    ///
    ///     {
    ///       "yacht": { "name": "...", "flag": "...",
    ///                  "registration_port": "...", "registration_number": "..." },
    ///       "departure_date": "YYYY-MM-DD",
    ///       "return_date": "YYYY-MM-DD",
    ///       "skipper_document_number": "..."
    ///     }
    private struct Voyage {
        var boat = Boat(name: "S/Y ELPIDA", flag: "GRC", registrationPort: "PIRAEUS", registrationNumber: "GR-1187-P")
        var departure = Date(timeIntervalSince1970: 1_756_684_800)
        var arrival = Date(timeIntervalSince1970: 1_757_289_600)
        var skipperDocumentNumber: String?
    }

    private func voyage() throws -> Voyage {
        var voyage = Voyage()
        guard let path = ProcessInfo.processInfo.environment["CREWLISTR_VOYAGE"] else { return voyage }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("CREWLISTR_VOYAGE is not a JSON object")
            return voyage
        }
        if let yacht = object["yacht"] as? [String: String] {
            voyage.boat = Boat(
                name: yacht["name"] ?? voyage.boat.name,
                flag: yacht["flag"] ?? "",
                registrationPort: yacht["registration_port"] ?? "",
                registrationNumber: yacht["registration_number"] ?? ""
            )
        }
        if let value = object["departure_date"] as? String {
            voyage.departure = try XCTUnwrap(CrewFieldValidator.isoDate(value), "departure_date must be YYYY-MM-DD")
        }
        if let value = object["return_date"] as? String {
            voyage.arrival = try XCTUnwrap(CrewFieldValidator.isoDate(value), "return_date must be YYYY-MM-DD")
        }
        voyage.skipperDocumentNumber = object["skipper_document_number"] as? String
        XCTAssertGreaterThanOrEqual(voyage.arrival, voyage.departure, "the voyage returns before it departs")
        return voyage
    }

    /// Reproduces what `CrewStore.importDocuments` builds for one file.
    private func importDocument(_ url: URL, tripID: UUID) throws -> Extraction {
        let result = try OCRService.extract(from: url)
        let document = CrewDocument(
            tripID: tripID, personID: UUID(),
            originalName: url.lastPathComponent, encryptedFileName: "",
            documentNumber: result.fields[CrewField.documentNumber.rawValue] ?? "",
            documentType: result.fields[CrewField.documentType.rawValue] ?? "unknown",
            risk: result.risk, riskReasons: result.reasons, fields: result.fields
        )
        return Extraction(file: url, result: result, document: document)
    }

    // MARK: - Extraction quality on real documents

    /// Line 2 is self-checking, so every real document must give up its number,
    /// nationality, birth date, sex and expiry however badly line 1 photographed.
    func testEveryRealDocumentYieldsItsLine2Identity() throws {
        let extractions = try fixtures().map { try importDocument($0, tripID: UUID()) }
        XCTAssertFalse(extractions.isEmpty)
        for extraction in extractions {
            let name = extraction.file.lastPathComponent
            XCTAssertFalse(extraction.document[.documentNumber].isEmpty, name)
            XCTAssertFalse(extraction.document[.birthDate].isEmpty, name)
            XCTAssertFalse(extraction.document[.nationality].isEmpty, name)
            XCTAssertFalse(extraction.document[.sex].isEmpty, name)
            XCTAssertFalse(extraction.document[.expiryDate].isEmpty, name)
        }
    }

    /// A name the camera destroyed must come back empty and blocking, never as
    /// plausible-looking debris on a crew list.
    func testAnUnreadableNameIsEmptyRatherThanInvented() throws {
        let extractions = try fixtures().map { try importDocument($0, tripID: UUID()) }
        for extraction in extractions {
            let name = extraction.document[.fullName]
            XCTAssertFalse(name.contains(where: \.isNumber), "invented name \"\(name)\" in \(extraction.file.lastPathComponent)")
            if name.isEmpty {
                XCTAssertTrue(extraction.document.blockingFields().contains(.fullName), extraction.file.lastPathComponent)
            }
        }
        // Half the MIO set has a readable name line; the rest is glare and crop.
        // Recovering three and refusing to guess the other three is the correct
        // outcome — an earlier build "recovered" four by accepting OCR debris.
        let named = extractions.filter { !$0.document[.fullName].isEmpty }
        XCTAssertGreaterThanOrEqual(named.count, 3, "the parser lost a name it used to read")
    }

    /// The review gate must catch what extraction gets wrong. Every field the
    /// pipeline cannot stand behind has to surface as a blocker, not as a
    /// silently exported value.
    func testEveryExtractionProblemSurfacesAsAReviewBlocker() throws {
        let extractions = try fixtures().map { try importDocument($0, tripID: UUID()) }
        for extraction in extractions {
            XCTAssertFalse(extraction.document.canExport(),
                           "\(extraction.file.lastPathComponent) cleared export without any operator review")
            XCTAssertEqual(extraction.document.reviewStatus(), .awaitingReview, extraction.file.lastPathComponent)
        }
    }

    func testNoValidPassportIsReadAsExpired() throws {
        let extractions = try fixtures().map { try importDocument($0, tripID: UUID()) }
        let expiredLooking = extractions.filter {
            if case .warning = $0.document.validation(of: .expiryDate) { return true }
            return false
        }
        for extraction in expiredLooking {
            print("⚠︎ \(extraction.document.documentNumber): expiry reads \(extraction.document[.expiryDate])")
        }
        XCTAssertTrue(expiredLooking.isEmpty, "a valid passport was read as expired — the century pivot is wrong again")
    }

    func testNamesWithOCRNoiseAreFlagged() throws {
        let extractions = try fixtures().map { try importDocument($0, tripID: UUID()) }
        let noisy = extractions.filter {
            if case .warning = $0.document.validation(of: .fullName) { return true }
            return false
        }
        for extraction in noisy {
            print("⚠︎ \(extraction.document.documentNumber): name reads \"\(extraction.document[.fullName])\" — flagged for review")
        }
        // Not an assertion about count: the point is that nothing noisy is silent.
        XCTAssertTrue(noisy.allSatisfy { !$0.document.canExport() })
    }

    func testDocumentNumbersAreUniqueAcrossTheFixtureSet() throws {
        let numbers = try fixtures().map { try importDocument($0, tripID: UUID()).document.documentNumber }.filter { !$0.isEmpty }
        XCTAssertEqual(Set(numbers).count, numbers.count, "duplicate document numbers: \(numbers)")
    }

    // MARK: - The real crew list

    func testGeneratesACrewListFromTheRealDocumentSet() throws {
        let files = try fixtures()
        let output = try outputDirectory()

        let voyage = try voyage()
        let boat = voyage.boat
        let trip = Trip(boatID: boat.id, departureDate: voyage.departure, returnDate: voyage.arrival)

        var extractions = try files.map { try importDocument($0, tripID: trip.id) }
        let typed = try corrections()

        // The operator works through the review pane: type what the camera lost,
        // confirm what is valid, and record what still blocks.
        var stillBlocked: [String] = []
        var applied: [String] = []
        for index in extractions.indices {
            if let fixes = typed[extractions[index].document.documentNumber] {
                for (key, value) in fixes {
                    guard let field = CrewField(rawValue: key) else {
                        XCTFail("unknown correction field \(key)")
                        continue
                    }
                    extractions[index].document[field] = value
                    applied.append("\(extractions[index].document.documentNumber): \(field.label) typed from the image")
                }
            }
            for field in CrewField.allCases where !extractions[index].document.validation(of: field).isBlocking {
                extractions[index].document.verifiedFields.insert(field.rawValue)
            }
            let blocking = extractions[index].document.blockingFields()
            if !blocking.isEmpty {
                stillBlocked.append("\(extractions[index].file.lastPathComponent): \(blocking.map(\.label).joined(separator: ", "))")
            }
        }

        let exportable = extractions.filter { $0.document.canExport() }
        // Exactly one skipper: the nominated document, or the first crew member
        // old enough to hold the licence when none was nominated.
        let skipperNumber = voyage.skipperDocumentNumber
            ?? exportable.first { isAdult($0.document, on: voyage.departure) }?.document.documentNumber
        XCTAssertNotNil(skipperNumber, "no crew member could be the skipper")
        XCTAssertTrue(exportable.contains { $0.document.documentNumber == skipperNumber },
                      "the nominated skipper \(skipperNumber ?? "-") is not on this crew list")
        let rows = exportable.map {
            CrewListRow(document: $0.document, role: $0.document.documentNumber == skipperNumber ? .skipper : .passenger)
        }
        XCTAssertEqual(rows.filter { $0.role == .skipper }.count, 1, "a crew list carries exactly one skipper")

        let minors = exportable.filter { !isAdult($0.document, on: voyage.departure) }
        for minor in minors {
            print("ℹ︎ \(minor.document.documentNumber) is a minor on the departure date — check local requirements")
        }
        for extraction in exportable {
            let expiry = extraction.document[.expiryDate]
            XCTAssertGreaterThan(expiry, CrewFieldValidator.iso8601String(voyage.arrival),
                                 "\(extraction.document.documentNumber) expires before the voyage ends")
        }

        let base = ExportService.fileNameStem(boat: boat, trip: trip)
        try ExportService.exportCSV(to: output.appending(path: "\(base).csv"), trip: trip, boat: boat, rows: rows)
        try ExportService.exportPDF(to: output.appending(path: "\(base).pdf"), trip: trip, boat: boat, rows: rows)

        let csv = String(decoding: try Data(contentsOf: output.appending(path: "\(base).csv")).dropFirst(3), as: UTF8.self)
        print("""

        ===== CREW LIST FROM THE REAL MIO SET =====
        \(csv)
        ----- typed by the operator (\(applied.count)) -----
        \(applied.isEmpty ? "none" : applied.joined(separator: "\n"))
        ----- held back by review (\(stillBlocked.count) of \(files.count)) -----
        \(stillBlocked.isEmpty ? "none" : stillBlocked.joined(separator: "\n"))
        Written to: \(output.path(percentEncoded: false))
        ===========================================
        """)

        // Whatever reaches the crew list must be complete.
        for row in rows {
            XCTAssertFalse(row.fullName.isEmpty, "a nameless row reached the crew list")
            XCTAssertFalse(row.birthDate.isEmpty, "a row with no birth date reached the crew list")
            XCTAssertFalse(row.documentNumber.isEmpty)
            XCTAssertFalse(row.nationality.isEmpty)
        }
        XCTAssertEqual(rows.count + stillBlocked.count, files.count, "every document is either exported or explained")
    }

    /// 18 on the departure date, using the confirmed birth date.
    private func isAdult(_ document: CrewDocument, on date: Date) -> Bool {
        guard let birth = CrewFieldValidator.isoDate(document[.birthDate]) else { return false }
        let years = Calendar(identifier: .gregorian).dateComponents([.year], from: birth, to: date).year ?? 0
        return years >= 18
    }

    // MARK: - Machine-readable report of what the pipeline did

    func testWritesAnExtractionReport() throws {
        let files = try fixtures()
        let output = try outputDirectory()

        var report: [[String: Any]] = []
        for file in files {
            let extraction = try importDocument(file, tripID: UUID())
            var validations: [String: String] = [:]
            for field in CrewField.allCases {
                validations[field.rawValue] = switch extraction.document.validation(of: field) {
                case .valid: "valid"
                case .warning(let message): "warning: \(message)"
                case .invalid(let message): "invalid: \(message)"
                }
            }
            report.append([
                "file": file.lastPathComponent,
                "extraction_risk": extraction.result.risk.rawValue,
                "extraction_reasons": extraction.result.reasons,
                "fields": extraction.result.fields,
                "validation": validations,
                "blocking_fields": extraction.document.blockingFields().map(\.rawValue),
                "ocr_lines": extraction.result.rawText.components(separatedBy: .newlines).count,
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appending(path: "extraction-report.json"), options: .atomic)
        print("Extraction report: \(output.appending(path: "extraction-report.json").path(percentEncoded: false))")
        XCTAssertEqual(report.count, files.count)
    }
}
