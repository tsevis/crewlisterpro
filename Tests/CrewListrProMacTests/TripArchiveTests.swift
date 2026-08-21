import Foundation
import XCTest
@testable import CrewListrProMac

/// Putting a finished charter away without destroying it.
///
/// `deleteTrip` is the only way a trip could leave the picker, and it shreds the
/// encrypted passport scans with it. An operator whose season is over wants the
/// list to stop growing, not the documents burned — a charter can be queried by
/// a port authority long after it sailed. Archiving is the difference between
/// "done with this" and "destroy this", and the two must never be confused.
///
/// The trap these guard against: an archive with no way back. A trip hidden from
/// the picker cannot be selected, and a trip that cannot be selected cannot be
/// restored *or* deleted — the documents would be stranded in the database with
/// no route to them from the UI.
@MainActor
final class TripArchiveTests: XCTestCase {

    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    // NOT `CrewStore(secureStore: nil)` — that opens the operator's live data.
    private func makeStore() throws -> CrewStore {
        CrewStore(secureStore: try TemporaryStore.make(in: &homes))
    }

    @discardableResult
    private func addTrip(to store: CrewStore, named name: String) -> Trip {
        let boat = Boat(name: name, flag: "GRC", registrationPort: "LAVRIO", registrationNumber: "GR-4471-P")
        let trip = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        store.data.boats.append(boat)
        store.data.trips.append(trip)
        return trip
    }

    private func addDocument(to store: CrewStore, trip: Trip) {
        var document = CrewDocument(tripID: trip.id, personID: UUID(), originalName: "a.jpeg", encryptedFileName: "a.bin")
        document[.fullName] = "YUKI NAKAMURA"
        store.data.documents.append(document)
        store.data.people.append(CrewPerson(id: document.personID, fullName: "YUKI NAKAMURA"))
        store.data.assignments.append(CrewAssignment(tripID: trip.id, personID: document.personID, role: .skipper))
    }

    // MARK: - A trip starts out active

    func testANewTripIsNotArchived() throws {
        let store = try makeStore()
        let id = store.createTrip()
        XCTAssertEqual(store.data.trips.first { $0.id == id }?.status, .draft)
        XCTAssertEqual(store.activeTrips.count, 1)
        XCTAssertTrue(store.archivedTrips.isEmpty)
    }

    // MARK: - Archiving hides without destroying

    func testArchivingRemovesTheTripFromTheActiveList() throws {
        let store = try makeStore()
        let trip = addTrip(to: store, named: "S/Y ANEMOS")
        store.archiveTrip(trip.id)

        XCTAssertTrue(store.activeTrips.isEmpty, "an archived trip must not clutter the picker")
        XCTAssertEqual(store.archivedTrips.map(\.id), [trip.id])
    }

    /// The whole point of archiving rather than deleting.
    func testArchivingKeepsEveryDocumentAndPerson() throws {
        let store = try makeStore()
        let trip = addTrip(to: store, named: "S/Y ANEMOS")
        addDocument(to: store, trip: trip)

        store.archiveTrip(trip.id)

        XCTAssertEqual(store.data.trips.count, 1, "the trip itself must survive")
        XCTAssertEqual(store.data.documents.count, 1, "archiving must never shred a passport scan")
        XCTAssertEqual(store.data.people.count, 1)
        XCTAssertEqual(store.data.assignments.count, 1)
        XCTAssertEqual(store.data.boats.count, 1, "the yacht is still the yacht that sailed")
    }

    /// Contrast: `deleteTrip` is the destructive one, and stays destructive.
    func testDeletingStillDestroysWhatArchivingKeeps() throws {
        let store = try makeStore()
        let trip = addTrip(to: store, named: "S/Y ANEMOS")
        addDocument(to: store, trip: trip)

        store.deleteTrip(trip.id)

        XCTAssertTrue(store.data.trips.isEmpty)
        XCTAssertTrue(store.data.documents.isEmpty)
        XCTAssertTrue(store.data.people.isEmpty)
    }

