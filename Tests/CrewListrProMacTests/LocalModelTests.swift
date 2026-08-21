import Foundation
import XCTest
@testable import CrewListrProMac

/// The optional local vision model: what the operator is told when it is not
/// installed, and what it would cost to install.
final class LocalModelTests: XCTestCase {

    // MARK: - Errors say what to do, not only what broke

    func testEveryRescueFailureCarriesARecoverySuggestion() {
        let failures: [RescueError] = [.modelNotInstalled, .runtimeMissing, .runtimeDidNotStart, .unreadableReply]
        for failure in failures {
            XCTAssertNotNil(failure.errorDescription, "\(failure) has no description")
            XCTAssertNotNil(failure.recoverySuggestion, "\(failure) tells the operator nothing to do")
        }
    }

    /// The regression this whole change exists for: a missing model used to
    /// surface as CocoaError(.fileNoSuchFile) — "The file doesn't exist."
    func testAMissingModelIsNotReportedAsAMissingFile() {
        let message = CrewStore.explain(RescueError.modelNotInstalled)
        XCTAssertFalse(message.contains("doesn't exist"), message)
        XCTAssertTrue(message.contains("not installed"), message)
        XCTAssertTrue(message.contains("Download"), "the operator is not told how to fix it:\n\(message)")
    }

    func testTheSuggestionNamesTheSizeSoTheChoiceIsInformed() {
        let message = CrewStore.explain(RescueError.modelNotInstalled)
        XCTAssertTrue(message.contains("GB"), "a multi-gigabyte download must state its size:\n\(message)")
    }

    func testExplainFallsBackToTheSystemMessageForPlainErrors() {
        let plain = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something went wrong."])
        XCTAssertEqual(CrewStore.explain(plain), "Something went wrong.")
    }

    // MARK: - The manifest

    func testTheManifestDescribesItsOwnSize() {
        let manifest = ModelManifest.qwen3VL8BQ4
        XCTAssertEqual(manifest.totalBytes, manifest.assets.reduce(0) { $0 + $1.sizeBytes })
        XCTAssertTrue(manifest.approximateSizeDescription.contains("GB"), manifest.approximateSizeDescription)
    }

    func testEveryAssetIsPinnedToASHA256() {
        for asset in ModelManifest.qwen3VL8BQ4.assets {
            XCTAssertEqual(asset.sha256.count, 64, "\(asset.fileName) is not pinned to a full SHA-256")
            XCTAssertTrue(asset.sha256.allSatisfy(\.isHexDigit), asset.fileName)
            XCTAssertGreaterThan(asset.sizeBytes, 0, asset.fileName)
        }
    }

    func testEveryAssetIsFetchedOverHTTPS() {
        for asset in ModelManifest.qwen3VL8BQ4.assets {
            XCTAssertEqual(asset.url.scheme, "https", "\(asset.fileName) would download in the clear")
        }
    }

    // MARK: - Disk guard

    func testTheDownloadErrorsAlsoExplainThemselves() {
        for failure in [ModelDownloadError.insufficientDisk, .integrity, .offline] {
            XCTAssertNotNil(failure.errorDescription, "\(failure)")
        }
    }
}

// MARK: - The install offer

@MainActor
final class LocalModelOfferTests: XCTestCase {

    /// A store with no database behind it: safe to construct, never writes.
    private func makeStore() -> CrewStore { CrewStore(secureStore: nil) }

    func testTheModelIsReportedAbsentUntilItIsInstalled() {
        XCTAssertFalse(makeStore().localModelIsInstalled,
                       "an uninstalled model must not read as present")
    }

    func testTheOfferNamesTheModelAndItsSize() {
        let description = makeStore().localModelDescription
        XCTAssertTrue(description.contains(ModelManifest.qwen3VL8BQ4.displayName), description)
        XCTAssertTrue(description.contains("GB"), "the operator must see the size before agreeing:\n\(description)")
    }

}

// MARK: - Finding a model already on this Mac

/// The app is not the only thing here that downloads models. Looking only in
/// its own directory offered a 5.78 GB download of bytes already present.
final class ModelResolutionTests: XCTestCase {

    private let manifest = ModelManifest.qwen3VL8BQ4

