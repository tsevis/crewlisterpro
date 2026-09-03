import Foundation
import XCTest
@testable import CrewListrProMac

/// Reading the name off line 1 when the camera did not give a clean one.
///
/// The shapes here are the ones measured on real passports: a line that lost
/// its `P<XXX` prefix, a line the recogniser cut short, and a line with digits
/// smeared through it. Names are invented for the test; the failures are not.
final class MRZNameRecoveryTests: XCTestCase {

    // MARK: - Where the name starts

    func testAWholePrefixIsSkipped() {
        XCTAssertEqual(MRZ.prefixLength(of: "P<HUNKOLISZNIK<<ANNA<<<", issuedBy: "HUN"), 5)
    }

    /// The failure this was written for. The recogniser missed `P<HUN`
    /// entirely, and dropping five characters regardless took the first five
    /// letters of the surname with it — an eight-letter surname came out three.
    func testNothingIsSkippedWhenThePrefixIsNotThere() {
        XCTAssertEqual(MRZ.prefixLength(of: "KOLISZNIK<<ANNA<<<<<<", issuedBy: "HUN"), 0)
    }

    func testAPrefixWithoutItsDocumentClassIsStillRecognised() {
        XCTAssertEqual(MRZ.prefixLength(of: "HUNKOLISZNIK<<ANNA<<<", issuedBy: "HUN"), 3)
    }

    /// With no proven state to match, only the standard shape is trusted.
    func testTheShapeAloneIsEnoughWhenTheStateIsUnknown() {
        XCTAssertEqual(MRZ.prefixLength(of: "P<UTONAKAMURA<<YUKI<<<", issuedBy: nil), 5)
        XCTAssertEqual(MRZ.prefixLength(of: "NAKAMURA<<YUKI<<<<<<<<", issuedBy: nil), 0)
    }

    func testANameSurvivesAMissingPrefix() {
        XCTAssertEqual(MRZ.names("KOLISZNIK<<ANNA<<<<<<<<<<", issuedBy: "HUN"), "ANNA KOLISZNIK")
    }

    func testANameIsStillReadFromAWholeLine() {
        XCTAssertEqual(MRZ.names("P<HUNKOLISZNIK<<ANNA<<<<<<", issuedBy: "HUN"), "ANNA KOLISZNIK")
    }

    // MARK: - Choosing among readings

    /// The recogniser proposes several readings of the same line. Choosing
    /// between them is not inventing: every character considered is one it
    /// actually reported.
    func testTheReadingThatObeysTheGrammarIsChosen() {
        let readings = [
            "KOLISZNIK<ANNA<<<<<<<<<<<<<<<<<<<<<<",          // lost its separator
            "P<HUNKOLISZNIK<<ANNA<<<<<<<<<<<<<<<<<<<<<<<<",  // whole and well-formed
        ]
        XCTAssertEqual(MRZ.bestName(among: readings, issuedBy: "HUN"), "ANNA KOLISZNIK")
    }

    func testAReadingWithDigitsIsNeverChosen() {
        let readings = ["P<HUNK0L1SZN1K<<ANNA<<<<<<<<<<<<<<<<<<<<<<<<"]
        XCTAssertNil(MRZ.bestName(among: readings, issuedBy: "HUN"),
                     "a line with digits cannot be line 1, and guessing which letters they were is inventing a name")
    }

    func testNoReadingAtAllYieldsNoName() {
        XCTAssertNil(MRZ.bestName(among: [], issuedBy: "HUN"))
        XCTAssertNil(MRZ.bestName(among: ["SOME PRINTED TEXT FROM THE PAGE ABOVE"], issuedBy: "HUN"))
    }

    /// A reading missing the separator carries no given name, and half a name
    /// on a crew list is worse than none.
    func testAReadingWithoutASeparatorIsRefused() {
        XCTAssertNil(MRZ.bestName(among: ["KOLISZNIK<ANNA<<<<<<<<<<<<<<<<<<<<<<"], issuedBy: "HUN"))
    }

    /// Whole lines beat truncated ones, so a name cannot be taken from a
    /// reading that stopped in the middle of the surname.
    func testAWholeLineIsPreferredToATruncatedOne() {
        let readings = [
            "P<HUNKOLI<<ANNA<<",
            "P<HUNKOLISZNIK<<ANNA<<<<<<<<<<<<<<<<<<<<<<<<",
        ]
        XCTAssertEqual(MRZ.bestName(among: readings, issuedBy: "HUN"), "ANNA KOLISZNIK")
    }
}
