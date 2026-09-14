import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The three edits offered on a stored document: turn it, trim it, lift it.
///
/// Every one of them goes bitmap in, bitmap out, through Core Graphics alone.
/// It used to go through `NSImage.lockFocus`, which is why the tests for this
/// file carried three recorded bugs: `lockFocus` renders at the *display's*
/// backing scale, so a rotation returned a different pixel grid on a Retina
/// Mac than on an external display and a full turn was not the identity; and
/// `tiffRepresentation` returns uncompressed pixels, so every edit multiplied
/// the size of the encrypted original on disk. Neither is true of a context
/// this file makes itself, at the size it asks for.
enum DocumentProcessor {

    /// What an edited revision is written as.
    ///
    /// JPEG, not TIFF. A photographed passport is already a JPEG, and
    /// re-encoding it uncompressed turned a 300 KB original into a 3.6 MB
    /// revision — which is then sealed and kept forever beside every other
    /// revision of the same page. The quality is high enough that the machine-
    /// readable zone survives a re-read, which is checked by re-running OCR
    /// after every edit.
    private static let revisionQuality: CGFloat = 0.92

    /// Turns the page clockwise.
    ///
    /// Clockwise for a positive angle, which is the direction "rotate right"
    /// means everywhere else; the iOS review pane offers both directions and
    /// passes -90 for the other one.
    static func rotate(_ data: Data, degrees: CGFloat) throws -> Data {
        guard let image = PlatformImageCodec.decode(data) else { throw CocoaError(.fileReadCorruptFile) }
        let radians = -degrees * .pi / 180
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        // The bounding box of the turned rectangle, rounded to whole pixels.
        //
        // Rounded and not `.integral`: cos(π/2) is not exactly zero in binary
        // floating point, so a quarter turn of a 400×300 page measures
        // 300.00000000000006 wide and `.integral` — which expands outwards —
        // would make that 301, leaving a one-pixel white seam that the next
        // quarter turn widens. Rounding gives back exactly the original grid
        // with its sides swapped, so four presses of the button are the
        // identity.
        let bounding = CGRect(x: 0, y: 0, width: width, height: height)
            .applying(CGAffineTransform(rotationAngle: radians))
        let canvas = CGSize(width: bounding.width.rounded(), height: bounding.height.rounded())
        guard let context = makeContext(width: Int(canvas.width), height: Int(canvas.height)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
        context.rotate(by: radians)
        context.draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        return try encoded(context.makeImage())
    }

    /// Trims the page to a fraction of itself.
    ///
    /// The rectangle is in the image's own coordinates — origin top-left, x and
    /// y from 0 to 1 — which is how a crop gesture on screen reports itself and
    /// how `CGImage` measures. An empty, inverted or out-of-bounds rectangle is
    /// refused rather than quietly shrunk to nothing: a crop that returns a
    /// blank page loses the operator their document.
    static func crop(_ data: Data, normalized rect: CGRect) throws -> Data {
        guard let image = PlatformImageCodec.decode(data) else { throw CocoaError(.fileReadCorruptFile) }
        // `rect.size`, not `rect.width`: the property is the *standardised*
        // width and reports a rectangle 0.25 wide as 0.25 whether it was asked
        // for as -0.25 or +0.25. A negative request is a gesture that ran
        // backwards, not a rectangle, and quietly reflecting it crops somewhere
        // the operator did not point at.
        guard rect.size.width > 0, rect.size.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let bounds = CGRect(x: rect.minX * CGFloat(image.width),
                            y: rect.minY * CGFloat(image.height),
                            width: rect.width * CGFloat(image.width),
                            height: rect.height * CGFloat(image.height))
            .intersection(CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
            .integral
        guard !bounds.isNull, bounds.width >= 1, bounds.height >= 1,
              let cropped = image.cropping(to: bounds) else { throw CocoaError(.fileReadCorruptFile) }
        return try encoded(cropped)
    }

    /// Grey, with the contrast lifted — the state a faint or yellowed scan has
    /// to reach before the machine-readable zone is legible to OCR.
    static func enhance(_ data: Data) throws -> Data {
        guard let decoded = PlatformImageCodec.decode(data) else { throw CocoaError(.fileReadCorruptFile) }
        let filter = CIFilter.colorControls()
        filter.inputImage = CIImage(cgImage: decoded)
        filter.contrast = 1.35
        filter.saturation = 0
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { throw CocoaError(.fileWriteUnknown) }
        return try encoded(cgImage)
    }

    /// A bitmap context at exactly the pixel size asked for, in sRGB.
    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        // A document has no transparency, and a rotation exposes corners that
        // are outside the page. White is what the page's own margin is.
        context?.setFillColor(gray: 1, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context?.interpolationQuality = .high
        return context
    }

    private static func encoded(_ image: CGImage?) throws -> Data {
        guard let image,
              let data = PlatformImageCodec.encode(image, as: .jpeg, quality: revisionQuality)
        else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