    // MARK: - Selection cannot rest on an archived trip

    func testArchivingTheSelectedTripSelectsAnotherActiveOne() throws {
        let store = try makeStore()
        let first = addTrip(to: store, named: "S/Y ANEMOS")
        let second = addTrip(to: store, named: "MY AURORA")
        store.selectedTripID = first.id

        store.archiveTrip(first.id)

        XCTAssertEqual(store.selectedTripID, second.id, "the pane must move to a trip the operator can still work on")
    }

    func testArchivingTheOnlyTripLeavesNothingSelected() throws {
        let store = try makeStore()
        let trip = addTrip(to: store, named: "S/Y ANEMOS")
        store.selectedTripID = trip.id
        addDocument(to: store, trip: trip)
        store.selectedDocumentID = store.data.documents[0].id

        store.archiveTrip(trip.id)

        XCTAssertNil(store.selectedTripID)
        XCTAssertNil(store.selectedDocumentID, "a document from the archived trip must not stay in the review pane")
    }

    /// Archiving a trip the operator is not looking at must not move them.
    func testArchivingAnotherTripLeavesTheSelectionAlone() throws {
        let store = try makeStore()
        let first = addTrip(to: store, named: "S/Y ANEMOS")
        let second = addTrip(to: store, named: "MY AURORA")
        store.selectedTripID = first.id

        store.archiveTrip(second.id)

        XCTAssertEqual(store.selectedTripID, first.id)
    }

    // MARK: - The way back

    func testRestoringPutsTheTripBackInTheActiveList() throws {
        let store = try makeStore()
        let trip = addTrip(to: store, named: "S/Y ANEMOS")
        store.archiveTrip(trip.id)

        store.restoreTrip(trip.id)

        XCTAssertEqual(store.activeTrips.map(\.id), [trip.id])
        XCTAssertTrue(store.archivedTrips.isEmpty)
        XCTAssertEqual(store.data.trips.first?.status, .draft)
    }

    /// An archived trip must remain reachable, or its documents are stranded.
    func testAnArchivedTripCanStillBeSelectedAndDeleted() throws {
        let store = try makeStore()
        let trip = addTrip(to: store, named: "S/Y ANEMOS")
        addDocument(to: store, trip: trip)
        store.archiveTrip(trip.id)

        store.selectedTripID = trip.id
        XCTAssertNotNil(store.selectedTrip, "an archived trip must still be addressable")

        store.deleteTrip(trip.id)
        XCTAssertTrue(store.data.trips.isEmpty, "the operator must retain a route to erase the documents")
        XCTAssertTrue(store.data.documents.isEmpty)
    }

    // MARK: - Opening the app

    /// `load()` opens on the work in hand. An archived trip is not work in hand.
    func testLoadingOpensOnAnActiveTripRatherThanAnArchivedOne() async throws {
        let secureStore = try TemporaryStore.make(in: &homes)
        let archivedBoat = Boat(name: "S/Y ANEMOS")
        let activeBoat = Boat(name: "MY AURORA")
        var archived = Trip(boatID: archivedBoat.id, departureDate: .now, returnDate: .now)
        archived.status = .archived
        let active = Trip(boatID: activeBoat.id, departureDate: .now, returnDate: .now)
        // Archived first, so a naive `trips.first` picks the wrong one.
        try await secureStore.save(AppData(boats: [archivedBoat, activeBoat], trips: [archived, active]))

        let store = CrewStore(secureStore: secureStore)
        await store.load()

        XCTAssertEqual(store.selectedTripID, active.id)
    }

