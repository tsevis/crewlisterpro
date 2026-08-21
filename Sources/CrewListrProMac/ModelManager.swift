import CryptoKit
import Foundation

struct ModelAsset: Codable, Sendable {
    let fileName: String
    let url: URL
    let sha256: String
    let sizeBytes: Int64
}

struct ModelManifest: Codable, Sendable {
    let assets: [ModelAsset]
    let displayName: String

    var totalBytes: Int64 { assets.reduce(0) { $0 + $1.sizeBytes } }

    /// For telling the operator what they are about to commit to.
    var approximateSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    static let qwen3VL8BQ4 = ModelManifest(
        assets: [
            ModelAsset(fileName: "Qwen3VL-8B-Instruct-Q4_K_M.gguf", url: URL(string: "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf")!, sha256: "67d1659bfe71b89d50b45a4ad1a9e5b997e5bb16ce5da66a6a6167abd569e9e2", sizeBytes: 5_027_784_800),
            ModelAsset(fileName: "mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf", url: URL(string: "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf")!, sha256: "c6ba85508d82f42590e6eb77d5340369ab6fecf107a7561d809523d8aa5f3bfd", sizeBytes: 752_289_728),
        ],
        displayName: "Qwen3-VL 8B Q4"
    )
}

enum ModelDownloadError: LocalizedError {
    case insufficientDisk, integrity, offline
    var errorDescription: String? {
        switch self {
        case .insufficientDisk: "At least 8 GB of free disk space is required for this model."
        case .integrity: "The downloaded model did not pass its SHA-256 integrity check."
        case .offline: "The model could not be downloaded. Check your internet connection and retry."
        }
    }
}

actor ModelManager {
    private let directory: URL

    init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = support.appending(path: "CrewListrPro/models", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func localURL(for asset: ModelAsset) -> URL { directory.appending(path: asset.fileName) }

    /// Streams the file through SHA-256 a chunk at a time.
    private static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    func isReady(_ manifest: ModelManifest) -> Bool { manifest.assets.allSatisfy { FileManager.default.fileExists(atPath: localURL(for: $0).path(percentEncoded: false)) } }

    /// Call only after the UI presents storage use and obtains explicit consent.
    func download(_ manifest: ModelManifest) async throws {
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let requiredBytes = manifest.assets.reduce(Int64(0)) { $0 + $1.sizeBytes }
        guard (values.volumeAvailableCapacityForImportantUsage ?? 0) > requiredBytes + 1_500_000_000 else { throw ModelDownloadError.insufficientDisk }
        for asset in manifest.assets where !FileManager.default.fileExists(atPath: localURL(for: asset).path(percentEncoded: false)) {
            do {
                let (temporary, response) = try await URLSession.shared.download(from: asset.url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ModelDownloadError.offline }
                // Hash by streaming. Reading a 5 GB model into memory to
                // checksum it, then holding it again to write, needed ~10 GB of
                // RAM for a file already sitting on disk.
                guard try Self.sha256(ofFileAt: temporary) == asset.sha256.lowercased() else {
                    try? FileManager.default.removeItem(at: temporary)
                    throw ModelDownloadError.integrity
                }
                let destination = localURL(for: asset)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch let error as ModelDownloadError { throw error }
            catch { throw ModelDownloadError.offline }
        }
    }
}
