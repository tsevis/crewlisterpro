import SwiftUI

/// Yacht and voyage details. `Boat.flag`, `registrationPort` and
/// `registrationNumber` existed in the model but had no way in, so every crew
/// list printed "NEW YACHT" with three blank header boxes.
///
/// A screen rather than a sheet, and so it saves as you type rather than
/// collecting an edit behind Cancel and Save. A modal asks "are you sure";
/// a screen just holds what is true.
struct TripScreen: View {
    @Environment(CrewStore.self) private var store

    @State private var boat = Boat(name: "")
    @State private var trip: Trip?
    @State private var loadedTripID: Trip.ID?
    @State private var pendingRestore: SecureStore.Backup?

    var body: some View {
        DocumentGrid {
            VStack(spacing: 0) {
                PanelHeader(eyebrow: "Trip details", title: "Yacht and voyage")

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section("Yacht") {
                            field("Name", placeholder: "S/Y ELPIDA", text: $boat.name)
                            rule
                            field("Flag", placeholder: "GRC", text: $boat.flag)
                            rule
                            field("Port of registry", placeholder: "PIRAEUS", text: $boat.registrationPort)
                            rule
                            field("Registration no.", placeholder: "GR-1187-P", text: $boat.registrationNumber)
                        }

                        if let current = trip {
                            section("Voyage") {
                                datePicker("Departure", selection: Binding(
                                    get: { current.departureDate },
                                    set: { trip?.departureDate = $0; save() }
                                ), range: nil)
                                rule
                                datePicker("Return", selection: Binding(
                                    get: { current.returnDate },
                                    set: { trip?.returnDate = $0; save() }
                                ), range: current.departureDate...)
                            }
                        }

                        PhilonNote(
                            kind: .verified,
                            message: "These four values are printed in the header boxes of the crew list a port authority receives."
                        )

                        snapshots

                        EarlierVersions()
                    }
                    // Capped for line length, then pushed left: the cap alone
                    // centres the block and leaves it adrift from the header.
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .contentMargins(.bottom, MakersMark.reservedHeight, for: .scrollContent)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: load)
        .onChange(of: store.selectedTripID) { _, _ in load() }
    }

    // MARK: - Loading and saving

    private func load() {
        guard loadedTripID != store.selectedTripID else { return }
        loadedTripID = store.selectedTripID
        boat = store.selectedBoat ?? Boat(name: "")
        trip = store.selectedTrip
        if boat.name == Boat.placeholderName { boat.name = "" }
    }

    /// Normalising on every keystroke would fight the field — uppercasing a
    /// flag as it is typed moves the caret. The value is stored as typed and
    /// squared up when the field gives up focus.
    /// Saves as you type. `CrewStore.updateBoat` refuses a blank name, so an
    /// emptied field cannot overwrite a real one on its way past.
    private func save() {
        store.updateBoat(boat)
        if let trip { store.updateTrip(trip) }
    }

    private func normaliseAndSave() {
        boat.name = boat.name.trimmingCharacters(in: .whitespacesAndNewlines)
        boat.flag = boat.flag.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        boat.registrationPort = boat.registrationPort.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        boat.registrationNumber = boat.registrationNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        save()
    }

    // MARK: - Snapshots

    /// The store keeps the state it replaces on every save. This is the only
    /// place an operator can see that history or step back into it.
    private var snapshots: some View {
        section("Earlier versions") {
            if store.backups.isEmpty {
                Text("No earlier versions yet. One is kept each time this trip changes.")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
            } else {
                ForEach(Array(store.backups.prefix(8).enumerated()), id: \.element.id) { index, backup in
                    if index > 0 { rule }
                    snapshotRow(backup)
                }
            }
        }
        .onAppear { Task { await store.refreshBackups() } }
        .confirmationDialog(
            "Restore this version?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let backup = pendingRestore {
                    Task { await store.restoreBackup(backup.id) }
                }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("""
            This replaces what is on this Mac now with \(pendingRestore.map(CrewStore.describe) ?? "an earlier version").

            What you have now is kept as another version first, so you can step back again.
            """)
        }
    }

    private func snapshotRow(_ backup: SecureStore.Backup) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(backup.created.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Font.support)
                    .foregroundStyle(Theme.ink)
                Text(CrewStore.describe(backup))
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer(minLength: 8)

            Button("Restore") { pendingRestore = backup }
                .buttonStyle(.philonQuiet)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
            VStack(spacing: 0) { content() }.philonInset(radius: Theme.Radius.panel)
        }
    }

    private var rule: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 138)
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.Font.support)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 118, alignment: .trailing)

            FocusAwareField(placeholder: placeholder, text: text, onCommit: normaliseAndSave)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func datePicker(_ label: String, selection: Binding<Date>, range: PartialRangeFrom<Date>?) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.Font.support)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 118, alignment: .trailing)

            Group {
                if let range {
                    DatePicker(label, selection: selection, in: range, displayedComponents: .date)
                } else {
                    DatePicker(label, selection: selection, displayedComponents: .date)
                }
            }
            .labelsHidden()
            .font(Theme.Font.body)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// A text field that reports when it has been left, so the value can be
/// normalised then rather than under the caret.
private struct FocusAwareField: View {
    let placeholder: String
    @Binding var text: String
    let onCommit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                    .strokeBorder(focused ? Theme.accentText.opacity(0.55) : Theme.hairlineStrong, lineWidth: 1)
            )
            .onSubmit(onCommit)
            .onChange(of: focused) { _, isFocused in if !isFocused { onCommit() } }
    }
}
