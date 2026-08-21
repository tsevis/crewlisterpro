import Foundation
import XCTest
@testable import CrewListrProMac

/// Rebuilds the operator's trip in the live encrypted store from the source
/// documents, after a test overwrote it.
///
/// The store holds only metadata — which documents belong to which trip, the
/// fields read from them, and what the operator confirmed. The documents
/// themselves are the originals on disk, so the trip can be reconstructed
/// exactly by importing them again and replaying the review.
///
/// Opt-in and destructive: CREWLISTR_RECOVER=1, with CREWLISTR_FIXTURES,
/// CREWLISTR_VOYAGE and CREWLISTR_CORRECTIONS as used elsewhere. Quit the app
/// first — it holds its own copy and would write it back.
final class StoreRecovery: XCTestCase {

    func testRebuildTripFromSourceDocuments() async throws {
        guard ProcessInfo.processInfo.environment["CREWLISTR_RECOVER"] == "1" else {
            throw XCTSkip("Set CREWLISTR_RECOVER=1 to rebuild the live store from source documents.")
        }
        let sourceDirectory = try XCTUnwrap(ProcessInfo.processInfo.environment["CREWLISTR_FIXTURES"],
                                            "CREWLISTR_FIXTURES must point at the source documents")
        let files = try FileManager.default
            .contentsOfDirectory(at: URL(fileURLWithPath: sourceDirectory), includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no source documents to rebuild from")

        let store = try SecureStore()
        var data = try await store.load()
        XCTAssertTrue(data.trips.isEmpty, "the store already has a trip; refusing to add a duplicate")

        // MARK: The voyage
        var boat = Boat(name: Boat.placeholderName)
        var departure = Calendar.current.startOfDay(for: .now)
        var arrival = departure
        var skipperNumber: String?
        if let path = ProcessInfo.processInfo.environment["CREWLISTR_VOYAGE"] {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
            if let yacht = object["yacht"] as? [String: String] {
                boat = Boat(name: yacht["name"] ?? boat.name,
                            flag: yacht["flag"] ?? "",
                            registrationPort: yacht["registration_port"] ?? "",
                            registrationNumber: yacht["registration_number"] ?? "")
            }
            departure = (object["departure_date"] as? String).flatMap(CrewFieldValidator.isoDate) ?? departure
            arrival = (object["return_date"] as? String).flatMap(CrewFieldValidator.isoDate) ?? arrival
            skipperNumber = object["skipper_document_number"] as? String
        }
        let trip = Trip(boatID: boat.id, departureDate: departure, returnDate: arrival)
        data.boats.append(boat)
        data.trips.append(trip)

        var typed: [String: [String: String]] = [:]
        if let path = ProcessInfo.processInfo.environment["CREWLISTR_CORRECTIONS"] {
            typed = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: URL(fileURLWithPath: path))) as? [String: [String: String]])
        }

        // MARK: Re-import and replay the review
        for url in files {
            let result = try OCRService.extract(from: url)
            var person = CrewPerson(fullName: result.fields[CrewField.fullName.rawValue] ?? "",
                                    nationality: result.fields[CrewField.nationality.rawValue] ?? "")
            person.birthDate = result.fields[CrewField.birthDate.rawValue].flatMap(CrewFieldValidator.isoDate)

            var document = CrewDocument(
                tripID: trip.id, personID: person.id,
                originalName: url.lastPathComponent, encryptedFileName: "",
                documentNumber: result.fields[CrewField.documentNumber.rawValue] ?? "",
                documentType: result.fields[CrewField.documentType.rawValue] ?? "unknown",
                risk: result.risk, riskReasons: result.reasons, fields: result.fields
            )
            document.encryptedFileName = try await store.importOriginal(from: url, documentID: document.id)

            for (key, value) in typed[document.documentNumber] ?? [:] {
                if let field = CrewField(rawValue: key) { document[field] = value }
            }
            for field in CrewField.allCases where !document.validation(of: field).isBlocking {
                guard !document[field].isEmpty else { continue }
                document.verifiedFields.insert(field.rawValue)
            }
            document.risk = document.canExport() ? .low : .review
            person.fullName = document[.fullName]
            person.nationality = document[.nationality]
            person.birthDate = CrewFieldValidator.isoDate(document[.birthDate])
            person.verification = document.canExport() ? .verified : .pending

            data.people.append(person)
            data.documents.append(document)
            data.assignments.append(CrewAssignment(tripID: trip.id, personID: person.id, role: .passenger))
        }

        // MARK: The skipper
        if let skipperNumber, let document = data.documents.first(where: { $0.documentNumber == skipperNumber }) {
            for index in data.assignments.indices where data.assignments[index].personID == document.personID {
                data.assignments[index].role = .skipper
            }
        }

        try await store.save(data)

        let reloaded = try await store.load()
        XCTAssertEqual(reloaded.documents.count, files.count)
        XCTAssertEqual(reloaded.assignments.filter { $0.role == .skipper }.count, 1, "exactly one skipper")
        let blocked = reloaded.documents.filter { !$0.canExport() }
        print("\n--- store rebuilt ---")
        if let boat = reloaded.boats.first, let trip = reloaded.trips.first {
            print("  \(boat.name) · \(boat.flag) · \(boat.registrationPort) · \(boat.registrationNumber)")
            print("  \(CrewFieldValidator.iso8601String(trip.departureDate)) → \(CrewFieldValidator.iso8601String(trip.returnDate))")
        }
        for document in reloaded.documents.sorted(by: { $0.documentNumber < $1.documentNumber }) {
            let role = reloaded.assignments.first { $0.personID == document.personID }?.role ?? .passenger
            print("  \(document.canExport() ? "✓" : "✗") \(role.label.padding(toLength: 9, withPad: " ", startingAt: 0)) \(document.documentNumber)  \(document[.fullName])")
        }
        print("---------------------\n")
        XCTAssertTrue(blocked.isEmpty, "still blocked: \(blocked.map(\.documentNumber))")
    }
}
