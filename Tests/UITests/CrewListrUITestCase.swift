import XCTest

/// Shared launch for every UI test: a throwaway store, and optionally a fleet
/// to click on.
///
/// The store root matters more than anything else here. A UI test drives the
/// real application binary, and the real binary keeps the operator's trips,
/// their sealed passport scans and its own encryption key under one directory.
/// Pointed at that directory, a test that clicks "Delete Trip and Documents"
/// would delete a real charter. Every test gets its own empty root instead, and
/// deletes it afterwards.
class CrewListrUITestCase: XCTestCase {

    private(set) var storeRoot: URL!
    private var launched: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        storeRoot = FileManager.default.temporaryDirectory
            .appending(path: "CrewListrUITest-\(UUID().uuidString)", directoryHint: .isDirectory)
        // A macOS app is a singleton. An instance left over from an interrupted
        // run is not replaced by `launch()` — it is *activated*, still carrying
        // the previous run's launch environment and therefore the previous
        // run's store. The next test then quietly clicks around a store it did
        // not create, and the failure it eventually produces points anywhere
        // but here. Start from nothing.
        terminateAnyRunningApp()
    }

    override func tearDownWithError() throws {
        launched?.terminate()
        launched = nil
        if let storeRoot { try? FileManager.default.removeItem(at: storeRoot) }
    }

    private func terminateAnyRunningApp() {
        let existing = makeApp()
        if existing.state != .notRunning {
            existing.terminate()
            _ = existing.wait(for: .notRunning, timeout: 10)
        }
    }

    /// The app built alongside this test bundle, addressed by path.
    ///
    /// NOT `XCUIApplication()`, which resolves through LaunchServices by bundle
    /// identifier. Every build of this project registers another copy under the
    /// same identifier, and after a few runs LaunchServices starts answering
    /// with a stale one — every test then failed with "no window appeared"
    /// while the app launched perfectly by hand. `scripts/release.sh` carries a
    /// long comment about this exact behaviour costing a week; it costs the
    /// same here, and a path cannot be answered with the wrong copy.
    /// The application under test.
    ///
    /// Plain `XCUIApplication()`, which the scheme points at this project's app
    /// target. Addressing the built bundle by URL instead was tried, on the
    /// theory that LaunchServices was answering with one of the several stale
    /// copies every rebuild registers under this identifier — it made no
    /// difference, so the simpler form stands.
    private func makeApp() -> XCUIApplication {
        XCUIApplication()
    }

    @discardableResult
    func launch(seeded: Bool = false) -> XCUIApplication {
        let app = makeApp()
        app.launchEnvironment["CREWLISTR_STORE_ROOT"] = storeRoot.path(percentEncoded: false)
        if seeded { app.launchEnvironment["CREWLISTR_SEED"] = "demo" }
        app.launch()
        launched = app
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "no window appeared")
        return app
    }

    /// Moves to a screen by clicking its tab, the way an operator does.
    ///
    /// By identifier, not by visible label. The crew-list count sits in the
    /// same row, and an element whose label is a number makes a label-matching
    /// query throw — taking every other match in the window down with it.
    func open(_ screen: Screen, in app: XCUIApplication) {
        let tab = app.buttons["screen.\(screen.rawValue)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "no \(screen.rawValue) tab to click")
        tab.click()
    }

    /// The screens, named the way the app names them internally.
    enum Screen: String {
        case fleet, trip, people, crewList, settings
    }

    /// Clicks a row in a list, by the text on its face.
    ///
    /// Not by identifier. `.accessibilityIdentifier` on the content of a `List`
    /// row does not reach the element XCUITest sees — and worse than not being
    /// found, a broad `descendants` query *does* match a wrapper around it,
    /// which clicks without changing the selection. Three tests passed against
    /// that: they were operating on the row the app had already selected, and
    /// the one test that needed the selection to actually move is the one that
    /// caught it.
    ///
    /// So the row's own text is the handle, and the caller says how to tell the
    /// click landed.
    func clickRow(labelled label: String, in app: XCUIApplication,
                  confirmedBy settled: () -> Bool,
                  file: StaticString = #filePath, line: UInt = #line) {
        let row = app.staticTexts.matching(identifier: label).element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no row reading \(label)", file: file, line: line)
        row.click()

        // Selection is what the click is for, so it is what gets waited on —
        // never the click returning.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !settled() {
            _ = app.windows.firstMatch.waitForExistence(timeout: 0.2)
        }
        XCTAssertTrue(settled(), "clicking \(label) did not select it", file: file, line: line)
    }
}
