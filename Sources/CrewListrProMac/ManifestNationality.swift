import Foundation

/// Turns a nationality as the app holds it — `GREEK`, `GRC`, `Ελληνική`, the
/// MRZ's `D` — into the code the passenger-manifest importer accepts.
///
/// Returns nil rather than a best guess. A wrong code on a government upload
/// is a person declared the wrong citizenship; an unresolved one is a cell the
/// importer rejects and the operator fixes.
enum ManifestNationality {
    static func code(for value: String) -> String? {
        let key = folded(value)
        guard !key.isEmpty else { return nil }
        return lookup[key]
    }

    /// Spellings the template does not list but documents and the MRZ use.
    ///
    /// MRZ codes from ICAO 9303: Germany is `D`, the British variants are
    /// `GBD`/`GBN`/`GBO`/`GBP`/`GBS`, and `XXA`–`XXC` are the stateless and
    /// refugee codes the template folds into its single `XXX`.
    private static let aliases: [String: String] = [
        "D": "DEU", "DEUTSCH": "DEU", "DEUTSCHE": "DEU",
        "GBD": "GBR", "GBN": "GBR", "GBO": "GBR", "GBP": "GBR", "GBS": "GBR", "BRITISH CITIZEN": "GBR",
        "HELLENIC": "GRC", "ELLINIKI": "GRC",
        "PSE": "TPO", "RKS": "XKX", "KOSOVAR": "XKX",
        "XXA": "XXX", "XXB": "XXX", "XXC": "XXX",
        "ITALIANA": "ITA", "FRANCAISE": "FRA", "ESPANOLA": "ESP", "NEDERLANDSE": "NLD",
        "UNITED STATES OF AMERICA": "USA",
    ]

    private static let lookup: [String: String] = {
        var entries: [String: String] = [:]
        for entry in table {
            entries[folded(entry.code)] = entry.code
            entries[folded(entry.english)] = entry.code
            entries[folded(entry.greek)] = entry.code
        }
        return entries.merging(aliases) { listed, _ in listed }
    }()

    /// Upper case, no accents, single spaces: `Ελληνική`, `ΕΛΛΗΝΙΚΗ` and
    /// `ελληνικη` are one word to an operator and must be one key here.
    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
