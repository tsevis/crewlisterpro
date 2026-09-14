import SwiftUI

/// Every yacht this operator charters, described once.
///
/// Name, flag, port of registry and registration number are facts about the
/// vessel and not about this August's booking, so they live on the yacht and
/// are read by every crew list made for it — instead of being retyped per trip
/// with four fresh chances a season to send a port authority the wrong
/// registration number.
struct FleetScreen: View {
    @Environment(CrewStore.self) private var store
    @State private var showingRetired = false

    var body: some View {
        NavigationStack {
            Group {
                if store.fleet.isEmpty, !showingRetired {
                    PhilonEmptyState(
                        symbol: "sailboat",
                        title: "No yachts yet",
                        message: "A charter needs a vessel. Add the boat once and every crew list made for it prints the same four registration values."
                    ) {
                        Button("Add Yacht") { store.addBoat() }
                            .buttonStyle(.philonPrimary)
                    }
                } else {
                    list
                }
            }
            .background(Theme.ground)
            .navigationTitle("Fleet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { store.addBoat() } label: { Label("Add Yacht", systemImage: "plus") }
                        Toggle(isOn: $showingRetired) { Label("Show Retired", systemImage: "archivebox") }
                        if !store.fleet.isEmpty { EditButton() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(store.fleet) { boat in
                    NavigationLink { FleetDetailScreen(boatID: boat.id) } label: { BoatRow(boat: boat) }
                }
                // Drag to reorder. The boat chartered every week does not belong
                // below one that goes out twice a season because of the letter
                // it starts with.
                .onMove { store.moveFleet(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("In the fleet")
            } footer: {
                Text("Drag to reorder. A new charter takes the yacht you chartered last — there is deliberately no default yacht to keep in step with a fleet that changes.")
            }

            if showingRetired, !store.retiredFleet.isEmpty {
                Section {
                    ForEach(store.retiredFleet) { boat in
                        NavigationLink { FleetDetailScreen(boatID: boat.id) } label: { BoatRow(boat: boat) }
                    }
                } header: {
                    Text("Retired")
                } footer: {
                    Text("Retiring takes a sold yacht out of the picker while leaving it named on its past crew lists — a charter can be queried long after it sailed.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct BoatRow: View {
    @Environment(CrewStore.self) private var store
    let boat: Boat

    /// The registered name only when it is not already the title.
    ///
    /// `displayName` is the nickname when there is one and the registered name
    /// when there is not, so repeating `name` underneath printed "S/Y ELPIDA"
    /// twice on every row in a fleet nobody has nicknamed — which is most of
    /// them.
    private var subtitle: String {
        guard boat.isComplete else { return "Needs a registered name before it can print" }
        var parts: [String] = []
        if boat.displayName != boat.name { parts.append(boat.name) }
        parts.append(contentsOf: [boat.flag, boat.registrationNumber].filter { !$0.isEmpty })
        return parts.isEmpty ? "No flag or registration number yet" : parts.joined(separator: "  ·  ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(boat.displayName)
                    .font(Theme.Font.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(Theme.Font.meta)
                    .foregroundStyle(boat.isComplete ? Theme.inkSecondary : Theme.caution)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            let trips = store.tripCount(forBoatID: boat.id)
            if trips > 0 {
                Text("\(trips) charter\(trips == 1 ? "" : "s")")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One yacht: the four values that print across the top of its crew lists, what
/// the operator calls it, and what can be done with it.
struct FleetDetailScreen: View {
    @Environment(CrewStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let boatID: UUID
    @State private var confirmingDelete = false

    private var boat: Boat? { store.boat(withID: boatID) }

    var body: some View {
        Group {
            if let boat {
                form(boat)
            } else {
                PhilonEmptyState(symbol: "sailboat", title: "This yacht is gone",
                                 message: "It was deleted while this screen was open.")
            }
        }
        .background(Theme.ground)
        .navigationTitle(boat?.displayName ?? "Yacht")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func form(_ boat: Boat) -> some View {
        List {
            Section {
                field("Registered name", boat.name, placeholder: Boat.placeholderName, uppercased: true) {
                    var updated = boat; updated.name = $0; store.updateBoat(updated)
                }
                field("Flag", boat.flag, placeholder: "GRC", uppercased: true) {
                    var updated = boat; updated.flag = $0; store.updateBoat(updated)
                }
                field("Port of registry", boat.registrationPort, placeholder: "PIRAEUS", uppercased: true) {
                    var updated = boat; updated.registrationPort = $0; store.updateBoat(updated)
                }
                field("Registration no.", boat.registrationNumber, placeholder: "GR-1187-P", uppercased: true) {
                    var updated = boat; updated.registrationNumber = $0; store.updateBoat(updated)
                }
            } header: {
                Text("What prints on the crew list")
            } footer: {
                Text("These four values fill the boxes across the top of every crew list made for this yacht. A blank one prints blank.")
            }

            Section {
                field("Your name for it", boat.nickname, placeholder: "the blue one", uppercased: false) {
                    var updated = boat; updated.nickname = $0; store.updateBoat(updated)
                }
            } footer: {
                Text("Shown everywhere in the app. The registered name above is what prints — a port authority reads that one out of the header box.")
            }

            Section {
                Button {
                    store.duplicateBoat(boat.id)
                } label: {
                    Label("Duplicate as a Sister Ship", systemImage: "square.on.square")
                }
                Button {
                    boat.isRetired ? store.restoreBoat(boat.id) : store.retireBoat(boat.id)
                } label: {
                    Label(boat.isRetired ? "Return to the Fleet" : "Retire", systemImage: boat.isRetired ? "arrow.uturn.backward" : "archivebox")
                }
                Button("Delete This Yacht", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("A duplicate is everything but the name and the registration number. Deleting is refused while any charter still points at this yacht.")
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog("Delete this yacht?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if store.deleteBoat(boat.id) { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let trips = store.tripCount(forBoatID: boat.id)
            let documents = store.documentCount(forBoatID: boat.id)
            Text(trips == 0
                 ? "This yacht is on no charters."
                 : "This yacht is on \(trips) charter\(trips == 1 ? "" : "s") holding \(documents) encrypted document\(documents == 1 ? "" : "s"). Deleting it deletes those too, and cannot be undone.")
        }
    }

    /// A committed field: what was typed reaches the store when the field is
    /// left, not on every keystroke, so a half-typed registration number is
    /// never what the crew list would print.
    @ViewBuilder
    private func field(_ label: String, _ value: String, placeholder: String,
                       uppercased: Bool, onCommit: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Theme.Font.meta).foregroundStyle(Theme.inkSecondary)
            CommitTextField(placeholder: placeholder, value: value, uppercased: uppercased, onCommit: onCommit)
        }
        .padding(.vertical, 2)
    }
}

/// A text field that commits when it is left rather than on every keystroke.
///
/// `CommitField` in the shared design language does this on a Mac, where
/// "leaving" is a click elsewhere. On a phone it is the keyboard going away, so
/// this is the same contract written for the other gesture.
struct CommitTextField: View {
    let placeholder: String
    let value: String
    var uppercased = false
    /// Right-aligned when this is the *value* half of a labelled row, which is
    /// where iOS puts a value; left-aligned when it is a field with its own
    /// label above it.
    var alignment: TextAlignment = .leading
    let onCommit: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft,
                  prompt: Text(placeholder).foregroundStyle(Theme.inkTertiary))
            .font(Theme.Font.body)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .textInputAutocapitalization(uppercased ? .characters : .sentences)
            .autocorrectionDisabled(uppercased)
            .submitLabel(.done)
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onChange(of: value) { _, newValue in if !focused { draft = newValue } }
            .onAppear { draft = value }
    }

    private func commit() {
        let typed = uppercased
            ? draft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            : draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != value else { draft = value; return }
        onCommit(typed)
        draft = typed
    }
}
