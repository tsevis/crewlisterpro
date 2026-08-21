import XCTest
@testable import CrewListrProMac

/// Tests for the ICAO 9303 TD3 machine-readable zone parser.
final class MRZTests: XCTestCase {

    /// 2026-08-20 — fixed so two-digit year resolution is reproducible.
    private let today = Date(timeIntervalSince1970: 1_787_184_000)

    // MARK: - Check digits

    func testChecksumMatchesICAOSpecimen() {
        XCTAssertEqual(MRZ.checksum("L898902C3"), 6)
        XCTAssertEqual(MRZ.checksum("740812"), 2)
        XCTAssertEqual(MRZ.checksum("120415"), 9)
    }

    func testChecksumTreatsFillerAsZero() {
        XCTAssertEqual(MRZ.checksum("Z2468013<"), 7)
        XCTAssertEqual(MRZ.checksum("V2468013<"), 9)
        XCTAssertEqual(MRZ.checksum("<<<<<<<<<"), 0)
    }

    func testChecksumOfEmptyStringIsZero() {
        XCTAssertEqual(MRZ.checksum(""), 0)
    }

    // MARK: - Happy path

    func testParsesEveryValidSpecimen() {
        for specimen in MRZFixtures.all {
            let result = MRZ.parse(MRZFixtures.text(specimen))
            XCTAssertNotNil(result, "\(specimen.label) did not parse")
            XCTAssertEqual(result?["document_number"], specimen.expectedNumber, specimen.label)
            XCTAssertEqual(result?["full_name"], specimen.expectedName, specimen.label)
            XCTAssertEqual(result?["birth_date"], specimen.expectedBirth, specimen.label)
            XCTAssertEqual(result?["sex"], specimen.expectedSex, specimen.label)
            XCTAssertEqual(result?["document_type"], "passport", specimen.label)
        }
    }

    func testMapsKnownNationalityCodes() {
        // The issuer code sits at 10..12 and is covered by no check digit the
        // parser verifies, so it can be swapped without disturbing the fixture.
        var characters = Array(MRZFixtures.adult.line2)
        characters.replaceSubrange(10...12, with: "UKR")
        let line2 = String(characters)
        XCTAssertEqual(MRZ.parse("\(MRZFixtures.adult.line1)\n\(line2)")?["nationality"], "UKRAINIAN")
    }

    func testKeepsUnknownNationalityCodeVerbatim() {
        XCTAssertEqual(MRZ.parse(MRZFixtures.text(MRZFixtures.icaoSpecimen))?["nationality"], "UTO")
    }

    func testIgnoresSurroundingOCRNoise() {
        let noisy = """
        ПАСПОРТ
        PASSPORT
        \(MRZFixtures.adult.line1)
        \(MRZFixtures.adult.line2)
        SHOT ON MI 8 LITE
        """
        XCTAssertEqual(MRZ.parse(noisy)?["document_number"], MRZFixtures.adult.expectedNumber)
        XCTAssertEqual(MRZ.parse(noisy)?["full_name"], MRZFixtures.adult.expectedName)
    }

    // MARK: - Two-digit year resolution

    func testAnExpiryInTheThirtiesResolvesForward() {
        XCTAssertEqual(MRZ.date("350703", kind: .expiry, today: today), "2035-07-03")
        XCTAssertEqual(MRZ.date("310930", kind: .expiry, today: today), "2031-09-30")
    }

    func testAnExpiryInsideTheCurrentDecadeIsUnchanged() {
        XCTAssertEqual(MRZ.date("290528", kind: .expiry, today: today), "2029-05-28")
        XCTAssertEqual(MRZ.date("270722", kind: .expiry, today: today), "2027-07-22")
    }

    func testARecentlyExpiredDocumentStaysInThePast() {
        XCTAssertEqual(MRZ.date("200101", kind: .expiry, today: today), "2020-01-01")
    }

    /// A passport that lapsed years ago is an ordinary thing to be handed. It
    /// must read as expired, not be dragged a century forward to look valid.
    func testALongExpiredDocumentStaysInThePast() {
        XCTAssertEqual(MRZ.date("120415", kind: .expiry, today: today), "2012-04-15")
        XCTAssertEqual(MRZ.date("990101", kind: .expiry, today: today), "1999-01-01")
    }

