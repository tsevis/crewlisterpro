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
                        .accessibilityIdentifier("fleet.add")
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

    /// Says what will actually happen, counted rather than asserted.
    ///
    /// Deleting a yacht now takes its charters and their passport scans with
    /// it, so this is the last thing between an operator and erased identity
    /// documents. It names the numbers, and it names Retire — which is what
    /// most people reaching for Delete on a sold yacht actually want.
    private var deletionMessage: String {
        guard let boat = pendingDeletion else { return "" }
        let trips = store.tripCount(forBoatID: boat.id)
        guard trips > 0 else {
            return "\(boat.displayName) is removed from the fleet. No trip uses it, so no crew list changes."
        }
        let documents = store.documentCount(forBoatID: boat.id)
        let scans = documents == 0
            ? "no documents"
            : "\(documents) encrypted document\(documents == 1 ? "" : "s")"
        return """
        \(boat.displayName) is removed from the fleet, and so are the \(trips) trip\(trips == 1 ? "" : "s") made for it and their \(scans). The passport scans are erased from this Mac and cannot be recovered.

        To take a yacht out of the fleet while keeping its past charters, retire it instead.
        """
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
                // `.onMove` and nothing else: the order in this list is the
                // order the app uses everywhere, so dragging a row is the
                // whole of the reordering interface.
                ForEach(store.fleet) { row($0) }
                    .onMove { store.moveFleet(fromOffsets: $0, toOffset: $1) }

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
            isSelected: selection == boat.id
        )
        .tag(boat.id)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .contextMenu {
            Button("Duplicate") { selection = store.duplicateBoat(boat.id) }
            Divider()
            if boat.isRetired {
                Button("Return to Fleet") { store.restoreBoat(boat.id) }
            } else {
                Button("Retire") { store.retireBoat(boat.id) }
            }
            Button("Delete…", role: .destructive) { pendingDeletion = boat }
        }
    }
}

// MARK: - One yacht in the list

private struct FleetRow: View {
    let boat: Boat
    let trips: Int
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sailboat")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Theme.accentText : Theme.inkTertiary)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(boat.displayName)
                    .font(Theme.Font.bodyEmphasis)
                    .foregroundStyle(boat.isComplete || !boat.nickname.isEmpty ? Theme.ink : Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

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
        // The registered name leads when a nickname is standing in front of
        // it: the row still has to answer "which vessel is this on paper".
        let printed = boat.nickname.isEmpty || !boat.isComplete ? nil : boat.name
        let registry = [printed, boat.flag.isEmpty ? nil : boat.flag,
                        boat.registrationNumber.isEmpty ? nil : boat.registrationNumber]
            .compactMap { $0 }
            .joined(separator: " · ")
        let charters = trips == 0 ? "No trips" : "\(trips) trip\(trips == 1 ? "" : "s")"
        return registry.isEmpty ? charters : "\(registry) · \(charters)"
    }
}
