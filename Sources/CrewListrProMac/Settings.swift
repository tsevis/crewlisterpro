import Foundation

/// The defaults an operator sets once instead of re-deciding on every charter.
///
/// Kept in the encrypted store beside the trips rather than in `UserDefaults`,
/// for two reasons: it travels with the snapshots, so restoring an earlier
/// version restores the settings that produced it; and the store is already the
/// single writer for everything that describes this operator's work, which is
/// what makes "one bad write cannot outrun a good one" true.
///
/// **Nothing here can weaken the review gate.** There is deliberately no
/// setting to auto-confirm a field, to trust a clean check digit, or to export
/// an unreviewed document. Every value on a crew list is confirmed by a person
/// against the image it came from, and a preference that turned that off would
/// be a preference for a crew list nobody checked.
struct AppSettings: Codable, Hashable, Sendable {

    // MARK: - New trips

    /// The day a charter starts, 1–7 as Foundation counts them: 1 Sunday …
    /// 7 Saturday. Saturday because that is what this trade runs on.
    var charterStartWeekday: Int = 7

    /// How long a new charter runs. A week, unless this fleet does otherwise.
    var charterLengthDays: Int = 7

    /// The yacht a new trip is for when none is named. Cleared automatically if
    /// that yacht is retired or deleted, so it can never point at a boat the
    /// picker no longer offers.
    var defaultBoatID: UUID?

    // MARK: - New yachts

    /// Filled into a new fleet entry. Most operators' whole fleet flies one flag
    /// out of one port, and typing it per yacht is typing it every time.
    var defaultFlag: String = ""
    var defaultRegistrationPort: String = ""

    // MARK: - Export

    /// The first part of the exported file name, before the yacht and the
    /// departure date. Some ports want the operator's own word for it.
    var fileNamePrefix: String = AppSettings.defaultFileNamePrefix

    var writesCSV: Bool = true
    var writesPDF: Bool = true

    /// Where the export goes. Empty means ask every time, which stays the
    /// default: writing identity documents somewhere by habit is exactly the
    /// kind of thing an operator should be choosing deliberately.
    var exportFolderPath: String = ""

    /// Show the written files in the Finder afterwards.
    var revealsAfterExport: Bool = true

    // MARK: - Storage

    /// How many earlier versions of the database to keep.
    var versionsKept: Int = AppSettings.defaultVersionsKept

    // MARK: - Bounds

    static let defaultFileNamePrefix = "crew-list"
    static let defaultVersionsKept = 30
    static let longestCharterDays = 90
    static let fewestVersionsKept = 2
    static let mostVersionsKept = 200

    /// A copy with every value inside the range that produces a usable crew
    /// list.
    ///
    /// Applied on the way into the store rather than trusted at the point of
    /// use, so nothing downstream has to defend itself: a charter of -3 days
    /// or a file name of "../../etc/passwd" cannot be held, not merely cannot
    /// be exported.
    func normalised() -> AppSettings {
        var copy = self
        copy.charterStartWeekday = (1...7).contains(charterStartWeekday) ? charterStartWeekday : 7
        copy.charterLengthDays = min(max(charterLengthDays, 1), Self.longestCharterDays)
        copy.versionsKept = min(max(versionsKept, Self.fewestVersionsKept), Self.mostVersionsKept)
        copy.fileNamePrefix = Self.safePrefix(fileNamePrefix)
        copy.defaultFlag = defaultFlag.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        copy.defaultRegistrationPort = defaultRegistrationPort.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Export is a button that writes files. Both off would make it a button
        // that does nothing and says it succeeded; the printed form is the one
        // a port authority is actually handed, so that is the one that stays.
        if !writesCSV, !writesPDF { copy.writesPDF = true }
        return copy
    }

    /// Made safe by the exporter's own rule, so there is one answer to what may
    /// appear in a file name this app writes. A prefix that survives as nothing
    /// falls back rather than naming a file after its extension alone.
    private static func safePrefix(_ value: String) -> String {
        let squeezed = ExportService.fileSafe(value)
        return squeezed.isEmpty ? defaultFileNamePrefix : squeezed
    }

    /// What an export will write, in as few words as a button can carry.
    var exportFilesDescription: String {
        switch (writesCSV, writesPDF) {
        case (true, true): "CSV and PDF"
        case (true, false): "CSV"
        default: "PDF"
        }
    }

    /// The same fact in a sentence, for a help string or a panel's message.
    var exportDescription: String {
        switch (writesCSV, writesPDF) {
        case (true, true): "the crew list CSV and PDF"
        case (true, false): "the crew list CSV"
        default: "the crew list PDF"
        }
    }

    /// The name of a weekday, for the picker and for saying what a new trip
    /// will do. English and fixed, matching `DocumentDate`'s months: this is
    /// the same operator reading both.
    static func weekdayName(_ weekday: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard (1...7).contains(weekday) else { return names[6] }
        return names[weekday - 1]
    }
}

extension AppSettings {
    /// Decoded by hand, like every other persisted type here: a key absent from
    /// an older payload must use the property's default rather than throw
    /// `keyNotFound` and take the whole store with it.
    ///
    /// The result is normalised on the way out, so a hand-edited or
    /// half-written payload cannot put an out-of-range value into the app.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decoded = AppSettings()
        decoded.charterStartWeekday = (try? container.decode(Int.self, forKey: .charterStartWeekday)) ?? decoded.charterStartWeekday
        decoded.charterLengthDays = (try? container.decode(Int.self, forKey: .charterLengthDays)) ?? decoded.charterLengthDays
        decoded.defaultBoatID = try? container.decodeIfPresent(UUID.self, forKey: .defaultBoatID)
        decoded.defaultFlag = (try? container.decode(String.self, forKey: .defaultFlag)) ?? ""
        decoded.defaultRegistrationPort = (try? container.decode(String.self, forKey: .defaultRegistrationPort)) ?? ""
        decoded.fileNamePrefix = (try? container.decode(String.self, forKey: .fileNamePrefix)) ?? Self.defaultFileNamePrefix
        decoded.writesCSV = (try? container.decode(Bool.self, forKey: .writesCSV)) ?? true
        decoded.writesPDF = (try? container.decode(Bool.self, forKey: .writesPDF)) ?? true
        decoded.exportFolderPath = (try? container.decode(String.self, forKey: .exportFolderPath)) ?? ""
        decoded.revealsAfterExport = (try? container.decode(Bool.self, forKey: .revealsAfterExport)) ?? true
        decoded.versionsKept = (try? container.decode(Int.self, forKey: .versionsKept)) ?? Self.defaultVersionsKept
        self = decoded.normalised()
    }
}
