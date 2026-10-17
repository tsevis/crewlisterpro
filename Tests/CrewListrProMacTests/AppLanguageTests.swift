import XCTest
@testable import CrewListrProMac

/// The in-app language choice is the per-app `AppleLanguages` override the
/// system itself uses. Every test runs on a throwaway defaults suite.
final class AppLanguageTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "crewlistr-language-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testChoosingALanguageOverridesTheSystemOne() {
        AppLanguage.greek.apply(to: defaults)

        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["el"])
        XCTAssertEqual(AppLanguage.current(in: defaults, domain: suite), .greek)
    }

    /// Going back to the system language has to remove the override, not
    /// write the current system language into it — that would freeze it.
    func testGoingBackToTheSystemLanguageRemovesTheOverride() {
        AppLanguage.ukrainian.apply(to: defaults)
        AppLanguage.system.apply(to: defaults)

        XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
        XCTAssertEqual(AppLanguage.current(in: defaults, domain: suite), .system)
    }
}
