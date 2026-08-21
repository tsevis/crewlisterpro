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

    /// Downloads one asset to a temporary file, reporting bytes as they arrive
    /// and honouring cancellation. A cancelled transfer deletes its partial file
    /// rather than leaving something that looks like a model.
    private func streamToFile(
        _ asset: ModelAsset,
        alreadyReceived: Int64,
        total: Int64,
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> URL {
        let (stream, response) = try await URLSession.shared.bytes(from: asset.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ModelDownloadError.offline }

        let temporary = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).part")
        FileManager.default.createFile(atPath: temporary.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)

        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var written: Int64 = 0
        do {
            for try await byte in stream {
                buffer.append(byte)
                if buffer.count >= (1 << 20) {
                    try handle.write(contentsOf: buffer)
                    written += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    onProgress?(alreadyReceived + written, total)
                    try Task.checkCancellation()
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
            }
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        onProgress?(alreadyReceived + written, total)
        return temporary
    }

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
    ///
    /// `onProgress` receives bytes-so-far and the manifest total, across all
    /// assets, so a caller can draw one bar for the whole download rather than
    /// one per file. Cancelling the surrounding task stops the transfer and
    /// leaves nothing half-written in place.
    func download(_ manifest: ModelManifest, onProgress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws {
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let requiredBytes = manifest.assets.reduce(Int64(0)) { $0 + $1.sizeBytes }
        guard (values.volumeAvailableCapacityForImportantUsage ?? 0) > requiredBytes + 1_500_000_000 else { throw ModelDownloadError.insufficientDisk }
        let totalBytes = manifest.totalBytes
        var received: Int64 = 0
        for asset in manifest.assets {
            guard !FileManager.default.fileExists(atPath: localURL(for: asset).path(percentEncoded: false)) else {
                received += asset.sizeBytes
                onProgress?(received, totalBytes)
                continue
            }
            do {
                let temporary = try await streamToFile(asset, alreadyReceived: received, total: totalBytes, onProgress: onProgress)
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
                received += asset.sizeBytes
                onProgress?(received, totalBytes)
            } catch let error as ModelDownloadError { throw error }
            catch { throw ModelDownloadError.offline }
        }
    }
}
