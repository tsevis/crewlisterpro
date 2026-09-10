import Foundation
import XCTest
@testable import CrewListrProMac

/// Trips gathered by the day they sail.
///
/// The strip along the command line used to be one chip per trip, labelled
/// with a yacht. That is the wrong axis for this trade: an operator handling
/// four charters out on the same Saturday was reading four chips that all said
/// a boat name and none of which said the date they were actually working to,
/// and two boats chartered a month apart sat side by side as though they were
/// the same job. The day is what a charter base plans around, so the day is
/// what the strip is made of — and the boats for a day hang off it.
@MainActor
final class TripCalendarTests: XCTestCase {

    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    private func makeStore() throws -> CrewStore {
        CrewStore(secureStore: try TemporaryStore.make(in: &homes))
    }

    private func day(_ iso: String) -> Date {
        var parts = DateComponents()
        let pieces = iso.split(separator: "-").compactMap { Int($0) }
        parts.year = pieces[0]; parts.month = pieces[1]; parts.day = pieces[2]
        return Calendar.current.date(from: parts) ?? .now
    }

    private func trip(_ iso: String, boat: UUID = UUID()) -> Trip {
        Trip(boatID: boat, departureDate: day(iso), returnDate: day(iso))
    }

    // MARK: - Grouping

    func testTripsLeavingOnTheSameDayAreOneDay() {
        let days = TripCalendar.days(of: [trip("2026-09-12"), trip("2026-09-12"), trip("2026-09-19")])

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.first?.trips.count, 2)
        XCTAssertEqual(days.last?.trips.count, 1)
    }

    func testTheDaysRunInDateOrderWhateverOrderTheTripsWereMadeIn() {
        let days = TripCalendar.days(of: [trip("2026-09-26"), trip("2026-09-05"), trip("2026-09-12")])

        XCTAssertEqual(days.map { VoyageDate.iso($0.date) },
                       ["2026-09-05", "2026-09-12", "2026-09-26"])
    }

    /// A departure is a day, not an instant. Two trips stored at different
    /// hours of the same morning are one charter day, or the strip grows a
    /// second chip for the same Saturday.
    func testTheTimeOfDayDoesNotSplitADay() {
        let morning = Trip(boatID: UUID(), departureDate: day("2026-09-12").addingTimeInterval(3600),
                           returnDate: day("2026-09-19"))
        let evening = Trip(boatID: UUID(), departureDate: day("2026-09-12").addingTimeInterval(72_000),
                           returnDate: day("2026-09-19"))

        XCTAssertEqual(TripCalendar.days(of: [morning, evening]).count, 1)
    }

    func testNoTripsMeansNoDays() {
        XCTAssertTrue(TripCalendar.days(of: []).isEmpty)
    }

    /// An archived charter keeps its place in the calendar. A day nothing can
    /// reach is a day whose passport scans can be neither restored nor erased.
    func testAnArchivedTripStillHasItsDay() throws {
        var put = trip("2026-09-12")
        put.status = .archived

        let days = TripCalendar.days(of: [put])

        XCTAssertEqual(days.count, 1)
        XCTAssertTrue(try XCTUnwrap(days.first).isArchived, "a day of nothing but archived trips reads as archived")
    }

    func testADayWithOneLiveTripIsNotArchived() throws {
        var put = trip("2026-09-12")
        put.status = .archived

        let days = TripCalendar.days(of: [put, trip("2026-09-12")])

        XCTAssertFalse(try XCTUnwrap(days.first).isArchived)
    }

    // MARK: - Through the store

    func testTheStoreGroupsItsOwnTrips() throws {
        let store = try makeStore()
        let elpida = store.addBoat(named: "S/Y ELPIDA")
        let aurora = store.addBoat(named: "M/Y AURORA")
        let first = store.createTrip(boatID: elpida)
        let second = store.createTrip(boatID: aurora)
        store.setDepartureDate(day("2026-09-12"), onTripWith: first)
        store.setDepartureDate(day("2026-09-12"), onTripWith: second)

        XCTAssertEqual(store.tripDays.count, 1)
        XCTAssertEqual(store.tripDays.first?.trips.count, 2)
    }

    /// The label on a chip. A row of them reads as a calendar, so it leads with
    /// the weekday an operator plans by.
    func testADayIsLabelledForAChip() {
        XCTAssertEqual(VoyageDate.short(day("2026-09-12")), "SAT 12 SEP")
    }
}
