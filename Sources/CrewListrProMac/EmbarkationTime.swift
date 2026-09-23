import Foundation

/// The time passengers board, as the manifest importer wants it: `HH:MM`.
enum EmbarkationTime {
    /// `8:00`, `0800` and `08.00` all become `08:00`; empty stays empty, since
    /// a trip may not know its time yet. Nil means the input is not a time and
    /// must not be saved.
    static func normalised(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let (hour, minute) = parts(of: trimmed), (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func parts(of value: String) -> (Int, Int)? {
        let pieces = value.split(whereSeparator: { ":.".contains($0) })
        if pieces.count == 2, (1...2).contains(pieces[0].count), pieces[1].count == 2,
           let hour = Int(pieces[0]), let minute = Int(pieces[1]) {
            return (hour, minute)
        }
        // Four digits with no separator, as typed on a phone keypad.
        if pieces.count == 1, value.count == 4, value.allSatisfy(\.isASCII),
           let hour = Int(value.prefix(2)), let minute = Int(value.suffix(2)) {
            return (hour, minute)
        }
        return nil
    }
}
