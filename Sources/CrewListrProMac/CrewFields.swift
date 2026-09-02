import Foundation

/// The canonical field vocabulary shared by extraction, the review pane and the
/// exported crew list.
///
/// Extraction writes into `CrewDocument.fields` using these keys, the review
/// pane renders one editable row per key, and the exporter reads them back. A
/// single vocabulary is what lets an operator's correction actually reach the
/// crew list — previously the exporter read a separate `CrewPerson` copy that
/// nothing ever updated.
enum CrewField: String, CaseIterable, Identifiable, Codable, Sendable {
    case fullName = "full_name"
    case documentNumber = "document_number"
    case nationality = "nationality"
    case birthDate = "birth_date"
    case sex = "sex"
    case expiryDate = "expiry_date"
    case documentType = "document_type"

    var id: String { rawValue }

    /// Label shown in the review pane.
    var label: String {
        switch self {
        case .fullName: "Full name"
        case .documentNumber: "Document no."
        case .nationality: "Nationality"
        case .birthDate: "Date of birth"
        case .sex: "Sex"
        case .expiryDate: "Date of expiry"
        case .documentType: "Document type"
        }
    }

    /// Short hint rendered under an empty or invalid field.
    var placeholder: String {
        switch self {
        case .fullName: "GIVEN NAMES SURNAME"
        case .documentNumber: "AB1234567"
        case .nationality: "UKRAINIAN"
        case .birthDate, .expiryDate: "20 OCT 1972"
        case .sex: "M or F"
        case .documentType: "passport"
        }
    }

    /// Fields a port authority requires on the crew list. Export is blocked
    /// until every one of these is present and operator-verified.
    static let requiredForExport: [CrewField] = [.fullName, .documentNumber, .nationality, .birthDate, .sex]

    /// The only field the local vision model is allowed to offer.
    ///
    /// Measured against five real Ukrainian passports, then checked against the
    /// app's own MRZ-derived export of the same documents — check digits behind
    /// every value, confirmed by the operator:
    ///
    ///   document number   5 of 5 correct
    ///   birth date        4 of 5 correct
    ///   expiry date       3 of 5 correct
    ///
    /// The dates were dropped on those figures. Three wrong values in ten, and
    /// wrong in the worst available way: 2027-07-22 read as 2022-07-27 and
    /// 2029-05-28 as 2028-05-29, the day transposed with the last two digits of
    /// the year. A transposed date is still a valid date, so validation cannot
    /// object; one of the two happened to land in the past and tripped the
    /// expiry warning, and had it gone the other way an expired passport would
    /// have read as valid in silence.
    ///
    /// The name was never a candidate: it came back in Cyrillic, or
    /// transliterated into something invented — a page printing MINCHUK
    /// produced MIHCHYK, pure ASCII, passing every check this app makes.
    ///
    /// What is left is the one field the model has never got wrong, and the one
    /// an operator most wants recovered: a long alphanumeric string that is
    /// tedious to type and easy to mistype. Everything else on a crew list is
    /// theirs to enter.
    ///
    /// This is a declared policy rather than a habit of the rescuer: the prompt
    /// asks for exactly these keys and the reply is filtered to exactly these
    /// keys, both reading from here. Widening it means widening it in the field
    /// vocabulary, where the measurements above are written down.
    static let rescuable: [CrewField] = [.documentNumber]

    /// Display order in the review pane.
    static let reviewOrder: [CrewField] = [
        .fullName, .documentNumber, .documentType, .nationality, .birthDate, .sex, .expiryDate,
    ]

    var isRequiredForExport: Bool { Self.requiredForExport.contains(self) }

    /// Fields holding a calendar date printed on the document.
    var isDate: Bool { self == .birthDate || self == .expiryDate }

    // MARK: - Storage and presentation
    //
    // A date is held as ISO-8601 — that is what the machine-readable zone
    // gives, what validation checks and what the CSV carries — and shown as
    // `20 OCT 1972`, which is what the page in front of the operator says.
    // Both directions live here rather than in the review pane, so nothing that
    // renders a field has to know which of the two it is looking at.

    /// The stored value as the operator should see it.
    func presented(_ stored: String) -> String {
        isDate ? DocumentDate.display(stored) : stored
    }

    /// What to store for what the operator typed. A date that parses is stored
    /// in the canonical form; one that does not is stored exactly as typed, so
    /// validation objects to it rather than the field silently discarding it.
    func stored(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isDate else { return trimmed }
        return DocumentDate.stored(trimmed) ?? trimmed
    }
}

// MARK: - Validation

/// The outcome of checking one field's value. `warning` never blocks export;
/// `invalid` does, because a malformed value on a crew list is worse than a
/// blank one.
enum FieldValidation: Equatable, Sendable {
    case valid
    case warning(String)
    case invalid(String)

    var isBlocking: Bool { if case .invalid = self { true } else { false } }

    var message: String? {
        switch self {
        case .valid: nil
        case .warning(let text), .invalid(let text): text
        }
    }
}

