import Foundation
import XCTest
@testable import CrewListrProMac

/// Populates the app's live encrypted store with synthetic specimens so the UI
/// can be photographed for documentation.
///
/// Opt-in and destructive: it replaces whatever is in the operator's store.
/// Set CREWLISTR_SEED_DEMO=1 to run it, CREWLISTR_SEED_DEMO=wipe to clear it,
/// and only ever on a demo machine.
final class DemoSeed: XCTestCase {

    func testSeedDemoData() async throws {
        guard ProcessInfo.processInfo.environment["CREWLISTR_SEED_DEMO"] == "1" else {
            throw XCTSkip("Set CREWLISTR_SEED_DEMO=1 to overwrite the local store with demo data.")
        }
        let staging = FileManager.default.temporaryDirectory.appending(path: "crewlistr-demo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        let specimens = try SpecimenGenerator.write(to: staging, includeDamagedScan: true)

        let store = try SecureStore()
        let boat = Boat(name: "S/Y ELPIDA", flag: "GRC", registrationPort: "PIRAEUS", registrationNumber: "GR-1187-P")
        let trip = Trip(boatID: boat.id,
                        departureDate: Date(timeIntervalSince1970: 1_756_684_800),
                        returnDate: Date(timeIntervalSince1970: 1_757_289_600))
        var data = AppData(boats: [boat], trips: [trip])

        for (index, url) in specimens.enumerated() {
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

            // Show the three review states side by side: one cleared, one part
            // way through, and the glare-damaged scan untouched.
            switch index {
            case 0:
                for field in CrewField.allCases where !document.validation(of: field).isBlocking {
                    document.verifiedFields.insert(field.rawValue)
                }
                document.risk = .low
                document.riskReasons = ["Checked against the image by the operator."]
            case 1:
                document.verifiedFields = [CrewField.fullName.rawValue, CrewField.documentNumber.rawValue]
            default:
                break
            }

            data.people.append(person)
            data.documents.append(document)
            data.assignments.append(CrewAssignment(tripID: trip.id, personID: person.id,
                                                   role: index == 0 ? .skipper : .passenger))
        }

        try await store.save(data)
        let reloaded = try await store.load()
        XCTAssertEqual(reloaded.documents.count, specimens.count)
        XCTAssertEqual(reloaded.boats.first?.name, "S/Y ELPIDA")
        XCTAssertTrue(reloaded.documents[0].canExport(), "the first specimen should show as cleared")
        XCTAssertEqual(reloaded.documents[1].reviewStatus(), .inProgress)
        XCTAssertEqual(reloaded.documents.last?.reviewStatus(), .awaitingReview)
        print("Seeded \(reloaded.documents.count) demo documents into the live store.")
    }

    func testWipeDemoData() async throws {
        guard ProcessInfo.processInfo.environment["CREWLISTR_SEED_DEMO"] == "wipe" else {
            throw XCTSkip("Set CREWLISTR_SEED_DEMO=wipe to clear the local store.")
        }
        let store = try SecureStore()
        try await store.save(AppData())
        let reloaded = try await store.load()
        XCTAssertTrue(reloaded.documents.isEmpty)
        print("Cleared the local store.")
    }
}
