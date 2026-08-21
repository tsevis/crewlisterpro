import Foundation
import XCTest
@testable import CrewListrProMac

/// Runs the local vision model against a document its MRZ cannot rescue.
///
/// Opt-in — `CREWLISTR_RESCUE=1` — because it starts a real llama-server,
/// loads an 8B model and performs real inference. Minutes, not milliseconds,
/// and it needs the weights on the machine. Everything else about the rescue
/// path is unit-tested; this is the one check that the whole chain actually
/// produces fields from a picture.
///
/// The specimen is synthetic on the ICAO utopian issuer code. Sending a real
/// passport through a test would be the wrong way to prove a privacy-preserving
/// feature works.
final class LocalRescueIntegrationTests: XCTestCase {

    func testTheLocalModelReadsADocumentWhoseMRZIsUnreadable() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CREWLISTR_RESCUE"] == "1",
                          "opt-in: starts llama-server and runs real inference")

        let manager = try ModelManager()
        let ready = await manager.isReady(.qwen3VL8BQ4)
        try XCTSkipUnless(ready, "the local model is not available on this machine")

        // The case the feature exists for: a scan whose machine-readable zone
        // is destroyed, so MRZ parsing yields nothing and only looking at the
        // page can recover the identity.
        let specimen = SpecimenGenerator.demoCrew[1]
        let imageData = try SpecimenGenerator.damagedPNG(specimen)

        let mrzResult = try OCRService.extract(from: imageData)
        XCTAssertNil(mrzResult.fields["full_name"],
                     "this specimen is supposed to defeat MRZ parsing; if it does not, it is not testing the rescue")

        let started = Date()
        let fields = try await LlamaVisionRescuer().extract(imageData: imageData)
        print("RESCUE returned \(fields.count) fields in \(Int(Date().timeIntervalSince(started)))s: \(fields)")

        XCTAssertFalse(fields.isEmpty, "the rescue returned nothing at all")

        // Deliberately loose. A vision model is not a checksum, and the point
        // of the review gate is that nothing it says is trusted — its output
        // arrives unconfirmed like every other read. Asserting an exact
        // transcription would pin the test to one model's phrasing.
        let joined = fields.values.joined(separator: " ").uppercased()
        XCTAssertTrue(joined.contains(specimen.surname) || joined.contains(specimen.number),
                      "expected the surname or the document number somewhere in \(fields)")

        // Whatever it returns has to be in the app's own vocabulary. The model
        // reads what is printed on the page — "19 FEB 83" — and a value the
        // operator must retype before they can confirm it is a rescue that
        // recovered the answer and then threw it away.
        for (key, value) in fields {
            guard let field = CrewField(rawValue: key), !value.isEmpty else { continue }
            let validation = CrewFieldValidator.validate(field, value: value)
            XCTAssertFalse(validation.isBlocking,
                           "\(field.label) came back as \"\(value)\", which the app rejects: \(validation.message ?? "")")
        }
    }
}
