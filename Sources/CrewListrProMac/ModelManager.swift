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

    /// Where a download would put this asset. Not necessarily where it is.
    func localURL(for asset: ModelAsset) -> URL { directory.appending(path: asset.fileName) }

    /// Where the asset actually is, wherever that turns out to be.
    ///
    /// The app is not the only thing on this Mac that downloads models. Looking
    /// only in its own directory made it offer to fetch 5.78 GB that was already
    /// present — the operator had pulled the same model through llama.cpp months
    /// earlier, and it was sitting in the HuggingFace cache.
    ///
    /// The HuggingFace hub stores blobs content-addressed: the filename IS the
    /// SHA-256. Since the manifest already pins that hash, the lookup is exact
    /// rather than a guess — there is no way to pick up a different quantisation
    /// by matching a filename loosely, which matters here because the same
    /// snapshot also holds an F16 mmproj this app must not use.
    func resolvedURL(for asset: ModelAsset) -> URL? {
        for candidate in [localURL(for: asset)] + Self.hubBlobURLs(for: asset) {
            guard let size = try? FileManager.default.attributesOfItem(
                atPath: candidate.path(percentEncoded: false)
            )[.size] as? Int64 else { continue }
            // Size is the cheap guard against a truncated or partial file.
            // Re-hashing five gigabytes on every readiness check would cost
            // minutes; the hub's own content addressing carries the rest.
            guard size == asset.sizeBytes else { continue }
            return candidate
        }
        return nil
    }

    /// Candidate blob paths in the HuggingFace hub cache, honouring the
    /// environment variables the Python tooling uses.
    private static func hubBlobURLs(for asset: ModelAsset) -> [URL] {
        guard let repository = repositoryDirectoryName(from: asset.url) else { return [] }
        // HF_HOME and HUGGINGFACE_HUB_CACHE RELOCATE the cache in the Python
        // tooling — they do not add a second place to look. Honour that: an
        // operator who has moved their cache to another volume does not want
        // this app quietly reading a stale copy from the default path.
        let environment = ProcessInfo.processInfo.environment
        let roots: [URL]
        if let explicit = environment["HUGGINGFACE_HUB_CACHE"] {
            roots = [URL(fileURLWithPath: explicit)]
        } else if let home = environment["HF_HOME"] {
            roots = [URL(fileURLWithPath: home).appending(path: "hub")]
        } else {
            roots = [
                FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: ".cache").appending(path: "huggingface").appending(path: "hub")
            ]
        }
        return roots.map {
            $0.appending(path: repository).appending(path: "blobs").appending(path: asset.sha256)
        }
    }

    /// `https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/...`
    /// becomes `models--Qwen--Qwen3-VL-8B-Instruct-GGUF`.
    static func repositoryDirectoryName(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, url.host()?.contains("huggingface.co") == true else { return nil }
        return "models--\(parts[0])--\(parts[1])"
    }

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

    func isReady(_ manifest: ModelManifest) -> Bool {
        manifest.assets.allSatisfy { resolvedURL(for: $0) != nil }
    }

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
            // Anything already on this Mac — ours or someone else's — is not
            // downloaded again.
            guard resolvedURL(for: asset) == nil else {
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
