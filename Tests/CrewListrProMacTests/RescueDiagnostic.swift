import Foundation
import XCTest
@testable import CrewListrProMac

/// Runs the real local-AI rescue against a real document.
///
/// Opt-in: CREWLISTR_RESCUE=<path to an image>. It starts llama-server and
/// loads a 5 GB model, so it is a diagnostic, not part of the suite.
final class RescueDiagnostic: XCTestCase {

    func testRescueADocument() async throws {
        guard let path = ProcessInfo.processInfo.environment["CREWLISTR_RESCUE"] else {
            throw XCTSkip("Set CREWLISTR_RESCUE to an image path to exercise the local model.")
        }
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        print("\n--- rescuing \(url.lastPathComponent) (\(data.count) bytes) ---")

        let started = Date()
        do {
            let fields = try await LlamaVisionRescuer().extract(imageData: data)
            print("  took \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
                print("  \(key): \(value)")
            }
            XCTAssertFalse(fields.isEmpty, "the model returned nothing")
            let known = Set(CrewField.allCases.map(\.rawValue))
            for key in fields.keys where !known.contains(key) {
                print("  (unrecognised key ignored downstream: \(key))")
            }
        } catch {
            print("  FAILED after \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            print("  \(CrewStore.explain(error))")
            throw error
        }
    }
}
