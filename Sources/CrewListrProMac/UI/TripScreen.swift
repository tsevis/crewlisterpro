import SwiftUI

/// Which yacht, and when.
///
/// The yacht's own details moved to the Fleet, where a vessel is described once
/// and reused: a registration number is a fact about the boat, not about this
/// August's charter, and four fields retyped per trip is four chances a season
/// to send a port authority the wrong one. What is left here is the pair of
/// decisions that really do belong to a charter — which yacht it is for, and
/// the dates it sails.
///
/// A screen rather than a sheet, and so it saves as you go rather than
/// collecting an edit behind Cancel and Save. A modal asks "are you sure";
/// a screen just holds what is true.
struct TripScreen: View {
    @Environment(CrewStore.self) private var store

    /// Opens this yacht in the Fleet. The four printed values are editable in
    /// exactly one place, and this is the way there from a charter.
    let onEditYacht: (UUID) -> Void

    @State private var trip: Trip?
    @State private var loadedTripID: Trip.ID?
    @State private var pendingRestore: SecureStore.Backup?

    /// What the last "Save a Version Now" did. A snapshot is skipped when
    /// nothing has changed, and without this the button looks broken to
    /// someone who pressed it precisely because they were worried.
    @State private var snapshotResult: SnapshotResult?
    @State private var snapshotMessageID = 0

    enum SnapshotResult {
        case saved
        case alreadyCurrent

        var message: String {
            switch self {
            case .saved: "Version saved"
            case .alreadyCurrent: "Already saved — nothing has changed"
            }
        }

