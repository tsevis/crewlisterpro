import Foundation

/// Deleting a trip's personal data a week after its crew list first went out.
/// See `TripRetention`.
extension CrewStore {

    /// Starts the clock on the first export only: exporting again to fix a
    /// typo must not keep the data longer.
    func markFirstExport(ofTripWith id: UUID, at date: Date = .now) {
        guard var trip = data.trips.first(where: { $0.id == id }), trip.firstExportedAt == nil else { return }
        trip.firstExportedAt = date
        updateTrip(trip)
    }

    /// Deletes every trip past its retention date, exactly as Delete Trip does,
    /// then the snapshots that still hold them. Returns the trips deleted.
    @discardableResult
    func purgeExpiredTrips(now: Date = .now) -> [UUID] {
        let expired = data.trips.filter { TripRetention.isExpired($0, now: now) }.map(\.id)
        for id in expired { deleteTrip(id) }
        forgetInBackups(tripIDs: Set(expired))
        return expired
    }

    /// The same, telling the operator what went. Called on opening the store
    /// and whenever the app comes back to the front.
    func purgeExpiredTripsAndReport(now: Date = .now) {
        guard hasLoaded else { return }
        let count = purgeExpiredTrips(now: now).count
        guard count > 0 else { return }
        errorMessage = String(localized: "\(count) trip(s) deleted with their passports and scans, \(TripRetention.days) days after the crew list was first exported.")
    }
}
