import Foundation
#if canImport(UIKit)
import UIKit
#endif

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

    /// What the operator calls the thing in front of them.
    ///
    /// The claim this screen exists to make is that the documents do not leave
    /// the device, and a claim about "this Mac" read on an iPhone is a claim
    /// about somebody else's computer. One noun, used everywhere the promise is
    /// made — here, in the settings, and on every confirmation that says what
    /// deleting erases — so the builds say the same true thing about whatever
    /// the operator is actually holding.
    #if os(macOS)
    static let deviceName = "this Mac"
    #elseif canImport(UIKit)
    static var deviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this iPhone"
    }
    #else
    static let deviceName = "this device"
    #endif

    static var subtitle: String { "Crew lists prepared without the documents ever leaving \(deviceName)" }
    static var version: String { "Version \(AppVersion.short) (\(AppVersion.build))" }

    /// Two paragraphs: what a crew list is, and what this program refuses to do
    /// about it. Neither invents a namesake — the instrument is old enough to
    /// speak for itself.
    static var story: String { """
    A crew list is one of the oldest instruments in a harbour. Before a yacht clears \
    port, someone writes down who is aboard — the name, the nationality, the number \
    on the passport, the date of birth — and signs for it. The authority does not \
    check the yacht. It checks the list.

    Which is why this program will not fill one in for you. Extraction runs on \
    \(deviceName), reading the page with Vision and parsing the machine-readable zone against \
    its own ICAO 9303 arithmetic, and it always returns the same verdict: needs \
    review. A checksum agreeing with itself is not a person confirming that the \
    letters on the screen are the letters on the document. Every field carries its \
    own confirmation, editing a value retracts it, and nothing can be exported until \
    an operator has looked at each one beside the image it came from.
    """ }

    /// Two credits, because they are two different claims: who built it, and
    /// who it was built for. Each carries its own mark in the footer.
    static let credit = "Developed by Tsevis Studio"
    static let partnerCredit = "Union Yachting for the Greek charter community"

    /// The two destinations behind the footer's marks.
    static let links: [(label: String, address: URL)] = [
        ("tsevis.com", Brand.makerSite),
        ("unionyachting.com", Brand.unionSite),
    ]

    /// The obligations and the sources.
    ///
    /// The privacy paragraph goes last because it is the one an operator came
    /// looking for, and last is where a reader stops.
    /// Two storage paragraphs, because the two builds genuinely store
    /// differently and a shared sentence would have to be false on one of them.
    /// SQLCipher is a Homebrew library and OpenSSL is what it is built on;
    /// neither is on an iPhone, and claiming them there would be attributing
    /// software that is not in the binary. What an iPhone has instead — Data
    /// Protection, the whole container encrypted under the passcode — is
    /// stronger than what it replaces, and is named here rather than glossed.
    #if os(macOS)
    private static let storage = """
    Storage is SQLCipher (BSD-3-Clause) over SQLite (public domain), built on OpenSSL \
    (Apache-2.0). Document payloads are sealed with AES-GCM through Apple's CryptoKit \
    under a key held beside the database. Recognition is Apple Vision and the \
    interface is SwiftUI — both macOS system frameworks.
    """

    private static let localModel = """
    The optional local vision model is Qwen3-VL 8B Instruct (Apache-2.0), run through \
    llama.cpp (MIT). No model weights ship with this application: the download is \
    about 5.8 GB, happens only on explicit consent, is checked against a recorded \
    SHA-256 before it is kept, and inference talks to 127.0.0.1 and nowhere else. \
    A document whose machine-readable zone parsed cleanly never reaches the model \
    at all, and anything the model proposes arrives unconfirmed like every other read.
    """
    #else
    private static let storage = """
    Storage is SQLite (public domain) inside the app's own container, which iOS \
    encrypts under a key the passcode releases. Document payloads are sealed on top \
    of that with AES-GCM through Apple's CryptoKit, under a key held in the Keychain \
    as WhenUnlockedThisDeviceOnly. Recognition is Apple Vision, page scanning is \
    VisionKit and the interface is SwiftUI — all iOS system frameworks.
    """

    private static let localModel = """
    There is no local vision model on iPhone. The Mac build offers an optional \
    5.8 GB Qwen3-VL model for documents whose machine-readable zone cannot be read; \
    a phone has neither the room for it nor a way to run it, so a document that \
    cannot be read is held back asking for the field to be typed. Nothing is \
    guessed in its place.
    """
    #endif

    static var legal: String { """
    \(storage)

    \(localModel)

    CrewListr Pro is MIT licensed. Developed by Tsevis Studio for Union Yachting \
    and the whole charter and sailing community of Greece.

    Your documents are yours. CrewListr Pro never transmits a document, a fragment, \
    an extracted field or a filename anywhere. Deleting a document or a trip erases \
    the encrypted original and every revision from \(deviceName).
    """ }

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
