import XCTest

/// The controls this whole Xcode project exists to reach.
///
/// Every one of these is a SwiftUI `Button` or `Toggle` with a custom style, so
/// an in-process test can find no `NSButton` to press and cannot reach any of
/// them. See `InteractionHarness` in the package's own suite for how far that
/// gets and exactly where it stops.
final class ReviewUITests: CrewListrUITestCase {

    /// Confirming a field is the gate the whole app is built around: nothing
    /// reaches a crew list until a person has checked it against the image.
    func testConfirmingAFieldAdvancesTheReview() {
        let app = launch(seeded: true)
        open(.people, in: app)

        let confirm = app.checkBoxes["review.confirm.nationality"]
            .exists ? app.checkBoxes["review.confirm.nationality"] : app.buttons["review.confirm.nationality"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "no confirm control for nationality")
        XCTAssertFalse(app.staticTexts["Cleared for export"].exists)

        confirm.click()

        // The progress line names what is left, so it changes the moment a
        // field is confirmed.
        let stillToConfirm = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "Still to confirm")
        ).firstMatch
        XCTAssertTrue(stillToConfirm.waitForExistence(timeout: 10))
        XCTAssertFalse(stillToConfirm.value as? String == "" )
    }

    func testNamingTheClientMarksThePersonInTheDocumentList() {
        let app = launch(seeded: true)
        open(.people, in: app)

        let client = app.checkBoxes["review.client"]
        XCTAssertTrue(client.waitForExistence(timeout: 15), "no client checkbox")
        XCTAssertEqual(client.value as? Int, 0, "someone is already the client")

        client.click()

        XCTAssertEqual(client.value as? Int, 1, "the checkbox did not take")
        XCTAssertTrue(app.staticTexts["CLIENT"].waitForExistence(timeout: 10),
                      "the document list does not say who signs")
    }

    func testNamingASkipperShowsTheEmailFieldForThemAlone() {
        let app = launch(seeded: true)
        open(.people, in: app)

        // The seeded passenger, who has no email field until promoted.
        clickRow(labelled: "NIKOLAOS PAPADOPOULOS", in: app) {
            app.radioGroups["review.role"].radioButtons.element(boundBy: 1).value as? Int == 1
        }
        XCTAssertFalse(app.textFields["review.skipperEmail"].exists,
                       "a passenger was asked for an email address")

        let role = app.radioGroups["review.role"].radioButtons.element(boundBy: 0)
        XCTAssertTrue(role.waitForExistence(timeout: 15), "no role picker")
        role.click()

        XCTAssertTrue(app.textFields["review.skipperEmail"].waitForExistence(timeout: 10),
                      "the new skipper was not asked for an email address")
    }
}
