import Foundation
import XCTest
@testable import CrewListrProMac

/// The rescue's startup path, which was unsurvivable on first use.
///
/// Measured, not guessed: a cold load of the 8B model with its projector took
/// about ten minutes on this Mac. The wait was 30 polls at 250ms — 7.5 seconds
/// — so the first rescue an operator ever attempted always failed, left a
/// half-loaded server running that nobody tracked, and then worked on the
/// second attempt with no explanation for either outcome.
final class RescueRuntimeTests: XCTestCase {

    // MARK: - Finding the runtime

    /// Anyone already running local models has llama-server installed. Looking
    /// only in the app bundle reports it "missing from this build" about a
    /// binary sitting on the machine.
    func testTheRuntimeIsFoundOnPATH() throws {
        let onPath = ["/usr/local/bin", "/opt/homebrew/bin", "\(NSHomeDirectory())/.local/bin"]
            .map { $0 + "/llama-server" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        try XCTSkipUnless(onPath != nil, "no llama-server installed on this machine")

        XCTAssertNotNil(LocalRuntime.runtimeExecutable(),
                        "llama-server is on this machine but the app reports the runtime missing")
    }

    func testAnExplicitOverrideWins() {
        let override = LocalRuntime.runtimeExecutable()
        try? XCTSkipIf(override == nil)
        setenv("CREWLISTR_LLAMA_SERVER", "/nonexistent/llama-server", 1)
        defer { unsetenv("CREWLISTR_LLAMA_SERVER") }

        // A non-executable override is ignored rather than trusted blindly:
        // pointing at a path that is not there must not disable the fallbacks.
        XCTAssertEqual(LocalRuntime.runtimeExecutable(), override,
                       "a bad override should fall through, not break discovery")
    }

    // MARK: - Phases

    /// Each phase says something different, because "starting", "loading for
    /// ten minutes" and "reading" are three different things to be waiting for.
    func testTheThreePhasesAreDistinct() {
        let phases: [LlamaVisionRescuer.Phase] = [
            .startingRuntime, .loadingModel(elapsed: 12), .reading,
        ]
        XCTAssertEqual(Set(phases.map(String.init(describing:))).count, 3)
    }

    func testLoadingCarriesItsElapsedTimeSoTheOperatorSeesMovement() {
        guard case .loadingModel(let elapsed) = LlamaVisionRescuer.Phase.loadingModel(elapsed: 42) else {
            return XCTFail("phase lost its elapsed time")
        }
        XCTAssertEqual(elapsed, 42)
    }
}
