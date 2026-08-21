import Foundation
import XCTest
@testable import CrewListrProMac

/// A value from the local model must never be indistinguishable from one the
/// machine-readable zone produced.
///
/// Measured on a real Ukrainian passport photographed sideways: the page prints
/// MINCHUK and the model returned MIHCHYK. Pure ASCII, so the Latin guard
/// accepts it; no digits and long enough, so validation accepts it. Nothing in
/// the stack can tell it from a correct name, and the operator asked to confirm
/// it is reading the same unreadable line the model guessed from.
///
/// Marking it is not a fix for the model being wrong. It is what makes being
/// wrong visible instead of silent.
final class SuggestedFieldTests: XCTestCase {

    private func document() -> CrewDocument {
        CrewDocument(tripID: UUID(), personID: UUID(), originalName: "a.jpeg", encryptedFileName: "a.bin")
    }

    func testAFieldIsNotSuggestedUntilAModelProposesIt() {
        var subject = document()
        subject[.fullName] = "ANNA MARIA ERIKSSON"
        XCTAssertFalse(subject.isSuggested(.fullName))
    }

    func testASuggestedFieldSaysSo() {
        var subject = document()
        subject[.fullName] = "MIHCHYK"
        subject.suggestedFields.insert(CrewField.fullName.rawValue)
        XCTAssertTrue(subject.isSuggested(.fullName))
    }

    /// Typing over a suggestion makes the value the operator's own, so the
    /// warning stops applying — it would be false, and a warning that is
    /// sometimes false stops being read.
    func testTypingOverASuggestionClearsIt() {
        var subject = document()
        subject[.fullName] = "MIHCHYK"
        subject.suggestedFields.insert(CrewField.fullName.rawValue)

        subject[.fullName] = "MINCHUK"

        XCTAssertFalse(subject.isSuggested(.fullName), "the operator typed this; it is not the model's any more")
        XCTAssertFalse(subject.isVerified(.fullName), "and it still has to be confirmed")
    }

    /// The reason marking is necessary rather than belt-and-braces: nothing
    /// else in the stack objects to a wrong-but-plausible name.
    func testTheMeasuredWrongNamePassesEveryOtherCheck() {
        XCTAssertNotNil(LlamaVisionRescuer.latinised("MIHCHYK"),
                        "it is ASCII, so the Latin guard has no objection")
        XCTAssertFalse(CrewFieldValidator.validate(.fullName, value: "MIHCHYK").isBlocking,
                       "and validation has none either — marking is the only thing left")
    }

    func testSuggestionsSurviveEncodingSoTheWarningOutlastsARelaunch() throws {
        var subject = document()
        subject[.fullName] = "MIHCHYK"
        subject.suggestedFields.insert(CrewField.fullName.rawValue)

        let restored = try JSONDecoder().decode(CrewDocument.self, from: JSONEncoder().encode(subject))
        XCTAssertTrue(restored.isSuggested(.fullName), "a relaunch must not quietly launder a suggestion into a fact")
    }
}
