import Foundation
import XCTest
@testable import CrewListrProMac

/// Tests for the export gate, field validation and the persisted shapes.
final class ModelTests: XCTestCase {

    /// 2026-08-20, so validation results do not drift with the wall clock.
    private let today = Date(timeIntervalSince1970: 1_787_184_000)

    private func completeDocument() -> CrewDocument {
        var document = CrewDocument(tripID: UUID(), personID: UUID(), originalName: "a.jpeg", encryptedFileName: "a.bin")
        document[.fullName] = "YUKI NAKAMURA"
        document[.documentNumber] = "W1357924D"
        document[.nationality] = "UKRAINIAN"
        document[.birthDate] = "1984-12-16"
        document[.sex] = "F"
        document[.expiryDate] = "2027-07-22"
        return document
    }

    private func verifyAll(_ document: inout CrewDocument) {
        for field in CrewField.requiredForExport { document.verifiedFields.insert(field.rawValue) }
    }

    // MARK: - The export gate

    func testAFullyConfirmedDocumentCanExport() {
        var document = completeDocument()
        verifyAll(&document)
        XCTAssertTrue(document.canExport(today: today))
        XCTAssertEqual(document.reviewStatus(today: today), .cleared)
    }

    func testAFreshlyImportedDocumentCannotExport() {
        let document = completeDocument()
        XCTAssertFalse(document.canExport(today: today))
        XCTAssertEqual(document.reviewStatus(today: today), .awaitingReview)
    }

    /// The old gate accepted any non-empty `verifiedFields`, so one confirmed
    /// field cleared a document whose other four were never looked at.
    func testConfirmingOneFieldDoesNotClearTheDocument() {
        var document = completeDocument()
        document.verifiedFields.insert(CrewField.nationality.rawValue)
        XCTAssertFalse(document.canExport(today: today))
        XCTAssertEqual(document.reviewStatus(today: today), .inProgress)
        XCTAssertEqual(Set(document.blockingFields(today: today)), [.fullName, .documentNumber, .birthDate, .sex])
    }

    func testAStaleVerificationKeyDoesNotSatisfyTheGate() {
        var document = completeDocument()
        document.verifiedFields = ["a_field_that_no_longer_exists"]
        XCTAssertFalse(document.canExport(today: today))
    }

    func testARejectedDocumentCannotExport() {
        var document = completeDocument()
        verifyAll(&document)
        document.risk = .high
        XCTAssertFalse(document.canExport(today: today))
        XCTAssertEqual(document.reviewStatus(today: today), .rejected)
    }

    func testAConfirmedButInvalidFieldStillBlocks() {
        var document = completeDocument()
        verifyAll(&document)
        document.fields[CrewField.sex.rawValue] = "Q"   // bypass the subscript, which would clear verification
        XCTAssertFalse(document.canExport(today: today), "an invalid value cannot ride on a stale confirmation")
    }

    func testEditingAFieldRetractsItsConfirmation() {
        var document = completeDocument()
        verifyAll(&document)
        XCTAssertTrue(document.isVerified(.fullName))
        document[.fullName] = "YUKI NAKAMURA-LINDQVIST"
        XCTAssertFalse(document.isVerified(.fullName), "a corrected value must be re-confirmed")
        XCTAssertFalse(document.canExport(today: today))
    }

    func testProgressReflectsConfirmedRequiredFields() {
        var document = completeDocument()
        XCTAssertEqual(document.reviewProgress, 0)
        document.verifiedFields.insert(CrewField.fullName.rawValue)
        XCTAssertEqual(document.reviewProgress, 0.2, accuracy: 0.001)
        verifyAll(&document)
        XCTAssertEqual(document.reviewProgress, 1, accuracy: 0.001)
    }

    func testTheDocumentNumberMirrorIsKeptInStep() {
        var document = completeDocument()
        document[.documentNumber] = "Y7654321B"
        XCTAssertEqual(document.documentNumber, "Y7654321B")
    }

    // MARK: - Field validation

    func testARequiredFieldLeftEmptyBlocks() {
        XCTAssertTrue(CrewFieldValidator.validate(.fullName, value: "", today: today).isBlocking)
        XCTAssertTrue(CrewFieldValidator.validate(.birthDate, value: "  ", today: today).isBlocking)
    }

    func testAnOptionalFieldLeftEmptyIsFine() {
        XCTAssertEqual(CrewFieldValidator.validate(.expiryDate, value: "", today: today), .valid)
    }

    func testImpossibleCalendarDatesAreRejected() {
        for value in ["1974-99-12", "1984-02-31", "not-a-date", "84-12-16", "1984/12/16"] {
            XCTAssertTrue(CrewFieldValidator.validate(.birthDate, value: value, today: today).isBlocking, value)
        }
    }

    func testAFutureBirthDateIsRejected() {
        XCTAssertTrue(CrewFieldValidator.validate(.birthDate, value: "2030-01-01", today: today).isBlocking)
    }

    /// The MRZ century pivot turns a 2035 expiry into 1935; validation catches
    /// it at the point where it would otherwise reach a port authority.
    func testAnExpiredDocumentWarnsButDoesNotBlock() {
        let result = CrewFieldValidator.validate(.expiryDate, value: "1935-07-03", today: today)
        XCTAssertEqual(result, .warning("Document has expired."))
        XCTAssertFalse(result.isBlocking)
    }