    func testNoExpiryResolvesFurtherAheadThanAPassportCanBeValid() {
        for yy in 0...99 {
            let value = String(format: "%02d0101", yy)
            let resolved = MRZ.date(value, kind: .expiry, today: today).flatMap { Int($0.prefix(4)) }
            XCTAssertNotNil(resolved, value)
            XCTAssertLessThanOrEqual(resolved ?? 0, 2026 + MRZ.maximumValidityYears, "\(value) resolved too far ahead")
        }
    }

    func testABirthDateIsNeverResolvedIntoTheFuture() {
        XCTAssertEqual(MRZ.date("841216", kind: .birth, today: today), "1984-12-16")
        XCTAssertEqual(MRZ.date("130309", kind: .birth, today: today), "2013-03-09")
        // 2028 has not happened yet, so "28" must mean 1928.
        XCTAssertEqual(MRZ.date("280101", kind: .birth, today: today), "1928-01-01")
    }

    /// A passport scanned in January whose MRZ birth year equals the current
    /// year must not resolve to a birthday still ahead of the scan date.
    func testABirthDateLaterThisYearPivotsBackACentury() {
        let january = Date(timeIntervalSince1970: 1_768_435_200)  // 2026-01-15
        XCTAssertEqual(MRZ.date("261225", kind: .birth, today: january), "1926-12-25")
        // A birthday earlier in the current year genuinely is this year.
        XCTAssertEqual(MRZ.date("260101", kind: .birth, today: today), "2026-01-01")
        XCTAssertEqual(MRZ.date("260820", kind: .birth, today: today), "2026-08-20")
    }

    func testAnExpiryOfTheWholeFixtureSetIsInTheFuture() {
        for specimen in [MRZFixtures.expiring2035, MRZFixtures.expiring2031, MRZFixtures.minor, MRZFixtures.adult] {
            let expiry = MRZ.parse(MRZFixtures.text(specimen))?["expiry_date"] ?? ""
            XCTAssertEqual(expiry, specimen.expectedExpiry, specimen.label)
            XCTAssertGreaterThan(expiry, "2026", "\(specimen.label) expiry landed in the past")
        }
    }

    func testImpossibleCalendarDatesAreRejected() {
        XCTAssertNil(MRZ.date("749912", kind: .birth, today: today), "month 99")
        XCTAssertNil(MRZ.date("840231", kind: .birth, today: today), "31 February")
        XCTAssertNil(MRZ.date("840012", kind: .birth, today: today), "month 0")
        XCTAssertNil(MRZ.date("84121", kind: .birth, today: today), "too short")
    }

    // MARK: - Line 2 is trusted on its own

    /// Three of the six real MIO passports produced a perfect line 2 next to a
    /// line 1 the camera destroyed. All three used to yield nothing.
    func testExtractsLine2FieldsWhenLine1IsGarbled() {
        for observed in MRZFixtures.observed {
            let text = [observed.line1, observed.line2].compactMap { $0 }.joined(separator: "\n")
            let result = MRZ.parse(text)
            XCTAssertNotNil(result, "\(observed.label) lost every line-2 field")
            XCTAssertFalse((result?["document_number"] ?? "").isEmpty, observed.label)
            XCTAssertFalse((result?["birth_date"] ?? "").isEmpty, observed.label)
            XCTAssertFalse((result?["nationality"] ?? "").isEmpty, observed.label)
        }
    }

    func testMissingLine1StillYieldsEverythingLine2Knows() {
        let result = MRZ.parse(MRZFixtures.minor.line2)
        XCTAssertEqual(result?["document_number"], "Z2468013C")
        XCTAssertEqual(result?["birth_date"], "2013-03-09")
        XCTAssertEqual(result?["sex"], "F")
        XCTAssertNil(result?["full_name"], "there is no name to invent")
    }

    func testLine1BelowLine2IsAlsoAccepted() {
        // Vision does not guarantee reading order on a rotated photograph.
        let result = MRZ.parse("\(MRZFixtures.adult.line2)\n\(MRZFixtures.adult.line1)")
        XCTAssertEqual(result?["full_name"], MRZFixtures.adult.expectedName)
    }

    // MARK: - Names

