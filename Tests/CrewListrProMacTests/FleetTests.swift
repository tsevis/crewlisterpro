import Foundation
import XCTest
@testable import CrewListrProMac

/// The fleet: yachts an operator keeps and charters again, rather than a name
/// retyped into every new trip.
///
/// `Boat` was always a separate record joined to a trip by `boatID` — what was
/// missing was any way to make one, reuse one, or see the ones you have.
@MainActor
final class FleetTests: XCTestCase {

    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    private func makeStore() throws -> CrewStore {
        CrewStore(secureStore: try TemporaryStore.make(in: &homes))
    }

    // MARK: - Keeping a fleet

    func testANewYachtJoinsTheFleet() throws {
        let store = try makeStore()

        let id = store.addBoat(named: "S/Y ELPIDA")

        XCTAssertEqual(store.fleet.map(\.id), [id])
        XCTAssertEqual(store.fleet.first?.name, "S/Y ELPIDA")
    }

    /// Typed once in Settings, not once per yacht. Most operators' fleet flies
    /// one flag out of one port.
    func testANewYachtInheritsTheDefaultsFromSettings() throws {
        let store = try makeStore()
        var settings = store.settings
        settings.defaultFlag = "GRC"
        settings.defaultRegistrationPort = "PIRAEUS"
        store.updateSettings(settings)

        let id = store.addBoat(named: "S/Y ELPIDA")

        let boat = try XCTUnwrap(store.boat(withID: id))
        XCTAssertEqual(boat.flag, "GRC")
        XCTAssertEqual(boat.registrationPort, "PIRAEUS")
    }

    func testTheFleetIsListedByName() throws {
        let store = try makeStore()
        store.addBoat(named: "S/Y ZEPHYROS")
        store.addBoat(named: "M/Y AURORA")

        XCTAssertEqual(store.fleet.map(\.name), ["M/Y AURORA", "S/Y ZEPHYROS"])
    }

    /// Sister ships differ by a name and a registration number and agree on
    /// everything else.
    func testAYachtCanBeDuplicated() throws {
        let store = try makeStore()
        let first = store.addBoat(named: "S/Y ELPIDA I")
        var boat = try XCTUnwrap(store.boat(withID: first))
        boat.flag = "GRC"
        boat.registrationPort = "PIRAEUS"
        boat.registrationNumber = "GR-1187-P"
        store.updateBoat(boat)

        let copy = try XCTUnwrap(store.duplicateBoat(first))

        let made = try XCTUnwrap(store.boat(withID: copy))
        XCTAssertNotEqual(made.id, first)
        XCTAssertEqual(made.flag, "GRC")
        XCTAssertEqual(made.registrationPort, "PIRAEUS")
        XCTAssertNotEqual(made.registrationNumber, "GR-1187-P",
                          "two yachts must not share a registration number")
        XCTAssertTrue(made.name.contains("ELPIDA"), "the copy should be recognisable: \(made.name)")
    }

    // MARK: - Retiring, and what must not be deleted

    func testARetiredYachtLeavesTheFleetButKeepsItsTrips() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        let trip = store.createTrip(boatID: id)

        store.retireBoat(id)

