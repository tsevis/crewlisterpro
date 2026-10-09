import Foundation
import XCTest
@testable import CrewListrProMac

/// What the model returned from two trial passports, and why passing
/// it through unchanged was unsafe.
///
/// Passports print fields twice — "ПРИКЛАДЕНКО/PRYKLADENKO" — and the model transcribes
/// both halves. The consequences are not equal. "Ж/F" fails validation, so the
/// operator retypes it: visible, annoying, safe. A Cyrillic full_name PASSES
/// validation — no digits, long enough, no repeated-letter run — so it can be
/// confirmed and printed on a crew list in a script a port authority will not
/// accept. Silent, and it reaches the harbour.
final class RescuedNameTests: XCTestCase {

    // MARK: - What was actually measured

    func testTheLatinHalfIsTakenWordByWord() {
        // As returned by the model: both halves of each word.
        XCTAssertEqual(LlamaVisionRescuer.latinised("ПРИКЛАДЕНКО/PRYKLADENKO М'ЯТА/MYATA"), "PRYKLADENKO MYATA")
    }

    func testBilingualNationalityAndSexAreReduced() {
        XCTAssertEqual(LlamaVisionRescuer.latinised("УТОПІЯ/UTOPIA"), "UTOPIA")
        XCTAssertEqual(LlamaVisionRescuer.latinised("Ж/F"), "F")
        XCTAssertEqual(LlamaVisionRescuer.latinised("Ч/M"), "M")
    }

    /// The page prints "ПРИКЛАДЕНКО/PRYKLADENKO" and the model answered
    /// "ПРИКЛАДЕНКО/ПРІКЛАДЕНКО" — two Cyrillic spellings, one of them invented. There is
    /// no Latin half to take, so nothing is offered.
    func testAnInventedCyrillicVariantIsRefusedRatherThanPassedOn() {
        XCTAssertNil(LlamaVisionRescuer.latinised("ПРИКЛАДЕНКО/ПРІКЛАДЕНКО М'ЯТА"))
    }

    func testAWhollyNonLatinValueIsRefused() {
        XCTAssertNil(LlamaVisionRescuer.latinised("М'ЯТА"))
        XCTAssertNil(LlamaVisionRescuer.latinised(""))
    }

    // MARK: - Not breaking the ordinary case

    func testAPlainLatinNameIsUntouched() {
        XCTAssertEqual(LlamaVisionRescuer.latinised("ANNA MARIA ERIKSSON"), "ANNA MARIA ERIKSSON")
    }

    func testPunctuationCommonInPrintedNamesSurvives() {
        XCTAssertEqual(LlamaVisionRescuer.latinised("O'NEILL-SMITH"), "O'NEILL-SMITH")
        XCTAssertEqual(LlamaVisionRescuer.latinised("ST. JOHN"), "ST. JOHN")
    }

    /// A name is not a number, and a value with digits in it is not a name the
    /// MRZ parser would accept either.
    func testDigitsAreNotAcceptedAsALatinName() {
        XCTAssertNil(LlamaVisionRescuer.latinised("PRYKLADENKO 12345"))
    }

    /// But a document number is mostly digits. Excluding them everywhere
    /// silently dropped "AB1234567" from a rescue that had read it correctly —
    /// caught by running the real model, not by any unit test here.
    func testADocumentNumberKeepsItsDigits() {
        XCTAssertEqual(LlamaVisionRescuer.latinised("AB1234567", allowingDigits: true), "AB1234567")
        XCTAssertEqual(LlamaVisionRescuer.latinised("QX654321", allowingDigits: true), "QX654321")
    }

    func testADocumentNumberIsStillRefusedIfItIsNotLatin() {
        XCTAssertNil(LlamaVisionRescuer.latinised("АВ1234567", allowingDigits: true),
                     "those are Cyrillic А and В, which a port authority cannot read as a passport number")
    }

    // MARK: - The reason this matters

    /// The gap that made this dangerous rather than merely wrong: validation
    /// has no opinion about script, so an unusable name arrives confirmable.
    /// This canary has fired, deliberately.
    ///
    /// It used to assert that validation did NOT block a Cyrillic name, so that
    /// removing `latinised()` could not silently open the door. The operator has
    /// since decided a crew list carries Latin only, so validation blocks it too
    /// and `latinised()` is no longer the sole guard. Both now hold the line.
    func testACyrillicNameIsBlockedByValidationAsWell() {
        let validation = CrewFieldValidator.validate(.fullName, value: "ПРИКЛАДЕНКО М'ЯТА")
        XCTAssertTrue(validation.isBlocking,
                      "a crew list carries the Latin spelling; validation must refuse anything else")
    }
}
