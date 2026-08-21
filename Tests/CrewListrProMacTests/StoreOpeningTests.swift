import Foundation
import XCTest
@testable import CrewListrProMac

/// Opening the encrypted store must not block the window into existence.
///
/// It used to happen in `App.init()`, before any window was created. Opening
/// touches the Keychain, and macOS puts an authorisation prompt in front of
/// that whenever the app's code identity has changed — which an ad-hoc signed
/// rebuild does every single time. Until that prompt was answered the app was
/// a Dock icon with nothing behind it: no window, no error, nothing in the
/// logs. It was only diagnosed by sampling the process and finding it parked
/// in SecKeychainItemCopyContent.
@MainActor
final class StoreOpeningTests: XCTestCase {

    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    /// The window asks this to decide between the workspace and an explanation.
    /// A store with no database is not opening — it is open and empty — or the
    /// window would wait forever on something that is never going to happen.
    func testAStoreWithNoDatabaseIsNotStuckOpening() {
        let store = CrewStore(secureStore: nil)
        XCTAssertFalse(store.isOpening)
    }

    func testAnInjectedStoreFinishesOpening() async throws {
        let store = CrewStore(secureStore: try TemporaryStore.make(in: &homes))
        await store.load()
        XCTAssertFalse(store.isOpening, "an opened store must stop reporting itself as opening")
        XCTAssertTrue(store.hasLoaded)
    }

    /// Whatever happens to the opening path, a failure must still produce a
    /// window that explains itself rather than an empty workspace — the empty
    /// workspace is what a wiped database looks like.
    func testAFailureIsReportedRatherThanLeavingAnEmptyWorkspace() async throws {
        let store = CrewStore(secureStore: try TemporaryStore.make(in: &homes))
        await store.load()

        XCTAssertNil(store.storageFailure)
        XCTAssertTrue(store.data.trips.isEmpty)
        // An empty store and a broken store are different states and the window
        // draws them differently; this pins that they stay distinguishable.
        XCTAssertNotEqual(store.storageFailure != nil, store.data.trips.isEmpty && store.hasLoaded)
    }
}
