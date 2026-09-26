import Foundation
import XCTest
@testable import CrewListrProMac

/// Performs the operator's review pass over the documents already in the live
/// encrypted store, so the crew list can then be exported from the app itself.
///
/// This is the same sequence the review pane performs — set the yacht, type the
/// names the camera lost, confirm every valid field, nominate the skipper — done
/// against the store rather than through the UI. It edits the existing trip and
/// documents in place; it never replaces the store or touches the encrypted
/// originals.
///
/// Opt-in: set CREWLISTR_APPLY_REVIEW=1, with CREWLISTR_VOYAGE and
/// CREWLISTR_CORRECTIONS as used by `CrewListGenerationTests`.
/// Quit the app first — it holds its own copy of the data and would write it
/// back over these edits.
final class LiveStoreReview: XCTestCase {

    /// Removes trips that carry no documents, with the same cleanup
    /// `CrewStore.deleteTrip` performs: the trip, its assignments, its people
    /// and the boat once nothing else sails on it.
    ///
    /// Opt-in and destructive: set CREWLISTR_PRUNE_EMPTY=1. Quit the app first.
    func testPruneEmptyTrips() async throws {
        guard ProcessInfo.processInfo.environment["CREWLISTR_PRUNE_EMPTY"] == "1" else {
            throw XCTSkip("Set CREWLISTR_PRUNE_EMPTY=1 to remove trips with no documents.")
        }
        let store = try SecureStore()
        var data = try await store.load()
        let before = data.trips.count

        let empty = data.trips.filter { trip in !data.documents.contains { $0.tripID == trip.id } }
        guard !empty.isEmpty else {
            print("No empty trips to remove.")
            return
        }
        for trip in empty {
            let boat = data.boats.first { $0.id == trip.boatID }
            print("· removing \(boat?.name ?? "Untitled yacht") (\(VoyageDate.iso(trip.departureDate)))")
            data.assignments.removeAll { $0.tripID == trip.id }
            data.trips.removeAll { $0.id == trip.id }
            // Keep a boat that another trip still uses.
            if let boat, !data.trips.contains(where: { $0.boatID == boat.id }) {
                data.boats.removeAll { $0.id == boat.id }
            }
        }
        // A person is only reachable through a document, so none can be orphaned
        // by removing a trip that had none.
        try await store.save(data)

        let reloaded = try await store.load()
        XCTAssertEqual(reloaded.trips.count, before - empty.count)
        XCTAssertTrue(reloaded.trips.allSatisfy { trip in reloaded.documents.contains { $0.tripID == trip.id } },
                      "an empty trip survived")
        XCTAssertTrue(reloaded.boats.allSatisfy { boat in reloaded.trips.contains { $0.boatID == boat.id } },
                      "a boat was left with no trip")
        for trip in reloaded.trips {
            let boat = reloaded.boats.first { $0.id == trip.boatID }
            let documents = reloaded.documents.filter { $0.tripID == trip.id }
            print("remaining: \(boat?.name ?? "?")  \(documents.filter { $0.canExport() }.count)/\(documents.count) cleared")
        }
    }

    func testApplyReviewToTheLiveStore() async throws {
        guard ProcessInfo.processInfo.environment["CREWLISTR_APPLY_REVIEW"] == "1" else {
            throw XCTSkip("Set CREWLISTR_APPLY_REVIEW=1 to review the documents in the live store.")
        }
        let store = try SecureStore()
        var data = try await store.load()
        XCTAssertFalse(data.trips.isEmpty, "the live store has no trip to review")
        XCTAssertFalse(data.documents.isEmpty, "the live store has no documents to review")

        // MARK: The yacht and the voyage
        if let path = ProcessInfo.processInfo.environment["CREWLISTR_VOYAGE"] {
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any]
            )
            if let yacht = object["yacht"] as? [String: String], let trip = data.trips.first,
               let index = data.boats.firstIndex(where: { $0.id == trip.boatID }) {
                data.boats[index].name = yacht["name"] ?? data.boats[index].name
                data.boats[index].flag = yacht["flag"] ?? ""
                data.boats[index].registrationPort = yacht["registration_port"] ?? ""
                data.boats[index].registrationNumber = yacht["registration_number"] ?? ""
                print("· yacht set to \(data.boats[index].name)")
            }
            if let value = object["departure_date"] as? String, let date = CrewFieldValidator.isoDate(value) {
                data.trips[0].departureDate = date
            }
            if let value = object["return_date"] as? String, let date = CrewFieldValidator.isoDate(value) {
                data.trips[0].returnDate = date
            }

