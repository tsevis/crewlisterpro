import CSQLCipher
import Foundation
import XCTest
@testable import CrewListrProMac

/// The application-support directory always contains a space ("Application
/// Support"). `URL.path()` percent-encodes by default, so any filesystem or
/// SQLite call given that string addresses a directory that does not exist.
final class StoragePathTests: XCTestCase {

    private func applicationSupportRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "CrewListrPro", directoryHint: .isDirectory)
    }

    func testApplicationSupportPathContainsASpace() throws {
        XCTAssertTrue(try applicationSupportRoot().path(percentEncoded: false).contains(" "),
                      "this test only means something on a system where the path has a space")
    }

    // MARK: - BUG-18: percent-encoded paths are handed to filesystem APIs

    func testPercentEncodedPathDoesNotAddressARealDirectory() throws {
        let root = try applicationSupportRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path()),
                       "URL.path() is expected to percent-encode; if this passes, Foundation changed")
    }

    func testSQLiteCannotOpenAPercentEncodedPath() throws {
        let root = try applicationSupportRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appending(path: "path-probe-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: target.path(percentEncoded: false))) }

        var encodedHandle: OpaquePointer?
        let encodedStatus = sqlite3_open_v2(target.path(), &encodedHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        if let encodedHandle { sqlite3_close(encodedHandle) }
        XCTAssertEqual(encodedStatus, SQLITE_CANTOPEN, "SecureStore.init passes exactly this string to sqlite3_open_v2")

        var decodedHandle: OpaquePointer?
        let decodedStatus = sqlite3_open_v2(target.path(percentEncoded: false), &decodedHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        if let decodedHandle { sqlite3_close(decodedHandle) }
        XCTAssertEqual(decodedStatus, SQLITE_OK, "the decoded path opens fine")
    }

    // MARK: - BUG-18: the store itself must be constructible

    func testSecureStoreInitialisesWithoutTrapping() throws {
        // CrewStore.init calls fatalError() when this throws, so a failure here
        // is a launch crash, not a recoverable error.
        XCTAssertNoThrow(try SecureStore(), "SecureStore could not open its database — the app would fatalError on launch")
    }

    // MARK: - BUG-19: model paths are checked with the same encoded string

    func testModelReadinessUsesADecodablePath() async throws {
        let manager = try ModelManager()
        let asset = ModelManifest.qwen3VL8BQ4.assets[0]
        let url = await manager.localURL(for: asset)
        XCTAssertEqual(url.path(percentEncoded: false), url.path().removingPercentEncoding,
                       "sanity: the two spellings differ only by encoding")
        XCTAssertTrue(url.path().contains("%20"), "sanity: the encoded spelling really does differ")
        // Regression guard: readiness must be decided on the decoded path.
        let readiness = await manager.isReady(ModelManifest(assets: [], displayName: "empty"))
        XCTAssertTrue(readiness, "isReady over an empty manifest is vacuously true")
    }
}
