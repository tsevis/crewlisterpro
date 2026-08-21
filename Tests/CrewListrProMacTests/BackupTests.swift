import Foundation
import XCTest
@testable import CrewListrProMac

/// The store keeps a history of itself.
///
/// It did not before, and a single bad write erased an operator's trips with no
/// way back except re-importing every source document — which only worked
/// because those documents happened to still be on disk. These tests pin the
/// behaviour that makes that recoverable.
///
/// Every store here comes from `TemporaryStore`; none touches the real database.
final class BackupTests: XCTestCase {
    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    private func makeStore() throws -> SecureStore { try TemporaryStore.make(in: &homes) }

    private func appData(trips: Int, documents: Int) -> AppData {
        let boat = Boat(name: "S/Y ANEMOS", flag: "GRC", registrationPort: "LAVRIO", registrationNumber: "GR-4471-P")
        let made = (0..<trips).map { _ in Trip(boatID: boat.id, departureDate: .now, returnDate: .now) }
        let docs = made.first.map { trip in
            (0..<documents).map { index in
                CrewDocument(tripID: trip.id, personID: UUID(), originalName: "\(index).jpeg", encryptedFileName: "\(index).bin")
            }
        } ?? []
        return AppData(boats: [boat], trips: made, documents: docs)
    }

    // MARK: - A snapshot is taken before the state is replaced

    func testTheFirstSaveHasNothingToSnapshot() async throws {
        let store = try makeStore()
        try await store.save(appData(trips: 1, documents: 3))
        let backups = await store.backups()
        XCTAssertTrue(backups.isEmpty, "an empty store has no previous state worth keeping")
    }

    func testASecondSaveSnapshotsWhatItReplaces() async throws {
        let store = try makeStore()
        try await store.save(appData(trips: 1, documents: 6))
        try await store.save(appData(trips: 1, documents: 2))

        let backups = await store.backups()
        XCTAssertEqual(backups.count, 1)
        // The snapshot holds the OLD state, not the new one.
        XCTAssertEqual(backups[0].documents, 6)
        let peeked = try await store.peek(backups[0].id)
        XCTAssertEqual(backups[0].documents, peeked.documents.count)
    }

    /// The shape of the incident: a process overwrites the store with an empty
    /// document set. The write still happens — deleting everything is a thing an
    /// operator may legitimately do — but the previous state survives beside it.
    func testAnOverwriteWithNothingLeavesThePreviousStateRecoverable() async throws {
        let store = try makeStore()
        try await store.save(appData(trips: 1, documents: 6))
        try await store.save(AppData())

        let current = try await store.load()
        XCTAssertTrue(current.trips.isEmpty, "the destructive save still applied")

        let backups = await store.backups()
        XCTAssertEqual(backups.first?.trips, 1)
        XCTAssertEqual(backups.first?.documents, 6)
    }

    // MARK: - Restoring

    func testRestoringBringsTheEarlierStateBack() async throws {
        let store = try makeStore()
        try await store.save(appData(trips: 1, documents: 6))
        try await store.save(AppData())

        let backups = await store.backups()
        let recovered = try await store.restore(try XCTUnwrap(backups.first).id)
        XCTAssertEqual(recovered.documents.count, 6)
        let current = try await store.load()
        XCTAssertEqual(current.documents.count, 6, "the restore was not made current")
    }

    /// Restoring is itself a save, so it is itself undoable.
    func testRestoringIsUndoable() async throws {
        let store = try makeStore()
        try await store.save(appData(trips: 1, documents: 6))
        try await store.save(AppData())
        let empty = await store.backups().count

        let listed = await store.backups()
        let target = try XCTUnwrap(listed.first)
        try await store.restore(target.id)
        let after = await store.backups().count
        XCTAssertGreaterThan(after, empty, "the state the restore replaced was not kept")
    }

    func testPeekingDoesNotChangeWhatIsCurrent() async throws {
        let store = try makeStore()
        try await store.save(appData(trips: 1, documents: 6))
        try await store.save(AppData())

        let listed = await store.backups()
        let target = try XCTUnwrap(listed.first)
        _ = try await store.peek(target.id)
        let current = try await store.load()
        XCTAssertTrue(current.documents.isEmpty, "peek must not install anything")
    }

