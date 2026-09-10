import Foundation

/// The crew library: people kept for the next charter, with their scans.
///
/// Split out of `CrewStore` for the same reason the fleet was — everything here
/// is a method over the same `data`, so the class still has one writer and one
/// `persist()`.
@MainActor
extension CrewStore {

    /// Everyone kept, most recently used first and then alphabetically.
    ///
    /// Recency leads because a charter base runs the same three or four
    /// skippers all season and then a long tail of people who came once; an
    /// alphabet buries the four in the tail.
    var crewLibrary: [SavedCrewMember] {
        data.savedCrew.sorted { left, right in
            switch (left.lastUsedAt, right.lastUsedAt) {
            case let (l?, r?) where l != r: return l > r
            case (nil, .some): return false
            case (.some, nil): return true
            default: return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
            }
        }
    }

    func savedCrewMember(withID id: UUID) -> SavedCrewMember? {
        data.savedCrew.first { $0.id == id }
    }

    /// Whether this document's person is already kept.
    func isInCrewLibrary(documentID: UUID) -> Bool {
        guard let document = data.documents.first(where: { $0.id == documentID }) else { return false }
        let key = SavedCrewMember.key(number: document[.documentNumber], name: document[.fullName])
        return !key.isEmpty && data.savedCrew.contains {
            SavedCrewMember.key(number: $0.documentNumber, name: $0.fullName) == key
        }
    }

    // MARK: - Keeping someone

    /// Keeps this document's person for the next charter, scan and all.
    ///
    /// Refuses a document with neither a name nor a number: an entry with
    /// neither cannot be picked out of a list, and re-adding it would put an
    /// empty document on a trip. Anything else is kept — including a passport
    /// whose expiry has passed, which is exactly the record an operator wants
    /// on hand when the renewed one arrives.
    @discardableResult
    func keepInCrewLibrary(documentID: UUID) async -> Bool {
        guard let document = data.documents.first(where: { $0.id == documentID }) else { return false }
        guard !SavedCrewMember.key(number: document[.documentNumber], name: document[.fullName]).isEmpty else {
            errorMessage = "This document has neither a name nor a document number yet. Confirm at least one of them before keeping the person for later — the library is a list you pick from, and there would be nothing to pick."
            return false
        }
        guard let secureStore else { return false }

        let assignment = data.assignments.first { $0.personID == document.personID && $0.tripID == document.tripID }
        var saved = SavedCrewMember(
            fields: document.fields,
            role: assignment?.role ?? .passenger,
            email: assignment?.email ?? "",
            // Only a document whose every crew-list field is confirmed can
            // claim a confirmation date. Keeping someone mid-review is allowed
            // — the typing is still saved — but the entry must not say a person
            // checked what a person has not checked.
            confirmedAt: document.canExport() ? .now : nil
        )

        // A person with no scan is still worth keeping — their fields save the
        // typing — so a failed copy is not a failed save. It is announced,
        // because the next charter will ask for the photograph again and the
        // operator should know why.
        if !document.encryptedFileName.isEmpty {
            do {
                saved.encryptedFileName = try await secureStore.keepInCrewLibrary(originalNamed: document.encryptedFileName)
            } catch {
                errorMessage = "\(saved.displayName) was kept, but their scan could not be copied into the library: \(error.localizedDescription)"
            }
        }

        // The same passport kept twice is one person. The newer confirmation
        // wins, and the older scan is erased rather than left in `crew/` with
        // nothing pointing at it.
        if let existing = data.savedCrew.first(where: { $0.isSamePerson(as: saved) }) {
            saved.id = existing.id
            saved.lastUsedAt = existing.lastUsedAt
            if !existing.encryptedFileName.isEmpty, existing.encryptedFileName != saved.encryptedFileName {
                await secureStore.deleteCrewOriginals(named: [existing.encryptedFileName])
            }
            data.savedCrew = data.savedCrew.map { $0.id == existing.id ? saved : $0 }
        } else {
            data.savedCrew.append(saved)
        }
        persist()
        return true
    }

    /// Corrects a kept person's details in place. The library is a list of
    /// facts about people, and a renewed passport is a correction to one.
    func updateSavedCrewMember(_ saved: SavedCrewMember) {
        guard let index = data.savedCrew.firstIndex(where: { $0.id == saved.id }) else { return }
        data.savedCrew[index] = saved
        persist()
    }

    // MARK: - Using someone again

