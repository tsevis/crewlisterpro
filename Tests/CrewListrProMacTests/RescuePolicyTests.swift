import Foundation
import XCTest
@testable import CrewListrProMac

/// What the local vision model is allowed to contribute, and why the list is
/// this short.
///
/// Measured against two real Ukrainian passports across three prompt versions,
/// six runs in total. The document number was correct every time. Both dates
/// were correct on the shortest prompt. No version ever produced a usable Latin
/// name — and every attempt to make it do so changed how the model read the
/// dates, which it had been reading correctly.
///
/// These tests exist so that widening the rescue is a deliberate act with a
/// failing test attached, rather than a line quietly added to a prompt.
final class RescuePolicyTests: XCTestCase {

    // MARK: - The declared policy

    func testTheRescueOffersDocumentNumberAndTheTwoDates() {
        XCTAssertEqual(CrewField.rescuable, [.documentNumber, .birthDate, .expiryDate])
    }

    /// The name never came back usable. It arrived in Cyrillic — "МІНЧУК" — or
    /// transliterated into something the page does not print: MINCHUK read as
    /// MIHCHYK, pure ASCII, passing every check this app makes.
    func testTheNameIsNotRescuable() {
        XCTAssertFalse(CrewField.rescuable.contains(.fullName))
    }

    /// Nationality and sex are printed bilingually — "УКРАЇНА/UKRAINE", "Ж/F" —
    /// and were never the reason to load a 5 GB model. They are two keystrokes
    /// each, and every field asked for is another field the model can perturb.
    func testNationalityAndSexAreNotRescuable() {
        XCTAssertFalse(CrewField.rescuable.contains(.nationality))
        XCTAssertFalse(CrewField.rescuable.contains(.sex))
    }

    /// Three of the five fields a port authority requires are still the
    /// operator's to type. That is the point: the rescue recovers what it
    /// measurably reads, not what would be convenient.
    func testTheRescueDoesNotCoverEverythingExportNeeds() {
        let missing = CrewField.requiredForExport.filter { !CrewField.rescuable.contains($0) }
        XCTAssertEqual(Set(missing), [.fullName, .nationality, .sex])
    }

    // MARK: - The prompt asks for exactly that

    /// Not asked, rather than asked and discarded. The measured interference
    /// ran the other way: instructing the model about the name changed its
    /// reading of the dates, so the instruction itself is the cost.
    func testThePromptDoesNotAskForTheFieldsWeWillNotUse() {
        for unwanted in [CrewField.fullName, .nationality, .sex] {
            XCTAssertFalse(LlamaVisionRescuer.prompt.contains(unwanted.rawValue),
                           "the prompt still asks for \(unwanted.rawValue); asking is what perturbed the dates")
        }
        XCTAssertFalse(LlamaVisionRescuer.prompt.lowercased().contains("name"))
    }

    func testThePromptAsksForEveryFieldTheRescueWillKeep() {
        for wanted in CrewField.rescuable {
            XCTAssertTrue(LlamaVisionRescuer.prompt.contains(wanted.rawValue),
                          "the prompt does not ask for \(wanted.rawValue), so nothing will fill it")
        }
    }

    /// The prompt still has to say what a date should look like, or the model
    /// answers "19 FEB 83" and the operator retypes what was already recovered.
    func testThePromptStillPinsTheDateFormat() {
        XCTAssertTrue(LlamaVisionRescuer.prompt.contains("YYYY-MM-DD"))
    }

    // MARK: - And the reply is filtered to it anyway

    /// A model that volunteers a name unasked is exactly as wrong as one that
    /// was asked for it, so the policy is enforced on the way back too.
    func testAVolunteeredNameNeverReachesTheDocument() {
        let reply = [
            "full_name": "MIHCHYK OLEKSANDR",
            "nationality": "UKRAINE",
            "sex": "M",
            "document_number": "FH010367",
            "birth_date": "1990-06-29",
        ]
        let usable = LlamaVisionRescuer.usableFields(from: reply)

        XCTAssertEqual(usable, ["document_number": "FH010367", "birth_date": "1990-06-29"])
        XCTAssertNil(usable["full_name"], "MIHCHYK is what a real passport printing MINCHUK produced")
    }

    /// Filtering must not cost the shaping that made the rescue worth having:
    /// what the page prints is not what the app accepts.
    func testTheKeptFieldsAreStillNormalisedAndScriptChecked() {
        let usable = LlamaVisionRescuer.usableFields(from: [
            "document_number": "GB262590",
            "birth_date": "19 FEB 83",
            "expiry_date": "2031-04-17",
        ])
        XCTAssertEqual(usable["birth_date"], "1983-02-19")
        XCTAssertEqual(usable["document_number"], "GB262590")
        XCTAssertEqual(usable["expiry_date"], "2031-04-17")
    }

    func testACyrillicDocumentNumberIsStillDropped() {
        let usable = LlamaVisionRescuer.usableFields(from: ["document_number": "АВ1234567"])
        XCTAssertTrue(usable.isEmpty, "those are Cyrillic А and В; a port authority cannot read that as a number")
    }

    func testAnEmptyValueIsNotOfferedAsARescue() {
        XCTAssertTrue(LlamaVisionRescuer.usableFields(from: ["document_number": "  "]).isEmpty)
    }

    /// Keys the app has no vocabulary for — issuing authority, place of birth —
    /// were already ignored downstream. Now they are dropped where the policy
    /// lives, so "ignored" does not depend on the store remembering to ignore.
    func testKeysOutsideTheVocabularyAreDropped() {
        let usable = LlamaVisionRescuer.usableFields(from: ["place_of_birth": "KYIV", "document_type": "passport"])
        XCTAssertTrue(usable.isEmpty)
    }
}
