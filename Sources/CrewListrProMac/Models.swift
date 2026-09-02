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

/// One yacht in the operator's fleet.
///
/// Always a record of its own, joined to a charter by `Trip.boatID` — what
/// changed is that an operator can now make one, reuse it across seasons and
/// see the ones they have, instead of retyping a name into every new trip.
/// The four values here are the four boxes printed across the top of a crew
/// list, which is why editing them on a trip edits the vessel everywhere.
struct Boat: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var flag: String = ""
    var registrationPort: String = ""
    var registrationNumber: String = ""

    /// Out of the fleet, still on its own past charters.
    ///
    /// Retiring is not deleting, for the same reason archiving a trip is not:
    /// a yacht sold in October is still the yacht named on August's crew list,
    /// and a port authority can ask about that long after it left the fleet.
    /// `CrewStore.deleteBoat` is the other half of the pair, and it refuses
    /// while any trip still points here.
    var isRetired: Bool = false

    /// A boat is only printable on a crew list once it has a real name.
    var isComplete: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && name != Self.placeholderName }

    static let placeholderName = "NEW YACHT"
}

extension Boat {
    /// See `Trip.init(from:)` for why every persisted type here decodes by hand.
    ///
    /// The name falls back to the placeholder rather than to an empty string so
    /// `isComplete` reads false: a yacht whose name could not be read must stop
    /// the export and ask for one, not print a blank header box.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Identity is never invented — see the note on `CrewDocument`.
        id = try container.decode(UUID.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? Self.placeholderName
        flag = (try? container.decode(String.self, forKey: .flag)) ?? ""
        registrationPort = (try? container.decode(String.self, forKey: .registrationPort)) ?? ""
        registrationNumber = (try? container.decode(String.self, forKey: .registrationNumber)) ?? ""
        // In the fleet is the safe direction: a yacht that reads as retired
        // when it is not simply disappears from the picker, and an operator
        // cannot tell why.
        isRetired = (try? container.decode(Bool.self, forKey: .isRetired)) ?? false
    }
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

extension CrewPerson {
    /// An unreadable verification state reads as `.pending`: unreviewed is the
    /// only safe guess about a person nobody can prove was reviewed.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fullName = (try? container.decode(String.self, forKey: .fullName)) ?? ""
        nationality = (try? container.decode(String.self, forKey: .nationality)) ?? ""
        birthDate = try? container.decodeIfPresent(Date.self, forKey: .birthDate)
        verification = (try? container.decode(VerificationState.self, forKey: .verification)) ?? .pending
    }
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

extension CrewDocument {
    /// The rule this file follows, stated once here because this is the type it
    /// was learned on.
    ///
    /// **Descriptive fields are salvaged, and always in the direction that makes
    /// the operator look.** An unreadable `verifiedFields` decodes as empty, so
    /// the document is held back for review rather than waved onto a crew list;
    /// an unrecognised `risk` decodes as `.review` and never as `.low`.
    ///
    /// **Identity is never fabricated.** `id`, `tripID` and `personID` are what
    /// join this document to its trip and its person. Substituting a fresh UUID
    /// for a missing one would produce a passport scan attached to no trip,
    /// invisible in the interface and impossible to delete — strictly worse
    /// than a record that refuses to load and says so.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        tripID = try container.decode(UUID.self, forKey: .tripID)
        personID = try container.decode(UUID.self, forKey: .personID)
        originalName = (try? container.decode(String.self, forKey: .originalName)) ?? ""
        // Empty is already an anticipated state: `CrewStore.discardFiles`
        // filters empty names before asking the store to delete anything.
        encryptedFileName = (try? container.decode(String.self, forKey: .encryptedFileName)) ?? ""
        documentNumber = (try? container.decode(String.self, forKey: .documentNumber)) ?? ""
        documentType = (try? container.decode(String.self, forKey: .documentType)) ?? "unknown"
        risk = (try? container.decode(RiskLevel.self, forKey: .risk)) ?? .review
        riskReasons = (try? container.decode([String].self, forKey: .riskReasons)) ?? []
        fields = (try? container.decode([String: String].self, forKey: .fields)) ?? [:]
        verifiedFields = (try? container.decode(Set<String>.self, forKey: .verifiedFields)) ?? []
        suggestedFields = try? container.decodeIfPresent(Set<String>.self, forKey: .suggestedFields)
        imageRevisions = (try? container.decode([String].self, forKey: .imageRevisions)) ?? []
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

    /// The one person on this trip who signs the papers.
    ///
    /// Deliberately not a third `CrewRole`. The client is whoever chartered the
    /// yacht and they are aboard as either the skipper or a passenger — a role
    /// case would force a choice between the two facts and lose one of them.
    /// Exactly one assignment per trip carries this; `CrewStore.setClient`
    /// is what keeps that true.
    var isClient: Bool = false

