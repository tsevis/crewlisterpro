import Foundation
import XCTest
@testable import CrewListrProMac

/// Runs the real local-AI rescue against real identity documents.
///
/// Opt-in: `CREWLISTR_RESCUE` is a colon-separated list of image paths. The
/// committed integration test uses a synthetic ICAO specimen, which is right for
/// a suite but says nothing about a photographed passport whose name line the
/// camera destroyed — the case the rescue exists for. This measures that.
///
/// It loads a 5 GB model, so it is a diagnostic, not part of the suite. All
/// documents run in one process so the model loads once.
final class RescueDiagnostic: XCTestCase {

    func testRescueRealDocuments() async throws {
        guard let list = ProcessInfo.processInfo.environment["CREWLISTR_RESCUE"] else {
            throw XCTSkip("Set CREWLISTR_RESCUE to colon-separated image paths.")
        }
        let paths = list.split(separator: ":").map(String.init)
        XCTAssertFalse(paths.isEmpty)

        let rescuer = LlamaVisionRescuer()
        var anySucceeded = false

        for path in paths {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            print("\n===== \(url.lastPathComponent)  (\(data.count) bytes) =====")

            let started = Date()
            nonisolated(unsafe) var lastPhase = ""
            do {
                let fields = try await rescuer.extract(imageData: data) { phase in
                    let described = "\(phase)"
                    if described != lastPhase {
                        lastPhase = described
                        FileHandle.standardError.write(Data("    [phase] \(described)\n".utf8))
                    }
                }
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
                print("  returned \(fields.count) field(s) in \(elapsed)s")
                for key in CrewField.allCases.map(\.rawValue).sorted() {
                    guard let value = fields[key] else { continue }
                    print("    \(key.padding(toLength: 16, withPad: " ", startingAt: 0)) \(value)")
                }
                for (key, value) in fields.sorted(by: { $0.key < $1.key })
                where !CrewField.allCases.map(\.rawValue).contains(key) {
                    print("    (ignored downstream) \(key): \(value)")
                }
                anySucceeded = true
            } catch {
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
                print("  FAILED after \(elapsed)s")
                print("  \(CrewStore.explain(error))")
            }
        }

        XCTAssertTrue(anySucceeded, "the local model produced nothing for any document")
    }
}
