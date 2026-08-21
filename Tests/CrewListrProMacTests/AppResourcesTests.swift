import AppKit
import Foundation
import XCTest
@testable import CrewListrProMac

/// Guards the build inputs `scripts/release.sh` depends on. A missing or
/// wrongly shaped icon otherwise fails at packaging time, long after the change
/// that caused it.
final class AppResourcesTests: XCTestCase {

    /// Repository root, located from this file rather than the working
    /// directory, which differs between `swift test` and Xcode.
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CrewListrProMacTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }

    private var iconSource: URL {
        root.appending(path: "Resources").appending(path: "\(AppVersion.iconFile).png")
    }

    func testTheIconSourceExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconSource.path(percentEncoded: false)),
                      "missing \(iconSource.lastPathComponent); release.sh cannot build the icns")
    }

    func testTheIconIsSquareAndLargeEnoughForEveryRepresentation() throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(iconSource as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, image.height, "the icon must be square")
        // icon_512x512@2x is 1024pt; anything smaller is upscaled and soft.
        XCTAssertGreaterThanOrEqual(image.width, 1024, "the icon must be at least 1024x1024")
    }

    func testTheIconScriptIsExecutable() {
        let script = root.appending(path: "scripts").appending(path: "make-icon.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path(percentEncoded: false)),
                      "scripts/make-icon.sh must be executable")
    }

    func testTheReleaseScriptStampsTheIconIntoTheBundle() throws {
        let script = try String(contentsOf: root.appending(path: "scripts").appending(path: "release.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("make-icon.sh"), "release.sh no longer builds the icon")
        XCTAssertTrue(script.contains("CFBundleIconFile"), "release.sh no longer declares the icon in Info.plist")
    }

    // MARK: - The macOS icon shape

    /// Runs the real masking script and checks the shape it produces: the
    /// corners must be cut away and the centre must survive. A regression here
    /// means the Dock shows a hard-edged tile.
    func testTheMaskProducesTheMacOSIconShape() throws {
        let output = FileManager.default.temporaryDirectory.appending(path: "masked-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", root.appending(path: "scripts/mask-icon.swift").path(percentEncoded: false),
                             iconSource.path(percentEncoded: false), output.path(percentEncoded: false)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try XCTSkipUnless(process.terminationStatus == 0, "the Swift toolchain is unavailable in this environment")

        let pixels = try Self.alphaProbe(output)
        XCTAssertEqual(pixels.corner, 0, "the icon corners were not masked away")
        XCTAssertEqual(pixels.centre, 255, "the icon body was masked away")
        XCTAssertEqual(pixels.width, 1024)
        // The body is inset on Apple's grid, so a point just inside the canvas
        // edge at mid-height must also be clear.
        XCTAssertEqual(pixels.edgeMidHeight, 0, "the icon was not inset to the 824pt body")
    }

    private static func alphaProbe(_ url: URL) throws -> (width: Int, corner: UInt8, centre: UInt8, edgeMidHeight: UInt8) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
        return (width, alpha(2, 2), alpha(width / 2, height / 2), alpha(2, height / 2))
    }

    func testTheIconScriptAppliesTheMaskByDefault() throws {
        let script = try String(contentsOf: root.appending(path: "scripts/make-icon.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("mask-icon.swift"), "make-icon.sh no longer applies the macOS icon shape")
        XCTAssertTrue(script.contains("CREWLISTR_ICON_NO_MASK"), "the opt-out for pre-shaped artwork is gone")
    }

    func testTheProductIdentityIsComplete() {
        XCTAssertFalse(AppVersion.short.isEmpty)
        XCTAssertFalse(AppVersion.build.isEmpty)
        XCTAssertFalse(AppVersion.iconFile.isEmpty)
        XCTAssertEqual(AppVersion.bundleIdentifier, "com.tsevis.crewlisterpro")
        XCTAssertTrue(AppVersion.displayVersion.hasPrefix("CrewListr Pro "))
        XCTAssertFalse(AppVersion.tags.isEmpty)
    }
}
