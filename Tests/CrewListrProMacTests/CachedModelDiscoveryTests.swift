import Foundation
import XCTest
@testable import CrewListrProMac

/// Proves the resolution works against a real HuggingFace cache, not only
/// against a constructed one.
///
/// The unit tests build the blob path from a URL and check the string. That is
/// necessary and not sufficient: the question an operator cares about is
/// whether THIS machine's existing 5.78 GB is found, and the only way to answer
/// it is to look. A wrong assumption about where the hub puts its blobs, or
/// about which of the two mmproj files the manifest wants, would pass every
/// constructed test and still offer a pointless download.
///
/// Skips on a machine without the model, so it costs nothing in CI.
final class CachedModelDiscoveryTests: XCTestCase {

    private var cacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/huggingface/hub/models--Qwen--Qwen3-VL-8B-Instruct-GGUF/blobs")
    }

    private func blob(_ sha: String) -> URL { cacheRoot.appending(path: sha) }

    private func requireCachedModel() throws {
        let present = ModelManifest.qwen3VL8BQ4.assets.allSatisfy {
            FileManager.default.fileExists(atPath: blob($0.sha256).path(percentEncoded: false))
        }
        try XCTSkipUnless(present, "this machine has no HuggingFace copy of the model")
    }

    func testAnAlreadyCachedModelIsFoundRatherThanDownloadedAgain() async throws {
        try requireCachedModel()
        let manager = try ModelManager()

        let ready = await manager.isReady(.qwen3VL8BQ4)
        XCTAssertTrue(ready, "the model is on this Mac but the app would still offer to download it")
    }

    /// It must resolve to the cache, not to the app's own directory — otherwise
    /// `isReady` says yes and llama-server is handed a path to nothing.
    func testResolutionPointsAtTheCachedFileItActuallyFound() async throws {
        try requireCachedModel()
        let manager = try ModelManager()

        for asset in ModelManifest.qwen3VL8BQ4.assets {
            let candidate = await manager.resolvedURL(for: asset)
            let resolved = try XCTUnwrap(candidate, asset.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false)),
                          "resolved to a path that does not exist: \(resolved.path(percentEncoded: false))")

            let size = try XCTUnwrap(
                (try FileManager.default.attributesOfItem(atPath: resolved.path(percentEncoded: false)))[.size] as? Int64
            )
            XCTAssertEqual(size, asset.sizeBytes,
                           "\(asset.fileName) resolved to a file of the wrong size — a truncated or wrong-quantisation blob")
        }
    }

    /// The same snapshot also holds an F16 mmproj. The manifest wants Q8_0, and
    /// resolution is by SHA-256 rather than by filename, so the wrong one can
    /// never be adopted — this pins that they are genuinely different files.
    func testTheWrongProjectorCannotBeAdoptedByAccident() throws {
        try requireCachedModel()
        let wanted = ModelManifest.qwen3VL8BQ4.assets[1]
        XCTAssertTrue(wanted.fileName.contains("Q8_0"), "the manifest no longer pins the Q8_0 projector")

        let f16 = blob("ca524100ebf825c9a870db1c580d03879e0da0ab2541697e2458e64891cf9d38")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: f16.path(percentEncoded: false)),
                          "this machine has no F16 projector to confuse it with")
        XCTAssertNotEqual(f16.lastPathComponent, wanted.sha256.lowercased(),
                          "the F16 projector shares the Q8_0's hash, which cannot be")
    }
}
