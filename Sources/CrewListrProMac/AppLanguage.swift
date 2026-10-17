import Foundation

/// The interface language, chosen in Settings or left to the system.
///
/// Stored as the per-app `AppleLanguages` override, the same key macOS and iOS
/// write when a language is picked for one app in System Settings, so the two
/// never disagree. Read once at launch: a change applies the next time the app
/// opens.
///
/// Only the interface. The crew list, the PDF and the passenger manifest keep
/// the port authority's own bilingual English/Greek wording whatever is chosen.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = ""
    case german = "de"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case greek = "el"
    case ukrainian = "uk"

    var id: String { rawValue }

    static let defaultsKey = "AppleLanguages"

    /// Each language in its own name, which is how a person finds theirs in a
    /// list written in a language they may not read.
    var nativeName: String {
        switch self {
        case .system: String(localized: "System language")
        case .german: "Deutsch"
        case .english: "English"
        case .spanish: "Español"
        case .french: "Français"
        case .italian: "Italiano"
        case .greek: "Ελληνικά"
        case .ukrainian: "Українська"
        }
    }

    /// What this app overrides, read from its own domain only: the plain
    /// lookup falls through to the system-wide list and would report the
    /// system language as a choice.
    static func current(in defaults: UserDefaults = .standard,
                        domain: String? = Bundle.main.bundleIdentifier) -> AppLanguage {
        guard let domain,
              let codes = defaults.persistentDomain(forName: domain)?[defaultsKey] as? [String],
              let first = codes.first else { return .system }
        return AppLanguage.allCases.first { $0 != .system && first.hasPrefix($0.rawValue) } ?? .system
    }

    func apply(to defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set([rawValue], forKey: Self.defaultsKey)
        }
    }
}