    /// Reachable by email. Only the skipper's is asked for or printed: it is
    /// the address a port authority or charter base writes to about the vessel,
    /// and collecting an address for every passenger would be collecting
    /// personal data nothing on the crew list needs.
    ///
    /// Held on the assignment rather than on the person, so it follows the
    /// skippering of *this* trip — naming a new skipper brings their address
    /// with them instead of leaving the old one on the form.
    var email: String = ""
}

extension CrewAssignment {
    /// An unreadable role reads as `.passenger`, which is the safe direction:
    /// a trip with no skipper is blocked from export and says so, whereas
    /// guessing `.skipper` would let a crew list out naming the wrong person as
    /// master of the vessel.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        tripID = try container.decode(UUID.self, forKey: .tripID)
        personID = try container.decode(UUID.self, forKey: .personID)
        role = (try? container.decode(CrewRole.self, forKey: .role)) ?? .passenger
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        // Both added after operators had real data on disk. `try?` covers the
        // key simply not being there — Swift's synthesised decoding would throw
        // `keyNotFound` and take the assignment with it. Not being the client
        // is the safe direction: an unnamed signatory is a blank line on the
        // form, a wrongly named one is a signature attributed to the wrong
        // person.
        isClient = (try? container.decode(Bool.self, forKey: .isClient)) ?? false
        email = (try? container.decode(String.self, forKey: .email)) ?? ""
    }
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
    var isClient: Bool

    /// The birth date as the passport itself prints it — `16 DEC 1984`. The
    /// stored value stays ISO-8601, which is what the CSV and every validation
    /// rule read; only what a person looks at changes.
    ///
    /// No expiry equivalent: the expiry is not a column on the printed form and
    /// stays ISO in the CSV, so there would be nothing to read it.
    var printedBirthDate: String { DocumentDate.display(birthDate) }

    init(document: CrewDocument, role: CrewRole, isClient: Bool = false) {
        fullName = document[.fullName]
        documentNumber = document[.documentNumber]
        nationality = document[.nationality]
        birthDate = document[.birthDate]
        sex = document[.sex]
        expiryDate = document[.expiryDate]
        self.role = role
        self.isClient = isClient
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

    /// The operator's defaults. Held here rather than in `UserDefaults` so a
    /// restored snapshot restores the settings that produced it.
    var settings = AppSettings()

    /// Records this read could not decode, one line each.
    ///
    /// Not persisted, and deliberately not silent. Salvaging a collection means
    /// dropping something — a passport that will simply be missing from a trip —
    /// and the operator has to be told rather than left to notice. `CrewStore`
    /// surfaces this after `load()`; writing it back would save a complaint
    /// about data the next save has already rewritten.
    var decodingLosses: [String] = []

    /// 3 added `settings` and `Boat.isRetired`; both decode from an older
    /// payload as their defaults, so the bump records the change rather than
    /// gating it.
    static let currentSchemaVersion = 3

    /// Only the persisted properties. Declared explicitly so `decodingLosses`
    /// is never written to disk.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, boats, trips, people, documents, assignments, settings
    }

    init(schemaVersion: Int = AppData.currentSchemaVersion, boats: [Boat] = [], trips: [Trip] = [], people: [CrewPerson] = [], documents: [CrewDocument] = [], assignments: [CrewAssignment] = [], settings: AppSettings = AppSettings()) {
        self.schemaVersion = schemaVersion
        self.boats = boats
        self.trips = trips
        self.people = people
        self.documents = documents
        self.assignments = assignments
        self.settings = settings
    }

    /// A payload written before versioning decodes as version 1.
    ///
    /// Each collection is decoded element by element. Decoding `[CrewDocument]`
    /// in one go is all-or-nothing: a single malformed element threw, and took
    /// every trip, person and confirmation in the store down with it — the
    /// operator was told their data was corrupt when one record out of hundreds
    /// was. One unreadable record must cost one record.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var losses: [String] = []
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        boats = Self.salvage(from: container, forKey: .boats, describing: "boat", into: &losses)
        trips = Self.salvage(from: container, forKey: .trips, describing: "trip", into: &losses)
        people = Self.salvage(from: container, forKey: .people, describing: "person", into: &losses)
        documents = Self.salvage(from: container, forKey: .documents, describing: "document", into: &losses)
        assignments = Self.salvage(from: container, forKey: .assignments, describing: "crew assignment", into: &losses)
        // Not salvaged into `losses`: unreadable settings cost the operator a
        // handful of preferences they can set again in a minute, which is not
        // the same kind of loss as a passport that has left a trip, and saying
        // "some records could not be read" about it would be alarming and
        // wrong.
        settings = (try? container.decode(AppSettings.self, forKey: .settings)) ?? AppSettings()
        decodingLosses = losses
    }

    /// Decodes what it can from one collection, and names what it could not.
    private static func salvage<Element: Decodable>(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        describing noun: String,
        into losses: inout [String]
    ) -> [Element] {
        // An absent key is not damage: a store written before this collection
        // existed simply has none of them. Only a key that is present and
        // unreadable counts as a loss, or every older payload would open
        // accusing itself of corruption it does not have.
        guard container.contains(key), (try? container.decodeNil(forKey: key)) != true else { return [] }
        guard let wrapped = try? container.decode([Salvaged<Element>].self, forKey: key) else {
            // The collection itself was unreadable — not one bad element but a
            // key holding something that is not an array at all.
            losses.append("The stored \(noun) list could not be read.")
            return []
        }
        let recovered = wrapped.compactMap(\.value)
        let lost = wrapped.count - recovered.count
        if lost > 0 {
            losses.append("\(lost) \(noun)\(lost == 1 ? "" : "s") could not be read and \(lost == 1 ? "was" : "were") left out.")
        }
        return recovered
    }

    /// Decodes an element, or absorbs its failure so its neighbours survive.
    private struct Salvaged<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }
}
