import Foundation
import XCTest
@testable import CrewListrProMac

/// What the progress views are allowed to say.
///
/// The rendering itself needs a pointer to verify, but the decisions behind it
/// do not: which presentation an activity gets, what text is shown verbatim
/// rather than recomposed, and that an unmeasurable operation never grows a
/// percentage it cannot justify.
final class ActivityRenderingTests: XCTestCase {

    // MARK: - Routing

    func testAStepImportIsTransient() {
        let activity = Activity.step("Reading documents", completed: 2, total: 6, detail: "passport.jpeg")
        XCTAssertEqual(activity.style, .transient)
    }

    func testAnUnmeasurableOperationOffersNoPercentage() {
        let activity = Activity.indeterminate("Re-reading with OCR")
        XCTAssertNil(activity.fraction, "an unmeasurable operation must not invent a fraction")
        XCTAssertNil(activity.percentage, "and must not display a percentage it cannot justify")
        XCTAssertNil(activity.clampedFraction, "so the view draws a spinner, not a bar")
    }

    // MARK: - The bar cannot lie

    /// A miscounted step must not drive the bar past its end or behind its
    /// start — the two ways a progress bar loses an operator's trust.
    func testTheBarIsClampedAtBothEnds() {
        XCTAssertEqual(Activity(title: "x", fraction: 1.4).clampedFraction, 1)
        XCTAssertEqual(Activity(title: "x", fraction: -0.3).clampedFraction, 0)
        XCTAssertEqual(Activity(title: "x", fraction: 0.5).clampedFraction, 0.5)
    }

    func testThePercentageMatchesTheBarItSitsBeside() {
        XCTAssertEqual(Activity(title: "x", fraction: 0.455).percentage, "46%")
        XCTAssertEqual(Activity(title: "x", fraction: 1.2).percentage, "100%",
                       "a clamped bar and an unclamped percentage would disagree on screen")
        XCTAssertEqual(Activity(title: "x", fraction: 0).percentage, "0%")
    }

    /// A step counter must never read "7 of 6".
    func testAMiscountedStepCannotOverrunItsTotal() {
        let activity = Activity.step("Reading documents", completed: 99, total: 6)
        XCTAssertEqual(activity.detail?.hasPrefix("6 of 6"), true, "got \(activity.detail ?? "nil")")
    }

    func testAStepWithNoTotalStaysASpinner() {
        let activity = Activity.step("Reading documents", completed: 0, total: 0)
        XCTAssertNil(activity.fraction, "an unknown total cannot become a bar")
    }

    // MARK: - Cancellation

    /// Only what is safe to stop offers a way to stop it, and the strip renders
    /// Cancel from this flag alone.
    func testATransientOperationDoesNotOfferCancel() {
        XCTAssertFalse(Activity.indeterminate("Rotating").isCancellable)
    }
}
