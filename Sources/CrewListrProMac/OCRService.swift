import AppKit
import Foundation
import Vision

struct OCRResult: Sendable {
    var fields: [String: String]
    var risk: RiskLevel
    var reasons: [String]
    var rawText: String
}

enum OCRService {
    static func extract(from url: URL) throws -> OCRResult {
        guard let image = NSImage(contentsOf: url) else {
            return OCRResult(fields: [:], risk: .review, reasons: ["Preview or OCR is unavailable for this file."], rawText: "")
        }
        return try extract(image: image)
    }

    /// Re-reads an already-imported document from its decrypted bytes, so the
    /// review pane can re-analyse without touching the original file again.
    static func extract(from data: Data) throws -> OCRResult {
        guard let image = NSImage(data: data) else {
            return OCRResult(fields: [:], risk: .review, reasons: ["Preview or OCR is unavailable for this file."], rawText: "")
        }
        return try extract(image: image)
    }

    private static func extract(image: NSImage) throws -> OCRResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return OCRResult(fields: [:], risk: .review, reasons: ["Preview or OCR is unavailable for this file."], rawText: "")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "uk-UA", "ru-RU", "el-GR"]
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        if let mrz = MRZ.parse(text) {
            var reasons = ["Machine-readable zone read; document number, birth date and expiry all checksum-valid."]
            if mrz["full_name"] == nil {
                reasons.append("The name line could not be read — type it from the image.")
            }
            return OCRResult(fields: mrz, risk: .review, reasons: reasons, rawText: text)
        }
        return OCRResult(fields: MRZ.fallback(text), risk: .review, reasons: ["No checksum-valid machine-readable zone; every field needs checking against the image."], rawText: text)
    }
}
