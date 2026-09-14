import UniformTypeIdentifiers
import XCTest
@testable import CrewListrPro

/// The letterbox between the share sheet and the app.
///
/// This is the path a passport actually takes out of WhatsApp, so it is tested
/// as a path: what may be put in, what a hostile name cannot do, and that
/// draining is a move rather than a copy — a staged passport photograph that
/// survives its own import is a passport photograph sitting unencrypted in a
/// folder two processes can read.
final class SharedInboxTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SharedInbox.discardEverything()
    }

    override func tearDown() {
        SharedInbox.discardEverything()
        super.tearDown()
    }

    /// The App Group is the whole mechanism. Without it the extension has
    /// nowhere to put anything, so a failure here is not a detail.
    func testTheSharedContainerExists() throws {
        XCTAssertNoThrow(try SharedInbox.directory(),
                         "the app group entitlement is missing — every share would silently vanish")
    }

    // MARK: - What may be put in

    func testAnImageIsAccepted() {
        XCTAssertTrue(SharedInbox.accepts(.jpeg))
        XCTAssertTrue(SharedInbox.accepts(.heic))
        XCTAssertTrue(SharedInbox.accepts(.png))
    }

    func testAScannedPDFIsAccepted() {
        XCTAssertTrue(SharedInbox.accepts(.pdf))
    }

    func testAVideoIsNotADocument() {
        XCTAssertFalse(SharedInbox.accepts(.movie))
        XCTAssertFalse(SharedInbox.accepts(.zip))
        XCTAssertFalse(SharedInbox.accepts(.plainText))
    }

    func testSomethingThatIsNotADocumentIsRefusedRatherThanStaged() {
        XCTAssertThrowsError(try SharedInbox.stage(Data("hello".utf8), named: "notes.txt", type: .plainText))
        XCTAssertTrue(SharedInbox.waiting().isEmpty, "a refused share must leave nothing behind")
    }

    /// An extension runs on a short leash. A 400 MB share would be killed part
    /// way through, leaving a truncated file the app would try to read as a
    /// passport.
    func testSomethingTooLargeIsRefused() {
        let huge = Data(repeating: 0, count: SharedInbox.mostBytesPerItem + 1)
        XCTAssertThrowsError(try SharedInbox.stage(huge, named: "huge.jpg", type: .jpeg))
    }

    // MARK: - Names arriving from another application

    /// A file name from another app is untrusted input. The two that matter are
    /// a path separator, which would write outside the container, and the two
    /// names that are directories.
    func testANameCannotEscapeTheInbox() {
        let escaped = SharedInbox.safeName("../../Library/Preferences/evil.jpg", type: .jpeg)
        XCTAssertFalse(escaped.contains("/"), "a separator would write outside the container")
        XCTAssertFalse(escaped.hasPrefix("."), "a leading dot hides the document from every file browser")
        XCTAssertTrue(escaped.hasSuffix("evil.jpg"), "the sender's own name is still what the operator sees")
    }

    func testADirectoryNameIsReplacedRatherThanUsed() {
        XCTAssertEqual(SharedInbox.safeName("..", type: nil), "Shared document")
        XCTAssertEqual(SharedInbox.safeName(".", type: nil), "Shared document")
        XCTAssertEqual(SharedInbox.safeName("   ", type: nil), "Shared document")
    }

    func testAnExtensionIsAddedWhenTheSenderGaveNone() {
        XCTAssertEqual(SharedInbox.safeName("passport", type: .jpeg), "passport.jpeg")
    }

    func testAnExtensionTheSenderGaveIsKept() {
        XCTAssertEqual(SharedInbox.safeName("IMG_4471.HEIC", type: .jpeg), "IMG_4471.HEIC")
    }

    // MARK: - Staging and draining

    func testAStagedDocumentKeepsTheNameTheOperatorWillRecogniseIteBy() throws {
        let url = try SharedInbox.stage(Self.jpeg(), named: "IMG_4471.jpg", type: .jpeg)
        XCTAssertEqual(SharedInbox.originalName(of: url), "IMG_4471.jpg")
    }

    /// Two people sending "photo.jpg" in the same minute must not replace each
    /// other.
    func testTwoDocumentsWithTheSameNameBothSurvive() throws {
        _ = try SharedInbox.stage(Self.jpeg(), named: "photo.jpg", type: .jpeg)
        _ = try SharedInbox.stage(Self.jpeg(), named: "photo.jpg", type: .jpeg)
        XCTAssertEqual(SharedInbox.waiting().count, 2)
        XCTAssertEqual(Set(SharedInbox.waiting().map(SharedInbox.originalName)), ["photo.jpg"])
    }

    func testWaitingIsOldestFirstSoARunOfSharesArrivesInTheOrderItWasSent() throws {
        for index in 1...4 {
            _ = try SharedInbox.stage(Self.jpeg(), named: "page\(index).jpg", type: .jpeg)
        }
        XCTAssertEqual(SharedInbox.waiting().map(SharedInbox.originalName),
                       ["page1.jpg", "page2.jpg", "page3.jpg", "page4.jpg"])
    }

    func testDiscardingEverythingLeavesNothingBehind() throws {
        _ = try SharedInbox.stage(Self.jpeg(), named: "a.jpg", type: .jpeg)
        _ = try SharedInbox.stage(Self.jpeg(), named: "b.jpg", type: .jpeg)
        SharedInbox.discardEverything()
        XCTAssertTrue(SharedInbox.waiting().isEmpty)
    }

    // MARK: - A fixture

    static func jpeg(width: Int = 40, height: Int = 30) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return PlatformImageCodec.encode(context.makeImage()!, as: .jpeg)!
    }
}
