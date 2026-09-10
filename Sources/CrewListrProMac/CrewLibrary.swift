import Foundation

/// A person this operator has cleared before, kept apart from any one charter.
///
/// A charter base runs the same skippers all season, and every trip asked for
/// the same passport again: the photograph, the upload, the seven fields. Worse
/// than repetition — the previous copy was erased along with the trip it
/// belonged to, so the work was repeated from nothing. This record is where a
/// person outlives a charter.
///
/// It holds what was confirmed, and a copy of the scan those values were
/// confirmed against, in a folder of the library's own. The copy matters: a
/// remembered set of fields with no document behind it would put a name on a
/// crew list that nobody could check against anything, which is the one thing
/// this app does not do. `CrewStore.addFromCrewLibrary` brings the scan onto
/// the new trip with the fields, and every field arrives waiting to be
/// confirmed exactly as an imported one does.
struct SavedCrewMember: Codable, Identifiable, Hashable {
    var id = UUID()

    /// The crew-list values as they were last confirmed, keyed by
    /// `CrewField.rawValue` — the same shape `CrewDocument.fields` uses, so a
    /// saved person and a document are the same seven answers.
    var fields: [String: String] = [:]

    /// The library's own sealed copy of the scan, in `crew/`. Never the file a
    /// trip's document points at: deleting the trip shreds that one, and the
    /// library must survive the end of a season.
    var encryptedFileName: String = ""

    /// What this person usually is aboard. A library that is mostly skippers
    /// has to remember which of them are.
    var role: CrewRole = .skipper

    /// Only the skipper's is asked for or printed, and it follows them here for
    /// the same reason it lives on the assignment: naming a returning skipper
    /// brings their address with them instead of leaving the last one on the
    /// form.
    var email: String = ""

    /// When every crew-list field on this person was last confirmed against
    /// the scan, or nil if they were kept mid-review.
    ///
    /// Optional deliberately, and it is not decoration: the review pane of a
    /// document added from here says where its values came from, and "confirmed
    /// on 3 August" about a half-checked record would be the app vouching for
    /// something nobody vouched for. Nil says so instead.
    var confirmedAt: Date?

    /// The last time this person was put on a charter. What the library sorts
    /// its recently-used end by, and the only thing here that is about the
    /// operator's habits rather than about the person.
    var lastUsedAt: Date?

    subscript(field: CrewField) -> String { fields[field.rawValue] ?? "" }

    var fullName: String { self[.fullName] }
    var documentNumber: String { self[.documentNumber] }
    var nationality: String { self[.nationality] }

    /// What the library list calls this person. A saved entry always has one of
    /// the two, because `CrewStore.keepInCrewLibrary` refuses to make one that
    /// has neither.
    var displayName: String {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? documentNumber : name
    }

    /// Two entries are the same person when the passport is the same one.
    ///
    /// The number rather than the name: people marry, and a library that made a
    /// second row for NAKAMURA-JONES would leave the operator picking between
    /// two entries for one person with only a date to tell them apart. A saved
    /// entry with no number at all falls back to the name, which is the only
    /// other thing there is.
    func isSamePerson(as other: SavedCrewMember) -> Bool {
        let mine = Self.key(number: documentNumber, name: fullName)
        return !mine.isEmpty && mine == Self.key(number: other.documentNumber, name: other.fullName)
    }

    static func key(number: String, name: String) -> String {
        let number = number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard number.isEmpty else { return "no:\(number)" }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return name.isEmpty ? "" : "nm:\(name)"
    }
}

extension SavedCrewMember {
    /// Decoded by hand, like every other persisted type here: a key absent from
    /// an older payload uses the property's default rather than throwing
    /// `keyNotFound` and taking the record with it.
    ///
    /// Identity is never invented — `id` and the file name are what join this
    /// entry to the scan on disk, and a fabricated one would leave a sealed
    /// passport photograph in `crew/` that nothing points at and nothing can
    /// delete.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fields = (try? container.decode([String: String].self, forKey: .fields)) ?? [:]
        encryptedFileName = (try? container.decode(String.self, forKey: .encryptedFileName)) ?? ""
        // Passenger is the safe direction here as it is on an assignment: a
        // crew list naming the wrong person as master of the vessel is worse
        // than one an operator has to correct.
        role = (try? container.decode(CrewRole.self, forKey: .role)) ?? .passenger
        email = (try? container.decode(String.self, forKey: .email)) ?? ""
        confirmedAt = try? container.decodeIfPresent(Date.self, forKey: .confirmedAt)
        lastUsedAt = try? container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }
}
