import Foundation
import XCTest
@testable import CrewListrProMac

/// The issuing state, which is the one field on line 2 that no check digit
/// covers.
///
/// The composite digit spans the document number, the birth date and the expiry
/// date; positions 11 to 13 are not in it. So `ROU` read as `R0U` is not caught
/// by the arithmetic that catches everything else on that line — it was
/// reported from the field, and reproduced here from a rendered specimen whose
/// `UTO` came back `UT0`.
final class NationalityRepairTests: XCTestCase {

    // MARK: - Repair

    /// A digit cannot appear in a country code, so a digit there is a misread
    /// and the letter it was is not in doubt for the shapes OCR-B confuses.
    func testAZeroInACountryCodeIsTheLetterO() {
        XCTAssertEqual(MRZ.repairedStateCode("R0U", issuingState: nil), "ROU")
        XCTAssertEqual(MRZ.repairedStateCode("UT0", issuingState: nil), "UTO")
    }

    func testTheOtherShapesOCRConfuses() {
        XCTAssertEqual(MRZ.repairedStateCode("5WE", issuingState: nil), "SWE")
        XCTAssertEqual(MRZ.repairedStateCode("8EL", issuingState: nil), "BEL")
        XCTAssertEqual(MRZ.repairedStateCode("6BR", issuingState: nil), "GBR")
        XCTAssertEqual(MRZ.repairedStateCode("2AF", issuingState: nil), "ZAF")
    }

    /// A 1 is an I or an L and the shape does not say which, so it is left for
    /// the operator rather than guessed at.
    func testAnAmbiguousDigitIsLeftAlone() {
        XCTAssertEqual(MRZ.repairedStateCode("1TA", issuingState: nil), "1TA",
                       "a 1 could be I or L; guessing is not repairing")
    }

    /// Line 1 carries the same three letters. Two independent readings that
    /// agree everywhere except where one has a digit settle it without
    /// appealing to any table of shapes.
    func testLine1SettlesADigitThatTheShapesCannot() {
        XCTAssertEqual(MRZ.repairedStateCode("1TA", issuingState: "ITA"), "ITA")
    }

    /// But only when they are otherwise the same code. A line 1 that disagrees
    /// is a line 1 that was read badly, and it does not get to overrule line 2.
    func testADisagreeingLine1IsIgnored() {
        XCTAssertEqual(MRZ.repairedStateCode("1TA", issuingState: "FRA"), "1TA")
    }

    func testACleanCodeIsLeftExactlyAsItIs() {
        XCTAssertEqual(MRZ.repairedStateCode("HUN", issuingState: "HUN"), "HUN")
        XCTAssertEqual(MRZ.repairedStateCode("UKR", issuingState: nil), "UKR")
    }

    // MARK: - Through the parser

    func testAMisreadStateIsRepairedOnTheWayOut() throws {
        // A specimen line 2 with the issuing state misread as UT0.
        let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
        let line2 = "L898902C36UT07408122F1204159ZE184226B<<<<<10"
        let fields = try XCTUnwrap(MRZ.parse("\(line1)\n\(line2.replacingOccurrences(of: "UT0", with: "UT0"))"))

        XCTAssertEqual(fields["nationality"], "UTO", "the digit reached the crew list")
    }

    // MARK: - What validation must not wave through

    /// The repair cannot catch everything, so the field has to object to what
    /// is left. Before this, `UT0` was two characters or more and therefore
    /// valid — an operator could confirm a country code with a digit in it and
    /// nothing would have said a word.
    func testACountryCodeWithADigitIsRefused() {
        XCTAssertTrue(CrewFieldValidator.validate(.nationality, value: "UT0").isBlocking)
        XCTAssertTrue(CrewFieldValidator.validate(.nationality, value: "R0U").isBlocking)
        XCTAssertTrue(CrewFieldValidator.validate(.nationality, value: "1TA").isBlocking)
    }

    func testARealNationalityStillPasses() {
        XCTAssertEqual(CrewFieldValidator.validate(.nationality, value: "HUN"), .valid)
        XCTAssertEqual(CrewFieldValidator.validate(.nationality, value: "UKRAINIAN"), .valid)
        XCTAssertEqual(CrewFieldValidator.validate(.nationality, value: "CÔTE D'IVOIRE"), .valid)
    }
}
