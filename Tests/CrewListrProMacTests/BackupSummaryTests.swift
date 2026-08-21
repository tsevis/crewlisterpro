import Foundation
import XCTest
@testable import CrewListrProMac

/// The restore list names each version by what it contains, not only by when
/// it was taken. An operator choosing between two snapshots after something
/// went wrong recognises "1 trip, 6 documents"; they do not recognise a
/// timestamp, and picking the wrong one costs them the work twice.
final class BackupSummaryTests: XCTestCase {

    private func backup(trips: Int, documents: Int) -> SecureStore.Backup {
        SecureStore.Backup(id: "x", created: Date(timeIntervalSince1970: 0),
                           byteCount: 1024, trips: trips, documents: documents)
    }

    func testTheSummaryNamesBothCounts() {
        XCTAssertEqual(backup(trips: 2, documents: 6).summary, "2 trips, 6 documents")
    }

    func testSingularsReadAsEnglish() {
        XCTAssertEqual(backup(trips: 1, documents: 1).summary, "1 trip, 1 document")
    }

    /// An empty snapshot is exactly the state today's incident produced, and it
    /// has to be distinguishable at a glance from one holding the real work —
    /// otherwise the restore list cannot do its only job.
    func testAnEmptySnapshotIsRecognisablyEmpty() {
        XCTAssertEqual(backup(trips: 0, documents: 0).summary, "0 trips, 0 documents")
        XCTAssertNotEqual(backup(trips: 0, documents: 0).summary,
                          backup(trips: 1, documents: 6).summary)
    }
}