    func testFillerNoiseDoesNotLeakIntoGivenNames() {
        let result = MRZ.parse("P<UTONAKAMURA<<YUKI<<<KKKKKKKRKRS<<<<<<<<<<\n\(MRZFixtures.adult.line2)")
        XCTAssertEqual(result?["full_name"], "YUKI NAKAMURA")
    }

    func testNameStopsAtTheFirstDoubleFiller() {
        let result = MRZ.parse("P<UTOERIKSSON<<ANNA<MARIA<<XX<<<<<<<<<<<<<<<\nL898902C36UTO7408122F3204153ZE184226B<<<<<10")
        XCTAssertEqual(result?["full_name"], "ANNA MARIA ERIKSSON")
    }

    func testMultipleGivenNamesAreJoinedWithSingleSpaces() {
        XCTAssertEqual(MRZ.names("P<UTOERIKSSON<<ANNA<MARIA<LOUISE<<<<<<<<<<<<"), "ANNA MARIA LOUISE ERIKSSON")
    }

    func testADoubleBarrelledSurnameSurvives() {
        XCTAssertEqual(MRZ.names("P<GRCPAPADOPOULOS<KOSTA<<NIKOLAOS<<<<<<<<<<<"), "NIKOLAOS PAPADOPOULOS KOSTA")
    }

    func testANameLineContainingDigitsIsRejected() {
        // The real OCR of one MIO passport: security print read as characters.
        XCTAssertNil(MRZ.names("PEUTONAKAMURA<<YUK1AAAAAAA1<1X11111111155"))
    }

    func testANameLineWithNoSeparatorIsRejected() {
        XCTAssertNil(MRZ.names("P<UTOERIKSSONANNAMARIA<<<<<<<<<<<<<<<<<<<<<<"))
    }

    // MARK: - Every check digit on line 2 is honoured

    func testRejectsACorruptedDocumentNumberCheckDigit() {
        XCTAssertNil(MRZ.parse("P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C31UTO7408122F3204153ZE184226B<<<<<10"))
    }

    func testRejectsACorruptedBirthDateCheckDigit() {
        // 840812 carrying check digit 0; the correct value is 9.
        XCTAssertNil(MRZ.parse("P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO8408120F3204153ZE184226B<<<<<10"))
        // Sanity: the same line with the right digit does parse.
        XCTAssertNotNil(MRZ.parse("P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO8408129F3204153ZE184226B<<<<<10"))
    }

    func testRejectsACorruptedExpiryCheckDigit() {
        XCTAssertNil(MRZ.parse("P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO7408122F3204151ZE184226B<<<<<10"))
    }

    func testRejectsAnImpossibleBirthMonthEvenWithAValidCheckDigit() {
        // 749912 with its own correct check digit (8) — arithmetically sound,
        // calendrically impossible.
        XCTAssertNil(MRZ.parse("P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO7499128F3204153ZE184226B<<<<<10"))
    }

    // MARK: - Rejection paths

    func testRejectsPlainText() {
        XCTAssertNil(MRZ.parse("This document has nothing machine readable on it at all."))
        XCTAssertNil(MRZ.parse(""))
    }

    func testRejectsAnAllFillerDocumentNumber() {
        XCTAssertNil(MRZ.parse("P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n<<<<<<<<<0UTO7408122F3204153ZE184226B<<<<<10"))
    }

    func testRejectsATooShortLine() {
        XCTAssertNil(MRZ.parse("L898902C36UTO7408122F12"))
    }

    func testAnUnknownSexMarkerBecomesX() {
        let result = MRZ.parse("P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO7408122<3204153ZE184226B<<<<<10")
        XCTAssertEqual(result?["sex"], "X")
    }

    // MARK: - Fallback

    func testFallbackFindsADocumentNumberInFreeText() {
        XCTAssertEqual(MRZ.fallback("Passport No.\nXY123456")["document_number"], "XY123456")
    }

    func testFallbackStripsAnInternalSpace() {
        XCTAssertEqual(MRZ.fallback("XY 123456")["document_number"], "XY123456")
    }

    func testFallbackReturnsNothingWhenThereIsNoNumber() {
        XCTAssertTrue(MRZ.fallback("ПАСПОРТ PASSPORT УКРАЇНА").isEmpty)
    }

    func testFallbackDoesNotClaimADocumentType() {
        XCTAssertNil(MRZ.fallback("XY123456")["document_type"])
    }
}