        var symbol: String {
            switch self {
            case .saved: "checkmark.circle.fill"
            case .alreadyCurrent: "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        DocumentGrid {
            VStack(spacing: 0) {
                PanelHeader(eyebrow: "Trip details", title: "Yacht and voyage")

                if store.selectedTripID == nil {
                    PhilonEmptyState(
                        symbol: "calendar.badge.plus",
                        title: "No trip selected",
                        message: "Pick a yacht from the strip above, or start a charter from the Fleet."
                    )
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        yacht

                        if let current = trip {
                            FormSection(title: "Voyage") {
                                datePicker("Departure", selection: Binding(
                                    get: { current.departureDate },
                                    set: { pickDeparture($0) }
                                ), range: nil)
                                FormRule()
                                datePicker("Return", selection: Binding(
                                    get: { current.returnDate },
                                    set: { pickReturn($0) }
                                ), range: current.departureDate...)
                                FormRule()
                                FormRow(label: "Boarding time") {
                                    CommitField(placeholder: "08:00", value: current.embarkationTime) { value in
                                        store.setEmbarkationTime(value, onTripWith: current.id)
                                    }
                                    .frame(maxWidth: 90)
                                }
                                FormRule()
                                FormRow(label: "Boarding port") {
                                    CommitField(placeholder: "PIRAEUS", value: current.embarkationPort,
                                                normalise: { $0.uppercased() }) { value in
                                        store.setEmbarkationPort(value, onTripWith: current.id)
                                    }
                                    .frame(maxWidth: 220)
                                }
                                FormRule()
                                FormCaption("New trips already run \(charterRhythm). Moving the departure moves the return with it and keeps the charter the same length; pick a return date to override that. Boarding time and port go on the passenger manifest.")
                            }
                        }

                        snapshots
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
        trip = store.selectedTrip
    }

    private var charterRhythm: String {
        let day = AppSettings.weekdayName(store.settings.charterStartWeekday)
        let days = store.settings.charterLengthDays
        return days == 7 ? "\(day) to \(day)" : "\(days) days from a \(day)"
    }

    /// Takes a checkpoint, and says what happened. A snapshot is skipped when
    /// nothing has changed, and a button that silently does nothing reads as
    /// broken to the person who pressed it precisely because they were worried.
    private func saveAVersion() {
        Task {
            let written = await store.takeSnapshot()
            snapshotMessageID += 1
            let shownFor = snapshotMessageID
            withAnimation(.easeOut(duration: 0.16)) {
                snapshotResult = written ? .saved : .alreadyCurrent
            }
            // Clears itself, and only if no later press has replaced it.
            try? await Task.sleep(for: .seconds(4))
            if snapshotMessageID == shownFor {
                withAnimation(.easeOut(duration: 0.2)) { snapshotResult = nil }
            }
        }
    }

    /// Both go through the store rather than mutating the local copy, because
    /// the store is where the day is normalised and where the return is carried
    /// along — and the local copy is then re-read so the pickers show what was
    /// actually stored rather than what was asked for.
    private func pickDeparture(_ date: Date) {
        guard let id = trip?.id else { return }
        store.setDepartureDate(date, onTripWith: id)
        trip = store.data.trips.first { $0.id == id }
    }

    private func pickReturn(_ date: Date) {
        guard let id = trip?.id else { return }
        store.setReturnDate(date, onTripWith: id)
        trip = store.data.trips.first { $0.id == id }
    }

    // MARK: - The yacht

    /// Which yacht this charter is for, and a plain reading of what its four
    /// values will print. Read-only on purpose: they are edited in the Fleet,
    /// where changing them changes the vessel rather than this one booking.
    private var yacht: some View {
        FormSection(title: "Yacht") {
            FormRow(label: "Yacht") {
                Picker("Yacht", selection: Binding(
                    get: { trip?.boatID },
                    set: { pickYacht($0) }
                )) {
                    ForEach(store.fleet) { boat in
                        Text(boat.displayName).tag(Optional(boat.id))
                    }
                    // A retired yacht is not offered, but a charter already made
                    // for one has to keep saying which yacht it was.
                    if let current = store.selectedBoat, current.isRetired {
                        Divider()
                        Text("\(current.displayName) (retired)").tag(Optional(current.id))
                    }
                }
                .labelsHidden()
                .font(Theme.Font.body)
                .frame(maxWidth: 260)

                if let boatID = trip?.boatID {
                    Button("Edit in Fleet") { onEditYacht(boatID) }
                        .buttonStyle(.philonQuiet)
                        .font(Theme.Font.meta)
                }
            }

            FormRule()

            FormRow(label: "Prints as") {
                Text(printedHeader)
                    .font(Theme.Font.support)
                    .foregroundStyle(store.selectedBoat?.isComplete == true ? Theme.ink : Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FormRule()

            FormCaption("These four values are printed in the header boxes of the crew list a port authority receives. They belong to the yacht, so correcting one in the Fleet corrects every crew list made for it.")
        }
    }

    /// The header boxes as one line, so a missing flag or registration number
    /// is visible from the trip without opening the Fleet.
    private var printedHeader: String {
        guard let boat = store.selectedBoat else { return "No yacht on this trip." }
        let values = [
            boat.isComplete ? boat.name : "no name",
            boat.flag.isEmpty ? "no flag" : boat.flag,
            boat.registrationPort.isEmpty ? "no port of registry" : boat.registrationPort,
            boat.registrationNumber.isEmpty ? "no registration no." : boat.registrationNumber,
        ]
        return values.joined(separator: "  ·  ")
    }

    private func pickYacht(_ boatID: UUID?) {
        guard let boatID, var updated = trip, updated.boatID != boatID else { return }
        updated.boatID = boatID
        store.updateTrip(updated)
        trip = store.data.trips.first { $0.id == updated.id }
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
        .overlay(alignment: .topTrailing) {
            // Deliberately on the section's header line rather than a row of
            // its own: it is the one action here that belongs to no particular
            // version, and it was otherwise reachable only from the CLI.
            HStack(spacing: 8) {
                if let snapshotResult {
                    Label(snapshotResult.message, systemImage: snapshotResult.symbol)
                        .font(Theme.Font.meta)
                        .foregroundStyle(Theme.inkSecondary)
                        .labelStyle(.titleAndIcon)
                        .transition(.opacity)
                }

                Button("Save a Version Now") { saveAVersion() }
                    .buttonStyle(.philonQuiet)
                    .font(Theme.Font.meta)
            }
            .offset(y: -3)
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
        FormSection(title: title) { content() }
    }

    private var rule: some View { FormRule() }

    private func datePicker(_ label: String, selection: Binding<Date>, range: PartialRangeFrom<Date>?) -> some View {
        FormRow(label: label) {
            Group {
                if let range {
                    DatePicker(label, selection: selection, in: range, displayedComponents: .date)
                } else {
                    DatePicker(label, selection: selection, displayedComponents: .date)
                }
            }
            .labelsHidden()
            .font(Theme.Font.body)
        }
    }
}
