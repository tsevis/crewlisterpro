import Foundation
import XCTest
@testable import CrewListrProMac

/// The trip-level facts an operator asked for: a charter week that is already
/// Saturday to Saturday, a departure that survives being written down, the one
/// person who signs the papers, and the skipper's email address.
@MainActor
final class VoyageAndClientTests: XCTestCase {

    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    private func makeStore() throws -> CrewStore {
        CrewStore(secureStore: try TemporaryStore.make(in: &homes))
    }

    /// A store with one trip and two crew, both with a document.
    private func makeCrewedStore() throws -> (CrewStore, Trip, skipper: UUID, passenger: UUID) {
        let store = try makeStore()
        let boat = Boat(name: "S/Y ANEMOS", flag: "GRC")
        let trip = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        let skipper = UUID(), passenger = UUID()
        store.data = AppData(
            boats: [boat],
            trips: [trip],
            people: [CrewPerson(id: skipper, fullName: "ANNA ERIKSSON"),
                     CrewPerson(id: passenger, fullName: "YUKI NAKAMURA")],
            documents: [document(trip: trip.id, person: skipper, name: "ANNA ERIKSSON"),
                        document(trip: trip.id, person: passenger, name: "YUKI NAKAMURA")],
            assignments: [CrewAssignment(tripID: trip.id, personID: skipper, role: .skipper),
                          CrewAssignment(tripID: trip.id, personID: passenger, role: .passenger)]
        )
        store.selectedTripID = trip.id
        return (store, trip, skipper, passenger)
    }

    private func document(trip: UUID, person: UUID, name: String) -> CrewDocument {
        var document = CrewDocument(tripID: trip, personID: person, originalName: "\(name).jpeg", encryptedFileName: "\(name).bin")
        document[.fullName] = name
        document[.documentNumber] = "W1357924D"
        document[.nationality] = "UTOPIAN"
        document[.birthDate] = "1984-12-16"
        document[.sex] = "F"
        return document
    }

    // MARK: - The charter week

    func testANewTripAlreadyRunsSaturdayToSaturday() throws {
        let store = try makeStore()
        let id = store.createTrip()
        let trip = try XCTUnwrap(store.data.trips.first { $0.id == id })
        let calendar = Calendar.current

        XCTAssertEqual(calendar.component(.weekday, from: trip.departureDate), 7, "departure is not a Saturday")
        XCTAssertEqual(calendar.component(.weekday, from: trip.returnDate), 7, "return is not a Saturday")
        XCTAssertEqual(calendar.dateComponents([.day], from: trip.departureDate, to: trip.returnDate).day, 7)
    }

    // MARK: - Picking dates

