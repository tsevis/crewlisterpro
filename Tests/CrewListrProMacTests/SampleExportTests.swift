import Foundation
import XCTest
@testable import CrewListrProMac

/// Produces a crew list from fictional specimens for documentation, so no real
/// identity document is ever committed to the repository.
///
/// Set CREWLISTR_SAMPLE_OUT to a directory to write it.
final class SampleExportTests: XCTestCase {

    func testWritesASampleCrewList() throws {
        guard let path = ProcessInfo.processInfo.environment["CREWLISTR_SAMPLE_OUT"] else {
            throw XCTSkip("Set CREWLISTR_SAMPLE_OUT to write the documentation sample.")
        }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let boat = Boat(name: "S/Y ELPIDA", flag: "GRC", registrationPort: "PIRAEUS", registrationNumber: "GR-1187-P")
        let trip = Trip(boatID: boat.id,
                        departureDate: Date(timeIntervalSince1970: 1_756_684_800),
                        returnDate: Date(timeIntervalSince1970: 1_757_289_600))

        let rows = SpecimenGenerator.demoCrew.enumerated().map { index, specimen -> CrewListRow in
            var document = CrewDocument(tripID: trip.id, personID: UUID(),
                                        originalName: "specimen-\(specimen.number).png", encryptedFileName: "")
            let zone = SpecimenGenerator.mrz(specimen)
            let parsed = MRZ.parse("\(zone.line1)\n\(zone.line2)") ?? [:]
            for field in CrewField.allCases {
                document[field] = parsed[field.rawValue] ?? ""
            }
            return CrewListRow(document: document, role: index == 0 ? .skipper : .passenger)
        }

        let base = ExportService.fileNameStem(boat: boat, trip: trip)
        try ExportService.exportCSV(to: output.appending(path: "\(base).csv"), trip: trip, boat: boat, rows: rows)
        try ExportService.exportPDF(to: output.appending(path: "\(base).pdf"), trip: trip, boat: boat, rows: rows)

        for row in rows {
            XCTAssertFalse(row.fullName.isEmpty)
            XCTAssertFalse(row.birthDate.isEmpty)
        }
        print("Sample crew list: \(output.appending(path: "\(base).pdf").path(percentEncoded: false))")
    }
}
