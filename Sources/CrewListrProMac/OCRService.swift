import CoreGraphics
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
        guard let image = PlatformImageCodec.decode(contentsOf: url) else { return unreadable }
        return try extract(image: image)
    }

    /// Re-reads an already-imported document from its decrypted bytes, so the
    /// review pane can re-analyse without touching the original file again.
    static func extract(from data: Data) throws -> OCRResult {
        guard let image = PlatformImageCodec.decode(data) else { return unreadable }
        return try extract(image: image)
    }

    /// The answer for a file no image decoder on either platform can open. It
    /// is a result rather than a thrown error because an unreadable file is
    /// still a document the operator imported and can look at — it arrives on
    /// the trip with every field blank and its own reason attached, instead of
    /// failing the whole import.
    private static let unreadable = OCRResult(
        fields: [:], risk: .review,
        reasons: ["Preview or OCR is unavailable for this file."], rawText: ""
    )

    /// Reads a page that has already been decoded to pixels.
    ///
    /// `CGImage` rather than a platform image class, so the same bytes give the
    /// same reading on a Mac and on a phone: `UIImage` would have applied the
    /// EXIF rotation and `NSImage` would have reported a point size that is not
    /// the pixel size, and the band crop below is measured in pixels.
    static func extract(image cgImage: CGImage) throws -> OCRResult {
        let text = try read(cgImage)
        var mrz = MRZ.parse(text)

        // A second look at the machine-readable zone alone, when the first pass
        // did not come back with a name.
        //
        // Every field except the name comes from line 2, which carries check
        // digits; the name is the only thing line 1 has, and line 1 has no
        // arithmetic behind it at all. So the failure this addresses is
        // specific and was measured on real documents: of six passports in a
        // working store, three had a perfect line 2 and no name — one had lost
        // the `P<XXX` prefix off the front of line 1, one had thirteen digits
        // smeared through it, and one had no line 1 recognised at all.
        //
        // The cause is not the parser. On a photographed page the zone is a
        // narrow strip of a large image, and a whole-page pass gives it very
        // few pixels. Cropping to the strip and enlarging it gives the
        // recogniser the same characters several times the size.
        if mrz?["full_name"] == nil, let band = machineReadableBand(of: cgImage) {
            let bandText = try read(band, languages: ["en-US"])
            if let better = MRZ.parse(bandText), better["full_name"] != nil {
                // Accepted only if the closer look is reading the same
                // document. Both line 2s carry a checksum-valid document
                // number, so disagreement means the crop caught something else
                // — and a name taken from another page is worse than no name.
                let sameDocument = mrz == nil || better["document_number"] == mrz?["document_number"]
                if sameDocument { mrz = better }
            }

            // Still nothing. The recogniser reports several readings of each
            // line and only the first has been looked at so far; the others
            // cost nothing and are already sitting there.
            //
            // Choosing among them is not the same as inventing a name. Every
            // character considered is one the recogniser actually proposed, and
            // the reading is only taken if it satisfies the grammar line 1 must
            // obey — letters and fillers, no digits, a `<<` between surname and
            // given names, and the issuing state that line 2 has proved with a
            // check digit.
            if mrz?["full_name"] == nil,
               let state = mrz?["nationality"],
               let recovered = MRZ.bestName(among: try readCandidates(band), issuedBy: state) {
                mrz?["full_name"] = recovered
            }
        }

        if let mrz {
            var reasons = ["Machine-readable zone read; document number, birth date and expiry all checksum-valid."]
            if mrz["full_name"] == nil {
                reasons.append("The name line could not be read — type it from the image.")
            }
            return OCRResult(fields: mrz, risk: .review, reasons: reasons, rawText: text)
        }
        return OCRResult(fields: MRZ.fallback(text), risk: .review, reasons: ["No checksum-valid machine-readable zone; every field needs checking against the image."], rawText: text)
    }

    /// One recognition pass.
    ///
    /// The language list is for the printed page, not the zone: a passport's
    /// own page is in its issuing country's language, and the zone itself is
    /// OCR-B Latin whatever the country. The targeted pass therefore asks for
    /// English alone — offering it Cyrillic or Greek only invites a character
    /// from another script into a line that cannot legally contain one.
    private static func read(
        _ image: CGImage,
        languages: [String] = ["en-US", "uk-UA", "ru-RU", "el-GR", "hu-HU", "ro-RO", "pl-PL", "it-IT", "de-DE", "fr-FR"]
    ) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Every reading the recogniser proposed, not only the likeliest.
    private static func readCandidates(_ image: CGImage, perLine: Int = 4) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).flatMap { observation in
            observation.topCandidates(perLine).map(\.string)
        }
    }

    /// The bottom strip of the page, enlarged.
    ///
    /// On every TD3 travel document the zone is the last two lines of the data
    /// page, so the bottom third is where it is — with room to spare, because a
    /// page photographed by hand is never square to the camera. Grey rather
    /// than colour: the zone is black OCR-B on a pale ground, and the colour
    /// channels carry only the security print that OCR mistakes for letters.
    private static func machineReadableBand(of image: CGImage, scale: Int = 3) -> CGImage? {
        let bandHeight = CGFloat(image.height) * 0.34
        let crop = CGRect(x: 0, y: CGFloat(image.height) - bandHeight, width: CGFloat(image.width), height: bandHeight)
        guard let cropped = image.cropping(to: crop) else { return nil }

        // Enlarging beyond a few thousand pixels wide costs time and buys
        // nothing, so the scale gives way to a ceiling.
        let width = min(cropped.width * scale, 4000)
        let height = Int(CGFloat(cropped.height) * (CGFloat(width) / CGFloat(cropped.width)))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
