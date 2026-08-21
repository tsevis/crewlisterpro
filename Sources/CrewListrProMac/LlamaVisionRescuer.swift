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
    /// The server answered, but not with success. Carries the status, because
    /// "503 while the model is still loading" and "400 bad request" are not the
    /// same problem and must not read as the same message.
    case serverRefused(status: Int)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            "The local AI model is not installed on this Mac."
        case .runtimeMissing:
            "The local AI runtime is missing from this build of \(AppVersion.name)."
        case .serverRefused(let status):
            "The local AI is not answering yet (HTTP \(status))."
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
        case .serverRefused(let status):
            "The local AI is not answering yet (HTTP \(status))."
        case .runtimeDidNotStart:
            "It can take a minute on first use. Try again, and check there is free memory."
        case .unreadableReply:
            "Type the fields from the image instead — the machine-readable zone on this document could not be read either."
        }
    }
}

actor LlamaVisionRescuer {
    private let endpoint = URL(string: "http://127.0.0.1:18081")!

    func extract(imageData: Data, onPhase: (@Sendable (Phase) -> Void)? = nil) async throws -> [String: String] {
        try await startIfNeeded(onPhase: onPhase)
        onPhase?(.reading)
        var request = URLRequest(url: endpoint.appending(path: "v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "local", "temperature": 0,
            "messages": [["role": "user", "content": [["type": "text", "text": Self.prompt], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"]]]]],
        ])
        // A server that has answered `health` can still refuse work while it
        // finishes warming, so a refusal is retried rather than reported. The
        // old code collapsed five different failures into one message and named
        // only the last of them, so an HTTP 503 from a loading model reached the
        // operator as "returned something that was not a set of document
        // fields" — false, and it sends them looking in the wrong place.
        var data = Data()
        for attempt in 0..<6 {
            let (body, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { data = body; break }
            guard Self.isTransient(status), attempt < 5 else { throw RescueError.serverRefused(status: status) }
            onPhase?(.loadingModel(elapsed: Double(attempt + 1)))
            try await Task.sleep(for: .seconds(2))
        }
        guard !data.isEmpty else { throw RescueError.serverRefused(status: 0) }

        guard let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = outer["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RescueError.unreadableReply
        }
        let decoded = try Self.decodeFields(from: content)
        return Self.usableFields(from: decoded)
    }

    /// What the model asks for, built from `CrewField.rescuable` so the request
    /// and the filter below cannot drift apart.
    ///
    /// Deliberately minimal, after measuring three earlier versions against two
    /// real passports. Every instruction added to steer the NAME changed how the
    /// model read the rest of the image:
    ///
    ///   name asked for, no steering   both dates correct; names in Cyrillic
    ///   "give the Latin form"         one document perfect; the other invented
    ///                                 MIHCHYK for a page printing MINCHUK
    ///   "copy, do not transliterate"  the invented name stopped, but the
    ///                                 document that had been perfect came back
    ///                                 with June read as April — a field the
    ///                                 instruction never mentioned
    ///
    /// Three prompts, two documents, no version correct on both, and the damage
    /// spread to fields the instruction never named. So the name is not asked
    /// for at all: not asked, rather than asked and discarded, because the
    /// asking itself was what perturbed the reading.
    ///
    /// This wording is a fourth version, so it was measured the same way rather
    /// than assumed: five real passports, this prompt against the previous one,
    /// same images, same run. Document number and birth date came back
    /// character-for-character identical on all five — dropping the name cost
    /// nothing on the fields that are kept — and the expiry date, which the
    /// previous prompt never asked for, came back on all five as well.
    static let prompt = """
        Read only clearly visible identity-document fields. Reply with JSON keys \
        \(CrewField.rescuable.map(\.rawValue).joined(separator: ", ")). \
        Give dates as YYYY-MM-DD. Use empty strings when uncertain.
        """

    /// The model's decoded reply, reduced to what the app will actually offer.
    ///
    /// Two separate jobs, and both belong here rather than at the call site.
    /// First the policy: anything outside `CrewField.rescuable` is dropped, even
    /// though the prompt did not ask for it, because a model that volunteers a
    /// name is exactly as wrong as one that was asked for it. Second the shape:
    /// dates are normalised out of what the page prints, and anything else is
    /// held to Latin script.
    static func usableFields(from decoded: [String: String]) -> [String: String] {
        let allowed = Set(CrewField.rescuable.map(\.rawValue))
        return decoded
            .filter { allowed.contains($0.key) }
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .reduce(into: [String: String]()) { result, entry in
                switch entry.key {
                case CrewField.birthDate.rawValue:
                    result[entry.key] = normalisedDate(entry.value, kind: .birth)
                case CrewField.expiryDate.rawValue:
                    result[entry.key] = normalisedDate(entry.value, kind: .expiry)
                default:
                    // A value still carrying non-Latin script is dropped rather
                    // than offered. See `latinised`. A document number is the
                    // one field where digits are the point.
                    let digitsAllowed = entry.key == CrewField.documentNumber.rawValue
                    if let latin = latinised(entry.value, allowingDigits: digitsAllowed) {
                        result[entry.key] = latin
                    }
                }
            }
    }

    /// The Latin half of a bilingual field, or nil when there is not one.
    ///
    /// Passports print fields twice: "ЦИГІПА/TSYHIPA", "УКРАЇНА/UKRAINE",
    /// "Ж/F". Measured against two real Ukrainian passports, the model
    /// transcribes both halves verbatim, and the consequences are not equal.
    /// "Ж/F" fails validation, so the operator retypes it — visible and safe.
    /// A Cyrillic full_name PASSES: no digits, long enough, no repeated-letter
    /// run. It can be confirmed and reach a crew list in a script a port
    /// authority will not accept.
    ///
    /// So the Latin side is taken per word — the halves pair up word by word,
    /// not across the whole field — and anything still not Latin afterwards
    /// returns nil for the caller to drop. On one of those passports the model
    /// answered "МІНЧУК/МИНЧУК", two Cyrillic spellings where the page prints
    /// "МІНЧУК/MINCHUK", one of them invented. No name is better than a name
    /// that cannot go on the list, and far better than an invented one that can.
    ///
    /// The name is no longer rescued at all — see `CrewField.rescuable` — so
    /// what this now guards in production is the document number, where the
    /// same rule holds: Cyrillic А and В look like a passport number and are
    /// not one. The name history stays because it is why the rule exists, and
    /// because widening `rescuable` again would put it straight back in play.
    static func latinised(_ value: String, allowingDigits: Bool = false) -> String? {
        let words = value.split(separator: " ").map { word -> Substring in
            guard word.contains("/") else { return word }
            return word.split(separator: "/").first { isLatin($0, allowingDigits: allowingDigits) } ?? word
        }
        let rebuilt = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !rebuilt.isEmpty, isLatin(Substring(rebuilt), allowingDigits: allowingDigits) else { return nil }
        return rebuilt
    }

    /// Letters the Latin alphabet actually has, plus what a printed name uses
    /// to join them.
    ///
    /// Digits are excluded by default — a name is not a number, and the MRZ
    /// parser already refuses name lines containing them — but a document
    /// number is mostly digits, so it opts in. Getting that wrong silently
    /// dropped "AB1234567" from a rescue that had read it correctly.
    private static func isLatin(_ text: Substring, allowingDigits: Bool = false) -> Bool {
        !text.isEmpty && text.allSatisfy { character in
            guard character.isASCII else { return false }
            if character.isLetter || " '-.".contains(character) { return true }
            return allowingDigits && character.isNumber
        }
    }

    /// The model reads what is printed on the page — "19 FEB 83" — and the app
    /// only accepts YYYY-MM-DD. Without this the rescue recovers the date and
    /// then hands back a value the operator has to retype before they can
    /// confirm it, which is most of the benefit thrown away.
    ///
    /// Anything unrecognised is returned untouched: the operator then corrects
    /// one field, exactly as they would have before.
    static func normalisedDate(_ value: String, kind: MRZ.DateKind) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if CrewFieldValidator.isoDate(trimmed) != nil { return trimmed }

        let separators = CharacterSet(charactersIn: " -/.,")
        let parts = trimmed.uppercased().components(separatedBy: separators).filter { !$0.isEmpty }
        guard parts.count == 3, let day = Int(parts[0]), (1...31).contains(day) else { return value }

        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        let month: Int
        if let numeric = Int(parts[1]), (1...12).contains(numeric) {
            month = numeric
        } else if let named = months.firstIndex(where: { parts[1].hasPrefix($0) }) {
            month = named + 1
        } else {
            return value
        }

        guard let year = Int(parts[2]) else { return value }
        if parts[2].count == 4 {
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
        guard parts[2].count == 2 else { return value }
        // Two digits are ambiguous, and which way depends on what the date
        // means. `MRZ.date` already decides that for birth and expiry; a second
        // rule here would be one that could disagree with it.
        return MRZ.date(String(format: "%02d%02d%02d", year, month, day), kind: kind) ?? value
    }

    /// 503 and 429 mean "not yet"; a 400 means the request was wrong and
    /// retrying it will not help.
    static func isTransient(_ status: Int) -> Bool {
        status == 503 || status == 429 || status == 425 || status == 0
    }

    /// Decodes the model's JSON without insisting every value is a string.
    ///
    /// `as? [String: String]` discards the whole reply over a single `null` for
    /// an uncertain field — which is exactly what the prompt invites — or over
    /// a number where a string was expected. Values are coerced instead, and
    /// anything genuinely not scalar is dropped rather than taking the rest of
    /// the document's fields down with it.
    static func decodeFields(from content: String) throws -> [String: String] {
        // Local models often wrap JSON in a ```json fence. Taking the span
        // between the first { and the last } handles that, and prose either
        // side of the object, without parsing the fence syntax itself.
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start < end else {
            throw RescueError.unreadableReply
        }
        let json = String(content[start...end])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RescueError.unreadableReply
        }
        return object.reduce(into: [String: String]()) { result, entry in
            switch entry.value {
            case let text as String: result[entry.key] = text
            case let number as NSNumber: result[entry.key] = number.stringValue
            default: break   // null, array, nested object — no usable value
            }
        }
    }

    /// Where the rescue has got to, so the operator is told the difference
    /// between "loading a 5.78 GB model" and "hung".
    enum Phase: Sendable, Equatable {
        case startingRuntime
        case loadingModel(elapsed: TimeInterval)
        case reading
    }

    private func startIfNeeded(onPhase: (@Sendable (Phase) -> Void)?) async throws {
        try await LocalRuntime.shared.start(endpoint: endpoint, onPhase: onPhase)
    }
}

/// Owns the one llama-server this app may run.
///
/// Every rescue used to construct a fresh rescuer with no shared state, so a
/// second attempt while the first was still loading spawned another server —
/// two concurrent 8B loads on one machine. Serialising through an actor means
/// a rescue during a load waits for the server already coming up.
actor LocalRuntime {
    static let shared = LocalRuntime()

    private var process: Process?

    /// Long enough for a cold load of an 8B model with its projector, which is
    /// minutes on a laptop. The previous 7.5 seconds meant the first rescue an
    /// operator ever attempted always failed, left the server loading in the
    /// background, and then mysteriously worked on the second try.
    private static let loadTimeout: TimeInterval = 15 * 60

    func start(endpoint: URL, onPhase: (@Sendable (LlamaVisionRescuer.Phase) -> Void)?) async throws {
        if await Self.isHealthy(endpoint) { return }

        if process?.isRunning != true {
            onPhase?(.startingRuntime)
            process = try await Self.spawn()
        }

        let began = Date()
        while true {
            do {
                try Task.checkCancellation()
            } catch {
                // Stopping a ten-minute load is a choice the operator is
                // entitled to make, and leaving the server behind would make
                // the next attempt spawn a second one.
                await stop()
                throw error
            }

            if await Self.isHealthy(endpoint) { return }

            let elapsed = Date().timeIntervalSince(began)
            guard elapsed < Self.loadTimeout else {
                await stop()
                throw RescueError.runtimeDidNotStart
            }
            onPhase?(.loadingModel(elapsed: elapsed))
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// SIGTERM to a process mmap-ing five gigabytes is a request, not an
    /// outcome. This waits, then insists.
    func stop() async {
        guard let running = process, running.isRunning else { process = nil; return }
        running.terminate()
        for _ in 0..<20 {
            if !running.isRunning { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if running.isRunning { kill(running.processIdentifier, SIGKILL) }
        process = nil
    }

    private static func isHealthy(_ endpoint: URL) async -> Bool {
        var request = URLRequest(url: endpoint.appending(path: "health"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Where llama-server might be: an explicit override, this app's bundle,
    /// then the machine's PATH.
    ///
    /// PATH matters. Anyone already running local models has this binary
    /// installed — this user has it at ~/.local/bin — and looking only in the
    /// bundle reports "the local AI runtime is missing from this build" about a
    /// runtime that is sitting on the machine.
    static func runtimeExecutable() -> String? {
        if let override = ProcessInfo.processInfo.environment["CREWLISTR_LLAMA_SERVER"],
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        if let bundled = Bundle.main.url(forResource: "llama-server", withExtension: nil)?.path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        let searched = path.split(separator: ":").map(String.init)
            + ["\(NSHomeDirectory())/.local/bin", "/opt/homebrew/bin"]
        return searched
            .map { URL(fileURLWithPath: $0).appending(path: "llama-server").path(percentEncoded: false) }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func spawn() async throws -> Process {
        let manager = try ModelManager()
        guard let model = await manager.resolvedURL(for: ModelManifest.qwen3VL8BQ4.assets[0]),
              let projector = await manager.resolvedURL(for: ModelManifest.qwen3VL8BQ4.assets[1]) else {
            throw RescueError.modelNotInstalled
        }
        guard let executable = Self.runtimeExecutable() else { throw RescueError.runtimeMissing }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            // Resolved, not assumed: the model may live in the HuggingFace
            // cache rather than the app's own directory.
            "--model", model.path(percentEncoded: false),
            "--mmproj", projector.path(percentEncoded: false),
            "--host", "127.0.0.1", "--port", "18081", "--no-webui",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}
