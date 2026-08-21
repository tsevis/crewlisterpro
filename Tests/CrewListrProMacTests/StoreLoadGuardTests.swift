import Foundation
import XCTest
@testable import CrewListrProMac

/// `CrewStore.data` starts empty and is filled asynchronously from `init`.
/// Between those two moments the in-memory state describes nothing, and a
/// `persist()` in that window used to write the emptiness over the real
/// database — every trip, person and confirmation — leaving the encrypted
/// document files orphaned on disk with nothing pointing at them.
///
/// These pin the guard that closes that window.
@MainActor
final class StoreLoadGuardTests: XCTestCase {

    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    /// Every call returns a store over the SAME throwaway directory, so a
    /// second store sees what the first wrote.
    private func makeSecureStore() throws -> SecureStore {
        if let existing = homes.first { return try TemporaryStore.reopen(existing) }
        return try TemporaryStore.make(in: &homes)
    }

    // MARK: -

    func testAFreshStoreHasNotLoadedYet() throws {
        let secure = try makeSecureStore()
        let store = CrewStore(secureStore: secure)
        XCTAssertFalse(store.hasLoaded, "a store must not claim to have read the database before it has")
    }

    func testLoadingMarksTheStoreAsLoaded() async throws {
        let secure = try makeSecureStore()
        let store = CrewStore(secureStore: secure)
        await store.load()
        XCTAssertTrue(store.hasLoaded)
    }

    /// The defect itself: a write arriving before the read completes must not
    /// reach the database. Here a trip is created against a store that has not
    /// loaded, and the real contents on disk must survive it.
    func testAWriteBeforeTheFirstLoadCannotEraseTheDatabase() async throws {
        // Put a real trip on disk through a fully loaded store.
        let seeding = CrewStore(secureStore: try makeSecureStore())
        await seeding.load()
        seeding.createTrip()
        seeding.updateBoat(Boat(id: seeding.selectedBoat!.id, name: "S/Y ANEMOS"))
        await seeding.flushForTesting()

        let seeded = try await makeSecureStore().load()
        XCTAssertEqual(seeded.trips.count, 1, "the seed did not reach disk")

        // A second store mutates before its load() has run.
        let racing = CrewStore(secureStore: try makeSecureStore())
        XCTAssertFalse(racing.hasLoaded)
        racing.createTrip()
        await racing.flushForTesting()

        let onDisk = try await makeSecureStore().load()
        XCTAssertEqual(onDisk.trips.count, 1, "an unloaded store overwrote the database")
        XCTAssertEqual(onDisk.boats.first?.name, "S/Y ANEMOS", "the real yacht was erased by an empty snapshot")
    }

    /// No test may open the operator's real database.
    ///
    /// The initialiser that caused the damage is gone: `secureStore:` no longer
    /// has a default, so `CrewStore(secureStore: nil)` genuinely means "no
    /// disk". The remaining way for a test to reach live data is the
    /// no-argument `CrewStore()`, which is production's — so that is what this
    /// bans. A test needing persistence passes `TemporaryStore.make(in:)`.
    func testNoTestOpensTheUsersRealStore() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let swiftFiles = try FileManager.default
            .contentsOfDirectory(at: testsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        // `CrewStore()` with nothing between the parentheses.
        let production = try NSRegularExpression(pattern: #"\bCrewStore\(\s*\)"#)

        var offenders: [String] = []
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                guard !text.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                let range = NSRange(text.startIndex..., in: text)
                if production.firstMatch(in: text, range: range) != nil {
                    offenders.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            These open the operator's real encrypted database and can erase it. \
            Pass TemporaryStore.make(in:) instead: \(offenders.joined(separator: ", "))
            """)
    }
}