    func testRestoringAnUnknownSnapshotThrows() async throws {
        let store = try makeStore()
        try await store.save(appData(trips: 1, documents: 1))
        do {
            _ = try await store.restore("2020-01-01T000000Z")
            XCTFail("restoring a snapshot that does not exist should throw")
        } catch {}
    }

    // MARK: - Listing

    func testBackupsAreNewestFirstAndSummarised() async throws {
        let store = try makeStore()
        for count in [2, 4, 6] {
            try await store.save(appData(trips: 1, documents: count))
            // The stamp has one-second resolution; distinct snapshots need it.
            try await Task.sleep(for: .milliseconds(1_100))
        }
        let backups = await store.backups()
        XCTAssertEqual(backups.count, 2)
        XCTAssertGreaterThan(backups[0].created, backups[1].created, "newest first")
        XCTAssertEqual(backups.map(\.documents), [4, 2])
        XCTAssertTrue(backups.allSatisfy { $0.byteCount > 0 })
    }

    func testTheHistoryIsBounded() async throws {
        XCTAssertGreaterThan(SecureStore.backupDepth, 1)
        XCTAssertLessThanOrEqual(SecureStore.backupDepth, 100, "snapshots hold identity data; the history must not grow without limit")
    }

    // MARK: - Snapshots are encrypted at rest

    func testASnapshotOnDiskIsNotReadable() async throws {
        var homes: [URL] = []
        let root = FileManager.default.temporaryDirectory.appending(path: "CrewListrBackup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try TemporaryStore.make(in: &homes)
        homes.forEach { self.homes.append($0) }
        var data = appData(trips: 1, documents: 1)
        data.boats[0].name = "MARKER_YACHT_NAME"
        try await store.save(data)
        try await store.save(AppData())

        let backupDirectory = try XCTUnwrap(homes.first).appending(path: "CrewListrPro/backups")
        let files = try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path(percentEncoded: false))
        XCTAssertFalse(files.isEmpty, "no snapshot was written")
        for name in files {
            let raw = try Data(contentsOf: backupDirectory.appending(path: name))
            XCTAssertNil(raw.range(of: Data("MARKER_YACHT_NAME".utf8)),
                         "\(name) stores identity data in the clear")
        }
        _ = root
    }
}

// MARK: - What the restore UI shows

@MainActor
final class BackupPresentationTests: XCTestCase {

    private func backup(trips: Int, documents: Int) -> SecureStore.Backup {
        SecureStore.Backup(id: "2026-08-21T110225635Z", created: .now, byteCount: 2048,
                           trips: trips, documents: documents)
    }

    /// The row has to say what restoring would bring back. A timestamp alone
    /// makes the operator guess.
    func testARowDescribesWhatTheVersionContains() {
        XCTAssertEqual(CrewStore.describe(backup(trips: 1, documents: 6)), "1 trip, 6 documents")
    }

    func testTheDescriptionIsGrammaticalForSingletons() {
        XCTAssertEqual(CrewStore.describe(backup(trips: 1, documents: 1)), "1 trip, 1 document")
        XCTAssertEqual(CrewStore.describe(backup(trips: 2, documents: 0)), "2 trips, 0 documents")
    }

    /// A store with nothing behind it lists nothing rather than failing.
    func testAStoreWithNoDatabaseHasNoVersions() async {
        let store = CrewStore(secureStore: nil)
        await store.refreshBackups()
        XCTAssertTrue(store.backups.isEmpty)
    }

    func testRestoringThroughAStoreWithNoDatabaseIsANoOp() async {
        let store = CrewStore(secureStore: nil)
        await store.restoreBackup("2026-08-21T110225635Z")
        XCTAssertNil(store.errorMessage, "a store with nowhere to read from should not raise an error at the operator")
        XCTAssertTrue(store.data.trips.isEmpty)
    }
}
