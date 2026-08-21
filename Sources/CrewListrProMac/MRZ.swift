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
            if let name = candidates.compactMap({ $0.flatMap(Self.names) }).first {
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
            fields = [
                "document_number": number,
                "nationality": MRZ.nationality(String(characters[10..<13])),
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
    static func names(_ line: String) -> String? {
        // Tolerate a misread document-class or issuing-state character: only the
        // shape "<letter/filler><3 chars><name>" has to survive.
        guard line.count >= 10 else { return nil }
        // Line 1 of a TD3 zone holds letters and fillers only. A digit means the
        // camera turned security print into text, and every character on the
        // line is then suspect — better no name than an invented one.
        guard !line.contains(where: \.isNumber) else { return nil }
        let body = String(line.dropFirst(5))
        let parts = body.components(separatedBy: "<<")
        guard parts.count >= 2 else { return nil }

        let surname = tokens(parts[0]).joined(separator: " ")
        let given = tokens(parts[1]).joined(separator: " ")
        guard !surname.isEmpty, !given.isEmpty else { return nil }
        return "\(given) \(surname)"
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

        let currentYear = Calendar(identifier: .gregorian).component(.year, from: today)
        let century = currentYear - currentYear % 100
        let resolved: Int
        switch kind {
        case .birth:
            // Latest year not in the future.
            let candidate = century + year
            resolved = candidate > currentYear ? candidate - 100 : candidate
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
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
