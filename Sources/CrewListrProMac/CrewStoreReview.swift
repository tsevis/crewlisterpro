import Foundation

/// Reviewing what was read off a document, and saying who each person is on
/// this trip.
///
/// Split out of `CrewStore` when that file passed the size this project holds
/// itself to. Nothing here touches the encrypted store directly — every method
/// edits `data` and calls `persist()`, exactly as it did inline — which is what
/// makes this a seam rather than a cut.
@MainActor
extension CrewStore {

    func setField(_ field: CrewField, to value: String, on documentID: UUID) {
        guard let index = data.documents.firstIndex(where: { $0.id == documentID }) else { return }
        data.documents[index][field] = value
        syncPerson(from: data.documents[index])
        persist()
    }

    func setVerified(_ verified: Bool, field: CrewField, on documentID: UUID) {
        guard let index = data.documents.firstIndex(where: { $0.id == documentID }) else { return }
        // A field that fails validation cannot be marked correct.
        if verified, data.documents[index].validation(of: field).isBlocking { return }
        if verified { data.documents[index].verifiedFields.insert(field.rawValue) }
        else { data.documents[index].verifiedFields.remove(field.rawValue) }
        refreshRisk(at: index)
        persist()
    }

    /// Confirms every field that currently passes validation.
    func verifyAllValidFields(on documentID: UUID) {
        guard let index = data.documents.firstIndex(where: { $0.id == documentID }) else { return }
        for field in CrewField.allCases where !data.documents[index].validation(of: field).isBlocking {
            guard !data.documents[index][field].isEmpty || !field.isRequiredForExport else { continue }
            data.documents[index].verifiedFields.insert(field.rawValue)
        }
        refreshRisk(at: index)
        persist()
    }

    func rejectDocument(_ documentID: UUID, reason: String) {
        guard let index = data.documents.firstIndex(where: { $0.id == documentID }) else { return }
        data.documents[index].risk = .high
        data.documents[index].verifiedFields = []
        data.documents[index].riskReasons = [reason]
        if let person = data.people.firstIndex(where: { $0.id == data.documents[index].personID }) {
            data.people[person].verification = .rejected
        }
        persist()
    }

    func setRole(_ role: CrewRole, forPersonID personID: UUID) {
        guard let tripID = selectedTripID, isAboard(personID, on: tripID) else { return }
        if role == .skipper {
            for index in data.assignments.indices where data.assignments[index].tripID == tripID {
                data.assignments[index].role = data.assignments[index].personID == personID ? .skipper : .passenger
            }
        } else if let index = data.assignments.firstIndex(where: { $0.tripID == tripID && $0.personID == personID }) {
            data.assignments[index].role = .passenger
        }
        persist()
    }

    func role(forPersonID personID: UUID) -> CrewRole {
        assignment(forPersonID: personID)?.role ?? .passenger
    }

    // MARK: - The client, and how to reach the skipper

    /// Names the one person on this trip who signs the papers, or clears them.
    ///
    /// Independent of the role on purpose: the client chartered the yacht and
    /// is aboard as either the skipper or a passenger, and `setRole` must
    /// therefore leave this alone. Naming a new client clears the previous one,
    /// the same way naming a skipper demotes the previous — a form with two
    /// signatories says nothing about who is answerable for the vessel.
    func setClient(_ isClient: Bool, forPersonID personID: UUID) {
        guard let tripID = selectedTripID, isAboard(personID, on: tripID) else { return }
        for index in data.assignments.indices where data.assignments[index].tripID == tripID {
            let isThisPerson = data.assignments[index].personID == personID
            if isClient {
                // Naming one names exactly one.
                data.assignments[index].isClient = isThisPerson
            } else if isThisPerson {
                data.assignments[index].isClient = false
            }
        }
        persist()
    }

    func isClient(personID: UUID) -> Bool {
        assignment(forPersonID: personID)?.isClient ?? false
    }

    /// The email address for one person on this trip. Only the skipper's is
    /// asked for in the interface and only the skipper's is printed, but the
    /// address is stored against whoever it was typed for, so promoting a
    /// passenger brings their address with them instead of stranding it.
    func setEmail(_ email: String, forPersonID personID: UUID) {
        guard let tripID = selectedTripID,
              let index = data.assignments.firstIndex(where: { $0.tripID == tripID && $0.personID == personID })
        else { return }
        data.assignments[index].email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func email(forPersonID personID: UUID) -> String {
        assignment(forPersonID: personID)?.email ?? ""
    }

    /// The address printed on the crew list: the current skipper's, and nobody
    /// else's.
    var skipperEmail: String {
        guard let tripID = selectedTripID else { return "" }
        return skipperEmail(forTripID: tripID)
    }

    func skipperEmail(forTripID tripID: UUID) -> String {
        data.assignments.first { $0.tripID == tripID && $0.role == .skipper }?.email ?? ""
    }

    private func assignment(forPersonID personID: UUID) -> CrewAssignment? {
        data.assignments.first { $0.tripID == selectedTripID && $0.personID == personID }
    }

    /// Whether this person has an assignment on this trip.
    ///
    /// Both `setRole` and `setClient` sweep every assignment on the trip to
    /// enforce "exactly one", so a personID that matches none of them would
    /// clear the lot: naming a stranger as client would un-name the real one,
    /// and naming one as skipper would demote the real skipper and block the
    /// export. The rest of the store already treats a missing assignment as
    /// possible — `crewRows` and `role(forPersonID:)` both default it — so
    /// these two must not be the only places that assume it cannot happen.
    private func isAboard(_ personID: UUID, on tripID: UUID) -> Bool {
        data.assignments.contains { $0.tripID == tripID && $0.personID == personID }
    }
}
