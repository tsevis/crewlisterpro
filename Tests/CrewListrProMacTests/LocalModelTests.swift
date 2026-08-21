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
