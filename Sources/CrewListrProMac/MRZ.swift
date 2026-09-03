import Foundation

/// ICAO 9303 TD3 machine-readable zone parser.
///
/// Line 2 carries a check digit for the document number, the birth date, the
/// expiry date and a composite over all of them. Line 1 carries the names and no
/// check digit at all. The parser therefore trusts line 2 on its own arithmetic
/// and treats line 1 as best-effort: a photographed passport very often yields a
/// perfect line 2 next to a line 1 the camera smeared.
enum MRZ {

    /// Characters legal in a machine-readable zone.
    private static let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")

    static func parse(_ text: String) -> [String: String]? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.uppercased().filter { alphabet.contains($0) } }
            .filter { $0.count >= 28 }
        guard !lines.isEmpty else { return nil }

        for (index, line) in lines.enumerated() {
            guard let second = Line2(line) else { continue }
            var fields = second.fields

            // Names come from the preceding line when it is recognisable. When
            // it is not, everything line 2 knows is still worth keeping.
            let candidates = [index > 0 ? lines[index - 1] : nil, index + 1 < lines.count ? lines[index + 1] : nil]

            // Line 1 carries the same three letters at positions 3 to 5, so a
            // state that came off line 2 with a digit in it has a second,
            // independent reading to be settled against.
            let fromLine1 = candidates.compactMap { $0 }.compactMap(Self.issuingState).first
            let state = repairedStateCode(second.state, issuingState: fromLine1)
            fields["nationality"] = nationality(state)

            if let name = candidates.compactMap({ $0.flatMap { Self.names($0, issuedBy: state) } }).first {
                fields["full_name"] = name
            }
            fields["document_type"] = "passport"
            return fields
        }
        return nil
    }

    /// A parsed, self-consistent TD3 second line.
    private struct Line2 {
        let fields: [String: String]
        /// The issuing state exactly as it was read, before repair.
        ///
        /// Held apart because it is the one field on this line no check digit
        /// covers — the composite spans the document number, the birth date and
        /// the expiry date, and skips positions 11 to 13 entirely. Everything
        /// else here has arithmetic behind it; this has nothing, so it is the
        /// one value that can be wrong without the line failing to parse.
        let state: String

        init?(_ line: String) {
            let characters = Array(line)
            guard characters.count >= 28 else { return nil }

            let rawNumber = String(characters.prefix(9))
            let number = rawNumber.replacingOccurrences(of: "<", with: "")
            guard !number.isEmpty,
                  let numberCheck = characters[9].wholeNumberValue,
                  checksum(rawNumber) == numberCheck else { return nil }

            let birth = String(characters[13..<19])
            guard let birthCheck = characters[19].wholeNumberValue,
                  checksum(birth) == birthCheck,
                  let birthDate = MRZ.date(birth, kind: .birth) else { return nil }

            let expiry = String(characters[21..<27])
            guard let expiryCheck = characters[27].wholeNumberValue,
                  checksum(expiry) == expiryCheck,
                  let expiryDate = MRZ.date(expiry, kind: .expiry) else { return nil }

            let sex = characters[20]
            state = String(characters[10..<13])
            fields = [
                "document_number": number,
                "birth_date": birthDate,
                "expiry_date": expiryDate,
                "sex": ["M", "F"].contains(sex) ? String(sex) : "X",
            ]
        }
    }

    // MARK: - Names

    /// `P<UTONAKAMURA<<YUKI<<<KKKKKKKRKRS<<<` → `YUKI NAKAMURA`.
    ///
    /// The name field ends at its first run of two or more fillers; anything
    /// after that is padding, and on a photographed passport it is often
    /// security print that OCR mistook for letters.
    static func names(_ line: String, issuedBy state: String? = nil) -> String? {
        // Tolerate a misread document-class or issuing-state character: only the
        // shape "<letter/filler><3 chars><name>" has to survive.
        guard line.count >= 10 else { return nil }
        // Line 1 of a TD3 zone holds letters and fillers only. A digit means the
        // camera turned security print into text, and every character on the
        // line is then suspect — better no name than an invented one.
        guard !line.contains(where: \.isNumber) else { return nil }
        let body = String(line.dropFirst(prefixLength(of: line, issuedBy: state)))
        let parts = body.components(separatedBy: "<<")
        guard parts.count >= 2 else { return nil }

        let surname = tokens(parts[0]).joined(separator: " ")
        let given = tokens(parts[1]).joined(separator: " ")
        guard !surname.isEmpty, !given.isEmpty else { return nil }
        return "\(given) \(surname)"
    }

    /// How much of line 1 comes before the name.
    ///
    /// By the standard it is five characters: a document class, a filler, and
    /// the three-letter issuing state. Dropping five unconditionally is what
    /// the parser used to do, and on a photograph where the recogniser missed
    /// the `P<HUN` altogether it ate the first five letters of the surname
    /// instead — measured on a real passport, where it turned an eight-letter
    /// surname into three.
    ///
    /// So the prefix is identified rather than assumed, using the issuing state
    /// line 2 has already proved with a check digit. Nothing is dropped when
    /// nothing that looks like a prefix is there.
    static func prefixLength(of line: String, issuedBy state: String?) -> Int {
        let characters = Array(line)
        if let state, state.count == 3, characters.count > 5 {
            if String(characters[2..<5]) == state { return 5 }
            if String(characters[0..<3]) == state { return 3 }
        }
        // No state to check against: fall back to the shape alone — a letter,
        // a filler, then three more letters.
        if characters.count > 5, characters[1] == "<", characters[0].isLetter,
           characters[2...4].allSatisfy(\.isLetter) {
            return 5
        }
        return 0
    }

    /// The issuing state as line 1 gives it, when line 1 gives it cleanly.
    static func issuingState(_ line: String) -> String? {
        let characters = Array(line)
        guard characters.count > 5, characters[1] == "<", characters[0].isLetter else { return nil }
        let state = String(characters[2..<5])
        return state.allSatisfy(\.isLetter) ? state : nil
    }

    /// A three-letter country code with the camera's digits taken back out.
    ///
    /// Only letters and fillers are legal in this field, so a digit is always a
    /// misread — but knowing that is not the same as knowing which letter it
    /// was, and the two are treated differently here.
    ///
    /// Line 1 is asked first: it holds the same three letters, so two readings
    /// that agree everywhere except where one has a digit settle the question
    /// outright, with no appeal to what looks like what.
    ///
    /// Failing that, only the shapes OCR-B genuinely confuses are substituted.
    /// A 1 is not among them: it is an I or an L and nothing about the shape
    /// says which, so it is left in place for the operator — and validation now
    /// refuses a nationality with a digit in it, so what is left cannot be
    /// confirmed by accident.
    static func repairedStateCode(_ raw: String, issuingState: String?) -> String {
        guard raw.contains(where: \.isNumber) else { return raw }

        // Two readings of the same three letters, differing only where one of
        // them saw a digit.
        if let issuingState, issuingState.count == raw.count,
           zip(raw, issuingState).allSatisfy({ $0.isNumber || $0 == $1 }) {
            return issuingState
        }

        let unmistakable: [Character: Character] = ["0": "O", "2": "Z", "5": "S", "6": "G", "8": "B"]
        return String(raw.map { unmistakable[$0] ?? $0 })
    }

    /// The best name among several readings of the same line.
    ///
    /// Used only after the ordinary path has failed, and only over strings the
    /// recogniser itself proposed. A reading has to earn its place: it must
    /// hold no digits, since line 1 cannot legally contain one; it must carry
    /// the `<<` that separates surname from given names; and it is preferred
    /// when it is the full 44 characters and when it opens with the issuing
    /// state that line 2 has already proved.
    ///
    /// Ties are broken towards the longer reading, because the failure being
    /// repaired is a line the camera cut short.
    static func bestName(among readings: [String], issuedBy state: String) -> String? {
        let cleaned = readings
            .map { $0.uppercased().filter { alphabet.contains($0) } }
            .filter { $0.count >= 20 && $0.contains("<<") && !$0.contains(where: \.isNumber) }

        let ranked = cleaned.sorted { lhs, rhs in
            let left = (confidence(of: lhs, issuedBy: state), lhs.count)
            let right = (confidence(of: rhs, issuedBy: state), rhs.count)
            return left > right
        }
        return ranked.lazy.compactMap { names($0, issuedBy: state) }.first
    }

    /// How much a reading looks like the first line of a TD3 zone.
    private static func confidence(of line: String, issuedBy state: String) -> Int {
        var score = 0
        if prefixLength(of: line, issuedBy: state) == 5 { score += 2 }
        if line.count == 44 { score += 1 }
        // The filler run that pads the line out to 44 is the most recognisable
        // thing on it, and its absence usually means the reading stopped early.
        if line.hasSuffix("<<") { score += 1 }
        return score
    }

    private static func tokens(_ value: String) -> [String] {
        value.split(separator: "<").map(String.init).filter { !$0.isEmpty }
    }

    // MARK: - Fallback

    static func fallback(_ text: String) -> [String: String] {
        let range = text.range(of: #"[A-Z]{2}\s?\d{6,7}"#, options: .regularExpression)
        return range.map { ["document_number": text[$0].replacingOccurrences(of: " ", with: "")] } ?? [:]
    }

    // MARK: - Check digits

    static func checksum(_ value: String) -> Int {
        let weights = [7, 3, 1]
        return value.enumerated().reduce(0) { total, item in
            let value: Int
            if let digit = item.element.wholeNumberValue { value = digit }
            else if let ascii = item.element.asciiValue, ascii >= 65, ascii <= 90 { value = Int(ascii - 65) + 10 }
            else { value = 0 }   // filler
            return total + value * weights[item.offset % weights.count]
        } % 10
    }

    // MARK: - Dates

    enum DateKind { case birth, expiry }

    /// The longest validity any passport carries.
    static let maximumValidityYears = 10

    /// A two-digit year is ambiguous, and the direction of the ambiguity depends
    /// on what the date means. A birth date is always in the past; an expiry
    /// date on a document being presented is essentially always in the future.
    ///
    /// A fixed pivot at 30 got this wrong in both directions: it read a 2035
    /// expiry as 1935, and would read a 2028 birth date off a passport issued to
    /// a newborn in 1928.
    static func date(_ value: String, kind: DateKind, today: Date = .now) -> String? {
        guard value.count == 6,
              let year = Int(value.prefix(2)),
              let month = Int(value.dropFirst(2).prefix(2)),
              let day = Int(value.suffix(2)),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentYear = reference.year,
              let currentMonth = reference.month,
              let currentDay = reference.day else { return nil }
        let century = currentYear - currentYear % 100
        let resolved: Int
        switch kind {
        case .birth:
            // Latest date not in the future. Compared as a full calendar date,
            // not by year alone: a passport scanned in January whose holder was
            // born this December-years-ago must pivot back a century, and a
            // year-only comparison read it as a birth later this year.
            let candidate = century + year
            let isFuture = (candidate, month, day) > (currentYear, currentMonth, currentDay)
            resolved = isFuture ? candidate - 100 : candidate
        case .expiry:
            // An expiry may be long past, but cannot be far ahead: a passport
            // carries at most about ten years of validity. Pick the candidate
            // inside that window rather than simply pushing old ones forward —
            // a 2012 expiry is an expired passport, not a 2112 one.
            var candidate = century + year
            if candidate > currentYear + Self.maximumValidityYears {
                candidate -= 100
            } else if candidate < currentYear - (100 - Self.maximumValidityYears) {
                candidate += 100
            }
            resolved = candidate
        }

        // Reject impossible calendar days such as 31 February.
        var components = DateComponents()
        components.year = resolved
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }

        return String(format: "%04d-%02d-%02d", resolved, month, day)
    }

    private static func nationality(_ code: String) -> String {
        ["UKR": "UKRAINIAN", "GRC": "GREEK", "ITA": "ITALIAN", "RUS": "RUSSIAN",
         "POL": "POLISH", "GBR": "BRITISH", "DEU": "GERMAN", "FRA": "FRENCH",
         "TUR": "TURKISH", "USA": "AMERICAN"][code] ?? code
    }
}
