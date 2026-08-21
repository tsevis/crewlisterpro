import AppKit
import Foundation
import XCTest
@testable import CrewListrProMac

/// Guards the two marks the interface shows and the packaging step that carries
/// them into a real `.app`.
///
/// The failure this is written against is silent: `Bundle.module` returns nil,
/// `Brand` degrades to a text glyph, and the app looks *almost* right — so
/// nobody notices until a user asks why the corner is empty.
final class BrandAssetTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CrewListrProMacTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }

    // MARK: - The marks resolve

    func testTheMakersMarkLoadsFromTheResourceBundle() {
        XCTAssertNotNil(Brand.makersMark, "the maker's mark did not resolve through Bundle.module")
    }

    func testTheAppMarkLoadsFromTheResourceBundle() {
        XCTAssertNotNil(Brand.appMark, "the app mark did not resolve through Bundle.module")
    }

    /// The mark renders at 20pt in the window corner and 16pt in the info
    /// screen footer, so anything below 40pt is soft on a Retina display.
    func testTheMakersMarkIsLargeEnoughForItsRetinaSize() throws {
        let mark = try XCTUnwrap(Brand.makersMark)
        XCTAssertGreaterThanOrEqual(mark.size.width, 40)
        XCTAssertEqual(mark.size.width, mark.size.height, "the maker's mark must be square")
    }

    /// The app mark renders at 49pt in the info screen lockup and 29pt in the
    /// sidebar brand.
    func testTheAppMarkIsLargeEnoughForItsRetinaSize() throws {
        let mark = try XCTUnwrap(Brand.appMark)
        XCTAssertGreaterThanOrEqual(mark.size.width, 98)
        XCTAssertEqual(mark.size.width, mark.size.height, "the app mark must be square")
    }

    // MARK: - Union Yachting

    func testTheUnionMarkAndBannerLoad() throws {
        XCTAssertNotNil(Brand.unionMark, "the Union Yachting mark did not resolve through Bundle.module")
        XCTAssertNotNil(Brand.unionBanner, "the info screen's key art did not resolve through Bundle.module")
    }

    /// The banner fills a 640x250 lockup, so it has to be wider than that at
    /// 2x and wide enough not to letterbox when scaled to fill.
    func testTheBannerIsLargeEnoughAndWiderThanTheLockup() throws {
        let banner = try XCTUnwrap(Brand.unionBanner)
        XCTAssertGreaterThanOrEqual(banner.size.width, 1280)
        XCTAssertGreaterThan(banner.size.width / banner.size.height, 1.0,
                             "a portrait banner would crop to almost nothing in a 2.56:1 lockup")
    }

    func testTheUnionSiteIsHTTPS() {
        XCTAssertEqual(Brand.unionSite.scheme, "https")
        XCTAssertTrue(Brand.unionSite.host?.contains("unionyachting.com") == true)
    }

    func testTheUnionMarkSourcesAreInTheRepository() {
        let resources = root.appending(path: "Sources/CrewListrProMac/Resources")
        for name in ["UnionMark.png", "UnionBanner.jpg"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: resources.appending(path: name).path(percentEncoded: false)),
                "missing Sources/CrewListrProMac/Resources/\(name)"
            )
        }
    }

    func testTheMakerSiteIsHTTPS() {
        XCTAssertEqual(Brand.makerSite.scheme, "https")
    }

    // MARK: - Packaging

    /// SwiftPM emits the target's resources as a bundle beside the executable.
    /// A packaged build that does not copy it in shows the fallback glyphs.
    func testTheReleaseScriptCopiesTheResourceBundleIntoTheApp() throws {
        let script = try String(contentsOf: root.appending(path: "scripts/release.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("CrewListrProMac_CrewListrProMac.bundle"),
                      "release.sh no longer stages the SwiftPM resource bundle; Bundle.module will be nil in the app")
        XCTAssertTrue(script.contains("$APP/Contents/Resources/"),
                      "the resource bundle must land in Contents/Resources for Bundle.module to find it")
    }

    func testThePackageDeclaresTheResources() throws {
        let manifest = try String(contentsOf: root.appending(path: "Package.swift"), encoding: .utf8)
        XCTAssertTrue(manifest.contains("resources:"),
                      "the executable target no longer declares its resources")
    }

    /// Both marks must exist as files, not merely load from a stale build
    /// directory left over from an earlier checkout.
    func testTheMarkSourcesAreInTheRepository() {
        let resources = root.appending(path: "Sources/CrewListrProMac/Resources")
        for name in ["TsevisMark.png", "AppMark.png"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: resources.appending(path: name).path(percentEncoded: false)),
                "missing Sources/CrewListrProMac/Resources/\(name)"
            )
        }
    }
}
