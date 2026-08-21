// Applies the macOS app-icon shape to flat square artwork.
//
// Since Big Sur every system icon sits on the same grid: a 1024pt canvas with
// the artwork inset to an 824pt rounded square, corner radius 185.4pt, drawn
// with a soft shadow beneath. Shipping a full-bleed square instead leaves the
// icon reading as a hard-edged tile among its rounded neighbours in the Dock.
//
//   swift scripts/mask-icon.swift <source.png> <output.png>

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Apple's macOS icon grid, expressed for a 1024pt canvas.
private enum IconGrid {
    static let canvas: CGFloat = 1024
    static let body: CGFloat = 824
    static let cornerRadius: CGFloat = 185.4
    static var inset: CGFloat { (canvas - body) / 2 }

    /// Continuous ("squircle") corners, as the system uses — a circular-arc
    /// rounded rectangle is visibly a different shape at this radius.
    static var bodyPath: CGPath {
        let rect = CGRect(x: inset, y: inset, width: body, height: body)
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: rect)
            .cgPath
    }

    static let shadowOffset = CGSize(width: 0, height: -10)
    static let shadowBlur: CGFloat = 16
    static let shadowAlpha: CGFloat = 0.30
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("mask-icon: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: mask-icon.swift <source.png> <output.png>") }
let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fail("could not read \(sourceURL.lastPathComponent)")
}
guard artwork.width == artwork.height else {
    fail("artwork must be square; got \(artwork.width)x\(artwork.height)")
}

let scale = IconGrid.canvas
guard let context = CGContext(
    data: nil,
    width: Int(scale), height: Int(scale),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fail("could not create the drawing context") }

context.interpolationQuality = .high
context.clear(CGRect(x: 0, y: 0, width: scale, height: scale))

let body = CGRect(x: IconGrid.inset, y: IconGrid.inset, width: IconGrid.body, height: IconGrid.body)
let path = IconGrid.bodyPath

// The shadow is cast by the shape, so fill it opaquely first, then paint the
// artwork inside the same silhouette.
context.saveGState()
context.setShadow(offset: IconGrid.shadowOffset, blur: IconGrid.shadowBlur,
                  color: CGColor(gray: 0, alpha: IconGrid.shadowAlpha))
context.addPath(path)
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(path)
context.clip()
context.draw(artwork, in: body)
context.restoreGState()

guard let masked = context.makeImage() else { fail("could not render the icon") }
guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fail("could not write \(outputURL.lastPathComponent)")
}
CGImageDestinationAddImage(destination, masked, nil)
guard CGImageDestinationFinalize(destination) else { fail("could not finalise \(outputURL.lastPathComponent)") }

FileHandle.standardError.write(Data("mask-icon: wrote \(outputURL.path)\n".utf8))
