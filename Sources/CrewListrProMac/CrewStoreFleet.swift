import Foundation

/// The fleet: yachts an operator keeps and charters again.
///
/// Split out of `CrewStore` when that file passed the size this project holds
/// itself to. Everything here is a method or a computed property over the same
/// `data`, so it reads exactly as it did inline — the class still has one
/// writer and one `persist()`.
@MainActor
extension CrewStore {

    // MARK: - The fleet
    //
    // Yachts an operator keeps and charters again. `Boat` was always its own
    // record; what was missing was any way to make one, reuse one, or see the
    // ones you have.

    /// The yachts on offer, in the order the operator put them in. Retired ones
    /// are listed separately.
    ///
    /// Not sorted by name any more. An alphabet is a reasonable order for a
    /// list nobody has an opinion about, and a fleet is not that: the boat
    /// chartered every week of the season sat below one that goes out twice a
    /// year because of the letter it starts with, and there was no way to say
    /// so. The stored order *is* the operator's order — `moveFleet` is how it
    /// changes.
    var fleet: [Boat] { data.boats.filter { !$0.isRetired } }

    var retiredFleet: [Boat] { data.boats.filter(\.isRetired) }

    /// Moves yachts within the fleet, from a drag in the fleet list.
    ///
    /// The offsets are positions in `fleet`, which is `data.boats` with the
    /// retired ones taken out — so they are translated back before anything
    /// moves. Reordering the filtered list and writing it back wholesale would
    /// drop every retired yacht in the store.
    func moveFleet(fromOffsets source: IndexSet, toOffset destination: Int) {
        var active = fleet
        guard !active.isEmpty else { return }
        active.move(fromOffsets: source, toOffset: destination)
        // The retired ones keep the slots they already occupy; the active ones
        // are dealt back into the gaps between them, in their new order.
        var reordered = active.makeIterator()
        data.boats = data.boats.map { $0.isRetired ? $0 : (reordered.next() ?? $0) }
        persist()
    }

    func boat(withID id: UUID) -> Boat? { data.boats.first { $0.id == id } }

    /// How many charters name this yacht. What stands between it and deletion.
    func tripCount(forBoatID id: UUID) -> Int {
        data.trips.count { $0.boatID == id }
    }

    /// Adds a yacht, pre-filled from the fleet defaults. Most operators' whole
    /// fleet flies one flag out of one port, and asking for it per yacht is
    /// asking for it every time.
    @discardableResult
    func addBoat(named name: String = Boat.placeholderName) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let boat = Boat(name: trimmed.isEmpty ? Boat.placeholderName : trimmed,
                        flag: settings.defaultFlag,
                        registrationPort: settings.defaultRegistrationPort)
        data.boats.append(boat)
        persist()
        return boat.id
    }

    /// A sister ship: everything but the name and the registration number,
    /// which are the two things no two vessels share.
    @discardableResult
    func duplicateBoat(_ id: UUID) -> UUID? {
        guard let original = boat(withID: id) else { return nil }
        var copy = original
        copy.id = UUID()
        // "NEW YACHT (copy)" is not the placeholder name, so `isComplete` would
        // read true and a crew list would clear port with NEW YACHT (COPY) in
        // its header box. A copy of an unnamed yacht is an unnamed yacht.
        copy.name = original.isComplete ? "\(original.name) (copy)" : Boat.placeholderName
        copy.registrationNumber = ""
        copy.isRetired = false
        data.boats.append(copy)
        persist()
        return copy.id
    }

    func retireBoat(_ id: UUID) { setRetired(true, onBoatWith: id) }
    func restoreBoat(_ id: UUID) { setRetired(false, onBoatWith: id) }

    private func setRetired(_ retired: Bool, onBoatWith id: UUID) {
        guard let index = data.boats.firstIndex(where: { $0.id == id }),
              data.boats[index].isRetired != retired else { return }
        data.boats[index].isRetired = retired
        // A default the picker no longer offers is a setting that silently does
        // nothing. Clear it rather than leave it pointing into the retired list.
        if retired, data.settings.defaultBoatID == id { data.settings.defaultBoatID = nil }
        persist()
    }

    /// Removes a yacht from the fleet for good. Refuses, and reports so, while
    /// any charter still names it: the four header boxes of those crew lists
    /// are read off this record.
    @discardableResult
    func deleteBoat(_ id: UUID) -> Bool {
        guard tripCount(forBoatID: id) == 0 else {
            errorMessage = "\(boat(withID: id)?.name ?? "This yacht") is used by \(tripCount(forBoatID: id)) trip(s). Delete or archive those first, or retire the yacht instead — a retired yacht keeps its past crew lists."
            return false
        }
        guard data.boats.contains(where: { $0.id == id }) else { return false }
        data.boats.removeAll { $0.id == id }
        if data.settings.defaultBoatID == id { data.settings.defaultBoatID = nil }
        persist()
        return true
    }

    func updateBoat(_ boat: Boat) {
        guard let index = data.boats.firstIndex(where: { $0.id == boat.id }) else { return }
        var updated = boat
        // A blank name is never a value anyone means, in the same way a return
        // before departure never is: the yacht's name is printed in the crew
        // list's header box, and an empty one clears port as "Untitled yacht".
        // The trip editor saves as you type, so an emptied field would
        // otherwise overwrite a real name the moment it lost focus.
        if updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.name = data.boats[index].name
        }
        data.boats[index] = updated
        persist()
    }
}
