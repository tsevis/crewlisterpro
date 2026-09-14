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

    /// Average brightness of a decoded image, 0 (black) to 1 (white).
    private static func meanLuminance(_ data: Data) throws -> Double {
        let image = try XCTUnwrap(PlatformImageCodec.decode(data))
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count) / 255
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

    // MARK: - Rotation preserves the pixel grid
    //
    // Recorded here as BUG-13 while the implementation went through
    // `NSImage.lockFocus`, which renders at the current display's backing
    // scale: the same rotation returned 600×800 on a Retina Mac and 300×400 on
    // an external display, and a full turn was not the identity. The Core
    // Graphics context this file now makes is exactly the size it asks for.

    func testRotate90SwapsWidthAndHeightExactly() throws {
        let source = try Self.jpeg(width: 400, height: 300)
        let output = try DocumentProcessor.rotate(source, degrees: 90)
        XCTAssertEqual(try Self.pixelSize(output), CGSize(width: 300, height: 400))
    }

    func testRotate360IsIdentityInSize() throws {
        let source = try Self.jpeg(width: 400, height: 300)
        let output = try DocumentProcessor.rotate(source, degrees: 360)
        XCTAssertEqual(try Self.pixelSize(output), CGSize(width: 400, height: 300))
    }

    /// Four presses of the one button in the interface.
    func testFourQuarterTurnsReturnTheOriginalGrid() throws {
        var data = try Self.jpeg(width: 640, height: 480)
        for _ in 0..<4 { data = try DocumentProcessor.rotate(data, degrees: 90) }
        XCTAssertEqual(try Self.pixelSize(data), CGSize(width: 640, height: 480))
    }

    // MARK: - An edit does not inflate the encrypted original
    //
    // BUG-14: `tiffRepresentation` returns uncompressed pixels, so a 300 KB
    // photograph became a 3.6 MB revision — sealed, and kept beside every other
    // revision of the same page forever. Revisions are written as JPEG now.

    func testRotateDoesNotBalloonTheStoredFile() throws {
        let source = try Self.jpeg(width: 1280, height: 960)
        let output = try DocumentProcessor.rotate(source, degrees: 90)
        XCTAssertLessThan(output.count, source.count * 4, "\(source.count) bytes became \(output.count)")
    }

    func testEnhanceDoesNotBalloonTheStoredFile() throws {
        let source = try Self.jpeg(width: 1280, height: 960)
        let output = try DocumentProcessor.enhance(source)
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

    // MARK: - A crop that would return nothing is refused
    //
    // BUG-15: a negative width used to normalise to an empty rectangle only by
    // the luck of `.intersection`, and a crop that returns a blank page loses
    // the operator their document.

    func testCropRejectsANegativeSizedRectangle() throws {
        let source = try Self.jpeg(width: 200, height: 200)
        XCTAssertThrowsError(try DocumentProcessor.crop(source, normalized: CGRect(x: 0.5, y: 0.5, width: -0.25, height: 0.25)))
    }

    func testCropRejectsAZeroAreaRectangle() throws {
        let source = try Self.jpeg(width: 200, height: 200)
        XCTAssertThrowsError(try DocumentProcessor.crop(source, normalized: CGRect(x: 0.5, y: 0.5, width: 0, height: 0.25)))
    }

    func testCropReturnsTheRequestedFraction() throws {
        let source = try Self.jpeg(width: 400, height: 400)
        let output = try DocumentProcessor.crop(source, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(try Self.pixelSize(output), CGSize(width: 200, height: 200))
    }

    /// The rectangle is measured from the top-left, the way `CGImage` measures
    /// and the way a crop gesture on screen reports itself. The fixture paints
    /// its one black square into the bottom-left quarter, so the top-left
    /// quarter of it is white and the bottom-left quarter is not.
    func testCropMeasuresFromTheTopLeft() throws {
        let source = try Self.jpeg(width: 400, height: 400)
        let top = try DocumentProcessor.crop(source, normalized: CGRect(x: 0, y: 0, width: 0.25, height: 0.25))
        let bottom = try DocumentProcessor.crop(source, normalized: CGRect(x: 0, y: 0.75, width: 0.25, height: 0.25))
        XCTAssertGreaterThan(try Self.meanLuminance(top), 0.9, "the top-left corner of the fixture is white")
        XCTAssertLessThan(try Self.meanLuminance(bottom), 0.1, "the bottom-left corner of the fixture is black")
    }
}
