import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CrewListrProMac

/// Renders synthetic ICAO 9303 TD3 specimen data pages.
///
/// Real passports must never end up in documentation or in a repository, so the
/// screenshots and demo fixtures are produced from fictional specimens whose MRZ
/// check digits are nonetheless valid — Vision reads them exactly as it reads a
/// photographed passport.
enum SpecimenGenerator {

    struct Specimen {
        let surname: String
        let givenNames: String
        let number: String          // 9 characters, no filler
        let nationality: String     // 3-letter code
        let birth: String           // YYMMDD
        let sex: String             // M / F
        let expiry: String          // YYMMDD
        let personalNumber: String  // up to 14 characters
        let issuingAuthority: String
        let placeOfBirth: String
    }

    static let demoCrew: [Specimen] = [
        .init(surname: "ERIKSSON", givenNames: "ANNA MARIA", number: "L898902C3", nationality: "UTO",
              birth: "740812", sex: "F", expiry: "320415", personalNumber: "ZE184226B",
              issuingAuthority: "UTOPIA MFA", placeOfBirth: "ZENITH/UTO"),
        .init(surname: "PAPADOPOULOS", givenNames: "NIKOLAOS", number: "AB1234567", nationality: "GRC",
              birth: "830219", sex: "M", expiry: "310630", personalNumber: "",
              issuingAuthority: "HELLENIC POLICE", placeOfBirth: "PIRAEUS/GRC"),
        .init(surname: "ROSSI", givenNames: "GIULIA", number: "YA9876543", nationality: "ITA",
              birth: "950704", sex: "F", expiry: "290913", personalNumber: "",
              issuingAuthority: "QUESTURA DI BARI", placeOfBirth: "BARI/ITA"),
    ]

    // MARK: - MRZ assembly

    static func checkDigit(_ value: String) -> String {
        let weights = [7, 3, 1]
        let total = value.enumerated().reduce(0) { running, item in
            let digit: Int
            if let number = item.element.wholeNumberValue { digit = number }
            else if let ascii = item.element.asciiValue, ascii >= 65, ascii <= 90 { digit = Int(ascii - 65) + 10 }
            else { digit = 0 }
            return running + digit * weights[item.offset % weights.count]
        }
        return String(total % 10)
    }

    private static func pad(_ value: String, _ length: Int) -> String {
        String(value.prefix(length)) + String(repeating: "<", count: max(0, length - value.count))
    }

    static func mrz(_ specimen: Specimen) -> (line1: String, line2: String) {
        let names = "\(specimen.surname)<<\(specimen.givenNames.replacingOccurrences(of: " ", with: "<"))"
        let line1 = pad("P<\(specimen.nationality)\(names)", 44)

        let number = pad(specimen.number, 9)
        let numberCheck = checkDigit(number)
        let birthCheck = checkDigit(specimen.birth)
        let expiryCheck = checkDigit(specimen.expiry)
        let personal = pad(specimen.personalNumber, 14)
        let personalCheck = checkDigit(personal)
        let composite = number + numberCheck + specimen.birth + birthCheck + specimen.expiry + expiryCheck + personal + personalCheck
        let line2 = number + numberCheck + specimen.nationality + specimen.birth + birthCheck
            + specimen.sex + specimen.expiry + expiryCheck + personal + personalCheck + checkDigit(composite)
        return (line1, line2)
    }

    // MARK: - Rendering

    private static func draw(_ text: String, at point: CGPoint, size: CGFloat, bold: Bool = false, gray: CGFloat = 0.1, in context: CGContext) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: CGColor(gray: gray, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func drawMRZ(_ text: String, at point: CGPoint, in context: CGContext) {
        // A wide, evenly tracked monospace approximates the OCR-B of a real
        // passport closely enough for Vision to resolve every glyph.
        let font = CTFontCreateWithName("Menlo-Regular" as CFString, 25, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: CGColor(gray: 0.05, alpha: 1), .kern: 1.6,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    /// A scan whose machine-readable zone is obscured, the way a glare band or a
    /// fold across the bottom of a photographed passport destroys it. The app
    /// must fall back to the review path for these.
    static func damagedPNG(_ specimen: Specimen) throws -> Data {
        try png(specimen, obscureMRZ: true)
    }

    static func png(_ specimen: Specimen, obscureMRZ: Bool = false) throws -> Data {
        let width = 1250, height = 880
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))

        context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Guilloche-ish background wash so the page is not a flat white rectangle.
        context.setStrokeColor(CGColor(red: 0.86, green: 0.88, blue: 0.83, alpha: 1))
        context.setLineWidth(1)
        for step in stride(from: 0, through: width, by: 14) {
            context.move(to: CGPoint(x: step, y: 190))
            context.addLine(to: CGPoint(x: step + 90, y: height - 40))
        }
        context.strokePath()

        // Photo placeholder.
        context.setFillColor(CGColor(gray: 0.78, alpha: 1))
        context.fill(CGRect(x: 60, y: 230, width: 300, height: 400))
        draw("SPECIMEN", at: CGPoint(x: 105, y: 415), size: 34, bold: true, gray: 0.55, in: context)
        draw("NOT A REAL", at: CGPoint(x: 96, y: 375), size: 26, bold: true, gray: 0.55, in: context)
        draw("DOCUMENT", at: CGPoint(x: 104, y: 340), size: 26, bold: true, gray: 0.55, in: context)

        draw("PASSPORT", at: CGPoint(x: 60, y: 800), size: 30, bold: true, in: context)
        draw("SPECIMEN  ·  \(specimen.nationality)", at: CGPoint(x: 430, y: 800), size: 30, bold: true, in: context)

        let rows: [(String, String)] = [
            ("Type / Code / Passport No.", "P    \(specimen.nationality)    \(specimen.number)"),
            ("Surname", specimen.surname),
            ("Given names", specimen.givenNames),
            ("Nationality", specimen.nationality),
            ("Date of birth", formatted(specimen.birth)),
            ("Sex / Place of birth", "\(specimen.sex)    \(specimen.placeOfBirth)"),
            ("Date of expiry", formatted(specimen.expiry)),
            ("Authority", specimen.issuingAuthority),
        ]
        var y: CGFloat = 700
        for (label, value) in rows {
            draw(label, at: CGPoint(x: 430, y: y), size: 17, gray: 0.42, in: context)
            draw(value, at: CGPoint(x: 430, y: y - 30), size: 27, bold: true, in: context)
            y -= 68
        }

        let zone = mrz(specimen)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 150))
        drawMRZ(zone.line1, at: CGPoint(x: 40, y: 95), in: context)
        drawMRZ(zone.line2, at: CGPoint(x: 40, y: 40), in: context)

