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

        func collect(_ data: AppData, from source: String) {
            for document in data.documents {
                referenced.insert(document.encryptedFileName)
                for revision in document.imageRevisions { referenced.insert(revision) }
            }
            print("AUDIT source \(source): \(data.documents.count) documents")
        }

        collect(try await store.load(), from: "current")
        for backup in await store.backups() {
            collect(try await store.peek(backup.id), from: "snapshot \(backup.id)")
        }

        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/CrewListrPro/documents")
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasSuffix(".bin") }

        let orphans = onDisk.filter { !referenced.contains($0) }.sorted()
        print("AUDIT on-disk \(onDisk.count), referenced \(referenced.count), orphaned \(orphans.count)")
        for orphan in orphans { print("AUDIT orphan \(orphan)") }
        for name in referenced.sorted() where !onDisk.contains(name) {
            print("AUDIT MISSING (referenced but not on disk) \(name)")
        }
    }
}