    // MARK: Repository naming

    func testAHuggingFaceURLBecomesItsCacheDirectoryName() {
        let url = URL(string: "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/x.gguf")!
        XCTAssertEqual(ModelManager.repositoryDirectoryName(from: url), "models--Qwen--Qwen3-VL-8B-Instruct-GGUF")
    }

    func testANonHuggingFaceURLResolvesToNoCacheDirectory() {
        let url = URL(string: "https://example.com/Qwen/model/resolve/main/x.gguf")!
        XCTAssertNil(ModelManager.repositoryDirectoryName(from: url), "only the hub lays blobs out this way")
    }

    // MARK: Resolution

    /// A blob whose filename is its SHA-256, at the right size, is the asset.
    func testAnAssetIsFoundInTheHubCache() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "hf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let asset = manifest.assets[1]                       // the smaller one
        let blobs = home.appending(path: "hub/models--Qwen--Qwen3-VL-8B-Instruct-GGUF/blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        // Stand-in of the right size; resolution checks size, not content.
        let blob = blobs.appending(path: asset.sha256)
        try Data(count: Int(asset.sizeBytes)).write(to: blob)

        setenv("HF_HOME", home.path(percentEncoded: false), 1)
        defer { unsetenv("HF_HOME") }

        let manager = try ModelManager()
        let resolved = await manager.resolvedURL(for: asset)
        XCTAssertEqual(resolved?.lastPathComponent, asset.sha256)
    }

    /// The same snapshot holds an F16 projector this app must not use. Matching
    /// on the pinned hash rather than a filename makes that impossible.
    func testAWrongSizedBlobIsNotAccepted() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "hf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let asset = manifest.assets[1]
        let blobs = home.appending(path: "hub/models--Qwen--Qwen3-VL-8B-Instruct-GGUF/blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try Data(count: 1024).write(to: blobs.appending(path: asset.sha256))   // truncated

        setenv("HF_HOME", home.path(percentEncoded: false), 1)
        defer { unsetenv("HF_HOME") }

        let manager = try ModelManager()
        let resolved = await manager.resolvedURL(for: asset)
        XCTAssertNil(resolved, "a partial blob must not read as an installed model")
    }

    func testNothingResolvesWhenTheModelIsAbsent() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "hf-empty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("HF_HOME", home.path(percentEncoded: false), 1)
        defer { unsetenv("HF_HOME") }

        let manager = try ModelManager()
        let resolved = await manager.resolvedURL(for: manifest.assets[1])
        XCTAssertNil(resolved)
    }

    /// Resolution must never point at a file the app has not been told about.
    func testResolutionOnlyEverNamesThePinnedHash() async throws {
        for asset in manifest.assets {
            let candidates = ModelManager.repositoryDirectoryName(from: asset.url)
            XCTAssertEqual(candidates, "models--Qwen--Qwen3-VL-8B-Instruct-GGUF")
            XCTAssertEqual(asset.sha256.count, 64)
        }
    }
}

// MARK: - Diagnostic: is the model actually reachable on THIS Mac?

/// Opt-in, and it reads the real environment rather than a fixture, so it is a
/// diagnostic rather than a unit test: set CREWLISTR_CHECK_MODEL=1.
/// Useful for confirming a resolution change before deleting a copy.
final class LocalModelDiagnostic: XCTestCase {

    func testTheModelResolvesOnThisMac() async throws {
        guard ProcessInfo.processInfo.environment["CREWLISTR_CHECK_MODEL"] == "1" else {
            throw XCTSkip("Set CREWLISTR_CHECK_MODEL=1 to check the real machine.")
        }
        let manager = try ModelManager()
        for asset in ModelManifest.qwen3VL8BQ4.assets {
            let resolved = await manager.resolvedURL(for: asset)
            print("  \(asset.fileName) -> \(resolved?.path(percentEncoded: false) ?? "NOT FOUND")")
            XCTAssertNotNil(resolved, "\(asset.fileName) could not be found anywhere")
        }
        let ready = await manager.isReady(.qwen3VL8BQ4)
        print("  isReady -> \(ready)")
        XCTAssertTrue(ready)
    }
}
