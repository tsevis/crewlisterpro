import Foundation
import XCTest
@testable import CrewListrProMac

/// Lists which encrypted document files are still referenced and which are not.
///
/// Opt-in — CREWLISTR_AUDIT=1 — because it opens the live store. It only reads.
///
/// A file is referenced if the CURRENT state names it, or if ANY snapshot does:
/// backups hold the database, not the documents, so deleting a blob an older
/// version still points at would leave that version restorable but broken, and
/// it would fail at the moment someone reached for it.
final class OrphanAudit: XCTestCase {

    func testListReferencedAndOrphanedFiles() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CREWLISTR_AUDIT"] == "1",
                          "opt-in: reads the live store")

        let store = try SecureStore()
        var referenced = Set<String>()
        // The crew library seals its scans into a folder of its own, so its
        // files are counted against that folder rather than this one — a
        // library scan is not an orphan just because no trip points at it.
        var referencedByLibrary = Set<String>()

        func collect(_ data: AppData, from source: String) {
            for document in data.documents {
                referenced.insert(document.encryptedFileName)
                for revision in document.imageRevisions { referenced.insert(revision) }
            }
            for saved in data.savedCrew where !saved.encryptedFileName.isEmpty {
                referencedByLibrary.insert(saved.encryptedFileName)
            }
            print("AUDIT source \(source): \(data.documents.count) documents, \(data.savedCrew.count) kept people")
        }

        collect(try await store.load(), from: "current")
        for backup in await store.backups() {
            collect(try await store.peek(backup.id), from: "snapshot \(backup.id)")
        }

        let root = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/CrewListrPro")

        func audit(_ folder: String, against names: Set<String>) throws {
            let directory = root.appending(path: folder)
            let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)))?
                .filter { $0.hasSuffix(".bin") } ?? []

            let orphans = onDisk.filter { !names.contains($0) }.sorted()
            print("AUDIT \(folder): on-disk \(onDisk.count), referenced \(names.count), orphaned \(orphans.count)")
            for orphan in orphans { print("AUDIT orphan \(folder)/\(orphan)") }
            for name in names.sorted() where !onDisk.contains(name) {
                print("AUDIT MISSING (referenced but not on disk) \(folder)/\(name)")
            }
        }

        try audit("documents", against: referenced)
        try audit("crew", against: referencedByLibrary)
    }
}
