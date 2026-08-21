import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CrewListrProMac

/// Tests for the in-app image tools offered on the review pane.
final class DocumentProcessorTests: XCTestCase {

    /// Pure Core Graphics fixture. NSBitmapImageRep + NSGraphicsContext traps in a
    /// non-bundled XCTest host, so the synthetic image is built without AppKit drawing.
    private static func jpeg(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 4, height: height / 4))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private static func pixelSize(_ data: Data) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    // MARK: - Rotate

    func testRotateProducesADecodableImage() throws {
        let output = try DocumentProcessor.rotate(try Self.jpeg(width: 400, height: 300), degrees: 90)
        XCTAssertNotNil(NSImage(data: output))
    }

    func testRotateRejectsNonImageData() {
        XCTAssertThrowsError(try DocumentProcessor.rotate(Data("not an image".utf8), degrees: 90))
    }

    // MARK: - BUG-13: rotation does not preserve pixel dimensions

    func testRotate90SwapsWidthAndHeightExactly() throws {
        let source = try Self.jpeg(width: 400, height: 300)
        let output = try DocumentProcessor.rotate(source, degrees: 90)
        XCTExpectFailure("BUG-13: lockFocus() renders at the current display backing scale, so pixel dimensions are display-dependent")
        XCTAssertEqual(try Self.pixelSize(output), CGSize(width: 300, height: 400))
    }

    func testRotate360IsIdentityInSize() throws {
        let source = try Self.jpeg(width: 400, height: 300)
        let output = try DocumentProcessor.rotate(source, degrees: 360)
        XCTExpectFailure("BUG-13: a full turn should return the same pixel grid")
        XCTAssertEqual(try Self.pixelSize(output), CGSize(width: 400, height: 300))
    }

    // MARK: - BUG-14: every edit inflates the encrypted original into TIFF

    func testRotateDoesNotBalloonTheStoredFile() throws {
        let source = try Self.jpeg(width: 1280, height: 960)
        let output = try DocumentProcessor.rotate(source, degrees: 90)
        XCTExpectFailure("BUG-14: tiffRepresentation returns uncompressed pixels; each revision multiplies on-disk size")
        XCTAssertLessThan(output.count, source.count * 4, "\(source.count) bytes became \(output.count)")
    }

    func testEnhanceDoesNotBalloonTheStoredFile() throws {
        let source = try Self.jpeg(width: 1280, height: 960)
        let output = try DocumentProcessor.enhance(source)
        XCTExpectFailure("BUG-14: enhance also returns uncompressed TIFF")
        XCTAssertLessThan(output.count, source.count * 4, "\(source.count) bytes became \(output.count)")
    }

    // MARK: - Enhance

    func testEnhanceProducesADecodableGrayscaleImage() throws {
        let output = try DocumentProcessor.enhance(try Self.jpeg(width: 200, height: 200))
        XCTAssertNotNil(NSImage(data: output))
    }

    func testEnhanceRejectsNonImageData() {
        XCTAssertThrowsError(try DocumentProcessor.enhance(Data("not an image".utf8)))
    }

    func testEnhancePreservesPixelDimensions() throws {
        let source = try Self.jpeg(width: 320, height: 240)
        XCTAssertEqual(try Self.pixelSize(try DocumentProcessor.enhance(source)), CGSize(width: 320, height: 240))
    }

    // MARK: - Crop

    func testCropRejectsNonImageData() {
        XCTAssertThrowsError(try DocumentProcessor.crop(Data("nope".utf8), normalized: CGRect(x: 0, y: 0, width: 1, height: 1)))
    }

    func testCropRejectsAnOutOfBoundsRectangle() throws {
        let source = try Self.jpeg(width: 200, height: 200)
        XCTAssertThrowsError(try DocumentProcessor.crop(source, normalized: CGRect(x: 2, y: 2, width: 0.5, height: 0.5)))
    }

    // MARK: - BUG-15: crop ignores a negative or zero-area request

    func testCropRejectsANegativeSizedRectangle() throws {
        let source = try Self.jpeg(width: 200, height: 200)
        XCTExpectFailure("BUG-15: a negative width normalises to an empty rect only by luck of .intersection")
        XCTAssertThrowsError(try DocumentProcessor.crop(source, normalized: CGRect(x: 0.5, y: 0.5, width: -0.25, height: 0.25)))
    }

    func testCropReturnsTheRequestedFraction() throws {
        let source = try Self.jpeg(width: 400, height: 400)
        let output = try DocumentProcessor.crop(source, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        XCTExpectFailure("BUG-13/BUG-15: lockFocus scaling makes the cropped pixel size display-dependent")
        XCTAssertEqual(try Self.pixelSize(output), CGSize(width: 200, height: 200))
    }
}
