import Foundation

/// How a date is written down, in the two different senses this app has of one.
///
/// A **voyage date** is a day on the operator's own calendar. The picker offers
/// "29 August 2026" and hands back local midnight; the crew list has to say the
/// same day back.
///
/// A **document date** is a day printed on a passport. It arrives from the
/// machine-readable zone as an ISO-8601 string, is stored exactly that way so
/// validation and the CSV keep working, and is shown the way the page itself
/// shows it — `20 OCT 1972`, not `1972-10-20`.
///
/// The two were one function once — `CrewFieldValidator.iso8601String`,
/// formatting in UTC — and that is precisely what printed a departure picked as
/// 29/08 as 28/08: local midnight in Athens is 21:00 the previous day in UTC.
/// A document date genuinely is UTC, because a check digit says so; a voyage
/// date never was.

// MARK: - Voyage dates

enum VoyageDate {

    /// The day this instant falls on in the operator's calendar, in ISO-8601.
    ///
    /// Built from calendar components rather than a `DateFormatter` so there is
    /// no second time zone to get wrong: the time zone decides which day it is,
    /// and nothing after that can shift it.
    ///
    /// The *era* is pinned to Gregorian even so, because `Calendar.current` is
    /// whatever the operator chose in System Settings and that is not always
    /// Gregorian: a Mac set to Thailand numbers this year 2569 and a Japanese
    /// calendar numbers it 8. Either would reach the file name, the CSV's
    /// machine-readable date column and the printed form. The time zone still
    /// comes from the caller's calendar, since that is the half that decides
    /// which day an instant falls on.
    static func iso(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = gregorian(in: calendar).dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The same time zone, counted in Gregorian years. `MRZ` pins its calendar
    /// the same way and for the same reason.
    private static func gregorian(in calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian else { return calendar }
        var pinned = Calendar(identifier: .gregorian)
        pinned.timeZone = calendar.timeZone
        return pinned
    }

    /// `29 AUG 2026` — what a port authority reads on the printed crew list.
    /// The same shape the passport dates beside it are printed in.
    static func printed(_ date: Date, calendar: Calendar = .current) -> String {
        DocumentDate.display(iso(date, calendar: calendar))
    }

    /// Stripped to the start of its day, which is the only part of a voyage
    /// date that means anything. A trip stored at 14:37 crosses a day boundary
    /// the moment anyone reads it from another time zone.
    static func day(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// The dates a new trip starts as: the next charter day, and the end of a
    /// charter's length from it.
    ///
    /// Saturday to Saturday by default, because that is what this trade runs
    /// on — so it is what the pickers show before anyone touches them, and any
    /// other pair of dates is one the operator chose on purpose. A fleet that
    /// runs Wednesdays, or ten-day charters, says so once in Settings.
    static func charterWeek(
        from date: Date = .now,
        startingOn weekday: Int = 7,
        lastingDays days: Int = 7,
        calendar: Calendar = .current
    ) -> (departure: Date, arrival: Date) {
        let departure = nextDay(weekday, onOrAfter: date, calendar: calendar)
        let arrival = calendar.date(byAdding: .day, value: max(days, 0), to: departure) ?? departure
        return (departure, arrival)
    }

    /// The first `weekday` on or after `date`, counted 1 Sunday … 7 Saturday.
    /// Asked on the day itself the answer is that day: the charter being
    /// prepared is the one leaving today, not the one leaving in a week.
    static func nextDay(_ weekday: Int, onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        // Weekday numbering is the same in every calendar identifier and does
        // not move with the locale's first day of the week.
        let wanted = (1...7).contains(weekday) ? weekday : 7
        guard calendar.component(.weekday, from: start) != wanted else { return start }
        let next = calendar.nextDate(after: start,
                                     matching: DateComponents(weekday: wanted),
                                     matchingPolicy: .nextTime,
                                     direction: .forward)
        return next.map { calendar.startOfDay(for: $0) } ?? start
    }
}

// MARK: - Document dates

enum DocumentDate {

    /// The abbreviations passports themselves print. Fixed and English on
    /// purpose: a crew list is read by a port official who may share no
    /// language with the operator's Mac, and `DateFormatter` would hand them
    /// the month in whatever locale this machine happens to be set to.
    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                                 "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// `1972-10-20` → `20 OCT 1972`.
    ///
    /// Anything that is not a valid ISO date is handed back exactly as it came
    /// in. A half-typed or unreadable value has to stay visible so validation
    /// can object to it — reformatting is not the place to hide a bad value.
    static func display(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CrewFieldValidator.isoDate(trimmed) != nil else { return stored }
        let parts = trimmed.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), (1...12).contains(month), let day = Int(parts[2]) else {
            return stored
        }
        return String(format: "%02d %@ %@", day, months[month - 1], String(parts[0]))
    }

    /// `20 OCT 1972` or `1972-10-20` → `1972-10-20`; nil when it is neither.
    ///
    /// Both forms are accepted because the operator types into the same field
    /// the extraction wrote into, and an MRZ read is ISO. Separators are loose
    /// (`21-JUN-2029` and `21 JUN 2029` are the same day) but the year is not:
    /// a two-digit year on a passport is exactly the ambiguity that turns a
    /// birth date into an expiry date.
    static func stored(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if CrewFieldValidator.isoDate(trimmed) != nil { return trimmed }

        let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." || $0 == "/" })
        guard parts.count == 3,
              let day = Int(parts[0]),
              let year = Int(parts[2]), parts[2].count == 4,
              let month = monthNumber(String(parts[1]))
        else { return nil }

        let candidate = String(format: "%04d-%02d-%02d", year, month, day)
        // Round-tripped through the strict parser rather than trusted: it is
        // what rejects 40 OCT and 31 FEB.
        return CrewFieldValidator.isoDate(candidate) != nil ? candidate : nil
    }

    /// Matches on the first three letters, so OCT and OCTOBER are both October.
    ///
    /// Shared with `LlamaVisionRescuer.normalisedDate`, which reads months off
    /// the page the model transcribed. Two copies of this table would be two
    /// answers to "is APR a month", and they would drift.
    static func monthNumber(_ name: String) -> Int? {
        let abbreviation = String(name.uppercased().prefix(3))
        guard abbreviation.count == 3, name.count >= 3 else { return nil }
        return months.firstIndex(of: abbreviation).map { $0 + 1 }
    }
}
