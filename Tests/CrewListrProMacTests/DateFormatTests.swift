import Foundation
import XCTest
@testable import CrewListrProMac

/// The two senses this app has of a date, and the bug that came of conflating
/// them: a voyage date is a day on the operator's own calendar, a document date
/// is a day printed on a passport.
final class DateFormatTests: XCTestCase {

    // MARK: - Voyage dates

    /// The reported bug. The picker hands back local midnight; formatting that
    /// in UTC prints the previous day for every operator east of Greenwich.
    func testAPickedDayIsWrittenDownAsThatDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try! XCTUnwrap(TimeZone(identifier: "Europe/Athens"))
        let picked = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!

        XCTAssertEqual(VoyageDate.iso(picked, calendar: calendar), "2026-08-29")
    }

    /// The operator's *calendar* is a system setting too, and it is not always
    /// Gregorian. A Mac set to Thailand writes 2569 for 2026 unless the
    /// formatter pins the calendar — which would put a Buddhist-era year in the
    /// file name, in the CSV's machine-readable date column and on the printed
    /// form.
    func testAPickedDayIsWrittenDownInTheGregorianEraWhateverTheSystemCalendar() {
        for identifier in [Calendar.Identifier.buddhist, .japanese, .hebrew, .islamicUmmAlQura] {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = TimeZone(identifier: "Europe/Athens")!
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            let picked = gregorian.date(from: DateComponents(year: 2026, month: 8, day: 29))!

            XCTAssertEqual(VoyageDate.iso(picked, calendar: calendar), "2026-08-29",
                           "\(identifier) leaked into the written date")
            XCTAssertEqual(VoyageDate.printed(picked, calendar: calendar), "29 AUG 2026")
        }
    }

    /// And west of it, where UTC formatting happened to be right and a naive
    /// "add a day" fix would break it.
    func testAPickedDayIsWrittenDownAsThatDayWestOfGreenwich() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try! XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let picked = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!

        XCTAssertEqual(VoyageDate.iso(picked, calendar: calendar), "2026-08-29")
    }

    func testAVoyageDateIsPrintedWithAThreeLetterMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try! XCTUnwrap(TimeZone(identifier: "Europe/Athens"))
        let picked = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!

        XCTAssertEqual(VoyageDate.printed(picked, calendar: calendar), "29 AUG 2026")
    }

    // MARK: - The charter week

    func testANewTripStartsOnTheNextSaturday() {
        let calendar = Calendar(identifier: .gregorian)
        // Wednesday 2 September 2026.
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
        let week = VoyageDate.charterWeek(from: wednesday, calendar: calendar)

        XCTAssertEqual(calendar.component(.weekday, from: week.departure), 7, "departure is not a Saturday")
        XCTAssertEqual(VoyageDate.iso(week.departure, calendar: calendar), "2026-09-05")
    }

    func testACharterWeekReturnsTheFollowingSaturday() {
        let calendar = Calendar(identifier: .gregorian)
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
        let week = VoyageDate.charterWeek(from: wednesday, calendar: calendar)

        XCTAssertEqual(calendar.component(.weekday, from: week.arrival), 7, "return is not a Saturday")
        XCTAssertEqual(VoyageDate.iso(week.arrival, calendar: calendar), "2026-09-12")
    }

    /// Asked on a Saturday, the charter leaving that day is the one being
    /// prepared — not the one a week later.
    func testACharterWeekAskedOnASaturdayLeavesThatSaturday() {
        let calendar = Calendar(identifier: .gregorian)
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let week = VoyageDate.charterWeek(from: saturday, calendar: calendar)

        XCTAssertEqual(VoyageDate.iso(week.departure, calendar: calendar), "2026-09-05")
        XCTAssertEqual(VoyageDate.iso(week.arrival, calendar: calendar), "2026-09-12")
    }

    func testACharterWeekIgnoresTheTimeOfDayItWasAskedAt() {
        let calendar = Calendar(identifier: .gregorian)
        let lateWednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 23, minute: 47))!
        let week = VoyageDate.charterWeek(from: lateWednesday, calendar: calendar)

        XCTAssertEqual(week.departure, calendar.startOfDay(for: week.departure))
    }

    // MARK: - Document dates

    func testAStoredDateIsShownWithAThreeLetterMonth() {
        XCTAssertEqual(DocumentDate.display("1972-10-20"), "20 OCT 1972")
        XCTAssertEqual(DocumentDate.display("2029-06-21"), "21 JUN 2029")
        XCTAssertEqual(DocumentDate.display("2010-09-03"), "03 SEP 2010")
    }

    /// A half-typed or unreadable value must stay visible exactly as it is, so
    /// validation can object to it rather than the display quietly hiding it.
    func testAnUnreadableStoredDateIsShownUntouched() {
        for value in ["", "1972-13-40", "20/10/1972", "not a date"] {
            XCTAssertEqual(DocumentDate.display(value), value)
        }
    }

    func testATypedThreeLetterDateIsStoredAsISO() {
        XCTAssertEqual(DocumentDate.stored("20 OCT 1972"), "1972-10-20")
        XCTAssertEqual(DocumentDate.stored("3 sep 2010"), "2010-09-03")
        XCTAssertEqual(DocumentDate.stored("21-JUN-2029"), "2029-06-21")
    }

    func testAnISODateIsStoredUnchanged() {
        XCTAssertEqual(DocumentDate.stored("1972-10-20"), "1972-10-20")
    }

    func testAnUnparseableTypedDateIsNotStored() {
        for value in ["20 XXX 1972", "1972-13-40", "20 OCT", "", "40 OCT 1972"] {
            XCTAssertNil(DocumentDate.stored(value), "\(value) should not parse")
        }
    }

    func testDisplayAndStoredRoundTrip() {
        for iso in ["1900-01-01", "1984-12-16", "2027-07-22", "2099-12-31"] {
            XCTAssertEqual(DocumentDate.stored(DocumentDate.display(iso)), iso)
        }
    }
}
