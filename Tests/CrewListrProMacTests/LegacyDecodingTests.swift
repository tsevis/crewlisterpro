import Foundation
import XCTest
@testable import CrewListrProMac

/// What the app must survive reading off a disk written by an older build.
///
/// This suite exists because the repository has already shipped the bug it
/// guards against, twice over. Swift's synthesised `Codable` does NOT fall back
/// to a property's default when a key is absent — it throws `keyNotFound`. A
/// `RawRepresentable` enum throws a second way, on any value it does not
/// recognise, which is what a *newer* build writing a *new* case does to an
/// older one. Either throw travels all the way up: `SecureStore` catches it as
/// `invalidPayload`, and the operator is told their data is corrupt when in
/// fact every byte of it is intact.
///
/// The trap that hid it: a round-trip test that encodes and decodes a *new*
/// value passes trivially and proves nothing about the records already on disk.
/// Every test here therefore decodes a JSON **literal** in an older shape —
/// input that no code in this repository produced.
///
/// The governing rule, which the tests below pin from both sides:
///
/// - **Descriptive fields are salvaged.** A missing name, flag, risk level or
///   confirmation set costs that one value, and it always falls back in the
///   direction that makes the operator look rather than let something through.
/// - **Identity is never fabricated.** `id`, `tripID`, `personID` and `boatID`
///   are what join a document to its trip and its person. Inventing a fresh
///   UUID for a missing one would silently orphan a record — a passport
///   attached to no trip — so those still throw.
final class LegacyDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Boat

    /// A boat written before flag, port and registration number existed.
    func testABoatFromBeforeItsRegistrationFieldsDecodes() throws {
        let boat = try decode(Boat.self, #"{"id":"\#(UUID().uuidString)","name":"S/Y ANEMOS"}"#)
        XCTAssertEqual(boat.name, "S/Y ANEMOS")
        XCTAssertEqual(boat.flag, "")
        XCTAssertEqual(boat.registrationPort, "")
        XCTAssertEqual(boat.registrationNumber, "")
    }

    /// A nameless boat must read as unnamed, not as a valid yacht: the name is
    /// printed in the crew list's header box, and `isComplete` is the gate that
    /// stops an export going out with an empty one.
    func testABoatWithNoNameIsIncompleteRatherThanUndecodable() throws {
        let boat = try decode(Boat.self, #"{"id":"\#(UUID().uuidString)"}"#)
        XCTAssertFalse(boat.isComplete, "a nameless boat must not pass the export gate")
    }

    func testABoatWithNoIdentityIsRejected() {
        XCTAssertThrowsError(try decode(Boat.self, #"{"name":"S/Y ANEMOS"}"#),
                             "a fabricated id would orphan every trip pointing at this boat")
    }

    // MARK: - CrewPerson

    func testAPersonFromBeforeVerificationExistedDecodesAsPending() throws {
        let person = try decode(CrewPerson.self, #"{"id":"\#(UUID().uuidString)","fullName":"YUKI NAKAMURA"}"#)
        XCTAssertEqual(person.fullName, "YUKI NAKAMURA")
        XCTAssertEqual(person.verification, .pending, "unreviewed is the safe reading")
        XCTAssertNil(person.birthDate)
    }

    /// A state written by a future build must not make this one unreadable.
    func testAnUnknownVerificationStateReadsAsPending() throws {
        let person = try decode(CrewPerson.self, #"{"id":"\#(UUID().uuidString)","verification":"provisional"}"#)
        XCTAssertEqual(person.verification, .pending)
    }

    func testAPersonWithNoIdentityIsRejected() {
        XCTAssertThrowsError(try decode(CrewPerson.self, #"{"fullName":"YUKI NAKAMURA"}"#))
    }

    // MARK: - CrewDocument

    /// The oldest shape: identity, a file name, and nothing else.
    func testADocumentFromBeforeEveryOptionalFieldDecodes() throws {
        let json = #"""
        {"id":"\#(UUID().uuidString)","tripID":"\#(UUID().uuidString)","personID":"\#(UUID().uuidString)",
         "originalName":"passport.jpeg","encryptedFileName":"a.bin"}
        """#
        let document = try decode(CrewDocument.self, json)
        XCTAssertEqual(document.originalName, "passport.jpeg")
        XCTAssertEqual(document.documentType, "unknown")
        XCTAssertEqual(document.risk, .review)
        XCTAssertTrue(document.riskReasons.isEmpty)
        XCTAssertTrue(document.fields.isEmpty)
        XCTAssertTrue(document.verifiedFields.isEmpty)
        XCTAssertNil(document.suggestedFields)
        XCTAssertTrue(document.imageRevisions.isEmpty)
    }

    /// The direction of the fallback is the whole point. A document whose
    /// confirmations could not be read must be treated as unconfirmed, so it is
    /// held back for review — never waved through onto a crew list.
    func testADocumentWithUnreadableConfirmationsFailsClosed() throws {
        let json = #"""
        {"id":"\#(UUID().uuidString)","tripID":"\#(UUID().uuidString)","personID":"\#(UUID().uuidString)",
         "originalName":"p.jpeg","encryptedFileName":"a.bin",
         "fields":{"full_name":"YUKI NAKAMURA","document_number":"W1357924D","nationality":"UTOPIAN",
                   "birth_date":"1984-12-16","sex":"F","expiry_date":"2031-01-01"}}
        """#
        let document = try decode(CrewDocument.self, json)
        XCTAssertFalse(document.canExport(), "an unreadable confirmation set must block, not clear")
        XCTAssertEqual(document.reviewStatus(), .awaitingReview)
    }

    /// A risk level this build has never heard of must mean "look at it".
    func testAnUnknownRiskLevelReadsAsNeedingReview() throws {
        let json = #"""
        {"id":"\#(UUID().uuidString)","tripID":"\#(UUID().uuidString)","personID":"\#(UUID().uuidString)",
         "originalName":"p.jpeg","encryptedFileName":"a.bin","risk":"catastrophic"}
        """#
        XCTAssertEqual(try decode(CrewDocument.self, json).risk, .review)
    }

    /// `.high` is the one risk level that blocks export outright. An unknown
    /// value must not be silently downgraded to `.low`, which would clear it.
    func testAnUnknownRiskLevelIsNeverDowngradedToCleared() throws {
        let json = #"""
        {"id":"\#(UUID().uuidString)","tripID":"\#(UUID().uuidString)","personID":"\#(UUID().uuidString)",
         "originalName":"p.jpeg","encryptedFileName":"a.bin","risk":"???"}
        """#
        XCTAssertNotEqual(try decode(CrewDocument.self, json).risk, .low)
    }

    func testADocumentWithNoTripIsRejected() {
        let json = #"""
        {"id":"\#(UUID().uuidString)","personID":"\#(UUID().uuidString)",
         "originalName":"p.jpeg","encryptedFileName":"a.bin"}
        """#
        XCTAssertThrowsError(try decode(CrewDocument.self, json),
                             "a document belonging to no trip is worse than one that fails to load")
    }

    func testADocumentWithNoPersonIsRejected() {
        let json = #"""
        {"id":"\#(UUID().uuidString)","tripID":"\#(UUID().uuidString)",
         "originalName":"p.jpeg","encryptedFileName":"a.bin"}
        """#
        XCTAssertThrowsError(try decode(CrewDocument.self, json))
    }

    // MARK: - CrewAssignment

    func testAnAssignmentFromBeforeNotesExistedDecodes() throws {
        let json = #"""
        {"id":"\#(UUID().uuidString)","tripID":"\#(UUID().uuidString)","personID":"\#(UUID().uuidString)"}
        """#
        let assignment = try decode(CrewAssignment.self, json)
        XCTAssertEqual(assignment.role, .passenger)
        XCTAssertEqual(assignment.notes, "")
    }

    /// Defaulting to passenger is the safe direction: a trip with no skipper is
    /// blocked from export and says so, whereas inventing a skipper would let a
    /// crew list out naming the wrong person as master of the vessel.
    func testAnUnknownRoleReadsAsPassenger() throws {
        let json = #"""
        {"id":"\#(UUID().uuidString)","tripID":"\#(UUID().uuidString)","personID":"\#(UUID().uuidString)",
         "role":"deckhand"}
        """#
        XCTAssertEqual(try decode(CrewAssignment.self, json).role, .passenger)
    }

    // MARK: - AppData salvage

    /// One unreadable record must cost one record, not the database.
    ///
    /// `AppData` already tolerated a missing *collection*, but decoding
    /// `[CrewDocument]` is all-or-nothing: a single malformed element threw and
    /// took every trip, person and confirmation in the store down with it.
    func testOneUnreadableDocumentDoesNotTakeTheStoreDown() throws {
        let good = UUID().uuidString
        let json = #"""
        {"schemaVersion":2,
         "documents":[
           {"id":"\#(good)","tripID":"\#(UUID().uuidString)","personID":"\#(UUID().uuidString)",
            "originalName":"good.jpeg","encryptedFileName":"a.bin"},
           {"originalName":"orphan.jpeg","encryptedFileName":"b.bin"}
         ]}
        """#
        let data = try decode(AppData.self, json)
        XCTAssertEqual(data.documents.count, 1, "the readable document must survive its neighbour")
        XCTAssertEqual(data.documents.first?.id.uuidString, good)
    }

    /// Salvage must never be silent. A dropped record is a passport that has
    /// vanished from a trip, and the operator has to be told.
    func testADroppedRecordIsReported() throws {
        let json = #"""
        {"schemaVersion":2,
         "documents":[{"originalName":"orphan.jpeg","encryptedFileName":"b.bin"}],
         "boats":[{"name":"S/Y ANEMOS"}]}
        """#
        let data = try decode(AppData.self, json)
        XCTAssertTrue(data.documents.isEmpty)
        XCTAssertTrue(data.boats.isEmpty)
        XCTAssertEqual(data.decodingLosses.count, 2, "both dropped records must be accounted for")
        XCTAssertTrue(data.decodingLosses.contains { $0.contains("document") },
                      "the report must name what was lost: \(data.decodingLosses)")
        XCTAssertTrue(data.decodingLosses.contains { $0.contains("boat") })
    }

    func testAWhollyReadableStoreReportsNoLosses() throws {
        let json = #"""
        {"schemaVersion":2,"boats":[{"id":"\#(UUID().uuidString)","name":"S/Y ANEMOS"}]}
        """#
        XCTAssertTrue(try decode(AppData.self, json).decodingLosses.isEmpty)
    }

    /// A payload written before versioning still decodes as version 1.
    func testAnUnversionedPayloadIsStillVersionOne() throws {
        XCTAssertEqual(try decode(AppData.self, "{}").schemaVersion, 1)
    }

    /// The salvage report is state about *this* read, not a fact about the
    /// store. Writing it would persist a complaint about data already fixed.
    func testTheSalvageReportIsNeverWrittenBack() throws {
        var data = AppData(boats: [Boat(name: "S/Y ANEMOS")])
        data.decodingLosses = ["1 boat could not be read"]
        let encoded = try JSONEncoder().encode(data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["decodingLosses"])
        XCTAssertTrue(try JSONDecoder().decode(AppData.self, from: encoded).decodingLosses.isEmpty)
    }

    // MARK: - The loss has to reach the operator

    /// Salvage that nobody is told about is just quiet data loss. A document
    /// dropped on load is a passport missing from a trip, and the operator has
    /// to learn it here rather than when a port authority counts heads.
    /// Covers the message the operator actually sees, not the wiring.
    ///
    /// A lossy read cannot be staged through `SecureStore`: it only ever
    /// persists a well-formed `AppData` it encoded itself, and the database is
    /// SQLCipher-encrypted, so there is no way to plant a malformed record
    /// behind it. What is testable is that a salvaged read produces a message
    /// naming what went missing. That `load()` and `restoreBackup()` call this
    /// is a single line in each, verified by reading them.
    @MainActor
    func testASalvagedReadProducesAMessageNamingWhatWasLost() {
        let store = CrewStore(secureStore: nil)
        store.data.decodingLosses = ["1 document could not be read and was left out."]

        store.reportDecodingLosses()

        let message = store.errorMessage ?? ""
        XCTAssertTrue(message.contains("document"),
                      "the operator must be told what kind of record went missing: \(message)")
        XCTAssertTrue(message.contains("Earlier versions"),
                      "and pointed at the snapshot that may still hold it: \(message)")
    }

    /// A clean read must not raise an alarm about nothing.
    @MainActor
    func testACleanReadSaysNothing() {
        let store = CrewStore(secureStore: nil)
        store.reportDecodingLosses()
        XCTAssertNil(store.errorMessage)
    }

    // MARK: - No regression on the current shape

    /// Hardening the reader must not change what the app writes, or every
    /// record it saves from now on would be a new migration problem.
    func testTodaysShapeStillRoundTripsUnchanged() throws {
        var document = CrewDocument(tripID: UUID(), personID: UUID(), originalName: "p.jpeg", encryptedFileName: "a.bin")
        document[.fullName] = "YUKI NAKAMURA"
        document.verifiedFields.insert(CrewField.fullName.rawValue)
        document.markSuggested(.nationality)
        document.risk = .low

        let data = AppData(
            boats: [Boat(name: "S/Y ANEMOS", flag: "GRC", registrationPort: "LAVRIO", registrationNumber: "GR-4471-P")],
            trips: [Trip(boatID: UUID(), departureDate: .now, returnDate: .now)],
            people: [CrewPerson(fullName: "YUKI NAKAMURA", verification: .verified)],
            documents: [document],
            assignments: [CrewAssignment(tripID: UUID(), personID: UUID(), role: .skipper)]
        )

        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored.boats, data.boats)
        XCTAssertEqual(restored.trips, data.trips)
        XCTAssertEqual(restored.people, data.people)
        XCTAssertEqual(restored.documents, data.documents)
        XCTAssertEqual(restored.assignments, data.assignments)
        XCTAssertEqual(restored.schemaVersion, AppData.currentSchemaVersion)
        XCTAssertTrue(restored.decodingLosses.isEmpty)
    }
}