        if obscureMRZ {
            // Specular glare band across the MRZ, as a phone flash produces.
            context.setFillColor(CGColor(gray: 1, alpha: 0.94))
            context.fill(CGRect(x: 0, y: 18, width: width, height: 120))
            context.setFillColor(CGColor(gray: 0.9, alpha: 0.7))
            context.fill(CGRect(x: 0, y: 0, width: width, height: 150))
        }

        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private static func formatted(_ yymmdd: String) -> String {
        guard yymmdd.count == 6 else { return yymmdd }
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        let month = Int(yymmdd.dropFirst(2).prefix(2)) ?? 1
        return "\(yymmdd.suffix(2)) \(months[max(0, min(11, month - 1))]) \(yymmdd.prefix(2))"
    }

    @discardableResult
    static func write(to directory: URL, includeDamagedScan: Bool = false) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls = try demoCrew.map { specimen -> URL in
            let url = directory.appending(path: "specimen-\(specimen.number).png")
            try png(specimen).write(to: url, options: .atomic)
            return url
        }
        if includeDamagedScan, let specimen = demoCrew.last {
            let url = directory.appending(path: "glare-scan-\(specimen.number).png")
            try damagedPNG(specimen).write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }
}

final class SpecimenGeneratorTests: XCTestCase {

    func testGeneratedMRZMatchesTheICAOSpecimen() {
        let zone = SpecimenGenerator.mrz(SpecimenGenerator.demoCrew[0])
        XCTAssertTrue(zone.line1.hasPrefix("P<UTOERIKSSON<<ANNA<MARIA<"), zone.line1)
        XCTAssertEqual(zone.line1.count, 44, zone.line1)
        XCTAssertEqual(zone.line2.count, 44)
        XCTAssertTrue(zone.line2.hasPrefix("L898902C36UTO7408122F"), zone.line2)
    }

    func testEveryGeneratedSpecimenParsesThroughTheShippingParser() {
        for specimen in SpecimenGenerator.demoCrew {
            let zone = SpecimenGenerator.mrz(specimen)
            let parsed = MRZ.parse("\(zone.line1)\n\(zone.line2)")
            XCTAssertEqual(parsed?["document_number"], specimen.number, specimen.surname)
            XCTAssertEqual(parsed?["sex"], specimen.sex, specimen.surname)
        }
    }

    func testADamagedScanFallsBackToTheReviewPath() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "crewlistr-damaged-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "glare.png")
        try SpecimenGenerator.damagedPNG(SpecimenGenerator.demoCrew[2]).write(to: url)

        let result = try OCRService.extract(from: url)
        XCTAssertEqual(result.risk, .review, "an unreadable MRZ must not clear the gate")
        XCTAssertTrue(result.reasons.contains { $0.contains("No checksum-valid machine-readable zone") }, "\(result.reasons)")
    }

    /// Writes the fictional passports somewhere they can be used.
    ///
    /// Opt-in, like every other test here that produces a file. It exists for
    /// the iOS build: the share-sheet path can only be exercised end to end by
    /// actually sharing a passport into it, and the one thing that must never
    /// be used for that is a real one.
    ///
    ///     CREWLISTR_SPECIMEN_OUT=/tmp/specimens swift test --filter testWritesTheFictionalPassports
    func testWritesTheFictionalPassports() throws {
        guard let path = ProcessInfo.processInfo.environment["CREWLISTR_SPECIMEN_OUT"], !path.isEmpty else {
            throw XCTSkip("Set CREWLISTR_SPECIMEN_OUT to write the specimen passports.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let written = try SpecimenGenerator.write(to: directory, includeDamagedScan: true)
        XCTAssertFalse(written.isEmpty)
    }

    /// Round-trips a rendered specimen through Vision to prove the fixture is
    /// legible to the same OCR path the app uses on a photographed passport.
    func testRenderedSpecimenSurvivesTheRealOCRPipeline() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "crewlistr-specimen-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try SpecimenGenerator.write(to: directory)

        for url in urls {
            let result = try OCRService.extract(from: url)
            // Extraction never clears a document by itself — the operator does.
            // What it must do is read every field correctly.
            XCTAssertEqual(result.risk, .review, url.lastPathComponent)
            XCTAssertFalse((result.fields["full_name"] ?? "").isEmpty, "\(url.lastPathComponent):\n\(result.rawText)")
            XCTAssertFalse((result.fields["document_number"] ?? "").isEmpty, url.lastPathComponent)
            XCTAssertFalse((result.fields["birth_date"] ?? "").isEmpty, url.lastPathComponent)
        }
    }
}
