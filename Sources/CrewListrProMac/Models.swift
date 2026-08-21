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

struct Trip: Codable, Identifiable, Hashable {
    var id = UUID()
    var boatID: UUID
    var departureDate: Date
    var returnDate: Date
    var status: String = "draft"
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
    var imageRevisions: [String] = []

    // MARK: - Field access

    subscript(field: CrewField) -> String {
        get { fields[field.rawValue] ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            fields[field.rawValue] = trimmed
            // Editing a value retracts its verification: the operator must
            // confirm what they typed, exactly as they confirm what OCR read.
            verifiedFields.remove(field.rawValue)
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
