import Foundation

/// Single source of truth for the product identity that ships in the app bundle,
/// the DMG name and the About panel. `scripts/release.sh` reads these values so
/// the Info.plist can never drift from the binary.
enum AppVersion {
    /// Marketing version — CFBundleShortVersionString. Semantic versioning.
    static let short = "0.1.9"

    /// Build number — CFBundleVersion. Monotonic, bumped by CI on every build.
    static let build = "1"

    /// Reverse-DNS bundle identifier, matched by the Keychain service name.
    static let bundleIdentifier = "com.tsevis.crewlisterpro"

    static let name = "CrewListr Pro"

    /// One-line App Store style description.
    static let tagline = "Offline crew-list preparation for charter yachts."

    /// Long description used in the DMG, the About panel and the README.
    static let description = """
    CrewListr Pro turns photographed or scanned identity documents into the crew \
    list a port authority expects. Extraction runs entirely on this Mac using \
    Vision OCR and ICAO 9303 machine-readable-zone parsing, with an optional \
    local vision model for documents whose MRZ cannot be read. Documents and \
    extracted data never leave the machine: application state lives in a \
    SQLCipher database and original files are sealed with AES-GCM under a \
    Keychain-held key. Nothing can be exported until an operator has reviewed \
    the extracted fields.
    """

    /// Discovery keywords. Mirrored into the README topic list and, for a
    /// distributed build, into the bundle's LSItemContentTypes documentation.
    static let tags = [
        "crew-list", "yacht-charter", "maritime", "port-clearance",
        "passport", "mrz", "icao-9303", "ocr", "vision",
        "macos", "swiftui", "apple-silicon",
        "offline-first", "on-device-ai", "sqlcipher", "aes-gcm", "privacy",
    ]

    /// Apple's UTI for the Finder category shown in the Info window.
    static let applicationCategory = "public.app-category.business"

    /// Base name of the icon in the bundle's Resources, without the extension.
    static let iconFile = "AppIcon"

    static let copyright = "© 2026 Charis Tsevis. MIT licensed."

    /// Human-readable build stamp, e.g. "CrewListr Pro 1.0.0 (1)".
    static var displayVersion: String { "\(name) \(short) (\(build))" }
}
