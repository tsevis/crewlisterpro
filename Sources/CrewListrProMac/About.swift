import Foundation

/// What CrewListr Pro is, what it refuses to do, and what it owes.
///
/// Shown once at first launch and reachable afterwards from the window and the
/// application menu. An info screen is easy to skip past, and this one earns
/// its place by carrying the thing that has to be carried: the promise that no
/// document leaves the Mac and that nothing clears itself. First launch is
/// exactly when that is worth reading.
///
/// The text is data with tests on it rather than strings typed into a view, so
/// a claim cannot go missing without a test noticing.
enum About {
    static let title = AppVersion.name
    static let subtitle = "Crew lists prepared without the documents ever leaving this Mac"
    static var version: String { "Version \(AppVersion.short) (\(AppVersion.build))" }

    /// Two paragraphs: what a crew list is, and what this program refuses to do
    /// about it. Neither invents a namesake — the instrument is old enough to
    /// speak for itself.
    static let story = """
    A crew list is one of the oldest instruments in a harbour. Before a yacht clears \
    port, someone writes down who is aboard — the name, the nationality, the number \
    on the passport, the date of birth — and signs for it. The authority does not \
    check the yacht. It checks the list.

    Which is why this program will not fill one in for you. Extraction runs on this \
    Mac, reading the page with Vision and parsing the machine-readable zone against \
    its own ICAO 9303 arithmetic, and it always returns the same verdict: needs \
    review. A checksum agreeing with itself is not a person confirming that the \
    letters on the screen are the letters on the document. Every field carries its \
    own confirmation, editing a value retracts it, and nothing can be exported until \
    an operator has looked at each one beside the image it came from.
    """

    static let credit = "Created by Charis Tsevis, with the help of Claude Code."

    static let links: [(label: String, address: URL)] = [
        ("tsevis.com", URL(string: "https://tsevis.com")!),
        ("github.com/tsevis", URL(string: "https://github.com/tsevis")!),
    ]

    /// The obligations and the sources.
    ///
    /// The privacy paragraph goes last because it is the one an operator came
    /// looking for, and last is where a reader stops.
    static let legal = """
    Storage is SQLCipher (BSD-3-Clause) over SQLite (public domain), built on OpenSSL \
    (Apache-2.0). Document payloads are sealed with AES-GCM through Apple's CryptoKit \
    under a key held in the Keychain as WhenUnlockedThisDeviceOnly. Recognition is \
    Apple Vision and the interface is SwiftUI — both macOS system frameworks.

    The optional local vision model is Qwen3-VL 8B Instruct (Apache-2.0), run through \
    llama.cpp (MIT). No model weights ship with this application: the download is \
    about 5.8 GB, happens only on explicit consent, is checked against a recorded \
    SHA-256 before it is kept, and inference talks to 127.0.0.1 and nowhere else. \
    A document whose machine-readable zone parsed cleanly never reaches the model \
    at all, and anything the model proposes arrives unconfirmed like every other read.

    Your documents are yours. CrewListr Pro never transmits a document, a fragment, \
    an extracted field or a filename anywhere. Deleting a document or a trip erases \
    the encrypted original and every revision from this Mac.
    """

    /// Paragraphs, for a view that lays each one out separately.
    static func paragraphs(of text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Whether to show it

/// Where "has this version been seen" is kept.
///
/// A protocol rather than `UserDefaults` directly, so the rule below can be
/// tested against memory. Testing it against a real suite writes a preferences
/// domain into `~/Library/Preferences`, and `removeSuite(named:)` races
/// `cfprefsd`, which flushes after the test process has already exited — so the
/// tidy-up loses and the machine collects a plist per run.
protocol AboutSeenStore {
    func seenVersion() -> String?
    func recordSeen(_ version: String)
}

extension UserDefaults: AboutSeenStore {
    func seenVersion() -> String? { string(forKey: AboutPresentation.defaultsKey) }
    func recordSeen(_ version: String) { set(version, forKey: AboutPresentation.defaultsKey) }
}

/// First launch is when the promise above is worth reading, so absence means
/// yes. Keyed by version: a new release has something new to say.
enum AboutPresentation {
    static let defaultsKey = "crewlistr.about.seen.version"

    static func wanted(_ store: AboutSeenStore = UserDefaults.standard) -> Bool {
        store.seenVersion() != AppVersion.short
    }

    static func remember(_ store: AboutSeenStore = UserDefaults.standard) {
        store.recordSeen(AppVersion.short)
    }
}
