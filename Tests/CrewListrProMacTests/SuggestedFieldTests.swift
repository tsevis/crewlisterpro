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
        subject.markSuggested(.fullName)
        XCTAssertTrue(subject.isSuggested(.fullName))
    }

    /// Typing over a suggestion makes the value the operator's own, so the
    /// warning stops applying — it would be false, and a warning that is
    /// sometimes false stops being read.
    func testTypingOverASuggestionClearsIt() {
        var subject = document()
        subject[.fullName] = "MIHCHYK"
        subject.markSuggested(.fullName)

        subject[.fullName] = "MINCHUK"

        XCTAssertFalse(subject.isSuggested(.fullName), "the operator typed this; it is not the model's any more")
        XCTAssertFalse(subject.isVerified(.fullName), "and it still has to be confirmed")
    }

    /// The reason marking is necessary rather than belt-and-braces: nothing
    /// else in the stack objects to a wrong-but-plausible name.
    func testTheMeasuredWrongNamesPassEveryOtherCheck() {
        // Both produced by the model from real passports, both wrong, both
        // indistinguishable from a correct answer by anything in this app.
        for wrong in ["MIHCHYK", "TSYHHPA"] {
            XCTAssertNotNil(LlamaVisionRescuer.latinised(wrong),
                            "\(wrong) is ASCII, so the Latin guard has no objection")
            XCTAssertFalse(CrewFieldValidator.validate(.fullName, value: wrong).isBlocking,
                           "and validation has none either — marking is the only thing left")
        }
    }

    /// The more alarming one, because nobody reads a date twice.
    ///
    /// A passport printing 29 ЧЕР (June) 1990 produced 1990-04-29. It is a
    /// valid date, in the right format, two months wrong. Validation cannot
    /// object — an April date is as plausible as a June one — and it only
    /// failed to reach the crew list because the MRZ had already filled the
    /// field and the rescue fills empties. On a document whose MRZ fails
    /// entirely, which is the case the rescue exists for, nothing catches it.
    func testTheMeasuredWrongDatePassesEveryOtherCheck() {
        let wrong = "1990-04-29"
        XCTAssertFalse(CrewFieldValidator.validate(.birthDate, value: wrong).isBlocking,
                       "a wrong date in the right format is exactly what validation cannot see")
        XCTAssertNotEqual(wrong, "1990-06-29", "the truth, for the record")
    }

    func testSuggestionsSurviveEncodingSoTheWarningOutlastsARelaunch() throws {
        var subject = document()
        subject[.fullName] = "MIHCHYK"
        subject.markSuggested(.fullName)

        let restored = try JSONDecoder().decode(CrewDocument.self, from: JSONEncoder().encode(subject))
        XCTAssertTrue(restored.isSuggested(.fullName), "a relaunch must not quietly launder a suggestion into a fact")
    }
}
