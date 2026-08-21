import Foundation

enum VerificationState: String, Codable, CaseIterable { case pending, verified, rejected }
enum CrewRole: String, Codable, CaseIterable, Identifiable {
    case skipper, passenger
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}
enum RiskLevel: String, Codable, CaseIterable {
    case low, review, high

    var label: String {
        switch self {
        case .low: "Cleared"
        case .review: "Needs review"
        case .high: "Rejected"
        }
    }
}

struct Boat: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var flag: String = ""
    var registrationPort: String = ""
    var registrationNumber: String = ""

    /// A boat is only printable on a crew list once it has a real name.
    var isComplete: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && name != Self.placeholderName }

    static let placeholderName = "NEW YACHT"
}

/// Whether a charter is still being worked on, or has been put away.
///
/// Archiving is not deleting. `CrewStore.deleteTrip` shreds the encrypted
/// passport scans, which is right when an operator wants them gone and wrong
/// when the season merely ended — a charter can be queried by a port authority
/// long after it sailed. The raw values are the strings the Python build writes,
/// so both stores describe a trip the same way.
enum TripStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case archived
}

struct Trip: Codable, Identifiable, Hashable {
    var id = UUID()
    var boatID: UUID
    var departureDate: Date
    var returnDate: Date
    var status: TripStatus = .draft

    var isArchived: Bool { status == .archived }
}

extension Trip {
    /// Decoded by hand so an unreadable `status` costs one trip's status rather
    /// than the entire database.
    ///
    /// Two ways the synthesised version bites, both already paid for here once
    /// on `CrewDocument.suggestedFields`: a key absent from an older record
    /// throws `keyNotFound` rather than using the property's default, and a
    /// `RawRepresentable` enum throws on any value it does not know. Either
    /// would surface as the whole store reading as `invalidPayload` — an app
    /// that can no longer open its own data. A trip whose status is missing or
    /// unrecognised is simply a draft.
    ///
    /// In an extension deliberately: an `init` in the struct body would suppress
    /// the memberwise initialiser the rest of the app and its tests construct
    /// trips with.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        boatID = try container.decode(UUID.self, forKey: .boatID)
        departureDate = try container.decode(Date.self, forKey: .departureDate)
        returnDate = try container.decode(Date.self, forKey: .returnDate)
        // One `try?` covers both failures: the key being absent and the value
        // being a status this build has never heard of.
        status = (try? container.decode(TripStatus.self, forKey: .status)) ?? .draft
    }
}

struct CrewPerson: Codable, Identifiable, Hashable {
    var id = UUID()
    var fullName: String = ""
    var nationality: String = ""
    var birthDate: Date?
    var verification: VerificationState = .pending
}

struct CrewDocument: Codable, Identifiable, Hashable {
    var id = UUID()
    var tripID: UUID
    var personID: UUID
    var originalName: String
    var encryptedFileName: String
    var documentNumber: String = ""
    var documentType: String = "unknown"
    var risk: RiskLevel = .review
    var riskReasons: [String] = []
    var fields: [String: String] = [:]
    var verifiedFields: Set<String> = []

    /// Fields whose value came from the local vision model rather than from
    /// the machine-readable zone.
    ///
    /// The distinction is not decorative. An MRZ value has check digits behind
    /// it; a model's value has nothing behind it but a photograph, and on a
    /// damaged document it can be confidently wrong in a way that looks right —
    /// measured: a passport printing MINCHUK produced MIHCHYK, pure ASCII,
    /// passing every validation rule there is. The operator confirming it is
    /// looking at the same unreadable line the model guessed from, so the
    /// interface has to tell them which values carry no arithmetic.
    /// Optional in storage, deliberately.
    ///
    /// Swift's synthesised `Codable` does NOT fall back to a property's default
    /// when the key is absent — it throws `keyNotFound`. Declaring this
    /// non-optional made every document written before it existed fail to
    /// decode, which surfaced as the whole store reading as `invalidPayload`:
    /// an app that could no longer open its own data. An optional decodes as
    /// nil and reads as empty, so an old document is simply a document with no
    /// suggestions on it.
    ///
    /// Any field added here from now on must be optional for the same reason.
    var suggestedFields: Set<String>?
    var imageRevisions: [String] = []

    // MARK: - Field access

    func isSuggested(_ field: CrewField) -> Bool { suggestedFields?.contains(field.rawValue) == true }

    /// Records that a value came from the local model rather than the MRZ.
    mutating func markSuggested(_ field: CrewField) {
        suggestedFields = (suggestedFields ?? []).union([field.rawValue])
    }

    mutating func markSuggested(rawField key: String) {
        suggestedFields = (suggestedFields ?? []).union([key])
    }

