import XCTest

/// The first thing to establish: the app launches, against a store of its own.
final class AppLaunchUITests: CrewListrUITestCase {

    func testTheAppOpensOnItsOwnStore() {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.exists, "no window appeared")
    }
    func testTheScreenRowOffersEveryScreen() {
        let app = launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        for screen in ["fleet", "trip", "people", "crewList", "settings"] {
            XCTAssertTrue(app.buttons["screen.\(screen)"].waitForExistence(timeout: 5), "no \(screen) tab")
        }
    }
}
