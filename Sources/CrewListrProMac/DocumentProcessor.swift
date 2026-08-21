import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum DocumentProcessor {
    static func rotate(_ data: Data, degrees: CGFloat) throws -> Data {
        guard let image = NSImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        let radians = degrees * .pi / 180
        let size = image.size
        let canvas = NSImage(size: CGSize(width: abs(size.width * cos(radians)) + abs(size.height * sin(radians)), height: abs(size.width * sin(radians)) + abs(size.height * cos(radians))))
        canvas.lockFocus()
        NSGraphicsContext.current?.cgContext.translateBy(x: canvas.size.width / 2, y: canvas.size.height / 2)
        NSGraphicsContext.current?.cgContext.rotate(by: radians)
        image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        canvas.unlockFocus()
        guard let output = canvas.tiffRepresentation else { throw CocoaError(.fileWriteUnknown) }
        return output
    }

    static func crop(_ data: Data, normalized rect: CGRect) throws -> Data {
        guard let image = NSImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        let bounds = CGRect(x: rect.minX * image.size.width, y: rect.minY * image.size.height, width: rect.width * image.size.width, height: rect.height * image.size.height).intersection(CGRect(origin: .zero, size: image.size))
        guard !bounds.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let result = NSImage(size: bounds.size)
        result.lockFocus()
        image.draw(at: CGPoint(x: -bounds.minX, y: -bounds.minY), from: CGRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        result.unlockFocus()
        guard let output = result.tiffRepresentation else { throw CocoaError(.fileWriteUnknown) }
        return output
    }

    static func enhance(_ data: Data) throws -> Data {
        guard let input = CIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.contrast = 1.35
        filter.saturation = 0
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { throw CocoaError(.fileWriteUnknown) }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)).tiffRepresentation ?? data
    }
}
