import Foundation

/// Machine-readable zones used across the MRZ tests.
///
/// Every specimen here is **fictional**, on the ICAO 9303 utopian issuer code
/// `UTO`, with check digits computed rather than transcribed. An earlier version
/// of this file carried the real machine-readable zones of six Ukrainian
/// passports — real names and real document numbers — which had no business in
/// source control. The shapes that matter for the parser are reproduced instead:
/// an expiry beyond the old century pivot, a minor, an adult, and the four ways
/// a photographed name line comes back damaged.
///
/// To exercise the pipeline against genuine documents, point
/// `CREWLISTR_FIXTURES` at a directory of them — see `CrewListGenerationTests`.
enum MRZFixtures {
    struct Specimen {
        let label: String
        let line1: String
        let line2: String
        let expectedName: String
        let expectedNumber: String
        let expectedBirth: String
        let expectedExpiry: String
        let expectedSex: String
    }

    /// A name line as OCR returned it, paired with a sound line 2.
    struct ObservedOCR {
        let label: String
        let line1: String?
        let line2: String
    }

    static let icaoSpecimen = Specimen(
        label: "ICAO 9303 specimen",
        line1: "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
        line2: "L898902C36UTO7408122F3204153ZE184226B<<<<<16",
        expectedName: "ANNA MARIA ERIKSSON",
        expectedNumber: "L898902C3",
        expectedBirth: "1974-08-12",
        expectedExpiry: "2032-04-15",
        expectedSex: "F"
    )

    /// Expiring 2035 — the case a fixed pivot at 30 read as 1935.
    static let expiring2035 = Specimen(
        label: "X1234567A / LINDQVIST",
        line1: "P<UTOLINDQVIST<<ERIK<<<<<<<<<<<<<<<<<<<<<<<<",
        line2: "X1234567A7UTO8204055M3507038<<<<<<<<<<<<<<06",
        expectedName: "ERIK LINDQVIST",
        expectedNumber: "X1234567A",
        expectedBirth: "1982-04-05",
        expectedExpiry: "2035-07-03",
        expectedSex: "M"
    )

    /// Expiring 2031 — one year past the old pivot boundary.
    static let expiring2031 = Specimen(
        label: "Y7654321B / MARCHETTI",
        line1: "P<UTOMARCHETTI<<SOFIA<<<<<<<<<<<<<<<<<<<<<<<",
        line2: "Y7654321B3UTO9006290F3109306<<<<<<<<<<<<<<00",
        expectedName: "SOFIA MARCHETTI",
        expectedNumber: "Y7654321B",
        expectedBirth: "1990-06-29",
        expectedExpiry: "2031-09-30",
        expectedSex: "F"
    )

    /// Born this century: the birth pivot must not push it back a hundred years.
    static let minor = Specimen(
        label: "Z2468013C / HALVORSEN",
        line1: "P<UTOHALVORSEN<<INGRID<<<<<<<<<<<<<<<<<<<<<<",
        line2: "Z2468013C9UTO1303096F2905280<<<<<<<<<<<<<<06",
        expectedName: "INGRID HALVORSEN",
        expectedNumber: "Z2468013C",
        expectedBirth: "2013-03-09",
        expectedExpiry: "2029-05-28",
        expectedSex: "F"
    )

    static let adult = Specimen(
        label: "W1357924D / NAKAMURA",
        line1: "P<UTONAKAMURA<<YUKI<<<<<<<<<<<<<<<<<<<<<<<<<",
        line2: "W1357924D4UTO8412162F2707222<<<<<<<<<<<<<<02",
        expectedName: "YUKI NAKAMURA",
        expectedNumber: "W1357924D",
        expectedBirth: "1984-12-16",
        expectedExpiry: "2027-07-22",
        expectedSex: "F"
    )

    static let all = [icaoSpecimen, expiring2035, expiring2031, minor, adult]

    /// The four ways a photographed name line came back in practice, each beside
    /// a checksum-sound line 2. Line 2 must survive all of them.
    static let observed: [ObservedOCR] = [
        // Read cleanly.
        .init(label: "clean", line1: "P<UTONAKAMURA<<YUKI<<<<<<<<<<<<<<<<<<<<<<<<<",
              line2: adult.line2),
        // Leading "P<" lost and the given names destroyed by security print.
        .init(label: "damaged prefix", line1: "PEUTONAKAMURA<<YUK1AAAAAAA1<1X11111111155",
              line2: adult.line2),
        // Beyond recognition.
        .init(label: "unreadable", line1: "PAUTNKMRA< YUK A++<<<<<<<<<<<<<<<<<<<<<",
              line2: adult.line2),
        // Not returned by OCR at all.
        .init(label: "absent", line1: nil, line2: adult.line2),
        // Filler run contaminated by security print misread as letters.
        .init(label: "filler noise", line1: "P<UTONAKAMURA<<YUKI<<<KKKKKKKRKRS<<<<<<<<<<",
              line2: adult.line2),
    ]

    static func text(_ specimen: Specimen) -> String { "\(specimen.line1)\n\(specimen.line2)" }
}
