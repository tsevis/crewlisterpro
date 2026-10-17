import XCTest
@testable import CrewListrProMac

/// A trip's personal data leaves the database a week after its crew list was
/// first exported — and leaves the snapshots too, or deleting it would only
/// move it.
///
/// Every store here comes from `TemporaryStore` or has none; none touches the
/// real database.
@MainActor
final class RetentionTests: XCTestCase {
    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    private let day: TimeInterval = 86_400

    /// One boat, one trip, one person on it with a document.
    private func crewedData(exportedAt: Date?) -> (AppData, Trip) {
        let boat = Boat(name: "S/Y ELPIDA", flag: "GRC")
        var trip = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        trip.firstExportedAt = exportedAt
        let person = UUID()
        let data = AppData(
            boats: [boat],
            trips: [trip],
            people: [CrewPerson(id: person, fullName: "TEST PERSON")],
            documents: [CrewDocument(tripID: trip.id, personID: person, originalName: "a.jpeg", encryptedFileName: "")],
            assignments: [CrewAssignment(tripID: trip.id, personID: person, role: .passenger)]
        )
        return (data, trip)
    }

    // MARK: - Which trips go

    func testATripExportedMoreThanAWeekAgoIsDeletedWithItsPeople() {
        let store = CrewStore(secureStore: nil)
        let (data, trip) = crewedData(exportedAt: Date.now.addingTimeInterval(-8 * day))
        store.data = data

        let purged = store.purgeExpiredTrips()

        XCTAssertEqual(purged, [trip.id])
        XCTAssertTrue(store.data.trips.isEmpty)
        XCTAssertTrue(store.data.documents.isEmpty)
        XCTAssertTrue(store.data.people.isEmpty)
        XCTAssertTrue(store.data.assignments.isEmpty)
        XCTAssertEqual(store.data.boats.count, 1, "the yacht is not personal data and stays")
    }

    func testATripExportedLessThanAWeekAgoIsKept() {
        let store = CrewStore(secureStore: nil)
        store.data = crewedData(exportedAt: Date.now.addingTimeInterval(-6 * day)).0

        XCTAssertEqual(store.purgeExpiredTrips(), [])
        XCTAssertEqual(store.data.trips.count, 1)
    }

    func testATripNeverExportedIsKept() {
        let store = CrewStore(secureStore: nil)
        store.data = crewedData(exportedAt: nil).0

        XCTAssertEqual(store.purgeExpiredTrips(now: Date.now.addingTimeInterval(365 * day)), [])
        XCTAssertEqual(store.data.trips.count, 1)
    }

    // MARK: - When the clock starts

    func testTheFirstExportStartsTheClockAndALaterOneDoesNotMoveIt() throws {
        let store = CrewStore(secureStore: nil)
        var (data, trip) = crewedData(exportedAt: nil)
        data.assignments[0].role = .skipper
        data.documents[0][.fullName] = "TEST PERSON"
        data.documents[0][.documentNumber] = "X1234567"
        data.documents[0][.nationality] = "UTOPIAN"
        data.documents[0][.birthDate] = "1980-01-01"
        data.documents[0][.sex] = "F"
        for field in CrewField.requiredForExport { data.documents[0].verifiedFields.insert(field.rawValue) }
        data.documents[0].risk = .low
        store.data = data
        store.selectedTripID = trip.id
        let directory = FileManager.default.temporaryDirectory.appending(path: "crewlistr-retention-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        homes.append(directory)

        try store.exportSelectedTrip(to: directory)
        let first = try XCTUnwrap(store.data.trips.first?.firstExportedAt)
        try store.exportSelectedTrip(to: directory)

        XCTAssertEqual(store.data.trips.first?.firstExportedAt, first)
        XCTAssertEqual(TripRetention.deletionDate(for: store.data.trips[0]), first.addingTimeInterval(7 * day))
    }

    // MARK: - Snapshots

    func testSnapshotsHoldingADeletedTripAreDiscardedAndOthersKept() async throws {
        let secure = try TemporaryStore.make(in: &homes)
        let (expired, trip) = crewedData(exportedAt: .now)
        let unrelated = AppData(boats: expired.boats)

        try await secure.save(unrelated)
        try await secure.save(expired)
        try await secure.save(AppData(boats: expired.boats, trips: [Trip(boatID: expired.boats[0].id,
                                                                            departureDate: .now, returnDate: .now)]))
        let before = await secure.backups()
        XCTAssertEqual(before.count, 2)

        let discarded = await secure.discardBackups(containingAnyTripIn: [trip.id])

        XCTAssertEqual(discarded, 1)
        let after = await secure.backups()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.trips, 0, "the snapshot without the trip was kept")
    }
}
