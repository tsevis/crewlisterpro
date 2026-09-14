import CoreGraphics
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import CrewListrPro

/// The parts of the shared pipeline that had to be rewritten to leave the Mac,
/// tested on the platform they were rewritten for.
///
/// The Mac suite covers the same code and passes; these exist because "it
/// compiles for iOS" and "it does the same thing on iOS" are different claims,
/// and every one of these three had a way of being quietly wrong on a phone —
/// `UIImage` applying an EXIF rotation the Mac does not, UIKit's flipped text
/// coordinates printing a PDF upside down, a keychain-held key that differs
/// between two opens of the same store.
final class PlatformPipelineTests: XCTestCase {

    // MARK: - Decoding

    private func bitmap(width: Int, height: Int, darkCorner: Bool = true) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if darkCorner {
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width / 4, height: height / 4))
        }
        return try XCTUnwrap(context.makeImage())
    }

    func testAnImageDecodesAtItsTruePixelSize() throws {
        let data = try XCTUnwrap(PlatformImageCodec.encode(try bitmap(width: 400, height: 300), as: .jpeg))
        let decoded = try XCTUnwrap(PlatformImageCodec.decode(data))
        // Not the point size a Retina screen would report, and not a thumbnail:
        // the machine-readable-zone crop is measured in pixels.
        XCTAssertEqual(decoded.width, 400)
        XCTAssertEqual(decoded.height, 300)
    }

    func testSomethingThatIsNotAnImageDecodesToNothingRatherThanTrapping() {
        XCTAssertNil(PlatformImageCodec.decode(Data("not an image".utf8)))
    }

    /// A scanned passport arrives as a PDF as often as a photographed one
    /// arrives as a JPEG, and Vision cannot read a PDF.
    func testAPDFIsRenderedToPixelsSoVisionCanReadIt() throws {
        let pdf = try Self.onePagePDF(width: 300, height: 200)
        let rendered = try XCTUnwrap(PlatformImageCodec.decode(pdf))
        XCTAssertGreaterThan(rendered.width, 300, "a page rendered at 72 dpi has too few pixels for an MRZ")
        XCTAssertEqual(Double(rendered.width) / Double(rendered.height), 1.5, accuracy: 0.02)
    }

    // MARK: - Editing

    func testAQuarterTurnSwapsTheSidesExactly() throws {
        let data = try XCTUnwrap(PlatformImageCodec.encode(try bitmap(width: 400, height: 300), as: .jpeg))
        let turned = try XCTUnwrap(PlatformImageCodec.decode(try DocumentProcessor.rotate(data, degrees: 90)))
        XCTAssertEqual(turned.width, 300)
        XCTAssertEqual(turned.height, 400)
    }

    func testFourQuarterTurnsAreTheIdentity() throws {
        var data = try XCTUnwrap(PlatformImageCodec.encode(try bitmap(width: 640, height: 480), as: .jpeg))
        for _ in 0..<4 { data = try DocumentProcessor.rotate(data, degrees: 90) }
        let result = try XCTUnwrap(PlatformImageCodec.decode(data))
        XCTAssertEqual(result.width, 640)
        XCTAssertEqual(result.height, 480)
    }

    func testAnEditedRevisionDoesNotBalloonTheEncryptedOriginal() throws {
        let data = try XCTUnwrap(PlatformImageCodec.encode(try bitmap(width: 1280, height: 960), as: .jpeg))
        let enhanced = try DocumentProcessor.enhance(data)
        XCTAssertLessThan(enhanced.count, data.count * 4)
    }

    // MARK: - The printed crew list
    //
    // The PDF is drawn with Core Text because the AppKit and UIKit text stacks
    // disagree about which way up a graphics context is. If that port is wrong
    // on this platform, the page is still a valid PDF — it is simply upside
    // down, or empty. Reading the text back is what tells the two apart.

    func testTheCrewListPrintsTextAPortAuthorityCouldRead() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "crew.pdf")

        let boat = Boat(name: "S/Y ELPIDA", flag: "GRC", registrationPort: "PIRAEUS", registrationNumber: "GR-1187-P")
        let trip = Trip(boatID: boat.id, departureDate: Date(timeIntervalSince1970: 1_787_000_000),
                        returnDate: Date(timeIntervalSince1970: 1_787_600_000))
        var document = CrewDocument(tripID: trip.id, personID: UUID(), originalName: "p.jpg", encryptedFileName: "")
        document[.fullName] = "ANNA ERIKSSON"
        document[.documentNumber] = "L898902C3"
        document[.nationality] = "UTO"
        document[.birthDate] = "1974-08-12"
        document[.sex] = "F"

        try ExportService.exportPDF(to: url, trip: trip, boat: boat,
                                    rows: [CrewListRow(document: document, role: .skipper, isClient: true)],
                                    skipperEmail: "anna@example.com")

        let pdf = try XCTUnwrap(PDFDocument(url: url))
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        XCTAssertTrue(text.contains("CREW LIST"), "the title did not reach the page")
        XCTAssertTrue(text.contains("ANNA ERIKSSON"), "the crew did not reach the page")
        XCTAssertTrue(text.contains("L898902C3"), "the passport number did not reach the page")
        XCTAssertTrue(text.contains("S/Y ELPIDA"), "the yacht did not reach the header box")
        XCTAssertTrue(text.contains("anna@example.com"), "the skipper's email did not reach the page")
    }

    // MARK: - The encrypted store

    /// The claim the app makes about where documents live. The database holds
    /// one AES-GCM sealed box and nothing else, so a name typed into it must
    /// not be findable in the file.
    func testTheDatabaseFileContainsNoPlaintext() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "StoreTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try SecureStore(fileManager: ScopedFileManager(root: root))
        // `SecureStore` puts everything in a folder of its own under whatever
        // it is given as Application Support.
        let folder = root.appending(path: "CrewListrPro", directoryHint: .isDirectory)
        var data = AppData()
        data.boats = [Boat(name: "MELTEMI DAWN", flag: "GRC")]
        try await store.save(data)

        let file = try Data(contentsOf: folder.appending(path: "crewlistr.sqlite"))
        XCTAssertFalse(Self.contains(file, "MELTEMI DAWN"), "a yacht's name is readable in the database file")
        XCTAssertFalse(Self.contains(file, "boats"), "the payload's own shape is readable in the database file")
    }

    func testTheStoreReadsBackWhatItWrote() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "StoreTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var data = AppData()
        data.boats = [Boat(name: "MELTEMI DAWN", flag: "GRC")]
        let written = try SecureStore(fileManager: ScopedFileManager(root: root))
        try await written.save(data)

        // A second open, which is what a relaunch is. The key comes from the
        // Keychain rather than from this process's memory, so this is the test
        // that a restart can still read yesterday's charter.
        let reopened = try SecureStore(fileManager: ScopedFileManager(root: root))
        let recovered = try await reopened.load()
        XCTAssertEqual(recovered.boats.first?.name, "MELTEMI DAWN")
    }

    func testTheStoreIsKeptOutOfBackups() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "StoreTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try SecureStore(fileManager: ScopedFileManager(root: root))

        let folder = root.appending(path: "CrewListrPro", directoryHint: .isDirectory)
        let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true,
                       "sealed scans would travel to iCloud without the key that opens them")
    }

    // MARK: - Fixtures

    private static func contains(_ haystack: Data, _ needle: String) -> Bool {
        haystack.range(of: Data(needle.utf8)) != nil
    }

    private static func onePagePDF(width: CGFloat, height: CGFloat) throws -> Data {
        let output = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let consumer = try XCTUnwrap(CGDataConsumer(data: output))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(gray: 0.2, alpha: 1)
        context.fill(CGRect(x: 10, y: 10, width: width - 20, height: height - 20))
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }
}
