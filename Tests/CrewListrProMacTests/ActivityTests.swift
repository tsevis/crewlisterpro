import Foundation
import XCTest
@testable import CrewListrProMac

/// How work in flight is described.
///
/// The app used to report every long operation as one sentence with no sense of
/// how much, how far, or whether it could be stopped — including a 5.78 GB
/// download. These pin the arithmetic and the honesty of what replaced it.
final class ActivityTests: XCTestCase {

    // MARK: - Honesty about what can be measured

    func testWorkThatCannotBeMeasuredHasNoFraction() {
        let activity = Activity.indeterminate("Asking the local model")
        XCTAssertNil(activity.fraction, "a bar that invents a percentage is worse than a spinner")
        XCTAssertNil(activity.percentage)
    }

    func testStepsCountFromZeroButReadFromOne() {
        // Starting the first of six is 0% done and reads as "1 of 6".
        let first = Activity.step("Reading documents", completed: 0, total: 6)
        XCTAssertEqual(first.fraction, 0)
        XCTAssertEqual(first.detail, "1 of 6")

        let last = Activity.step("Reading documents", completed: 5, total: 6)
        XCTAssertEqual(last.fraction ?? 0, 5.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(last.detail, "6 of 6")
    }

    func testTheStepLabelNeverRunsPastTheTotal() {
        let overshoot = Activity.step("Reading documents", completed: 9, total: 6)
        XCTAssertEqual(overshoot.detail, "6 of 6", "a miscount must not read as '10 of 6'")
    }

    func testAnEmptyBatchIsIndeterminateRatherThanDividingByZero() {
        let activity = Activity.step("Reading documents", completed: 0, total: 0)
        XCTAssertNil(activity.fraction)
    }

    func testTheStepDetailNamesTheThingBeingWorkedOn() {
        let activity = Activity.step("Reading documents", completed: 2, total: 6, detail: "passport.jpeg")
        XCTAssertEqual(activity.detail, "3 of 6 · passport.jpeg")
    }

    // MARK: - Bars cannot be driven out of range

    func testAFractionIsClampedAtBothEnds() {
        XCTAssertEqual(Activity(title: "x", fraction: 1.4).clampedFraction, 1)
        XCTAssertEqual(Activity(title: "x", fraction: -0.2).clampedFraction, 0)
    }

    func testThePercentageIsRoundedForDisplay() {
        XCTAssertEqual(Activity(title: "x", fraction: 0.456).percentage, "46%")
        XCTAssertEqual(Activity(title: "x", fraction: 1).percentage, "100%")
    }

    // MARK: - Bytes

    func testAByteActivityStatesBothSides() {
        let activity = Activity.bytes("Downloading", received: 1_000_000, expected: 5_780_000_000)
        let detail = try? XCTUnwrap(activity.detail)
        XCTAssertTrue(detail?.contains(" of ") ?? false, detail ?? "")
        XCTAssertNotNil(activity.fraction)
    }

    func testAByteActivityWithNoKnownTotalStaysIndeterminate() {
        let activity = Activity.bytes("Downloading", received: 1_000_000, expected: 0)
        XCTAssertNil(activity.fraction, "an unknown total must not produce a bar")
        XCTAssertFalse(try XCTUnwrap(activity.detail).contains(" of "))
    }

    // MARK: - Where it gets drawn, and whether it can be stopped

    func testALongDownloadIsSustainedAndCancellable() {
        let activity = Activity.bytes("Downloading the local AI model", received: 0, expected: 5_780_000_000)
        XCTAssertEqual(activity.style, .sustained, "minutes of work needs a persistent place")
        XCTAssertTrue(activity.isCancellable, "a multi-gigabyte transfer must be stoppable")
    }

    func testShortWorkIsTransientAndNotCancellable() {
        for activity in [Activity.indeterminate("Applying image edit"),
                         Activity.step("Reading documents", completed: 0, total: 3)] {
            XCTAssertEqual(activity.style, .transient)
            XCTAssertFalse(activity.isCancellable)
        }
    }
}

// MARK: - What the store reports

@MainActor
final class StoreActivityTests: XCTestCase {

    func testNothingIsReportedWhenIdle() {
        let store = CrewStore(secureStore: nil)
        XCTAssertNil(store.activity)
        XCTAssertNil(store.busyMessage)
    }

    /// `busyMessage` is a compatibility alias over `activity` while the UI
    /// adopts the richer type; it must stay in step with it.
    func testTheLegacyMessageReflectsTheActivity() {
        let store = CrewStore(secureStore: nil)
        store.activity = .step("Reading documents", completed: 1, total: 4, detail: "a.jpeg")
        XCTAssertEqual(store.busyMessage, "Reading documents — 2 of 4 · a.jpeg")

        store.activity = .indeterminate("Restoring an earlier version")
        XCTAssertEqual(store.busyMessage, "Restoring an earlier version")
    }

    func testSettingTheLegacyMessageProducesAnIndeterminateActivity() {
        let store = CrewStore(secureStore: nil)
        store.busyMessage = "Working"
        XCTAssertEqual(store.activity?.title, "Working")
        XCTAssertNil(store.activity?.fraction)
    }

    func testCancellingClearsWhatIsReported() {
        let store = CrewStore(secureStore: nil)
        store.activity = .bytes("Downloading", received: 10, expected: 100)
        store.cancelActivity()
        XCTAssertNil(store.activity, "cancelling must leave nothing on screen")
    }
}
