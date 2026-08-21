import CSQLCipher
import CryptoKit
import Foundation
import Security

enum StoreError: LocalizedError {
    case unavailableKey, invalidPayload, database(String)

    var errorDescription: String? {
        switch self {
        case .unavailableKey: "The local encryption key could not be accessed."
        case .invalidPayload: "Encrypted local data could not be decoded."
        case .database(let message): "Encrypted database error: \(message)"
        }
    }
}

/// SQLCipher encrypts all database pages. The Keychain-held key also protects
/// original document files and revisions with AES-GCM.
actor SecureStore {
    private let documentsURL: URL
    private let keyData: Data
    private var database: OpaquePointer?

    init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = support.appending(path: "CrewListrPro", directoryHint: .isDirectory)
        documentsURL = root.appending(path: "documents", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        keyData = try Self.loadOrCreateKey()
        database = try Self.openDatabase(at: root.appending(path: "crewlistr.sqlite").path(percentEncoded: false), keyData: keyData)
    }

    deinit { if let database { sqlite3_close(database) } }

    func load() throws -> AppData {
        guard let encrypted = try blob(query: "SELECT payload FROM secure_state WHERE id=1") else { return AppData() }
        let key = SymmetricKey(data: keyData)
        let plain = try AES.GCM.open(try AES.GCM.SealedBox(combined: encrypted), using: key)
        guard let result = try? JSONDecoder().decode(AppData.self, from: plain) else { throw StoreError.invalidPayload }
        return result
    }

    func save(_ data: AppData) throws {
        let key = SymmetricKey(data: keyData)
        let plain = try JSONEncoder().encode(data)
        guard let encrypted = try AES.GCM.seal(plain, using: key).combined else { throw StoreError.invalidPayload }
        try writeBlob(encrypted)
    }

    func importOriginal(from source: URL, documentID: UUID) throws -> String {
        let encrypted = try encrypt(Data(contentsOf: source))
        let fileName = "\(documentID.uuidString).bin"
        try encrypted.write(to: documentsURL.appending(path: fileName), options: .atomic)
        return fileName
    }

    func readOriginal(named fileName: String) throws -> Data { try decrypt(Data(contentsOf: documentsURL.appending(path: fileName))) }

    /// Permanently removes stored originals and revisions. An app that holds
    /// passport scans has to be able to forget them.
    func deleteOriginals(named fileNames: [String]) {
        for name in fileNames {
            try? FileManager.default.removeItem(at: documentsURL.appending(path: name))
        }
    }

    func replaceOriginal(named fileName: String, with data: Data) throws -> String {
        let revisionName = "\(UUID().uuidString).bin"
        let original = documentsURL.appending(path: fileName)
        try FileManager.default.copyItem(at: original, to: documentsURL.appending(path: revisionName))
        try encrypt(data).write(to: original, options: .atomic)
        return revisionName
    }

    private static func openDatabase(at path: String, keyData: Data) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let handle else {
            // sqlite3_errmsg needs the handle, which open_v2 allocates even on failure.
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(status)"
            if let handle { sqlite3_close(handle) }
            throw StoreError.database("Could not open \(path): \(message)")
        }
        let result = keyData.withUnsafeBytes { sqlite3_key(handle, $0.baseAddress, Int32(keyData.count)) }
        guard result == SQLITE_OK else {
            defer { sqlite3_close(handle) }
            throw StoreError.database(String(cString: sqlite3_errmsg(handle)))
        }
        for sql in ["PRAGMA cipher_memory_security = ON", "CREATE TABLE IF NOT EXISTS secure_state (id INTEGER PRIMARY KEY CHECK(id = 1), payload BLOB NOT NULL)"] {
            var error: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
                let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
                sqlite3_free(error)
                sqlite3_close(handle)
                throw StoreError.database(message)
            }
        }
        return handle
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            defer { sqlite3_free(error) }
            throw StoreError.database(error.map { String(cString: $0) } ?? "Unknown SQLCipher error")
        }
    }

    private func blob(query: String) throws -> Data? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func writeBlob(_ data: Data) throws {
        let sql = "INSERT INTO secure_state(id, payload) VALUES(1, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bound = data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32(data.count), transient) }
        guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    private func encrypt(_ data: Data) throws -> Data {
        guard let encrypted = try AES.GCM.seal(data, using: SymmetricKey(data: keyData)).combined else { throw StoreError.invalidPayload }
        return encrypted
    }

    private func decrypt(_ data: Data) throws -> Data { try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: keyData)) }

    private func databaseError() -> StoreError { StoreError.database(database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLCipher error") }

    private static func loadOrCreateKey() throws -> Data {
        let service = "com.tsevis.crewlisterpro"
        let account = "local-encryption-key"
        let lookup: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return data }
        guard status == errSecItemNotFound else { throw StoreError.unavailableKey }
        let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw StoreError.unavailableKey }
        return data
    }
}
