import Foundation
import XCTest
@testable import CrewListrProMac

/// What may be dropped on the review pane.
///
/// Importing was a file panel and nothing else — an operator with a folder of
/// scans in the Finder had to open a dialog and navigate back to where they
/// already were. Dropping the files is the shorter path, and the only new
/// question it asks is which of the things a Finder drag can carry this app
/// can actually read.
final class DocumentDropTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "drop-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    @discardableResult
    private func file(_ name: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? scratch).appending(path: name)
        try Data("x".utf8).write(to: url)
        return url
    }

    // MARK: - What is a document

    func testAPhotographIsImportable() throws {
        let jpeg = try file("passport.jpeg")

        XCTAssertEqual(DocumentDrop.importable(from: [jpeg]), [jpeg])
    }

    func testAScanIsImportable() throws {
        let pdf = try file("passport.pdf")

        XCTAssertEqual(DocumentDrop.importable(from: [pdf]), [pdf])
    }

    /// The file panel offers images and PDFs only, and a drop must not be a way
    /// around that: a spreadsheet handed to Vision produces a document with
    /// nothing in it and a row in the list nobody can review.
    func testAnythingElseIsRefused() throws {
        let sheet = try file("bookings.csv")
        let archive = try file("scans.zip")

        XCTAssertTrue(DocumentDrop.importable(from: [sheet, archive]).isEmpty)
    }

    func testTheImportableOnesSurviveADropThatAlsoHeldRubbish() throws {
        let jpeg = try file("passport.jpeg")
        let sheet = try file("bookings.csv")

        XCTAssertEqual(DocumentDrop.importable(from: [sheet, jpeg]), [jpeg])
    }

    // MARK: - A folder of scans

    /// Dropping the folder is what an operator with a WhatsApp export actually
    /// does. Its documents are taken, in a stable order, and its own rubbish
    /// is left behind.
    func testAFolderIsOpenedAndItsDocumentsTaken() throws {
        let folder = scratch.appending(path: "crew", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try file("b.jpeg", in: folder)
        try file("a.png", in: folder)
        try file("notes.txt", in: folder)

        let found = DocumentDrop.importable(from: [folder])

        XCTAssertEqual(found.map(\.lastPathComponent), ["a.png", "b.jpeg"])
    }

    /// A folder inside a folder is not opened. A drag of a home directory would
    /// otherwise walk the whole of it and start reading passports out of a
    /// backup nobody meant to import.
    func testAFolderIsOpenedOnlyOneLevelDeep() throws {
        let folder = scratch.appending(path: "crew", directoryHint: .isDirectory)
        let nested = folder.appending(path: "older", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try file("a.jpeg", in: folder)
        try file("buried.jpeg", in: nested)

        XCTAssertEqual(DocumentDrop.importable(from: [folder]).map(\.lastPathComponent), ["a.jpeg"])
    }

    func testHiddenFilesAreLeftAlone() throws {
        let folder = scratch.appending(path: "crew", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try file(".DS_Store", in: folder)
        try file("a.jpeg", in: folder)

        XCTAssertEqual(DocumentDrop.importable(from: [folder]).map(\.lastPathComponent), ["a.jpeg"])
    }

    /// The same file dropped twice — once on its own, once inside a folder —
    /// is one document, not two rows for the same person.
    func testTheSameFileIsOnlyImportedOnce() throws {
        let folder = scratch.appending(path: "crew", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jpeg = try file("a.jpeg", in: folder)

        XCTAssertEqual(DocumentDrop.importable(from: [jpeg, folder]), [jpeg])
    }
}
