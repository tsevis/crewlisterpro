import Foundation
import XCTest
@testable import CrewListrProMac

/// How the model's reply is read.
///
/// One guard used to collapse five different failures and report only the
/// last: a server still warming up answered 503, and the operator was told
/// "the local AI returned something that was not a set of document fields" —
/// false, and it sends them looking in the wrong place.
final class RescueReplyTests: XCTestCase {

    // MARK: - Which failures are worth retrying

    func testAWarmingServerIsRetriedRatherThanReported() {
        for status in [503, 429, 425, 0] {
            XCTAssertTrue(LlamaVisionRescuer.isTransient(status), "\(status) should be retried")
        }
    }

    func testABadRequestIsNotRetriedForever() {
        for status in [400, 401, 404, 500] {
            XCTAssertFalse(LlamaVisionRescuer.isTransient(status), "\(status) will not fix itself")
        }
    }

    func testARefusalNamesItsStatusSoTheCauseIsFindable() {
        let message = RescueError.serverRefused(status: 503).errorDescription ?? ""
        XCTAssertTrue(message.contains("503"), "got: \(message)")
        XCTAssertNotEqual(message, RescueError.unreadableReply.errorDescription,
                          "a refusal and an unreadable reply must not read the same")
    }

    // MARK: - Reading the reply

    func testAPlainObjectDecodes() throws {
        let fields = try LlamaVisionRescuer.decodeFields(from: #"{"full_name":"ANNA MARIA ERIKSSON","sex":"F"}"#)
        XCTAssertEqual(fields["full_name"], "ANNA MARIA ERIKSSON")
        XCTAssertEqual(fields["sex"], "F")
    }

    /// The prompt invites the model to be uncertain, and a model expressing
    /// uncertainty as null used to discard every other field with it.
    func testANullForOneFieldDoesNotDiscardTheRest() throws {
        let fields = try LlamaVisionRescuer.decodeFields(from: #"{"full_name":"GIULIA ROSSI","birth_date":null}"#)
        XCTAssertEqual(fields["full_name"], "GIULIA ROSSI")
        XCTAssertNil(fields["birth_date"], "an unknown value should be absent, not invented")
    }

    func testANumberIsCoercedRatherThanRejected() throws {
        let fields = try LlamaVisionRescuer.decodeFields(from: #"{"document_number":1234567}"#)
        XCTAssertEqual(fields["document_number"], "1234567")
    }

    func testANestedObjectIsDroppedWithoutTakingTheRestWithIt() throws {
        let fields = try LlamaVisionRescuer.decodeFields(from: #"{"full_name":"ERIK LINDQVIST","issuer":{"name":"X"}}"#)
        XCTAssertEqual(fields["full_name"], "ERIK LINDQVIST")
        XCTAssertNil(fields["issuer"])
    }

    /// Local models wrap JSON in a fence often enough that calling it
    /// unreadable would fail on a correct answer.
    func testAFencedReplyIsRead() throws {
        let fenced = "```json\n{\"full_name\":\"YUKI NAKAMURA\"}\n```"
        XCTAssertEqual(try LlamaVisionRescuer.decodeFields(from: fenced)["full_name"], "YUKI NAKAMURA")
    }

    func testProseAroundTheObjectIsIgnored() throws {
        let chatty = "Here are the fields I could read:\n{\"sex\":\"M\"}\nLet me know if you need more."
        XCTAssertEqual(try LlamaVisionRescuer.decodeFields(from: chatty)["sex"], "M")
    }

    func testSomethingWithNoObjectAtAllIsStillUnreadable() {
        XCTAssertThrowsError(try LlamaVisionRescuer.decodeFields(from: "I cannot read this document."))
    }
}
