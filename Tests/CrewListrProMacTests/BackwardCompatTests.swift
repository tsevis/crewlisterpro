import Foundation
import XCTest
@testable import CrewListrProMac

/// A document stored before today must still decode today.
final class BackwardCompatTests: XCTestCase {

    /// Exactly the shape the store held before `suggestedFields` was added.
    func testADocumentStoredBeforeSuggestedFieldsStillDecodes() throws {
        let legacy = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "tripID":"22222222-2222-2222-2222-222222222222",
         "personID":"33333333-3333-3333-3333-333333333333",
         "originalName":"a.jpeg","encryptedFileName":"a.bin",
         "documentNumber":"AB1234567","documentType":"passport",
         "risk":"review","riskReasons":[],
         "fields":{"full_name":"ANNA MARIA ERIKSSON"},
         "verifiedFields":[],"imageRevisions":[]}
        """.data(using: .utf8)!

        let document = try JSONDecoder().decode(CrewDocument.self, from: legacy)
        XCTAssertEqual(document[.fullName], "ANNA MARIA ERIKSSON")
        XCTAssertFalse(document.isSuggested(.fullName), "an old document has no suggestions, not a decode failure")
    }
}
