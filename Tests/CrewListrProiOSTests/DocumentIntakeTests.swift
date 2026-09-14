import UniformTypeIdentifiers
import XCTest
@testable import CrewListrPro

/// Everything that can put a document into this app, and what happens to the
/// unencrypted copy afterwards.
///
/// The second half is the point. A staged file is a passport photograph in the
/// clear, in a temporary directory, and the only acceptable lifetime for one is
/// "until the store has its own sealed copy". Every test here that ends with
/// "leaves nothing behind" is testing that.
@MainActor
final class DocumentIntakeTests: XCTestCase {

    private var intake: DocumentIntake!

    override func setUp() async throws {
        try await super.setUp()
        intake = DocumentIntake()
        SharedInbox.discardEverything()
    }

    override func tearDown() async throws {
        intake.discardPending()
        SharedInbox.discardEverything()
        intake = nil
        try await super.tearDown()
    }

    // MARK: - The share sheet

    func testDrainingTakesWhatTheExtensionLeft() throws {
        _ = try SharedInbox.stage(SharedInboxTests.jpeg(), named: "WhatsApp Image.jpg", type: .jpeg)
        XCTAssertEqual(intake.drainSharedInbox(), 1)
        XCTAssertEqual(intake.pending.map(\.name), ["WhatsApp Image.jpg"])
        XCTAssertEqual(intake.pending.first?.origin, .shareSheet)
    }

    /// Draining is a move. A staged passport that survives its own import is a
    /// passport photograph left unencrypted in a folder two processes can read.
    func testDrainingEmptiesTheSharedFolder() throws {
        _ = try SharedInbox.stage(SharedInboxTests.jpeg(), named: "a.jpg", type: .jpeg)
        _ = try SharedInbox.stage(SharedInboxTests.jpeg(), named: "b.jpg", type: .jpeg)
        _ = intake.drainSharedInbox()
        XCTAssertTrue(SharedInbox.waiting().isEmpty, "the shared copy must not outlive the drain")
    }

    func testDrainingAnEmptyInboxTakesNothingAndSaysSo() {
        XCTAssertEqual(intake.drainSharedInbox(), 0)
        XCTAssertFalse(intake.hasPending)
    }

    // MARK: - What the banner says

    func testTheBannerCountsInWordsAPersonWouldUse() {
        _ = intake.stage(SharedInboxTests.jpeg(), named: "one.jpg", origin: .photos)
        XCTAssertEqual(intake.pendingSummary, "One document from Photos")
        _ = intake.stage(SharedInboxTests.jpeg(), named: "two.jpg", origin: .photos)
        XCTAssertEqual(intake.pendingSummary, "2 documents from Photos")
    }

    func testTheBannerDoesNotClaimOneOriginForDocumentsFromSeveral() {
        _ = intake.stage(SharedInboxTests.jpeg(), named: "one.jpg", origin: .photos)
        _ = intake.stage(SharedInboxTests.jpeg(), named: "two.jpg", origin: .camera)
        XCTAssertEqual(intake.pendingSummary, "2 documents waiting")
    }

    // MARK: - Staging

    func testAStagedDocumentIsAFileThatCanBeRead() throws {
        let staged = try XCTUnwrap(intake.stage(SharedInboxTests.jpeg(), named: "scan.jpg", origin: .camera))
        let data = try Data(contentsOf: staged.url)
        XCTAssertNotNil(PlatformImageCodec.decode(data), "the staged bytes must still be an image")
    }

    /// Two passports photographed a second apart are both called IMG_0042.jpg,
    /// and the name is what the operator recognises them by in the list.
    func testTwoDocumentsWithTheSameNameKeepBothNames() {
        _ = intake.stage(SharedInboxTests.jpeg(), named: "IMG_0042.jpg", origin: .photos)
        _ = intake.stage(SharedInboxTests.jpeg(), named: "IMG_0042.jpg", origin: .photos)
        XCTAssertEqual(intake.pending.count, 2)
        XCTAssertEqual(intake.pending.map(\.name), ["IMG_0042.jpg", "IMG_0042.jpg"])
        XCTAssertNotEqual(intake.pending[0].url, intake.pending[1].url)
    }

