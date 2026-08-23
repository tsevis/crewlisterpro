import Foundation
import Security
import XCTest

@testable import CrewListrProMac

/// The message this error carries is the only thing an operator has when the
/// app will not open. "The local encryption key could not be accessed" once
/// covered a locked Keychain, a denied ACL, a full disk and a stale app with
/// the same bundle identifier — four conditions with four different remedies,
/// reported identically. Diagnosing one of them cost an afternoon.
final class StoreErrorTests: XCTestCase {
    func testUnavailableKeyNamesTheStatusItFailedWith() {
        let message = StoreError.unavailableKey(stage: .read, status: errSecInteractionNotAllowed).errorDescription ?? ""
        XCTAssertTrue(message.contains("-25308"), "The numeric OSStatus is what a bug report can be searched on: \(message)")
    }

    func testUnavailableKeyExplainsTheStatusInWords() {
        let message = StoreError.unavailableKey(stage: .read, status: errSecInteractionNotAllowed).errorDescription ?? ""
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("interaction"),
            "macOS already writes a plain explanation of every OSStatus; not showing it wastes it: \(message)"
        )
    }

    /// A failed read means a key exists and cannot be reached. A failed create
    /// means there is no key at all. The remedies are opposites, so the message
    /// has to say which happened.
    func testUnavailableKeyDistinguishesReadingFromCreating() {
        let reading = StoreError.unavailableKey(stage: .read, status: errSecAuthFailed).errorDescription ?? ""
        let creating = StoreError.unavailableKey(stage: .create, status: errSecAuthFailed).errorDescription ?? ""
        XCTAssertNotEqual(reading, creating)
        XCTAssertTrue(reading.localizedCaseInsensitiveContains("existing"), reading)
        XCTAssertTrue(creating.localizedCaseInsensitiveContains("new"), creating)
    }

    /// An unknown code must still reach the operator rather than being dropped
    /// for want of a description.
    func testUnavailableKeyStillReportsAStatusItCannotExplain() {
        let message = StoreError.unavailableKey(stage: .read, status: OSStatus(-999_999)).errorDescription ?? ""
        XCTAssertTrue(message.contains("-999999"), message)
    }

    func testTheOtherStoreErrorsStillDescribeThemselves() {
        XCTAssertEqual(StoreError.invalidPayload.errorDescription, "Encrypted local data could not be decoded.")
        XCTAssertEqual(StoreError.database("disk full").errorDescription, "Encrypted database error: disk full")
    }
}
