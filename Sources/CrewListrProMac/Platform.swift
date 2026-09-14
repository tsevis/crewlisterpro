#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The handful of names AppKit and UIKit spell differently.
///
/// Deliberately small. Everything below this file works in `CGImage` and
/// `Data`, which both platforms have in the same shape — the typealiases exist
/// for the three places where a *view* has to hand a bitmap or a colour to
/// SwiftUI, and for nothing else. A second set of `#if` blocks scattered
/// through the image pipeline is what this file is there to prevent.
#if canImport(AppKit)
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#else
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#endif

extension PlatformImage {
    /// The bitmap behind this image, whatever the platform wraps it in.
    ///
    /// `NSImage` can hold several representations and vector art, so it is
    /// asked for a rendering; `UIImage` either has a `CGImage` or was built
    /// from a `CIImage`, and the second case is rendered rather than dropped.
    var platformCGImage: CGImage? {
        #if canImport(AppKit)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        if let existing = cgImage { return existing }
        guard let ciImage else { return nil }
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
        #endif
    }

    /// Wraps a bitmap at its own pixel size.
    static func from(cgImage: CGImage) -> PlatformImage {
        #if canImport(AppKit)
        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }
}

extension Image {
    /// One spelling for `Image(nsImage:)` and `Image(uiImage:)`.
    init(platformImage: PlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

extension Color {
    init(platformColor: PlatformColor) {
        #if canImport(AppKit)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}

/// Decoding and encoding bitmaps without going through a platform image class.
///
/// `NSImage(data:)` and `UIImage(data:)` are not interchangeable in the ways
/// that matter here: `UIImage` silently applies the EXIF orientation and
/// `NSImage` reports a point size that is not the pixel size on a Retina Mac.
/// ImageIO does neither, on either platform, so the pipeline that reads a
/// passport reads the same pixels on both.
enum PlatformImageCodec {

    /// The first frame of an image file, at its true pixel size.
    ///
    /// Orientation is applied here rather than left to the caller: a passport
    /// photographed sideways carries its rotation in EXIF, and Vision reads
    /// pixels, not metadata — an unrotated page is one whose machine-readable
    /// zone runs up the side of the image and is never found.
    static func decode(_ data: Data) -> CGImage? {
        // Asked first, because ImageIO does not politely decline a PDF — it
        // logs three lines of `failed to create image` per attempt, and a
        // charter of scanned passports would fill the log with errors that are
        // not errors.
        if data.starts(with: Array("%PDF".utf8)) { return pdfPage(data) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return pdfPage(data) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        guard let orientation = CGImagePropertyOrientation(rawValue: raw), orientation != .up else { return image }
        return rotated(image, to: orientation)
    }

    static func decode(contentsOf url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// A scanned document arrives as a PDF as often as a photograph arrives as
    /// a JPEG, and Vision cannot read a PDF. The first page is rendered at
    /// roughly 200 dpi, which is what the machine-readable zone needs.
    static func pdfPage(_ data: Data, number: Int = 1, scale: CGFloat = 2.8) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: max(1, min(number, document.numberOfPages)))
        else { return nil }
        let bounds = page.getBoxRect(.mediaBox)
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceDeviceRGBOrGray(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(page)
        return context.makeImage()
    }

    /// Bytes a file can be written from, and both platforms can read back.
    ///
    /// `quality` is ignored by the lossless formats, which is why it has a
    /// default rather than a separate entry point.
    static func encode(_ image: CGImage, as type: UTType = .jpeg, quality: CGFloat = 0.92) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Redraws a bitmap the right way up, so what Vision sees is what a person
    /// sees.
    static func rotated(_ image: CGImage, to orientation: CGImagePropertyOrientation) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let quarterTurned: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: quarterTurned = true
        default: quarterTurned = false
        }
        let canvas = CGSize(width: quarterTurned ? height : width, height: quarterTurned ? width : height)
        guard let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.concatenate(transform(for: orientation, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: quarterTurned ? height : width, height: quarterTurned ? width : height))
        return context.makeImage()
    }

    /// The eight EXIF orientations, as the affine transform that undoes each.
    private static func transform(for orientation: CGImagePropertyOrientation, width: CGFloat, height: CGFloat) -> CGAffineTransform {
        switch orientation {
        case .up: .identity
        case .upMirrored: CGAffineTransform(translationX: width, y: 0).scaledBy(x: -1, y: 1)
        case .down: CGAffineTransform(translationX: width, y: height).rotated(by: .pi)
        case .downMirrored: CGAffineTransform(translationX: 0, y: height).scaledBy(x: 1, y: -1)
        case .left: CGAffineTransform(translationX: 0, y: width).rotated(by: -.pi / 2)
        case .leftMirrored: CGAffineTransform(translationX: 0, y: width).rotated(by: -.pi / 2).translatedBy(x: width, y: 0).scaledBy(x: -1, y: 1)
        case .right: CGAffineTransform(translationX: height, y: 0).rotated(by: .pi / 2)
        case .rightMirrored: CGAffineTransform(translationX: height, y: 0).rotated(by: .pi / 2).translatedBy(x: width, y: 0).scaledBy(x: -1, y: 1)
        }
    }

    private static func CGColorSpaceDeviceRGBOrGray() -> CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}
