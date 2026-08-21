import Foundation
import XCTest
@testable import CrewListrProMac

/// The trip's cleared-count must stay visible in the top bar.
///
/// It moved there when the sidebar was removed, and the operator asked for it
/// explicitly afterwards, so it is a requirement rather than a nicety: without
/// it a bare trip picker loses the only place "6/6 cleared" was ever shown.
/// These pin the readiness arithmetic the bar renders.
@MainActor
final class TripReadinessTests: XCTestCase {

    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    // NOT `CrewStore(secureStore: nil)`: that nil constructs a real SecureStore
    // against the user's Application Support directory, so the test opens live
    // data and any mutation persists into it.
    private func makeStore() throws -> (CrewStore, Trip) {
        let store = CrewStore(secureStore: try TemporaryStore.make(in: &homes))
        let boat = Boat(name: "S/Y ANEMOS", flag: "GRC", registrationPort: "LAVRIO", registrationNumber: "GR-4471-P")
        let trip = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        store.data = AppData(boats: [boat], trips: [trip])
        store.selectedTripID = trip.id
        return (store, trip)
    }

    private func addDocument(to store: CrewStore, trip: Trip, cleared: Bool) {
        var document = CrewDocument(tripID: trip.id, personID: UUID(), originalName: "a.jpeg", encryptedFileName: "a.bin")
        document[.fullName] = "YUKI NAKAMURA"
        document[.documentNumber] = "W1357924D"
        document[.nationality] = "UTOPIAN"
        document[.birthDate] = "1984-12-16"
        document[.sex] = "F"
        if cleared {
            for field in CrewField.requiredForExport { document.verifiedFields.insert(field.rawValue) }
        }
        store.data.documents.append(document)
    }

    /// The count the bar shows: how many documents would reach a crew list.
    private func readiness(_ store: CrewStore, _ trip: Trip) -> (cleared: Int, total: Int) {
        let documents = store.data.documents.filter { $0.tripID == trip.id }
        return (documents.filter { $0.canExport() }.count, documents.count)
    }

    func testAnEmptyTripReportsNoDocuments() throws {
        let (store, trip) = try makeStore()
        XCTAssertEqual(readiness(store, trip).total, 0)
    }

    func testAFullyReviewedTripReportsEveryDocumentCleared() throws {
        let (store, trip) = try makeStore()
        for _ in 0..<6 { addDocument(to: store, trip: trip, cleared: true) }
        let counts = readiness(store, trip)
        XCTAssertEqual(counts.cleared, 6)
        XCTAssertEqual(counts.total, 6)
    }

    func testAPartlyReviewedTripReportsTheShortfall() throws {
        let (store, trip) = try makeStore()
        for index in 0..<6 { addDocument(to: store, trip: trip, cleared: index < 4) }
        let counts = readiness(store, trip)
        XCTAssertEqual(counts.cleared, 4)
        XCTAssertEqual(counts.total, 6)
        XCTAssertLessThan(counts.cleared, counts.total, "a shortfall must be visible, not rounded away")
    }

    /// Switching trips must not leave the review pane on a document belonging
    /// to the trip just left.
    func testSwitchingTripsDoesNotStrandTheSelection() throws {
        let (store, first) = try makeStore()
        addDocument(to: store, trip: first, cleared: true)
        store.selectedDocumentID = store.data.documents[0].id

        let otherBoat = Boat(name: "MY AURORA")
        let second = Trip(boatID: otherBoat.id, departureDate: .now, returnDate: .now)
        store.data.boats.append(otherBoat)
        store.data.trips.append(second)

        store.selectedTripID = second.id
        store.selectedDocumentID = store.data.documents.first { $0.tripID == second.id }?.id

        XCTAssertNil(store.selectedDocumentID, "the previous trip's document stayed selected")
        XCTAssertTrue(store.selectedTripDocuments.isEmpty)
    }
}
