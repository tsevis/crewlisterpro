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
        case .birthDate, .expiryDate: "YYYY-MM-DD"
        case .sex: "M or F"
        case .documentType: "passport"
        }
    }

    /// Fields a port authority requires on the crew list. Export is blocked
    /// until every one of these is present and operator-verified.
    static let requiredForExport: [CrewField] = [.fullName, .documentNumber, .nationality, .birthDate, .sex]

    /// The only fields the local vision model is allowed to offer.
    ///
    /// Measured against two real Ukrainian passports across three prompt
    /// versions, six runs. The document number came back correct every time,
    /// and both dates came back correct on the shortest prompt. The name never
    /// did: it arrived in Cyrillic, or transliterated into something invented —
    /// a page printing MINCHUK produced MIHCHYK, which is pure ASCII and passes
    /// every check this app makes. Worse, each attempt to steer the name
    /// changed how the model read the DATES, so instructing it about names cost
    /// accuracy on the fields it was good at.
    ///
    /// So this is a declared policy rather than a habit of the rescuer: the
    /// prompt asks for exactly these keys and the reply is filtered to exactly
    /// these keys, both reading from here. Widening it means widening it in the
    /// field vocabulary, where the reason above is written down.
    static let rescuable: [CrewField] = [.documentNumber, .birthDate, .expiryDate]

    /// Display order in the review pane.
    static let reviewOrder: [CrewField] = [
        .fullName, .documentNumber, .documentType, .nationality, .birthDate, .sex, .expiryDate,
    ]

    var isRequiredForExport: Bool { Self.requiredForExport.contains(self) }
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
            guard let date = isoDate(trimmed) else { return .invalid("Use YYYY-MM-DD.") }
            if date > today { return .invalid("Birth date is in the future.") }
            if date < Date(timeIntervalSince1970: -3_155_760_000) { return .warning("Over 100 years ago — check the century.") }
            return .valid
        case .expiryDate:
            guard let date = isoDate(trimmed) else { return .invalid("Use YYYY-MM-DD.") }
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

    static func iso8601String(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
