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

    /// The order is the operator's, not the alphabet's. A fleet was sorted by
    /// name, which put the boat chartered every week below one taken out twice
    /// a season and gave nobody a way to change that.
    func testTheFleetIsListedInTheOrderItWasBuilt() throws {
        let store = try makeStore()
        store.addBoat(named: "S/Y ZEPHYROS")
        store.addBoat(named: "M/Y AURORA")

        XCTAssertEqual(store.fleet.map(\.name), ["S/Y ZEPHYROS", "M/Y AURORA"])
    }

    /// Dragging a row in the fleet list moves the yacht, and it stays moved.
    func testAYachtCanBeMovedInTheFleet() throws {
        let store = try makeStore()
        store.addBoat(named: "S/Y ZEPHYROS")
        store.addBoat(named: "M/Y AURORA")
        store.addBoat(named: "S/Y ELPIDA")

        store.moveFleet(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(store.fleet.map(\.name), ["S/Y ELPIDA", "S/Y ZEPHYROS", "M/Y AURORA"])
    }

    /// A retired yacht sits in its own list and must not be dragged out of it,
    /// or a move within the fleet would silently reorder something else.
    func testMovingAYachtLeavesTheRetiredOnesWhereTheyAre() throws {
        let store = try makeStore()
        let sold = store.addBoat(named: "M/Y OLD")
        store.retireBoat(sold)
        store.addBoat(named: "S/Y ZEPHYROS")
        store.addBoat(named: "M/Y AURORA")

        store.moveFleet(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(store.fleet.map(\.name), ["M/Y AURORA", "S/Y ZEPHYROS"])
        XCTAssertEqual(store.retiredFleet.map(\.name), ["M/Y OLD"])
    }

    // MARK: - The operator's own name for a yacht

    /// The name in the header box is the vessel's registered name and a port
    /// authority reads it. What the operator calls the boat is a different
    /// fact, and it is the one they scan a list of trips for.
    func testAYachtCanCarryTheOperatorsOwnNameWithoutChangingWhatPrints() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA II")
        var boat = try XCTUnwrap(store.boat(withID: id))

        boat.nickname = "The blue one"
        store.updateBoat(boat)

        let saved = try XCTUnwrap(store.boat(withID: id))
        XCTAssertEqual(saved.displayName, "The blue one", "the operator's own name is what the app shows")
        XCTAssertEqual(saved.name, "S/Y ELPIDA II", "the printed name must not have moved")
    }

    /// With no name of their own, the app shows the registered one — there is
    /// nothing to fall back to but the paperwork.
    func testAYachtWithNoNameOfItsOwnShowsTheRegisteredName() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA II")

        XCTAssertEqual(try XCTUnwrap(store.boat(withID: id)).displayName, "S/Y ELPIDA II")
    }

    func testAnUnnamedYachtStillReadsAsUntitled() throws {
        let store = try makeStore()
        let id = store.addBoat()

        XCTAssertEqual(try XCTUnwrap(store.boat(withID: id)).displayName, "Untitled yacht")
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

    /// Deleting a yacht takes its charters with it.
    ///
    /// This used to refuse while any trip named the vessel, on the reasoning
    /// that a crew list's header boxes are read off this record. True, and it
    /// left an operator with a boat they could not remove and no way to find
    /// out which trips were holding it — the fleet filled up with yachts
    /// nobody could delete. Retire is still there for a sold yacht whose past
    /// charters matter; Delete now means delete, and the dialog counts what
    /// goes before it happens.
    func testDeletingAYachtTakesItsTripsWithIt() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        let kept = store.addBoat(named: "M/Y AURORA")
        let doomed = store.createTrip(boatID: id)
        let survivor = store.createTrip(boatID: kept)

        XCTAssertTrue(store.deleteBoat(id))

        XCTAssertNil(store.boat(withID: id))
        XCTAssertNil(store.data.trips.first { $0.id == doomed }, "the charter outlived its yacht")
        XCTAssertNotNil(store.data.trips.first { $0.id == survivor }, "another yacht's charter was taken too")
    }

    /// The documents on those trips are identity documents, so deleting a
    /// yacht has to erase them rather than orphan them in the database.
    func testDeletingAYachtErasesTheDocumentsOnItsTrips() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        let trip = store.createTrip(boatID: id)
        var document = CrewDocument(tripID: trip, personID: UUID(), originalName: "a.jpeg", encryptedFileName: "")
        document[.fullName] = "YUKI NAKAMURA"
        store.data.documents.append(document)
        store.data.people.append(CrewPerson(id: document.personID, fullName: "YUKI NAKAMURA"))
        store.data.assignments.append(CrewAssignment(tripID: trip, personID: document.personID, role: .skipper))

        XCTAssertEqual(store.documentCount(forBoatID: id), 1, "the dialog could not count what it was about to erase")
        XCTAssertTrue(store.deleteBoat(id))

        XCTAssertTrue(store.data.documents.isEmpty)
        XCTAssertTrue(store.data.people.isEmpty)
        XCTAssertTrue(store.data.assignments.isEmpty)
    }

    /// Retiring stays the non-destructive half of the pair.
    func testRetiringAYachtKeepsItsTrips() throws {
        let store = try makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        let trip = store.createTrip(boatID: id)

        store.retireBoat(id)

        XCTAssertNotNil(store.data.trips.first { $0.id == trip })
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