    /// Puts a kept person on a trip: their confirmed fields, their scan, and
    /// the role they usually take.
    ///
    /// Every field arrives **unconfirmed**, deliberately. The saving here is
    /// the upload, not the checking — a crew list is a document an operator has
    /// looked at, and "they were confirmed in April" is not that. The pane says
    /// where the values came from and when they were last confirmed, so the
    /// checking is a glance rather than a re-typing.
    @discardableResult
    func addFromCrewLibrary(_ savedID: UUID, toTripWith tripID: UUID? = nil) async -> Bool {
        guard let saved = savedCrewMember(withID: savedID) else { return false }
        guard let tripID = tripID ?? selectedTripID, data.trips.contains(where: { $0.id == tripID }) else {
            errorMessage = "Create or select a trip before adding someone from the crew library."
            return false
        }
        let key = SavedCrewMember.key(number: saved.documentNumber, name: saved.fullName)
        guard !data.documents.contains(where: {
            $0.tripID == tripID && SavedCrewMember.key(number: $0[.documentNumber], name: $0[.fullName]) == key
        }) else {
            errorMessage = "\(saved.displayName) is already on this trip."
            return false
        }
        guard let secureStore else { return false }

        var person = CrewPerson(fullName: saved.fullName, nationality: saved.nationality)
        person.birthDate = CrewFieldValidator.isoDate(saved[.birthDate])

        var document = CrewDocument(
            tripID: tripID,
            personID: person.id,
            originalName: "\(saved.displayName) (crew library)",
            encryptedFileName: "",
            documentNumber: saved.documentNumber,
            documentType: saved[.documentType].isEmpty ? "unknown" : saved[.documentType],
            risk: .review,
            riskReasons: [Self.libraryProvenance(saved)],
            fields: saved.fields
        )

        if !saved.encryptedFileName.isEmpty {
            do {
                document.encryptedFileName = try await secureStore.takeFromCrewLibrary(
                    named: saved.encryptedFileName, documentID: document.id)
            } catch {
                // Without the scan there is nothing to check the fields
                // against, and this app does not put a name on a crew list
                // that nobody can check. Better to say so than to add a row
                // that can never be cleared.
                errorMessage = "\(saved.displayName)'s scan could not be read from the crew library, so they were not added: \(error.localizedDescription)"
                return false
            }
        }

        data.people.append(person)
        data.documents.append(document)
        data.assignments.append(CrewAssignment(tripID: tripID, personID: person.id,
                                               role: role(saved.role, canTakeOn: tripID),
                                               email: saved.email))
        if let index = data.savedCrew.firstIndex(where: { $0.id == saved.id }) {
            data.savedCrew[index].lastUsedAt = .now
        }
        selectedTripID = tripID
        selectedDocumentID = document.id
        persist()
        return true
    }

    /// A crew list needs exactly one skipper, and the library remembers several
    /// people as skippers. The first one aboard keeps the role; anyone after
    /// them joins as a passenger rather than silently demoting the person
    /// already named.
    private func role(_ wanted: CrewRole, canTakeOn tripID: UUID) -> CrewRole {
        guard wanted == .skipper else { return wanted }
        let taken = data.assignments.contains { $0.tripID == tripID && $0.role == .skipper }
        return taken ? .passenger : .skipper
    }

    /// What the review pane says about a document that came from the library.
    private static func libraryProvenance(_ saved: SavedCrewMember) -> String {
        guard let confirmed = saved.confirmedAt else {
            return "From the crew library, where they were kept before every field had been confirmed. Check all of them against the scan."
        }
        return "From the crew library — these values were confirmed against this scan on \(VoyageDate.printed(confirmed)). Check them again before export."
    }

    // MARK: - Forgetting someone

    /// Removes a kept person and erases the library's copy of their scan.
    func removeFromCrewLibrary(_ savedID: UUID) async {
        guard let saved = savedCrewMember(withID: savedID) else { return }
        if !saved.encryptedFileName.isEmpty, let secureStore {
            await secureStore.deleteCrewOriginals(named: [saved.encryptedFileName])
        }
        data.savedCrew.removeAll { $0.id == savedID }
        persist()
    }

    /// The kept scan, for the pane that shows it. Nil when the entry was saved
    /// without one, or its file has gone.
    func crewLibraryImageData(for saved: SavedCrewMember) async -> Data? {
        guard let secureStore, !saved.encryptedFileName.isEmpty else { return nil }
        return try? await secureStore.readCrewOriginal(named: saved.encryptedFileName)
    }
}
