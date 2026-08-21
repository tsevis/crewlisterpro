import Foundation

/// Optional local-only VLM rescue for documents without a valid MRZ. The
/// caller keeps every returned field pending until the operator verifies it.
/// Why a rescue could not run. The previous version threw bare `CocoaError`s,
/// so a missing model surfaced to the operator as "The file doesn't exist." —
/// true, unhelpful, and giving no hint that a 5.8 GB download is the fix.
enum RescueError: LocalizedError {
    case modelNotInstalled
    case runtimeMissing
    case runtimeDidNotStart
    case unreadableReply

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            "The local AI model is not installed on this Mac."
        case .runtimeMissing:
            "The local AI runtime is missing from this build of \(AppVersion.name)."
        case .runtimeDidNotStart:
            "The local AI model did not finish loading."
        case .unreadableReply:
            "The local AI returned something that was not a set of document fields."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotInstalled:
            "Download \(ModelManifest.qwen3VL8BQ4.displayName) (\(ModelManifest.qwen3VL8BQ4.approximateSizeDescription)). It is a one-time download and stays on this Mac. Everything else works without it."
        case .runtimeMissing:
            "This build was packaged without llama-server. Rebuild with scripts/release.sh on a machine that has it."
        case .runtimeDidNotStart:
            "It can take a minute on first use. Try again, and check there is free memory."
        case .unreadableReply:
            "Type the fields from the image instead — the machine-readable zone on this document could not be read either."
        }
    }
}

actor LlamaVisionRescuer {
    private let endpoint = URL(string: "http://127.0.0.1:18081")!

    func extract(imageData: Data) async throws -> [String: String] {
        try await startIfNeeded()
        var request = URLRequest(url: endpoint.appending(path: "v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let prompt = "Read only clearly visible identity-document fields. Reply with JSON keys full_name, document_number, nationality, birth_date, sex. Use empty strings when uncertain."
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "local", "temperature": 0,
            "messages": [["role": "user", "content": [["type": "text", "text": prompt], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"]]]]],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = outer["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let jsonData = content.data(using: .utf8),
              let fields = try JSONSerialization.jsonObject(with: jsonData) as? [String: String] else {
            throw RescueError.unreadableReply
        }
        return fields.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func startIfNeeded() async throws {
        if (try? await URLSession.shared.data(from: endpoint.appending(path: "health"))) != nil { return }
        let manager = try ModelManager()
        guard await manager.isReady(.qwen3VL8BQ4) else { throw RescueError.modelNotInstalled }
        guard let model = await manager.resolvedURL(for: ModelManifest.qwen3VL8BQ4.assets[0]),
              let projector = await manager.resolvedURL(for: ModelManifest.qwen3VL8BQ4.assets[1]) else {
            throw RescueError.modelNotInstalled
        }
        let executable = ProcessInfo.processInfo.environment["CREWLISTR_LLAMA_SERVER"] ?? Bundle.main.url(forResource: "llama-server", withExtension: nil)?.path
        guard let executable else { throw RescueError.runtimeMissing }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            // Resolved, not assumed: the model may live in the HuggingFace
            // cache rather than the app's own directory.
            "--model", model.path(percentEncoded: false),
            "--mmproj", projector.path(percentEncoded: false),
            "--host", "127.0.0.1", "--port", "18081", "--no-webui",
        ]
        try process.run()
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(250))
            if (try? await URLSession.shared.data(from: endpoint.appending(path: "health"))) != nil { return }
        }
        process.terminate()
        throw RescueError.runtimeDidNotStart
    }
}
