import Foundation
import XCTest
@testable import CrewListrProMac

/// What the local vision model is allowed to contribute, and why the list is
/// this short.
///
/// Measured against five real Ukrainian passports and then checked against the
/// app's own MRZ-derived export of the same documents: the document number was
/// correct 5 times out of 5, the birth date 4 out of 5, the expiry date 3 out
/// of 5. No prompt version ever produced a usable Latin name — and every
/// attempt to make it do so changed how the model read the dates.
///
/// The rescue is now the document number and nothing else. The dates went on
/// those figures: three wrong values in ten, two of them the day transposed
/// with the last two digits of the year, and a transposed date is still a valid
/// date — so to this software a suggested date that validates is
/// indistinguishable from a confirmed one.
///
/// These tests exist so that widening the rescue is a deliberate act with a
/// failing test attached, rather than a line quietly added to a prompt.
final class RescuePolicyTests: XCTestCase {

    // MARK: - The declared policy

    func testTheRescueOffersTheDocumentNumberAndNothingElse() {
        XCTAssertEqual(CrewField.rescuable, [.documentNumber])
    }

    /// The dates read well enough to look worth keeping and did not survive
    /// being checked. `testTheMeasuredWrongDatesAreStillWellFormedDates` below
    /// is the evidence; this is the decision it produced.
    func testTheDatesAreNotRescuable() {
        XCTAssertFalse(CrewField.rescuable.contains(.birthDate))
        XCTAssertFalse(CrewField.rescuable.contains(.expiryDate))
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

    /// Four of the five fields a port authority requires are still the
    /// operator's to type. That is the point: the rescue recovers what it
    /// measurably reads, not what would be convenient.
    func testTheRescueDoesNotCoverEverythingExportNeeds() {
        let missing = CrewField.requiredForExport.filter { !CrewField.rescuable.contains($0) }
        XCTAssertEqual(Set(missing), [.fullName, .nationality, .birthDate, .sex])
    }

    // MARK: - The prompt asks for exactly that

    /// Not asked, rather than asked and discarded. The measured interference
    /// ran the other way: instructing the model about the name changed its
    /// reading of the dates, so the instruction itself is the cost.
    func testThePromptDoesNotAskForTheFieldsWeWillNotUse() {
        for unwanted in [CrewField.fullName, .nationality, .sex, .birthDate, .expiryDate] {
            XCTAssertFalse(LlamaVisionRescuer.prompt.contains(unwanted.rawValue),
                           "the prompt still asks for \(unwanted.rawValue); asking is what perturbed the reading")
        }
        XCTAssertFalse(LlamaVisionRescuer.prompt.lowercased().contains("name"))
    }

    func testThePromptAsksForEveryFieldTheRescueWillKeep() {
        for wanted in CrewField.rescuable {
            XCTAssertTrue(LlamaVisionRescuer.prompt.contains(wanted.rawValue),
                          "the prompt does not ask for \(wanted.rawValue), so nothing will fill it")
        }
    }

    /// The date-format instruction is derived from the policy, not written into
    /// the prompt by hand. With no date requested it must be absent — an
    /// instruction about fields nobody asked for is exactly the kind of extra
    /// wording that moved the model's reading in the first place.
    func testThePromptSaysNothingAboutDatesWhileNoneAreRequested() {
        XCTAssertFalse(LlamaVisionRescuer.prompt.contains("YYYY-MM-DD"))
        XCTAssertFalse(LlamaVisionRescuer.prompt.lowercased().contains("date"))
    }

    // MARK: - And the reply is filtered to it anyway

    /// A model that volunteers a name unasked is exactly as wrong as one that
    /// was asked for it, so the policy is enforced on the way back too.
    func testAVolunteeredNameOrDateNeverReachesTheDocument() {
        let reply = [
            "full_name": "MIHCHYK OLEKSANDR",
            "nationality": "UKRAINE",
            "sex": "M",
            "document_number": "FH010367",
            "birth_date": "1980-11-20",
            "expiry_date": "2022-07-27",
        ]
        let usable = LlamaVisionRescuer.usableFields(from: reply)

        XCTAssertEqual(usable, ["document_number": "FH010367"])
        XCTAssertNil(usable["full_name"], "MIHCHYK is what a real passport printing MINCHUK produced")
        XCTAssertNil(usable["expiry_date"], "2022-07-27 is what a passport reading 2027-07-22 produced")
    }

    /// The one kept field still has to survive the shaping: a document number is
    /// mostly digits, and excluding them everywhere once dropped a number the
    /// model had read correctly.
    func testTheKeptFieldIsStillScriptChecked() {
        let usable = LlamaVisionRescuer.usableFields(from: ["document_number": "GB262590"])
        XCTAssertEqual(usable["document_number"], "GB262590")
    }

    func testACyrillicDocumentNumberIsStillDropped() {
        let usable = LlamaVisionRescuer.usableFields(from: ["document_number": "АВ1234567"])
        XCTAssertTrue(usable.isEmpty, "those are Cyrillic А and В; a port authority cannot read that as a number")
    }

    // MARK: - What the kept fields actually got wrong

    /// The readings that cost the dates their place, recorded so nobody has to
    /// rediscover them — or argue the dates back in without new measurements.
    ///
    /// Read from five real passports and compared against the app's export of
    /// the same documents. Two of the three are the day transposed with the
    /// last two digits of the year, which is the shape to watch for.
    func testTheMeasuredWrongDatesAreStillWellFormedDates() {
        let measured = [
            (wrong: "2022-07-27", truth: "2027-07-22", field: CrewField.expiryDate),
            (wrong: "2028-05-29", truth: "2029-05-28", field: CrewField.expiryDate),
            (wrong: "2013-09-13", truth: "2013-03-09", field: CrewField.birthDate),
        ]
        for (wrong, truth, field) in measured {
            XCTAssertNotEqual(wrong, truth)
            XCTAssertNotNil(CrewFieldValidator.isoDate(wrong),
                            "\(wrong) is a real date, which is exactly why nothing rejects it")
            XCTAssertFalse(CrewFieldValidator.validate(field, value: wrong).isBlocking,
                           "\(wrong) reaches the operator looking like every other value")
        }
    }

    /// One of the three is catchable, and only by accident: reading 2027 as
    /// 2022 puts the expiry in the past, and the app already warns about that.
    /// It does not block, and it would say nothing at all had the transposition
    /// gone the other way — an expired document read as valid.
    func testOnlyTheExpiryPushedIntoThePastRaisesAnything() {
        let past = CrewFieldValidator.validate(.expiryDate, value: "2022-07-27",
                                               today: CrewFieldValidator.isoDate("2026-08-21")!)
        XCTAssertEqual(past.message, "Document has expired.")
        XCTAssertFalse(past.isBlocking, "a warning, not a block — the operator still has to look")

        let future = CrewFieldValidator.validate(.expiryDate, value: "2028-05-29",
                                                 today: CrewFieldValidator.isoDate("2026-08-21")!)
        XCTAssertNil(future.message, "a year out on a future expiry is silent, and that is the common case")
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

    // MARK: - Widening it again

    /// The policy is one list and everything reads from it, so this is what a
    /// future widening has to hold: add a field there and the prompt asks for
    /// it, the filter admits it, and — for a date — the format instruction
    /// returns. Nothing else needs editing, and nothing else may be edited
    /// instead.
    func testThePromptAndTheFilterAgreeWhateverThePolicySays() {
        for field in CrewField.rescuable {
            XCTAssertTrue(LlamaVisionRescuer.prompt.contains(field.rawValue))
            let sample = field == .documentNumber ? "GB262590" : "1984-12-16"
            XCTAssertNotNil(LlamaVisionRescuer.usableFields(from: [field.rawValue: sample])[field.rawValue],
                            "\(field.rawValue) is declared rescuable but the filter drops it")
        }
    }
}