enum CrewFieldValidator {
    /// What to type when a date could not be read. Phrased as an example
    /// rather than a pattern: the field shows and accepts `20 OCT 1972`, the
    /// form the document itself is printed in, and "YYYY-MM-DD" would send the
    /// operator looking for a shape that is no longer on screen.
    static let dateAdvice = "Use a date like 20 OCT 1972."

    /// Dates are compared against a fixed reference rather than `Date.now` so a
    /// validation result is reproducible in tests and in a saved document.
    static func validate(_ field: CrewField, value: String, today: Date = .now) -> FieldValidation {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return field.isRequiredForExport ? .invalid("Required on the crew list.") : .valid
        }
        switch field {
        case .fullName:
            if trimmed.count < 2 { return .invalid("Too short to be a name.") }
            // No identity document carries digits in the name field.
            if trimmed.contains(where: { $0.isNumber }) { return .invalid("A name cannot contain digits.") }
            // A crew list carries the Latin transliteration printed on the
            // document, because that is what a port authority reads. A name in
            // another script is legitimate on the page and unusable on the list.
            if let offending = trimmed.first(where: { !isNameCharacter($0) }) {
                return .invalid("A crew list needs the Latin spelling from the document — \"\(offending)\" is not Latin.")
            }
            if trimmed.split(separator: " ").contains(where: looksLikeNoise) {
                return .warning("Looks like OCR noise — check against the document.")
            }
            return .valid
        case .documentNumber:
            if trimmed.count < 5 { return .warning("Unusually short document number.") }
            if trimmed.contains(" ") { return .warning("Contains a space.") }
            return .valid
        case .nationality:
            return trimmed.count < 2 ? .invalid("Use a country name or 3-letter code.") : .valid
        case .sex:
            return ["M", "F", "X"].contains(trimmed.uppercased()) ? .valid : .invalid("Use M, F or X.")
        case .documentType:
            return .valid
        case .birthDate:
            guard let date = isoDate(trimmed) else { return .invalid(Self.dateAdvice) }
            if date > today { return .invalid("Birth date is in the future.") }
            if date < Date(timeIntervalSince1970: -3_155_760_000) { return .warning("Over 100 years ago — check the century.") }
            return .valid
        case .expiryDate:
            guard let date = isoDate(trimmed) else { return .invalid(Self.dateAdvice) }
            return date < today ? .warning("Document has expired.") : .valid
        }
    }

    /// Latin letters, and the punctuation names actually contain.
    ///
    /// Diacritics count: MÜLLER, ŁUKASZ and O'BRIEN are Latin spellings and a
    /// port authority reads them without difficulty. Cyrillic, Greek, Arabic and
    /// CJK do not, whatever the passport's own page shows — the document prints
    /// both, and the crew list takes the Latin half.
    static func isNameCharacter(_ character: Character) -> Bool {
        if character == " " || character == "-" || character == "." { return true }
        if character == "'" || character == "\u{2019}" { return true }
        return character.unicodeScalars.allSatisfy { scalar in
            (0x0041...0x005A).contains(scalar.value)     // A-Z
                || (0x0061...0x007A).contains(scalar.value)   // a-z
                || (0x00C0...0x024F).contains(scalar.value)   // Latin-1 Supplement .. Extended-B
                || (0x1E00...0x1EFF).contains(scalar.value)   // Latin Extended Additional
                || (0x0300...0x036F).contains(scalar.value)   // combining marks on the above
        }
    }

    /// A run of one repeated letter, or a long token built from almost no
    /// distinct letters, is filler bleeding out of the MRZ name field rather
    /// than a name. "ANNA" and "ERIKSSON" must not trip this.
    private static func looksLikeNoise(_ token: Substring) -> Bool {
        guard token.count >= 4 else { return false }
        var longestRun = 1, run = 1
        for (previous, current) in zip(token, token.dropFirst()) {
            run = current == previous ? run + 1 : 1
            longestRun = max(longestRun, run)
        }
        if longestRun >= 4 { return true }
        return token.count >= 6 && Set(token).count <= 3
    }

    /// Strict ISO-8601 calendar date. The shape is checked before parsing so
    /// "84-12-16" and "1984/12/16" are rejected rather than silently coerced,
    /// and `DateFormatter` then rejects impossible days such as month 99.
    static func isoDate(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

}


// MARK: - Contact details

/// The skipper's email address — the one contact detail a crew list carries.
///
/// Its own validator rather than a `CrewField`, because it belongs to the
/// person's assignment on this trip and not to the document that identifies
/// them: it is not read off a passport, it is not confirmed against an image,
/// and it never blocks the export. A crew list with a mistyped address is still
/// a valid crew list, so every finding here is a warning.
enum ContactValidator {
    static func validate(email: String) -> FieldValidation {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        // Optional. A skipper who did not give an address is not an error.
        guard !trimmed.isEmpty else { return .valid }
        guard !trimmed.contains(" ") else { return .warning("An email address cannot contain a space.") }
        // Deliberately shallow. The full grammar of an address is famously
        // unmatchable, and an over-strict rule that rejects a working address
        // is worse than a loose one that accepts a typo the operator can see.
        let shape = #"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"#
        guard trimmed.range(of: shape, options: .regularExpression) != nil else {
            return .warning("Doesn't look like an email address — check it.")
        }
        return .valid
    }
}
