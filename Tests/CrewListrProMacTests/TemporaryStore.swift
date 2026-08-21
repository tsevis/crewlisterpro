import Foundation
@testable import CrewListrProMac

/// A `SecureStore` in a throwaway directory.
///
/// `CrewStore(secureStore: nil)` reads as "no store" but constructs a real one
/// against `~/Library/Application Support/CrewListrPro` — the user's actual
/// encrypted database. A test that does that opens live data, and any mutation
/// persists into it. One of these tests erased a real trip that way.
///
/// Every test that needs a store builds it through here instead.
enum TemporaryStore {

    /// Redirects `.applicationSupportDirectory` so `SecureStore` cannot find
    /// the real one.
    private final class TemporaryHome: FileManager, @unchecked Sendable {
        let root: URL
        init(root: URL) { self.root = root; super.init() }

        override func url(
            for directory: FileManager.SearchPathDirectory,
            in domain: FileManager.SearchPathDomainMask,
            appropriateFor url: URL?,
            create shouldCreate: Bool
        ) throws -> URL {
            guard directory == .applicationSupportDirectory else {
                return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
            }
            try super.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }
    }

    /// Opens another store over a directory `make` already created, so a test
    /// can check what an earlier store actually wrote to disk.
    static func reopen(_ root: URL) throws -> SecureStore {
        try SecureStore(fileManager: TemporaryHome(root: root))
    }

    /// Appends the directory it created to `homes` so the test can delete it.
    static func make(in homes: inout [URL]) throws -> SecureStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "CrewListrTest-\(UUID().uuidString)")
        homes.append(root)
        return try SecureStore(fileManager: TemporaryHome(root: root))
    }
}
