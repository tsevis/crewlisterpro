import Foundation
import XCTest
@testable import CrewListrProMac

/// The yacht's name is printed in a header box of the crew list a port
/// authority receives, so it must not be possible to lose one by accident.
///
/// The trip editor used to be a modal sheet whose Save button was disabled on a
/// blank name. It is a screen now and saves as you type, so that guard had to
/// move somewhere that cannot be bypassed — the store, beside the existing
/// clamp that stops a return date landing before its departure.
@MainActor
final class BoatNameTests: XCTestCase {

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    /// NEVER `CrewStore(secureStore: nil)`. That initialiser's nil does not
    /// mean "no store" — it constructs a real SecureStore against
    /// ~/Library/Application Support, so the test opens, and writes to, the
    /// user's actual encrypted database. A test of mine did exactly that and
    /// erased a real trip. Every store test must inject a throwaway store.
    private var homes: [URL] = []

    private func makeStore(named name: String = "S/Y ANEMOS") throws -> (CrewStore, Boat) {
        let store = CrewStore(secureStore: try TemporaryStore.make(in: &homes))
        let boat = Boat(name: name, flag: "GRC", registrationPort: "LAVRIO", registrationNumber: "GR-4471-P")
        store.data = AppData(boats: [boat], trips: [])
        return (store, boat)
    }

    func testAnEmptyNameDoesNotOverwriteARealOne() throws {
        let (store, boat) = try makeStore()

        var cleared = boat
        cleared.name = ""
        store.updateBoat(cleared)

        XCTAssertEqual(store.data.boats.first?.name, "S/Y ANEMOS",
                       "an emptied name field overwrote the yacht's real name")
    }

    func testAWhitespaceOnlyNameDoesNotOverwriteARealOne() throws {
        let (store, boat) = try makeStore()

        var blanked = boat
        blanked.name = "   \n "
        store.updateBoat(blanked)

        XCTAssertEqual(store.data.boats.first?.name, "S/Y ANEMOS",
                       "whitespace is as blank as empty and must be refused too")
    }

    /// The guard protects the name only. Everything else on the boat, and the
    /// name itself when it has content, must still save normally — otherwise
    /// the fix would be worse than the defect.
    func testTheRestOfTheBoatStillSavesWhenTheNameIsBlank() throws {
        let (store, boat) = try makeStore()

        var edited = boat
        edited.name = ""
        edited.flag = "ITA"
        edited.registrationPort = "NAPOLI"
        store.updateBoat(edited)

        XCTAssertEqual(store.data.boats.first?.flag, "ITA")
        XCTAssertEqual(store.data.boats.first?.registrationPort, "NAPOLI")
    }

    func testARealNameStillSaves() throws {
        let (store, boat) = try makeStore()

        var renamed = boat
        renamed.name = "S/Y ELPIDA"
        store.updateBoat(renamed)

        XCTAssertEqual(store.data.boats.first?.name, "S/Y ELPIDA")
    }

    /// A boat that never had a name is a different case: there is nothing to
    /// protect, and refusing the write would leave the operator unable to make
    /// progress on a freshly created trip.
    func testABoatWithNoNameYetIsNotHeldToTheGuard() throws {
        let (store, boat) = try makeStore(named: "")

        var named = boat
        named.name = "S/Y ELPIDA"
        store.updateBoat(named)

        XCTAssertEqual(store.data.boats.first?.name, "S/Y ELPIDA")
    }
}