    subscript(field: CrewField) -> String {
        get { fields[field.rawValue] ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            fields[field.rawValue] = trimmed
            // Editing a value retracts its verification: the operator must
            // confirm what they typed, exactly as they confirm what OCR read.
            verifiedFields.remove(field.rawValue)
            // And it stops being the model's suggestion: what the operator
            // typed is theirs, however it got there.
            suggestedFields?.remove(field.rawValue)
            if field == .documentNumber { documentNumber = trimmed }
            if field == .documentType { documentType = trimmed.isEmpty ? "unknown" : trimmed }
        }
    }

    func isVerified(_ field: CrewField) -> Bool { verifiedFields.contains(field.rawValue) }

    func validation(of field: CrewField, today: Date = .now) -> FieldValidation {
        CrewFieldValidator.validate(field, value: self[field], today: today)
    }

    // MARK: - The export gate

    /// Fields still standing between this document and a crew list.
    func blockingFields(today: Date = .now) -> [CrewField] {
        CrewField.requiredForExport.filter { field in
            !isVerified(field) || validation(of: field, today: today).isBlocking
        }
    }

    /// Export requires every crew-list field to be both valid and individually
    /// confirmed by the operator. A non-empty `verifiedFields` set is not
    /// enough — that let unreviewed fields through.
    func canExport(today: Date = .now) -> Bool {
        risk != .high && blockingFields(today: today).isEmpty
    }

    var reviewProgress: Double {
        let required = CrewField.requiredForExport
        guard !required.isEmpty else { return 1 }
        return Double(required.filter(isVerified).count) / Double(required.count)
    }

    /// What the operator sees in the document list. Derived from review state,
    /// not from the extraction's own risk guess — a freshly imported document
    /// has never been looked at, whatever its MRZ check digit said.
    func reviewStatus(today: Date = .now) -> ReviewStatus {
        if risk == .high { return .rejected }
        if canExport(today: today) { return .cleared }
        if verifiedFields.isEmpty { return .awaitingReview }
        return .inProgress
    }
}

enum ReviewStatus: String, Sendable {
    case awaitingReview, inProgress, cleared, rejected

    var label: String {
        switch self {
        case .awaitingReview: "Awaiting review"
        case .inProgress: "Review in progress"
        case .cleared: "Cleared for export"
        case .rejected: "Rejected"
        }
    }

    var symbol: String {
        switch self {
        case .awaitingReview: "exclamationmark.triangle.fill"
        case .inProgress: "ellipsis.circle.fill"
        case .cleared: "checkmark.seal.fill"
        case .rejected: "xmark.octagon.fill"
        }
    }
}

struct CrewAssignment: Codable, Identifiable, Hashable {
    var id = UUID()
    var tripID: UUID
    var personID: UUID
    var role: CrewRole = .passenger
    var notes: String = ""
}

/// One printable line of the crew list, projected from a reviewed document.
///
/// The crew list is derived from `CrewDocument.fields` at export time rather
/// than from a `CrewPerson` snapshot taken at import, so an operator correction
/// always reaches the exported document.
struct CrewListRow: Hashable, Identifiable, Sendable {
    let id = UUID()
    var fullName: String
    var documentNumber: String
    var nationality: String
    var birthDate: String
    var sex: String
    var expiryDate: String
    var role: CrewRole

    init(document: CrewDocument, role: CrewRole) {
        fullName = document[.fullName]
        documentNumber = document[.documentNumber]
        nationality = document[.nationality]
        birthDate = document[.birthDate]
        sex = document[.sex]
        expiryDate = document[.expiryDate]
        self.role = role
    }
}

struct AppData: Codable {
    /// Bumped whenever the persisted shape changes so `SecureStore` can tell a
    /// migration apart from a corrupt payload.
    var schemaVersion: Int = AppData.currentSchemaVersion
    var boats: [Boat] = []
    var trips: [Trip] = []
    var people: [CrewPerson] = []
    var documents: [CrewDocument] = []
    var assignments: [CrewAssignment] = []

    static let currentSchemaVersion = 2

    init(schemaVersion: Int = AppData.currentSchemaVersion, boats: [Boat] = [], trips: [Trip] = [], people: [CrewPerson] = [], documents: [CrewDocument] = [], assignments: [CrewAssignment] = []) {
        self.schemaVersion = schemaVersion
        self.boats = boats
        self.trips = trips
        self.people = people
        self.documents = documents
        self.assignments = assignments
    }

    /// A payload written before versioning decodes as version 1.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        boats = try container.decodeIfPresent([Boat].self, forKey: .boats) ?? []
        trips = try container.decodeIfPresent([Trip].self, forKey: .trips) ?? []
        people = try container.decodeIfPresent([CrewPerson].self, forKey: .people) ?? []
        documents = try container.decodeIfPresent([CrewDocument].self, forKey: .documents) ?? []
        assignments = try container.decodeIfPresent([CrewAssignment].self, forKey: .assignments) ?? []
    }
}