    /// With nothing but archived trips there is no active trip to open on, and
    /// the app must not silently open an archived one as though it were live.
    func testLoadingWithOnlyArchivedTripsSelectsNothing() async throws {
        let secureStore = try TemporaryStore.make(in: &homes)
        let boat = Boat(name: "S/Y ANEMOS")
        var archived = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        archived.status = .archived
        try await secureStore.save(AppData(boats: [boat], trips: [archived]))

        let store = CrewStore(secureStore: secureStore)
        await store.load()

        XCTAssertNil(store.selectedTripID)
    }

    // MARK: - Persisted shape

    /// The status is written as the same string the Python app uses, so the two
    /// stores describe a trip the same way.
    func testStatusPersistsAsItsPythonSpelling() throws {
        let boat = Boat(name: "S/Y ANEMOS")
        var trip = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        XCTAssertEqual(TripStatus.draft.rawValue, "draft")
        XCTAssertEqual(TripStatus.archived.rawValue, "archived")

        trip.status = .archived
        let encoded = try JSONEncoder().encode(trip)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(json["status"] as? String, "archived")

        let decoded = try JSONDecoder().decode(Trip.self, from: encoded)
        XCTAssertEqual(decoded.status, .archived)
    }

    /// A status this build does not know must not make the whole database
    /// undecodable — that would lock the operator out of every trip they own.
    func testAnUnknownStatusReadsAsADraftRatherThanFailing() throws {
        let json = """
        {"id":"\(UUID().uuidString)","boatID":"\(UUID().uuidString)","departureDate":0,"returnDate":0,"status":"mothballed"}
        """
        let trip = try JSONDecoder().decode(Trip.self, from: Data(json.utf8))
        XCTAssertEqual(trip.status, .draft)
    }

    /// A trip written before the status existed at all.
    func testAMissingStatusReadsAsADraft() throws {
        let json = """
        {"id":"\(UUID().uuidString)","boatID":"\(UUID().uuidString)","departureDate":0,"returnDate":0}
        """
        let trip = try JSONDecoder().decode(Trip.self, from: Data(json.utf8))
        XCTAssertEqual(trip.status, .draft)
    }

    // MARK: - The scriptable export

    /// `--export` with no `--trip` means "the only trip there is". Archiving the
    /// finished ones is what makes that unambiguous again.
    func testHeadlessExportIgnoresArchivedTripsWhenResolvingTheOnlyOne() throws {
        let archivedBoat = Boat(name: "S/Y ANEMOS")
        let activeBoat = Boat(name: "MY AURORA")
        var archived = Trip(boatID: archivedBoat.id, departureDate: .now, returnDate: .now)
        archived.status = .archived
        let active = Trip(boatID: activeBoat.id, departureDate: .now, returnDate: .now)
        let data = AppData(boats: [archivedBoat, activeBoat], trips: [archived, active])

        let (trip, boat) = try HeadlessExport.resolveTrip(in: data, named: nil)
        XCTAssertEqual(trip.id, active.id)
        XCTAssertEqual(boat.name, "MY AURORA")
    }

    /// Naming an archived trip is an explicit request for it — a port authority
    /// asking about last season must still be answerable.
    func testHeadlessExportStillFindsAnArchivedTripByName() throws {
        let boat = Boat(name: "S/Y ANEMOS")
        var archived = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        archived.status = .archived
        let data = AppData(boats: [boat], trips: [archived])

        let (trip, resolved) = try HeadlessExport.resolveTrip(in: data, named: "S/Y ANEMOS")
        XCTAssertEqual(trip.id, archived.id)
        XCTAssertEqual(resolved.name, "S/Y ANEMOS")
    }

    /// With every trip archived there is no implicit trip to export, and the
    /// operator must be told that rather than handed last season's crew.
    func testHeadlessExportRefusesWhenEveryTripIsArchived() throws {
        let boat = Boat(name: "S/Y ANEMOS")
        var archived = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        archived.status = .archived
        let data = AppData(boats: [boat], trips: [archived])

        XCTAssertThrowsError(try HeadlessExport.resolveTrip(in: data, named: nil))
    }
}
