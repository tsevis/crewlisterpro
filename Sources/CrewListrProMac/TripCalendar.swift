import Foundation

/// The charters leaving on one day.
///
/// A charter base plans by the day, not by the vessel: four boats going out on
/// the same Saturday are one morning's work, and the same boat going out in
/// September and again in October is two unrelated jobs. The command line's
/// strip used to say the second thing and never the first — one chip per trip,
/// each labelled with a yacht — so a Saturday with four departures read as four
/// unrelated charters and gave the operator no date to work to at all.
struct TripDay: Identifiable, Hashable {
    /// The start of the day these trips depart on, in the operator's calendar.
    let date: Date

    /// The charters leaving that day, in the order they were handed over.
    let trips: [Trip]

    var id: Date { date }

    /// A day nothing is live on. Its chip reads as put away, exactly as an
    /// archived trip's did — but it stays in the row, because a trip nothing
    /// can reach is a trip whose passport scans can be neither restored nor
    /// erased.
    var isArchived: Bool { trips.allSatisfy(\.isArchived) }
}

/// Gathers trips into the days they sail on.
///
/// Deliberately a free function over a list rather than a property of the
/// store: it is the whole of the rule, it can be tested without a database,
/// and `CrewStore.tripDays` is one line on top of it.
enum TripCalendar {

    /// The days these trips depart on, earliest first.
    ///
    /// Departures are stripped to the start of their day first. A trip stored
    /// at 14:37 and another at 09:02 on the same morning are one charter day;
    /// grouping on the raw instants would put a second chip in the strip for
    /// the same Saturday and neither would say why.
    static func days(of trips: [Trip], calendar: Calendar = .current) -> [TripDay] {
        let grouped = Dictionary(grouping: trips) { VoyageDate.day($0.departureDate, calendar: calendar) }
        return grouped
            .sorted { $0.key < $1.key }
            .map { TripDay(date: $0.key, trips: $0.value) }
    }
}
