import CSQLCipher
import Foundation
import XCTest

final class SQLCipherTests: XCTestCase {
    func testDatabaseDoesNotContainInsertedPlaintext() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "crewlistr-sqlcipher-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let marker = "CREWLISTR_PRIVATE_MARKER_\(UUID().uuidString)"
        let passphrase = Array("test-only-passphrase".utf8)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let handle = database else { return XCTFail("SQLCipher did not open the test database") }
        defer { if let database { sqlite3_close(database) } }
        XCTAssertEqual(passphrase.withUnsafeBytes { sqlite3_key(handle, $0.baseAddress, Int32(passphrase.count)) }, SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "CREATE TABLE records (value TEXT)", nil, nil, nil), SQLITE_OK)
        let sql = "INSERT INTO records(value) VALUES ('\(marker)')"
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        database = nil
        let raw = try Data(contentsOf: url)
        XCTAssertNil(raw.range(of: Data(marker.utf8)), "SQLCipher database leaked a plaintext record")
    }
}