    func testMovingTheDepartureKeepsTheCharterTheSameLength() throws {
        let store = try makeStore()
        let id = store.createTrip()
        let original = try XCTUnwrap(store.data.trips.first { $0.id == id })
        let moved = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 14, to: original.departureDate))

        store.setDepartureDate(moved, onTripWith: id)

        let trip = try XCTUnwrap(store.data.trips.first { $0.id == id })
        XCTAssertEqual(VoyageDate.iso(trip.departureDate), VoyageDate.iso(moved))
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: trip.departureDate, to: trip.returnDate).day, 7,
                       "the week should have moved with the departure")
    }

    func testAReturnPickedByHandIsKept() throws {
        let store = try makeStore()
        let id = store.createTrip()
        let original = try XCTUnwrap(store.data.trips.first { $0.id == id })
        let fortnight = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 14, to: original.departureDate))

        store.setReturnDate(fortnight, onTripWith: id)

        let trip = try XCTUnwrap(store.data.trips.first { $0.id == id })
        XCTAssertEqual(VoyageDate.iso(trip.returnDate), VoyageDate.iso(fortnight))
    }

    func testAReturnBeforeTheDepartureIsClamped() throws {
        let store = try makeStore()
        let id = store.createTrip()
        let original = try XCTUnwrap(store.data.trips.first { $0.id == id })
        let earlier = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -3, to: original.departureDate))

        store.setReturnDate(earlier, onTripWith: id)

        let trip = try XCTUnwrap(store.data.trips.first { $0.id == id })
        XCTAssertEqual(trip.returnDate, trip.departureDate)
    }

    /// The reported bug, end to end: what the picker was given is what the
    /// export writes down.
    func testTheDepartureExportedIsTheDayThatWasPicked() throws {
        let store = try makeStore()
        let id = store.createTrip()
        let picked = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 29)))

        store.setDepartureDate(picked, onTripWith: id)

        let trip = try XCTUnwrap(store.data.trips.first { $0.id == id })
        XCTAssertEqual(VoyageDate.iso(trip.departureDate), "2026-08-29")
        XCTAssertTrue(ExportService.fileNameStem(boat: Boat(name: "X"), trip: trip).hasSuffix("2026-08-29"))
    }

    func testAPickedDateIsStoredAtTheStartOfItsDay() throws {
        let store = try makeStore()
        let id = store.createTrip()
        let afternoon = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 29, hour: 14, minute: 37)))

        store.setDepartureDate(afternoon, onTripWith: id)

        let trip = try XCTUnwrap(store.data.trips.first { $0.id == id })
        XCTAssertEqual(trip.departureDate, Calendar.current.startOfDay(for: afternoon))
    }

    // MARK: - The client

    func testNamingAClientMarksThatPerson() throws {
        let (store, _, skipper, _) = try makeCrewedStore()

        store.setClient(true, forPersonID: skipper)

        XCTAssertTrue(store.isClient(personID: skipper))
    }

    func testOnlyOnePersonCanBeTheClient() throws {
        let (store, _, skipper, passenger) = try makeCrewedStore()

        store.setClient(true, forPersonID: skipper)
        store.setClient(true, forPersonID: passenger)

        XCTAssertFalse(store.isClient(personID: skipper), "naming a new client must clear the previous one")
        XCTAssertTrue(store.isClient(personID: passenger))
    }

    func testAClientCanBeAPassenger() throws {
        let (store, _, _, passenger) = try makeCrewedStore()

        store.setClient(true, forPersonID: passenger)

        XCTAssertEqual(store.role(forPersonID: passenger), .passenger)
        XCTAssertTrue(store.isClient(personID: passenger))
    }

    func testTheClientSurvivesARoleChange() throws {
        let (store, _, _, passenger) = try makeCrewedStore()
        store.setClient(true, forPersonID: passenger)

        store.setRole(.skipper, forPersonID: passenger)

        XCTAssertTrue(store.isClient(personID: passenger), "promoting the client must not un-name them")
    }

    func testAClientCanBeCleared() throws {
        let (store, _, skipper, _) = try makeCrewedStore()
        store.setClient(true, forPersonID: skipper)

        store.setClient(false, forPersonID: skipper)

        XCTAssertFalse(store.isClient(personID: skipper))
    }

    /// A person with no assignment on this trip is not a person to name, and
    /// naming them must not quietly un-name whoever was named. The store cannot
    /// assume every person has an assignment: `crewRows` and `role(forPersonID:)`
    /// both already default a missing one, and a store written by another build
    /// or half-recovered from a snapshot can arrive that way.
    func testNamingSomeoneWithNoAssignmentLeavesTheClientAlone() throws {
        let (store, _, skipper, _) = try makeCrewedStore()
        store.setClient(true, forPersonID: skipper)

        store.setClient(true, forPersonID: UUID())

        XCTAssertTrue(store.isClient(personID: skipper), "the named client was erased")
    }

    /// The same hazard on the role, where the cost is worse: it would demote the
    /// skipper and block the export with "Nominate a skipper."
    func testMakingSomeoneWithNoAssignmentSkipperLeavesTheSkipperAlone() throws {
        let (store, _, skipper, _) = try makeCrewedStore()

        store.setRole(.skipper, forPersonID: UUID())

        XCTAssertEqual(store.role(forPersonID: skipper), .skipper, "the skipper was demoted")
    }

    func testTheClientReachesTheCrewList() throws {
        let (store, trip, _, passenger) = try makeCrewedStore()
        store.setClient(true, forPersonID: passenger)

        let rows = store.crewRows(forTripID: trip.id)

        XCTAssertEqual(rows.filter(\.isClient).count, 1)
        XCTAssertEqual(rows.first { $0.isClient }?.fullName, "YUKI NAKAMURA")
    }

    // MARK: - The skipper's email

    func testTheSkipperCarriesAnEmailAddress() throws {
        let (store, _, skipper, _) = try makeCrewedStore()

        store.setEmail("anna@example.com", forPersonID: skipper)

        XCTAssertEqual(store.email(forPersonID: skipper), "anna@example.com")
        XCTAssertEqual(store.skipperEmail, "anna@example.com")
    }

    /// "Only the skipper's email": a passenger's address is not what the crew
    /// list carries, whoever typed it.
    func testAPassengersEmailIsNotTheSkippersEmail() throws {
        let (store, _, _, passenger) = try makeCrewedStore()

        store.setEmail("yuki@example.com", forPersonID: passenger)

        XCTAssertEqual(store.skipperEmail, "")
    }

    func testTheSkippersEmailFollowsTheSkipper() throws {
        let (store, _, skipper, passenger) = try makeCrewedStore()
        store.setEmail("anna@example.com", forPersonID: skipper)
        store.setEmail("yuki@example.com", forPersonID: passenger)

        store.setRole(.skipper, forPersonID: passenger)

        XCTAssertEqual(store.skipperEmail, "yuki@example.com")
    }

    func testAnEmailAddressIsCheckedButNeverBlocksTheExport() throws {
        XCTAssertEqual(ContactValidator.validate(email: "anna@example.com"), .valid)
        XCTAssertEqual(ContactValidator.validate(email: ""), .valid)
        XCTAssertFalse(ContactValidator.validate(email: "anna at example").isBlocking)
        XCTAssertNotNil(ContactValidator.validate(email: "anna at example").message)
        XCTAssertNotNil(ContactValidator.validate(email: "anna@example").message)
    }

    // MARK: - Backward compatibility

    /// Both fields were added after operators had real data. An assignment
    /// written before they existed must still decode.
    func testAnAssignmentWrittenBeforeTheseFieldsExistedStillDecodes() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","tripID":"\(UUID().uuidString)","personID":"\(UUID().uuidString)","role":"skipper","notes":""}
        """
        let assignment = try JSONDecoder().decode(CrewAssignment.self, from: Data(legacy.utf8))

        XCTAssertEqual(assignment.role, .skipper)
        XCTAssertFalse(assignment.isClient)
        XCTAssertEqual(assignment.email, "")
    }
}
