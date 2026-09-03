import XCTest

/// The Fleet tab, clicked.
final class FleetUITests: CrewListrUITestCase {

    /// The seeded fleet sorts by name, so this is the one selected on arrival —
    /// and it is deliberately NOT the one carrying the charter.
    private let unchartered = "M/Y AURORA"
    private let chartered = "S/Y ELPIDA"

    func testAddingAYachtPutsItInTheFleet() {
        let app = launch()
        open(.fleet, in: app)

        XCTAssertTrue(app.staticTexts["No yachts yet"].waitForExistence(timeout: 15))
        app.buttons["fleet.add"].firstMatch.click()

        XCTAssertTrue(app.staticTexts["Untitled yacht"].firstMatch.waitForExistence(timeout: 15),
                      "the new yacht did not appear")
    }

    func testTypingAYachtNameShowsItInTheFleetList() {
        let app = launch()
        open(.fleet, in: app)
        app.buttons["fleet.add"].firstMatch.click()

        let name = app.textFields["fleet.field.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("S/Y ELPIDA\t")

        XCTAssertTrue(app.staticTexts["S/Y ELPIDA"].firstMatch.waitForExistence(timeout: 15),
                      "the name did not reach the list")
    }

    func testRetiringAYachtTakesItOutOfTheFleet() {
        let app = launch(seeded: true)
        open(.fleet, in: app)
        select(unchartered, in: app)

        let retire = app.buttons["fleet.retire"]
        XCTAssertTrue(retire.waitForExistence(timeout: 15))
        retire.click()

        // Asserted through the control that replaces it rather than through the
        // section header, whose text a list may or may not expose.
        XCTAssertTrue(app.buttons["fleet.restore"].waitForExistence(timeout: 15),
                      "the yacht was not retired")
        XCTAssertFalse(app.buttons["fleet.retire"].exists)
    }

    func testARetiredYachtCanBeBroughtBack() {
        let app = launch(seeded: true)
        open(.fleet, in: app)
        select(unchartered, in: app)
        app.buttons["fleet.retire"].click()
        XCTAssertTrue(app.buttons["fleet.restore"].waitForExistence(timeout: 15))

        app.buttons["fleet.restore"].click()

        XCTAssertTrue(app.buttons["fleet.retire"].waitForExistence(timeout: 15),
                      "the yacht did not come back")
    }

    /// The guard that matters most here: a yacht a charter still names cannot
    /// be deleted, because the crew list reads its header boxes off that record.
    func testAYachtInUseOffersNoWayToDeleteIt() {
        let app = launch(seeded: true)
        open(.fleet, in: app)
        select(chartered, in: app)

        let delete = app.buttons["fleet.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 15))
        XCTAssertFalse(delete.isEnabled, "a yacht carrying a charter offered to delete itself")
    }

    func testAYachtNoCharterUsesCanBeDeleted() {
        let app = launch(seeded: true)
        open(.fleet, in: app)
        select(unchartered, in: app)

        XCTAssertTrue(app.buttons["fleet.delete"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["fleet.delete"].isEnabled)
    }

    func testDuplicatingAYachtAddsASisterShip() {
        let app = launch(seeded: true)
        open(.fleet, in: app)
        select(unchartered, in: app)

        XCTAssertTrue(app.buttons["fleet.duplicate"].waitForExistence(timeout: 15))
        app.buttons["fleet.duplicate"].click()

        XCTAssertTrue(app.staticTexts["\(unchartered) (copy)"].waitForExistence(timeout: 15),
                      "the sister ship did not join the fleet")
    }

    /// Picks a yacht in the list by name, the way an operator does, and waits
    /// for the detail pane to be showing it.
    private func select(_ name: String, in app: XCUIApplication) {
        clickRow(labelled: name, in: app) {
            app.textFields["fleet.field.name"].value as? String == name
        }
    }
}
