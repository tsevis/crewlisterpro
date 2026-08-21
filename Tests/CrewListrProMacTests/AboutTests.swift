import Foundation
import XCTest
@testable import CrewListrProMac

/// The info screen's text is data so that a claim cannot go missing without a
/// test noticing. These are those tests.
///
/// They assert what the screen must *say*, not how it is worded: a paragraph
/// can be rewritten freely, but the privacy promise, the review gate and the
/// licence of every shipped component have to survive the rewrite.
final class AboutTests: XCTestCase {

    // MARK: - Identity

    func testTheIdentityComesFromVersionRatherThanBeingTypedTwice() {
        XCTAssertEqual(About.title, AppVersion.name)
        XCTAssertTrue(About.version.contains(AppVersion.short),
                      "the info screen must show the marketing version")
        XCTAssertTrue(About.version.contains(AppVersion.build),
                      "the info screen must show the build number")
    }

    func testTheSubtitleIsOneLine() {
        XCTAssertFalse(About.subtitle.isEmpty)
        XCTAssertFalse(About.subtitle.contains("\n"), "the subtitle sits on one line beside the mark")
        XCTAssertLessThan(About.subtitle.count, 80, "a longer subtitle wraps under the 36pt title")
    }

    // MARK: - The promises
    //
    // Three claims justify showing this screen at first launch at all. If any
    // of them stops being made, the screen has lost its reason to exist.

    func testTheStoryStatesThatNothingLeavesTheMachine() {
        let text = (About.story + About.legal).lowercased()
        XCTAssertTrue(text.contains("this mac") || text.contains("never transmits"),
                      "the info screen no longer says the documents stay on this machine")
    }

    func testTheStoryStatesThatNothingClearsItself() {
        let story = About.story.lowercased()
        XCTAssertTrue(story.contains("review"), "the review gate is the product's central claim")
        XCTAssertTrue(story.contains("operator"),
                      "the info screen must name who does the confirming")
    }

    func testTheStoryNamesHowExtractionActuallyWorks() {
        XCTAssertTrue(About.story.contains("Vision"), "Vision is what reads the page")
        XCTAssertTrue(About.story.contains("9303"), "the MRZ standard is what the arithmetic checks against")
    }

    // MARK: - The obligations

    /// Every third-party component that ships in, or is downloaded by, the app
    /// has to be named with its licence. A component added without a line here
    /// fails this test rather than shipping unattributed.
    func testTheLegalTextNamesEveryShippedComponent() {
        for component in ["SQLCipher", "SQLite", "OpenSSL", "CryptoKit", "Vision", "SwiftUI"] {
            XCTAssertTrue(About.legal.contains(component), "\(component) is unattributed")
        }
    }

    func testTheLegalTextNamesTheOptionalModelAndItsRuntime() {
        XCTAssertTrue(About.legal.contains(ModelManifest.qwen3VL8BQ4.displayName.prefix(6)),
                      "the optional model is unattributed")
        XCTAssertTrue(About.legal.contains("llama.cpp"), "the inference runtime is unattributed")
    }

    func testEveryNamedComponentCarriesALicence() {
        for licence in ["BSD-3-Clause", "public domain", "Apache-2.0", "MIT"] {
            XCTAssertTrue(About.legal.contains(licence), "\(licence) is no longer declared")
        }
    }

    /// The model is the one thing that can touch the network, so the screen has
    /// to say it is opt-in, checked, and local at inference time.
    func testTheLegalTextQualifiesTheOnlyNetworkAccessTheAppHas() {
        let legal = About.legal.lowercased()
        XCTAssertTrue(legal.contains("consent"), "the model download must be described as opt-in")
        XCTAssertTrue(legal.contains("sha-256"), "the integrity check must be described")
        XCTAssertTrue(legal.contains("127.0.0.1"), "inference must be described as local")
    }

    /// The credit names the studio; the corner mark's tooltip names the person.
    /// Both are true and they are not interchangeable, so each is pinned where
    /// it belongs.
    func testTheCreditNamesTheStudio() {
        XCTAssertTrue(About.credit.contains(Brand.studioName),
                      "the info screen credit no longer names the studio")
    }

    func testTheCreditNamesWhoItWasBuiltFor() {
        XCTAssertTrue(About.credit.contains("Union Yachting"),
                      "the credit no longer names who the app was built for")
    }

    func testTheLegalTextDeclaresTheLicence() {
        XCTAssertTrue(About.legal.contains("MIT licensed"),
                      "the info screen must state the app's own licence, not only its dependencies'")
    }

    func testTheLinksAreHTTPSAndReachTheMaker() {
        XCTAssertFalse(About.links.isEmpty)
        for link in About.links {
            XCTAssertEqual(link.address.scheme, "https", "\(link.label) is not served over HTTPS")
            XCTAssertFalse(link.label.isEmpty)
        }
    }

    // MARK: - Layout inputs

    func testTheStoryAndLegalTextSplitIntoParagraphsTheScreenCanLayOut() {
        XCTAssertGreaterThanOrEqual(About.paragraphs(of: About.story).count, 2)
        XCTAssertGreaterThanOrEqual(About.paragraphs(of: About.legal).count, 3)
    }

    func testParagraphSplittingDropsEmptiesAndTrimsEdges() {
        let split = About.paragraphs(of: "  one  \n\n\n\n  two  \n\n")
        XCTAssertEqual(split, ["one", "two"])
    }

    // MARK: - When it is shown

    /// Absent means yes: first launch is when the promises above are worth
    /// reading. Keyed by version, so a release with something new to say gets
    /// one more chance to say it.
    func testTheScreenIsWantedUntilThisVersionHasBeenSeen() {
        let store = InMemorySeenStore()

        XCTAssertTrue(AboutPresentation.wanted(store), "the first launch must show it")

        AboutPresentation.remember(store)
        XCTAssertFalse(AboutPresentation.wanted(store), "it must not reappear on the next launch")

        store.version = "0.0.0-previous"
        XCTAssertTrue(AboutPresentation.wanted(store), "a new version must show it again")
    }

    func testTheRealStoreReadsAndWritesTheDocumentedKey() {
        let store = InMemorySeenStore()
        AboutPresentation.remember(store)
        XCTAssertEqual(store.version, AppVersion.short)
    }
}

/// Memory, so the suite never touches ~/Library/Preferences.
private final class InMemorySeenStore: AboutSeenStore {
    var version: String?
    func seenVersion() -> String? { version }
    func recordSeen(_ version: String) { self.version = version }
}
