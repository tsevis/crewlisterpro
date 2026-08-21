import Foundation
import XCTest
@testable import CrewListrProMac

/// What the model returned from two real Ukrainian passports, and why passing
/// it through unchanged was unsafe.
///
/// Passports print fields twice — "ЦИГІПА/TSYHIPA" — and the model transcribes
/// both halves. The consequences are not equal. "Ж/F" fails validation, so the
/// operator retypes it: visible, annoying, safe. A Cyrillic full_name PASSES
/// validation — no digits, long enough, no repeated-letter run — so it can be
/// confirmed and printed on a crew list in a script a port authority will not
/// accept. Silent, and it reaches the harbour.
final class RescuedNameTests: XCTestCase {

    // MARK: - What was actually measured

    func testTheLatinHalfIsTakenWordByWord() {
        // GB262590, as returned by the model.
        XCTAssertEqual(LlamaVisionRescuer.latinised("ЦИГІПА/TSYHIPA DAP'Я/DARIA"), "TSYHIPA DARIA")
    }

    func testBilingualNationalityAndSexAreReduced() {
        XCTAssertEqual(LlamaVisionRescuer.latinised("УКРАЇНА/UKRAINE"), "UKRAINE")
        XCTAssertEqual(LlamaVisionRescuer.latinised("Ж/F"), "F")
        XCTAssertEqual(LlamaVisionRescuer.latinised("Ч/M"), "M")
    }

    /// FH010367: the page prints "МІНЧУК/MINCHUK" and the model answered
    /// "МІНЧУК/МИНЧУК" — two Cyrillic spellings, one of them invented. There is
    /// no Latin half to take, so nothing is offered.
    func testAnInventedCyrillicVariantIsRefusedRatherThanPassedOn() {
        XCTAssertNil(LlamaVisionRescuer.latinised("МІНЧУК/МИНЧУК ОЛЕКСАНДР"))
    }

    func testAWhollyNonLatinValueIsRefused() {
        XCTAssertNil(LlamaVisionRescuer.latinised("ОЛЕКСАНДР"))
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
        XCTAssertNil(LlamaVisionRescuer.latinised("MINCHUK 12345"))
    }

    /// But a document number is mostly digits. Excluding them everywhere
    /// silently dropped "AB1234567" from a rescue that had read it correctly —
    /// caught by running the real model, not by any unit test here.
    func testADocumentNumberKeepsItsDigits() {
        XCTAssertEqual(LlamaVisionRescuer.latinised("AB1234567", allowingDigits: true), "AB1234567")
        XCTAssertEqual(LlamaVisionRescuer.latinised("GB262590", allowingDigits: true), "GB262590")
    }

    func testADocumentNumberIsStillRefusedIfItIsNotLatin() {
        XCTAssertNil(LlamaVisionRescuer.latinised("АВ1234567", allowingDigits: true),
                     "those are Cyrillic А and В, which a port authority cannot read as a passport number")
    }

    // MARK: - The reason this matters

    /// The gap that made this dangerous rather than merely wrong: validation
    /// has no opinion about script, so an unusable name arrives confirmable.
    func testACyrillicNameWouldOtherwiseHavePassedValidation() {
        let validation = CrewFieldValidator.validate(.fullName, value: "ЦИГІПА ДАР'Я")
        XCTAssertFalse(validation.isBlocking,
                       "if this ever starts blocking, latinised() is no longer the only thing standing between a Cyrillic name and a crew list")
    }
}
