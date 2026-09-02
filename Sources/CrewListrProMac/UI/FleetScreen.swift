import SwiftUI

/// The yachts this operator charters, and the four values printed across the
/// top of every crew list made for one.
///
/// Before this, a yacht existed only inside the trip it was typed into: an
/// operator running the same six boats all season retyped a name, a flag, a
/// port of registry and a registration number six times a week, and a typo in
/// any of them reached a port authority. A vessel's registration is a fact
/// about the vessel, so it is held once and read by every charter that names it.
///
/// Two panels: the fleet, and the one yacht being looked at. The same shape as
/// the review pane, because it is the same job — pick a thing on the left,
/// check its fields on the right.
struct FleetScreen: View {
    @Environment(CrewStore.self) private var store
    @Binding var selection: UUID?

    @State private var pendingDeletion: Boat?

    var body: some View {
        DocumentGrid {
            // A fleet with nothing in it does not need two panels: an empty
            // list beside an empty detail pane is the same emptiness twice,
            // with "No yachts yet" written on both halves of it.
            if store.data.boats.isEmpty {
                PhilonEmptyState(
                    symbol: "sailboat",
                    title: "No yachts yet",
                    message: "Add every yacht you charter once. A trip then picks one, and its registration details are printed on the crew list without being retyped."
                ) {
                    Button("Add a Yacht") { add() }
                        .buttonStyle(.philonPrimary)
                }
                .frame(maxWidth: .infinity)
            } else {
            list
                .frame(minWidth: 250, idealWidth: 290, maxWidth: 330)

            GridDivider()

            if let boat = selected {
                FleetDetail(boat: boat, onRetire: { store.retireBoat(boat.id) },
                            onRestore: { store.restoreBoat(boat.id) },
                            onDuplicate: { selection = store.duplicateBoat(boat.id) },
                            onDelete: { pendingDeletion = boat })
                    .frame(maxWidth: .infinity)
            } else {
                PhilonEmptyState(
                    symbol: "sailboat",
                    title: "Select a yacht",
                    message: "Choose a yacht on the left to check or correct what is printed on its crew lists."
                )
                .frame(maxWidth: .infinity)
            }
            }
        }
        .onAppear { if selection == nil { selection = store.fleet.first?.id } }
        .confirmationDialog(
            "Delete this yacht?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let boat = pendingDeletion, store.deleteBoat(boat.id) {
                    selection = store.fleet.first?.id
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(deletionMessage)
        }
    }

    private var selected: Boat? { selection.flatMap(store.boat(withID:)) }

    /// Says what will actually happen. The dialog used to assert "No trip uses
    /// it" for whatever yacht was right-clicked, including one carrying six
    /// charters — a destructive confirmation stating something false.
    private var deletionMessage: String {
        guard let boat = pendingDeletion else { return "" }
        let trips = store.tripCount(forBoatID: boat.id)
        guard trips == 0 else {
            return "\(boat.name) is used by \(trips) trip\(trips == 1 ? "" : "s") and cannot be deleted. Retire it instead: a retired yacht leaves the fleet and keeps its past crew lists."
        }
        return "\(boat.name) is removed from the fleet. No trip uses it, so no crew list changes. To take a yacht out of the fleet while keeping its past charters, retire it instead."
    }

    private func add() {
        let id = store.addBoat()
        selection = id
    }

    // MARK: - The fleet

    private var list: some View {
        VStack(spacing: 0) {
            // No count badge: the title already reads "2 yachts", and a badge
            // beside it saying 2 is the same fact twice.
            PanelHeader(eyebrow: "Fleet", title: title)

            List(selection: $selection) {
                ForEach(store.fleet) { row($0) }

                if !store.retiredFleet.isEmpty {
                    Section {
                        ForEach(store.retiredFleet) { row($0) }
                    } header: {
                        Text("Retired")
                            .font(Theme.Font.eyebrow)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, MakersMark.reservedHeight, for: .scrollContent)
        }
        .background(Theme.panelRecessed)
    }

    private var title: String {
        let count = store.fleet.count
        guard count > 0 else { return "No yachts yet" }
        return count == 1 ? "1 yacht" : "\(count) yachts"
    }

    private func row(_ boat: Boat) -> some View {
        FleetRow(
            boat: boat,
            trips: store.tripCount(forBoatID: boat.id),
            isDefault: store.settings.defaultBoatID == boat.id,
            isSelected: selection == boat.id
        )
        .tag(boat.id)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .contextMenu {
            Button("Use for New Trips") { setDefault(boat.id) }
                .disabled(boat.isRetired || store.settings.defaultBoatID == boat.id)
            Button("Duplicate") { selection = store.duplicateBoat(boat.id) }
            Divider()
            if boat.isRetired {
                Button("Return to Fleet") { store.restoreBoat(boat.id) }
            } else {
                Button("Retire") { store.retireBoat(boat.id) }
            }
            Button("Delete…", role: .destructive) { pendingDeletion = boat }
                .disabled(store.tripCount(forBoatID: boat.id) > 0)
        }
    }

    private func setDefault(_ id: UUID?) {
        var settings = store.settings
        settings.defaultBoatID = id
        store.updateSettings(settings)
    }
}

// MARK: - One yacht in the list

private struct FleetRow: View {
    let boat: Boat
    let trips: Int
    let isDefault: Bool
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sailboat")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Theme.accentText : Theme.inkTertiary)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(boat.isComplete ? boat.name : "Untitled yacht")
                        .font(Theme.Font.bodyEmphasis)
                        .foregroundStyle(boat.isComplete ? Theme.ink : Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isDefault {
                        Tag(text: "DEFAULT")
                    }
                }

                Text(subtitle)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .opacity(boat.isRetired ? 0.6 : 1)
        .philonInset(highlighted: isSelected)
    }

    /// What distinguishes one yacht from another at a glance: where it is
    /// registered, and how much of this operator's season it carries.
    private var subtitle: String {
        let registry = [boat.flag, boat.registrationNumber].filter { !$0.isEmpty }.joined(separator: " · ")
        let charters = trips == 0 ? "No trips" : "\(trips) trip\(trips == 1 ? "" : "s")"
        return registry.isEmpty ? charters : "\(registry) · \(charters)"
    }
}

/// A small uppercase marker. Used where a row needs one word of status that is
/// not worth a whole column.
private struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.eyebrow)
            .tracking(0.4)
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
    }
}
