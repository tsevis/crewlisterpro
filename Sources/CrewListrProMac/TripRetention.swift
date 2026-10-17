import Foundation

/// How long a trip's personal data is kept: one week from the first time its
/// crew list was exported. Passports, scans, people and the trip itself then
/// leave the database and every snapshot holding them; the yacht and the Crew
/// Library stay. A trip never exported is never deleted by this.
enum TripRetention {
    static let days = 7

    /// When this trip is deleted, or nil while it has never been exported.
    static func deletionDate(for trip: Trip, calendar: Calendar = .current) -> Date? {
        trip.firstExportedAt.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
    }

    static func isExpired(_ trip: Trip, now: Date = .now) -> Bool {
        deletionDate(for: trip).map { $0 <= now } ?? false
    }
}