        XCTAssertTrue(store.fleet.isEmpty)
        XCTAssertEqual(store.retiredFleet.map(\.id), [id])
        XCTAssertEqual(store.data.trips.first { $0.id == trip }?.boatID, id)
        XCTAssertNotNil(store.boat(withID: id), "a sold yacht's past crew lists still name it")
    }

    func testARetiredYachtCanComeBack() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        store.retireBoat(id)

        store.restoreBoat(id)

        XCTAssertEqual(store.fleet.map(\.id), [id])
    }

    /// The crew list's header boxes are read off this record. Deleting it out
    /// from under a trip would leave a charter that cannot say what it sailed.
    func testAYachtInUseCannotBeDeleted() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        store.createTrip(boatID: id)

        XCTAssertFalse(store.deleteBoat(id))
        XCTAssertNotNil(store.boat(withID: id))
    }

    func testAYachtNoTripUsesCanBeDeleted() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")

        XCTAssertTrue(store.deleteBoat(id))
        XCTAssertNil(store.boat(withID: id))
    }

    func testTheFleetKnowsHowManyTripsUseAYacht() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        store.createTrip(boatID: id)
        store.createTrip(boatID: id)

        XCTAssertEqual(store.tripCount(forBoatID: id), 2)
    }

    /// Deleting a charter used to delete its yacht along with it, which was
    /// right when a yacht existed only for one trip and is wrong now: a fleet
    /// record outlives the charters made against it.
    func testDeletingATripLeavesTheYachtInTheFleet() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        let trip = store.createTrip(boatID: id)

        store.deleteTrip(trip)

        XCTAssertEqual(store.fleet.map(\.id), [id])
    }

    // MARK: - Chartering one

    func testANewTripUsesTheYachtItWasGiven() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")

        let trip = store.createTrip(boatID: id)

        XCTAssertEqual(store.data.trips.first { $0.id == trip }?.boatID, id)
    }

    func testANewTripUsesTheDefaultYachtWhenNoneIsNamed() throws {
        let store = try makeStore()
        store.addBoat(named: "M/Y AURORA")
        let elpida = store.addBoat(named: "S/Y ELPIDA")
        var settings = store.settings
        settings.defaultBoatID = elpida
        store.updateSettings(settings)

        let trip = store.createTrip()

        XCTAssertEqual(store.data.trips.first { $0.id == trip }?.boatID, elpida)
    }

    /// One yacht in the fleet is not a choice; asking would be ceremony.
    func testANewTripUsesTheOnlyYachtInTheFleet() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")

        let trip = store.createTrip()

        XCTAssertEqual(store.data.trips.first { $0.id == trip }?.boatID, id)
    }

    /// The fleet is not empty, so there is nothing to invent. Minting a
    /// placeholder here gave the operator a charter for a vessel they do not
    /// own and a fourth row in their fleet list — once per ⌘N, and unremovable
    /// while the trip existed.
    func testANewTripWithSeveralYachtsAndNoDefaultAddsNoYacht() throws {
        let store = try makeStore()
        store.addBoat(named: "S/Y ELPIDA")
        store.addBoat(named: "M/Y AURORA")
        store.addBoat(named: "S/Y ZEPHYROS")

        store.createTrip()
        store.createTrip()

        XCTAssertEqual(store.fleet.count, 3, "a new trip invented a yacht")
        XCTAssertFalse(store.fleet.contains { $0.name == Boat.placeholderName })
    }

    /// The yacht the operator was last working with is a better guess than the
    /// alphabetically first one.
    func testANewTripFallsBackToTheYachtLastChartered() throws {
        let store = try makeStore()
        store.addBoat(named: "M/Y AURORA")
        let zephyros = store.addBoat(named: "S/Y ZEPHYROS")
        store.createTrip(boatID: zephyros)

        let next = store.createTrip()

        XCTAssertEqual(store.data.trips.first { $0.id == next }?.boatID, zephyros)
    }

    /// An id for a yacht that has since been deleted would make a charter
    /// pointing at nothing — invisible in every screen, unnameable in an export.
    func testANewTripForAYachtThatIsNotThereFallsBackToOneThatIs() throws {
        let store = try makeStore()
        let real = store.addBoat(named: "S/Y ELPIDA")

        let trip = store.createTrip(boatID: UUID())

        XCTAssertEqual(store.data.trips.first { $0.id == trip }?.boatID, real)
    }

    /// "NEW YACHT (copy)" is not the placeholder name, so `isComplete` read
    /// true and a crew list could clear port with NEW YACHT (COPY) printed in
    /// its header box.
    func testDuplicatingAnUnnamedYachtProducesAnotherUnnamedYacht() throws {
        let store = try makeStore()
        let placeholder = store.addBoat(named: Boat.placeholderName)

        let copy = try XCTUnwrap(store.duplicateBoat(placeholder))

        XCTAssertFalse(try XCTUnwrap(store.boat(withID: copy)).isComplete,
                       "a copy of an unnamed yacht must still block the export")
    }

    /// An operator who has not built a fleet yet still gets a working trip.
    func testANewTripWithAnEmptyFleetStillGetsAYacht() throws {
        let store = try makeStore()

        let trip = store.createTrip()

        let boatID = try XCTUnwrap(store.data.trips.first { $0.id == trip }?.boatID)
        XCTAssertNotNil(store.boat(withID: boatID))
    }

    func testARetiredDefaultYachtIsNotUsedForANewTrip() throws {
        let store = try makeStore()
        let retired = store.addBoat(named: "S/Y ELPIDA")
        let active = store.addBoat(named: "M/Y AURORA")
        var settings = store.settings
        settings.defaultBoatID = retired
        store.updateSettings(settings)
        store.retireBoat(retired)

        let trip = store.createTrip()

        XCTAssertEqual(store.data.trips.first { $0.id == trip }?.boatID, active)
    }

    /// Retiring the default clears it rather than leaving a setting pointing at
    /// a yacht the picker no longer offers.
    func testRetiringTheDefaultYachtClearsTheDefault() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        var settings = store.settings
        settings.defaultBoatID = id
        store.updateSettings(settings)

        store.retireBoat(id)

        XCTAssertNil(store.settings.defaultBoatID)
    }

    func testDeletingTheDefaultYachtClearsTheDefault() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        var settings = store.settings
        settings.defaultBoatID = id
        store.updateSettings(settings)

        XCTAssertTrue(store.deleteBoat(id))
        XCTAssertNil(store.settings.defaultBoatID)
    }

    // MARK: - Backward compatibility

    func testABoatWrittenBeforeRetirementExistedStillDecodes() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"S/Y ELPIDA","flag":"GRC","registrationPort":"PIRAEUS","registrationNumber":"GR-1187-P"}
        """
        let boat = try JSONDecoder().decode(Boat.self, from: Data(legacy.utf8))

        XCTAssertEqual(boat.name, "S/Y ELPIDA")
        XCTAssertFalse(boat.isRetired)
    }
}