            // MARK: Names the camera lost
            var typed: [String: [String: String]] = [:]
            if let corrections = ProcessInfo.processInfo.environment["CREWLISTR_CORRECTIONS"] {
                typed = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: try Data(contentsOf: URL(fileURLWithPath: corrections))) as? [String: [String: String]]
                )
            }
            for index in data.documents.indices {
                if let fixes = typed[data.documents[index].documentNumber] {
                    for (key, value) in fixes {
                        guard let field = CrewField(rawValue: key) else { continue }
                        data.documents[index][field] = value
                        print("· \(data.documents[index].documentNumber): \(field.label) = \(value)")
                    }
                }
            }

            // MARK: Confirm everything that validates
            for index in data.documents.indices {
                for field in CrewField.allCases where !data.documents[index].validation(of: field).isBlocking {
                    guard !data.documents[index][field].isEmpty else { continue }
                    data.documents[index].verifiedFields.insert(field.rawValue)
                }
                data.documents[index].risk = data.documents[index].canExport() ? .low : .review
                if let person = data.people.firstIndex(where: { $0.id == data.documents[index].personID }) {
                    data.people[person].fullName = data.documents[index][.fullName]
                    data.people[person].nationality = data.documents[index][.nationality]
                    data.people[person].birthDate = CrewFieldValidator.isoDate(data.documents[index][.birthDate])
                    data.people[person].verification = data.documents[index].canExport() ? .verified : .pending
                }
            }

            // MARK: The skipper
            if let skipperNumber = object["skipper_document_number"] as? String,
               let document = data.documents.first(where: { $0.documentNumber == skipperNumber }) {
                for index in data.assignments.indices where data.assignments[index].tripID == document.tripID {
                    data.assignments[index].role = data.assignments[index].personID == document.personID ? .skipper : .passenger
                }
                print("· skipper set to \(document[.fullName]) (\(skipperNumber))")
            }
        }

        try await store.save(data)

        // MARK: Report what the app will now show
        let reloaded = try await store.load()
        let blocked = reloaded.documents.filter { !$0.canExport() }
        print("\n--- live store after review ---")
        for document in reloaded.documents.sorted(by: { $0.documentNumber < $1.documentNumber }) {
            let role = reloaded.assignments.first { $0.personID == document.personID }?.role ?? .passenger
            print("  \(document.reviewStatus() == .cleared ? "✓" : "✗") \(role.label.padding(toLength: 9, withPad: " ", startingAt: 0)) \(document.documentNumber)  \(document[.fullName])")
        }
        if let boat = reloaded.boats.first, let trip = reloaded.trips.first {
            print("  yacht: \(boat.name) · \(boat.flag) · \(boat.registrationPort) · \(boat.registrationNumber)")
            print("  dates: \(VoyageDate.iso(trip.departureDate)) → \(VoyageDate.iso(trip.returnDate))")
        }
        print("-------------------------------\n")

        XCTAssertTrue(blocked.isEmpty, "still blocked: \(blocked.map { "\($0.documentNumber): \($0.blockingFields().map(\.label).joined(separator: ", "))" })")
        XCTAssertEqual(reloaded.assignments.filter { $0.role == .skipper }.count, 1, "exactly one skipper")
    }
}
