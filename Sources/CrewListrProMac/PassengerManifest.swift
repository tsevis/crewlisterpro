import Foundation

/// The passenger manifest in the port authority's own template
/// (`docs/passengers_manifest_template.xlsx`): one sheet, nine bilingual
/// columns, one row per person aboard.
///
/// Every cell is written as text. The template's instructions sheet asks for
/// exactly that, because Excel turns `2026-07-01` and `08:00` into serial
/// numbers the importer then cannot read.
enum PassengerManifest {
    static let sheetName = "Passengers"

    /// The template's headers, verbatim and in its order. The importer reads
    /// by position; nothing here may be reordered.
    static let headers = [
        "Full Name / Ονοματεπώνυμο",
        "ID/Passport No / Αρ. Ταυτότητας/Διαβατηρίου",
        "Sex (M/F) / Φύλο (Α/Θ)",
        "Nationality / Ιθαγένεια",
        "Date of Birth / Ημ. Γέννησης",
        "Embarkation Date / Ημ. Επιβίβασης",
        "Embarkation Time / Ώρα Επιβίβασης",
        "Embarkation Port / Λιμένας Επιβίβασης",
        "Notes / Σημειώσεις",
    ]

    static let columnWidths: [Double] = [28, 22, 10, 12, 14, 16, 14, 20, 24]

    /// Header row first, then one line per person — the skipper included and
    /// said so in Notes, since everyone aboard is on the manifest.
    static func lines(trip: Trip, rows: [CrewListRow]) -> [[String]] {
        [headers] + rows.map { line(for: $0, trip: trip) }
    }

    static func export(to url: URL, trip: Trip, rows: [CrewListRow]) throws {
        let workbook = XLSXWriter.workbook(sheetName: sheetName, rows: lines(trip: trip, rows: rows),
                                           columnWidths: columnWidths)
        try workbook.write(to: url, options: .atomic)
    }

    private static func line(for row: CrewListRow, trip: Trip) -> [String] {
        [
            row.fullName,
            row.documentNumber,
            row.sex.uppercased(),
            // Written as read when it cannot be resolved, rather than blank: an
            // empty cell hides which person needs fixing.
            ManifestNationality.code(for: row.nationality) ?? row.nationality,
            row.birthDate,
            VoyageDate.iso(trip.departureDate),
            trip.embarkationTime,
            trip.embarkationPort,
            notes(for: row),
        ]
    }

    private static func notes(for row: CrewListRow) -> String {
        let own = row.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let marks = (row.role == .skipper ? ["Skipper"] : []) + (own.isEmpty ? [] : [own])
        return marks.joined(separator: " · ")
    }
}
