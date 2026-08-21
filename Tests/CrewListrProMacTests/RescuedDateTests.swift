import Foundation
import XCTest
@testable import CrewListrProMac

/// The vision model reads what is printed on the page, and passports do not
/// print ISO dates. "19 FEB 83" is the correct answer in the wrong vocabulary:
/// the app rejects it as blocking-invalid, so the operator must retype a date
/// the rescue had already recovered.
///
/// Verified end to end once against the real model; pinned here so it does not
/// take an 8B model to check again.
final class RescuedDateTests: XCTestCase {

    private func birth(_ value: String) -> String {
        LlamaVisionRescuer.normalisedDate(value, kind: .birth)
    }

    // MARK: - What the model actually returned

    func testThePrintedFormOnTheSpecimenBecomesISO() {
        XCTAssertEqual(birth("19 FEB 83"), "1983-02-19")
    }

    func testAFourDigitYearIsTakenLiterally() {
        XCTAssertEqual(birth("19 FEB 1983"), "1983-02-19")
        XCTAssertEqual(birth("07/03/1961"), "1961-03-07")
    }

    func testCommonPrintedSeparatorsAreAccepted() {
        for value in ["19-02-83", "19/02/83", "19.02.83", "19 02 83"] {
            XCTAssertEqual(birth(value), "1983-02-19", "failed on \(value)")
        }
    }

    func testAnISODateIsLeftAlone() {
        XCTAssertEqual(birth("1983-02-19"), "1983-02-19")
    }

    // MARK: - Refusing to guess

    /// Anything unrecognised comes back untouched. The operator then corrects
    /// one field, exactly as they would have before — a wrong guess would be
    /// worse than no guess, because it might validate.
    func testAnUnparseableValueIsReturnedUnchanged() {
        for value in ["sometime in 1983", "FEB 83", "", "19 FLORÉAL 83"] {
            XCTAssertEqual(birth(value), value, "invented a date from \(value)")
        }
    }

    func testAnImpossibleDayIsNotInvented() {
        XCTAssertEqual(birth("47 FEB 83"), "47 FEB 83")
    }

    /// A two-digit year is ambiguous and which way it resolves depends on what
    /// the date means. Both kinds defer to the rule MRZ parsing already uses,
    /// so the rescue and the machine-readable zone can never disagree.
    func testTwoDigitYearsFollowTheSameRuleAsTheMRZ() {
        let printed = "19 FEB 30"
        XCTAssertEqual(birth(printed), MRZ.date("300219", kind: .birth))
        XCTAssertEqual(LlamaVisionRescuer.normalisedDate(printed, kind: .expiry),
                       MRZ.date("300219", kind: .expiry))
    }
}