    func testAValidFutureExpiryPasses() {
        XCTAssertEqual(CrewFieldValidator.validate(.expiryDate, value: "2035-07-03", today: today), .valid)
    }

    func testSexAcceptsOnlyMFX() {
        for value in ["M", "F", "X", "m", "f"] {
            XCTAssertFalse(CrewFieldValidator.validate(.sex, value: value, today: today).isBlocking, value)
        }
        for value in ["Q", "MALE", "1"] {
            XCTAssertTrue(CrewFieldValidator.validate(.sex, value: value, today: today).isBlocking, value)
        }
    }

    func testOCRNoiseInANameIsFlagged() {
        let result = CrewFieldValidator.validate(.fullName, value: "YUKI KKKKKKKRKRS NAKAMURA", today: today)
        XCTAssertEqual(result, .warning("Looks like OCR noise — check against the document."))
    }

    func testACleanNamePasses() {
        XCTAssertEqual(CrewFieldValidator.validate(.fullName, value: "ANNA MARIA ERIKSSON", today: today), .valid)
    }

    func testADigitInANameIsRejected() {
        let result = CrewFieldValidator.validate(.fullName, value: "ANNA 3RIKSSON", today: today)
        XCTAssertEqual(result, .invalid("A name cannot contain digits."))
        XCTAssertTrue(result.isBlocking, "OCR debris must not reach a crew list")
    }

    func testISORoundTrip() throws {
        let date = try XCTUnwrap(CrewFieldValidator.isoDate("1984-12-16"))
        XCTAssertEqual(CrewFieldValidator.iso8601String(date), "1984-12-16")
    }

    // MARK: - Crew list projection

    /// Export reads the document's own fields, so a correction always lands on
    /// the crew list. The old exporter read a `CrewPerson` copy taken at import.
    func testTheCrewRowIsProjectedFromTheDocument() {
        var document = completeDocument()
        document[.fullName] = "CORRECTED NAME"
        let row = CrewListRow(document: document, role: .skipper)
        XCTAssertEqual(row.fullName, "CORRECTED NAME")
        XCTAssertEqual(row.birthDate, "1984-12-16")
        XCTAssertEqual(row.role, .skipper)
    }

    // MARK: - Persistence shapes

    func testAppDataCarriesASchemaVersion() throws {
        let json = try JSONEncoder().encode(AppData())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, AppData.currentSchemaVersion)
    }

    func testAPayloadWrittenBeforeVersioningDecodesAsVersionOne() throws {
        let legacy = Data("{\"boats\":[],\"trips\":[],\"people\":[],\"documents\":[],\"assignments\":[]}".utf8)
        let decoded = try JSONDecoder().decode(AppData.self, from: legacy)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testAppDataRoundTripsThroughJSON() throws {
        let boat = Boat(name: "S/Y ELPIDA", flag: "GRC", registrationPort: "PIRAEUS", registrationNumber: "1234")
        let trip = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        var document = completeDocument()
        verifyAll(&document)
        document.imageRevisions = ["r1.bin", "r2.bin"]
        let data = AppData(boats: [boat], trips: [trip], people: [], documents: [document],
                           assignments: [CrewAssignment(tripID: trip.id, personID: document.personID, role: .skipper)])

        let decoded = try JSONDecoder().decode(AppData.self, from: try JSONEncoder().encode(data))
        XCTAssertEqual(decoded.boats.first?.registrationPort, "PIRAEUS")
        XCTAssertEqual(decoded.documents.first?.verifiedFields.count, CrewField.requiredForExport.count)
        XCTAssertEqual(decoded.documents.first?.imageRevisions, ["r1.bin", "r2.bin"])
        XCTAssertEqual(decoded.assignments.first?.role, .skipper)
        XCTAssertTrue(decoded.documents.first?.canExport(today: today) ?? false)
    }

    func testDecodingRejectsATruncatedPayload() {
        XCTAssertThrowsError(try JSONDecoder().decode(AppData.self, from: Data("{\"boats\":[{\"name\"".utf8)))
    }

    func testABoatKeepsItsPlaceholderMarkedIncomplete() {
        XCTAssertFalse(Boat(name: Boat.placeholderName).isComplete)
        XCTAssertFalse(Boat(name: "   ").isComplete)
        XCTAssertTrue(Boat(name: "S/Y ELPIDA").isComplete)
    }

    func testEnumerationRawValuesAreStable() {
        XCTAssertEqual(VerificationState.allCases.map(\.rawValue), ["pending", "verified", "rejected"])
        XCTAssertEqual(CrewRole.allCases.map(\.rawValue), ["skipper", "passenger"])
        XCTAssertEqual(RiskLevel.allCases.map(\.rawValue), ["low", "review", "high"])
    }

    func testCrewFieldKeysMatchTheExtractionVocabulary() {
        XCTAssertEqual(Set(CrewField.allCases.map(\.rawValue)),
                       ["full_name", "document_number", "nationality", "birth_date", "sex", "expiry_date", "document_type"])
    }
}
