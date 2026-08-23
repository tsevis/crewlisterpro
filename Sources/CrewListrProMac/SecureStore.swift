import CSQLCipher
import CryptoKit
import Foundation
import Security

enum StoreError: LocalizedError {
    /// What the Keychain was asked to do when it refused. The two stages are
    /// opposite situations with opposite remedies: a failed read means a key
    /// exists and cannot be reached, a failed create means there is no key at
    /// all. A message that does not say which sends the reader the wrong way.
    enum KeychainStage {
        case read, create

        var description: String {
            switch self {
            case .read: "reading the existing key"
            case .create: "storing a new key"
            }
        }
    }

    case unavailableKey(stage: KeychainStage, status: OSStatus)
    case invalidPayload
    case database(String)

    var errorDescription: String? {
        switch self {
        case .unavailableKey(let stage, let status):
            // The bare sentence used to be the whole message, which made a
            // locked Keychain, a denied ACL and a stale app with the same
            // bundle identifier indistinguishable on screen. The status is the
            // one thing that separates them, so it travels with the sentence.
            "The local encryption key could not be accessed: \(stage.description) failed with OSStatus \(status) (\(Self.explain(status)))."
        case .invalidPayload: "Encrypted local data could not be decoded."
        case .database(let message): "Encrypted database error: \(message)"
        }
    }

    /// macOS already writes a plain-language explanation for every Security
    /// status; not showing it would throw away the readable half of the answer.
    /// Codes it does not know still reach the operator as a number.
    private static func explain(_ status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "no description available"
    }
}

/// SQLCipher encrypts all database pages. The Keychain-held key also protects
/// original document files and revisions with AES-GCM.
actor SecureStore {
    private let documentsURL: URL
    private let backupsURL: URL
    private let keyData: Data
    private var database: OpaquePointer?

    init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = support.appending(path: "CrewListrPro", directoryHint: .isDirectory)
        documentsURL = root.appending(path: "documents", directoryHint: .isDirectory)
        backupsURL = root.appending(path: "backups", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
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
        // Snapshot BEFORE overwriting, so the copy on disk is the state that is
        // about to be replaced. A save that turns out to be wrong — a bad
        // import, a mistaken delete, a stray process writing an empty document
        // set — is then one restore away instead of gone.
        snapshotCurrentState()
        try writeBlob(encrypted)
    }

    // MARK: - Backups
    //
    // The store is a single sealed blob in one row. Before today it had no
    // history at all: one bad write and the operator's trips were unrecoverable
    // except by re-importing every source document, which only worked because
    // those documents happened to still exist.

    /// How many snapshots are kept. They are a few tens of kilobytes each, so
    /// depth costs nothing and buys a long way back.
    static let backupDepth = 30

    struct Backup: Identifiable, Sendable {
        let id: String
        let created: Date
        let byteCount: Int
        /// Decoded so the operator can choose by content, not by timestamp.
        let trips: Int
        let documents: Int
    }

    /// Best-effort: a failed snapshot must never block a save.
    private func snapshotCurrentState() {
        guard let existing = (try? blob(query: "SELECT payload FROM secure_state WHERE id=1")) ?? nil else { return }

        // Skip a state already captured. `persist()` runs on every field edit,
        // so without this the history fills with identical copies and the
        // useful older states fall off the end of the prune.
        if let newest = newestBackupURL(), let previous = try? Data(contentsOf: newest), previous == existing {
            return
        }

        // Millisecond resolution: at one-second granularity two saves in the
        // same second wrote the same filename, and the second silently replaced
        // the first — losing exactly the state a restore would want.
        var url = backupsURL.appending(path: "\(Self.stampFormatter.string(from: Date())).bin")
        var attempt = 1
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)), attempt < 100 {
            url = backupsURL.appending(path: "\(Self.stampFormatter.string(from: Date()))-\(attempt).bin")
            attempt += 1
        }
        try? existing.write(to: url, options: .atomic)
        pruneBackups()
    }

    private func newestBackupURL() -> URL? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path(percentEncoded: false)) else { return nil }
        guard let newest = names.filter({ $0.hasSuffix(".bin") }).max() else { return nil }
        return backupsURL.appending(path: newest)
    }

    private func pruneBackups() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path(percentEncoded: false)) else { return }
        let ordered = names.filter { $0.hasSuffix(".bin") }.sorted()
        guard ordered.count > Self.backupDepth else { return }
        for name in ordered.prefix(ordered.count - Self.backupDepth) {
            try? FileManager.default.removeItem(at: backupsURL.appending(path: name))
        }
    }

    /// Snapshots the current state on demand, without changing it. For taking a
    /// deliberate checkpoint before something risky, and for protecting a state
    /// that predates backups existing at all.
    @discardableResult
    /// Takes a snapshot, reporting whether one was actually written — it is
    /// skipped when the current state is already the newest version.
    ///
    /// Compares the newest identifier rather than the file count: once the
    /// history is at its cap, writing a snapshot also prunes one, so the count
    /// is unchanged and a count-based check would report "nothing saved" at
    /// exactly the moment the history is busiest.
    func snapshot() -> Bool {
        let before = newestBackupURL()?.lastPathComponent
        snapshotCurrentState()
        return newestBackupURL()?.lastPathComponent != before
    }

    /// Newest first, each summarised by what it actually contains.
    func backups() -> [Backup] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path(percentEncoded: false)) else { return [] }
        return names.filter { $0.hasSuffix(".bin") }.sorted(by: >).compactMap { name in
            let url = backupsURL.appending(path: name)
            guard let sealed = try? Data(contentsOf: url) else { return nil }
            let identifier = String(name.dropLast(4))
            let stamp = identifier.split(separator: "-").count > 3
                ? String(identifier.prefix(while: { $0 != "Z" })) + "Z"
                : identifier
            guard let created = Self.stampFormatter.date(from: stamp) else { return nil }
            let decoded = try? decodeSnapshot(sealed)
            return Backup(
                id: identifier,
                created: created,
                byteCount: sealed.count,
                trips: decoded?.trips.count ?? 0,
                documents: decoded?.documents.count ?? 0
            )
        }
    }

    /// Reads a snapshot without installing it, so a caller can look before it leaps.
    func peek(_ identifier: String) throws -> AppData {
        try decodeSnapshot(try Data(contentsOf: backupsURL.appending(path: "\(identifier).bin")))
    }

    /// Makes a snapshot current. The state being replaced is itself snapshotted
    /// first, so restoring is undoable too.
    @discardableResult
    func restore(_ identifier: String) throws -> AppData {
        let recovered = try peek(identifier)
        try save(recovered)
        return recovered
    }

    private func decodeSnapshot(_ sealed: Data) throws -> AppData {
        let plain = try AES.GCM.open(try AES.GCM.SealedBox(combined: sealed), using: SymmetricKey(data: keyData))
        guard let decoded = try? JSONDecoder().decode(AppData.self, from: plain) else { throw StoreError.invalidPayload }
        return decoded
    }

    /// Sortable, filename-safe, and parseable back to a date.
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmssSSS'Z'"
        return formatter
    }()

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
        // Anything other than "no key yet" is a refusal that has to be reported
        // with its status: the same failed lookup can mean a locked Keychain, a
        // denied ACL, or a different app answering for this bundle identifier.
        guard status == errSecItemNotFound else { throw StoreError.unavailableKey(stage: .read, status: status) }
        let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw StoreError.unavailableKey(stage: .create, status: added) }
        return data
    }
}