    func testDiscardingErasesTheUnencryptedCopy() throws {
        let staged = try XCTUnwrap(intake.stage(SharedInboxTests.jpeg(), named: "scan.jpg", origin: .camera))
        intake.discardPending()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.url.path(percentEncoded: false)))
        XCTAssertFalse(intake.hasPending)
    }

    func testDiscardingOneLeavesTheRest() throws {
        let first = try XCTUnwrap(intake.stage(SharedInboxTests.jpeg(), named: "a.jpg", origin: .photos))
        _ = intake.stage(SharedInboxTests.jpeg(), named: "b.jpg", origin: .photos)
        intake.discard(first)
        XCTAssertEqual(intake.pending.map(\.name), ["b.jpg"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path(percentEncoded: false)))
    }

    // MARK: - Handing them to a charter

    func testDeliveringSealsEveryDocumentAndErasesTheStagedCopies() async throws {
        let store = try TemporaryStore.make(cleanedUpBy: self)
        let tripID = store.createTrip()
        let staged = [
            try XCTUnwrap(intake.stage(SharedInboxTests.jpeg(), named: "one.jpg", origin: .shareSheet)),
            try XCTUnwrap(intake.stage(SharedInboxTests.jpeg(), named: "two.jpg", origin: .shareSheet)),
        ]

        await intake.deliver(to: tripID, store: store)

        XCTAssertEqual(store.data.documents.filter { $0.tripID == tripID }.count, 2)
        XCTAssertFalse(intake.hasPending)
        for document in staged {
            XCTAssertFalse(FileManager.default.fileExists(atPath: document.url.path(percentEncoded: false)),
                           "\(document.name) was left unencrypted in the temporary directory")
        }
    }

    /// The whole point of the phone build is that a passport can arrive from
    /// WhatsApp — and the whole point of the app is that arriving is not the
    /// same as being checked.
    func testADeliveredDocumentArrivesAwaitingReview() async throws {
        let store = try TemporaryStore.make(cleanedUpBy: self)
        let tripID = store.createTrip()
        _ = intake.stage(SharedInboxTests.jpeg(), named: "passport.jpg", origin: .shareSheet)

        await intake.deliver(to: tripID, store: store)

        let document = try XCTUnwrap(store.data.documents.first)
        XCTAssertEqual(document.reviewStatus(), .awaitingReview)
        XCTAssertFalse(document.canExport())
        XCTAssertTrue(document.verifiedFields.isEmpty)
    }

    func testDeliveringNothingDoesNothing() async throws {
        let store = try TemporaryStore.make(cleanedUpBy: self)
        let tripID = store.createTrip()
        await intake.deliver(to: tripID, store: store)
        XCTAssertTrue(store.data.documents.isEmpty)
    }
}

/// A store in a throwaway directory, never the operator's own.
///
/// The directory is removed when the test that made it finishes. Not tidiness:
/// what it holds is a sealed passport scan, and a test suite that leaves a
/// trail of them across the temporary directory is doing the one thing this
/// application exists not to do.
enum TemporaryStore {
    @MainActor
    static func make(cleanedUpBy testCase: XCTestCase) throws -> CrewStore {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StoreTests/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return CrewStore(secureStore: try SecureStore(fileManager: ScopedFileManager(root: root)))
    }
}

/// A `FileManager` whose Application Support directory is a directory of this
/// test's own.
///
/// `SecureStore` asks the file manager where Application Support is and puts
/// everything under it — the database, the key, the sealed scans. Overriding
/// that one answer is what keeps a test out of the operator's real store.
final class ScopedFileManager: FileManager, @unchecked Sendable {
    private let root: URL

    init(root: URL) {
        self.root = root
        super.init()
    }

    override func url(for directory: FileManager.SearchPathDirectory,
                      in domain: FileManager.SearchPathDomainMask,
                      appropriateFor url: URL?,
                      create shouldCreate: Bool) throws -> URL {
        guard directory == .applicationSupportDirectory else {
            return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
        }
        if shouldCreate { try super.createDirectory(at: root, withIntermediateDirectories: true) }
        return root
    }
}
