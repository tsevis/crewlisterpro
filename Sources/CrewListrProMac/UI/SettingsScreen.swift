import AppKit
import SwiftUI

/// Everything the app decides for you, in one place, with the reasoning beside
/// it.
///
/// Grouped by the moment each setting applies rather than by which part of the
/// code reads it — an operator looking for "our charters run Wednesdays" is
/// thinking about making a trip, not about `VoyageDate`. Every control writes
/// straight through `CrewStore.updateSettings`, which is where values are
/// brought back into range, so there is no Save button and nothing to lose by
/// leaving the screen.
///
/// One section is deliberately about what is *not* here. This app's whole
/// design is that a person confirms every value against the document it came
/// from, and a preference that switched that off would be a preference for a
/// crew list nobody checked.
struct SettingsScreen: View {
    @Environment(CrewStore.self) private var store

    @State private var confirmingReset = false

    private var settings: AppSettings { store.settings }

    var body: some View {
        DocumentGrid {
            VStack(spacing: 0) {
                PanelHeader(eyebrow: "Settings", title: "Defaults for this Mac")

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        newTrips
                        newYachts
                        export
                        localModel
                        storage
                        notSettings
                        reset
                    }
                    .frame(maxWidth: 660, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .contentMargins(.bottom, MakersMark.reservedHeight, for: .scrollContent)
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            await store.refreshLocalModelState()
            // So the row below can say what lowering the cap would discard.
            await store.refreshBackups()
        }
        .confirmationDialog(
            "Restore the shipped defaults?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) { store.updateSettings(AppSettings()) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only the settings on this screen change back. No trip, document, yacht or crew list is touched — but if you keep more than \(AppSettings.defaultVersionsKept) earlier versions, the number goes back to \(AppSettings.defaultVersionsKept) and the oldest are discarded at the next save.")
        }
    }

    /// Writes one change through the store, which normalises it.
    private func edit(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        store.updateSettings(updated)
    }

    // MARK: - New trips

    private var newTrips: some View {
        FormSection(title: "New trips") {
            FormRow(label: "Starts on") {
                Picker("Starts on", selection: Binding(
                    get: { settings.charterStartWeekday },
                    set: { day in edit { $0.charterStartWeekday = day } }
                )) {
                    ForEach(1...7, id: \.self) { Text(AppSettings.weekdayName($0)).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            FormRule()

            FormRow(label: "Runs for") {
                Stepper(value: Binding(
                    get: { settings.charterLengthDays },
                    set: { days in edit { $0.charterLengthDays = days } }
                ), in: 1...AppSettings.longestCharterDays) {
                    Text(settings.charterLengthDays == 1 ? "1 day" : "\(settings.charterLengthDays) days")
                        .font(Theme.Font.body.monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        // A Stepper centres its label in whatever width it is
                        // given, which left this row's value floating while
                        // every row above it started hard against the label.
                        .frame(width: 64, alignment: .leading)
                }
                .fixedSize()
            }

            FormRule()

            FormCaption("A new trip opens on the next \(AppSettings.weekdayName(settings.charterStartWeekday)) — \(nextDeparture) — and returns \(settings.charterLengthDays) day\(settings.charterLengthDays == 1 ? "" : "s") later. Charters in this trade run Saturday to Saturday, which is what an untouched install does.")
        }
    }

    private var nextDeparture: String {
        VoyageDate.printed(VoyageDate.charterWeek(startingOn: settings.charterStartWeekday,
                                                  lastingDays: settings.charterLengthDays).departure)
    }

    // MARK: - New yachts

    private var newYachts: some View {
        FormSection(title: "New yachts") {
            FormRow(label: "Flag") {
                CommitField(placeholder: "GRC", value: settings.defaultFlag,
                            normalise: { $0.uppercased() }) { value in
                    edit { $0.defaultFlag = value }
                }
                .frame(maxWidth: 180)
            }

            FormRule()

            FormRow(label: "Port of registry") {
                CommitField(placeholder: "PIRAEUS", value: settings.defaultRegistrationPort,
                            normalise: { $0.uppercased() }) { value in
                    edit { $0.defaultRegistrationPort = value }
                }
                .frame(maxWidth: 260)
            }

            FormRule()

            FormCaption("Filled into a yacht added to the Fleet, so the details most of a fleet shares are typed once instead of per vessel. Either can be changed on the yacht itself.")
        }
    }

    // MARK: - Export

    private var export: some View {
        FormSection(title: "Export") {
            FormRow(label: "Writes") {
                HStack(spacing: 14) {
                    Toggle("PDF — the printed crew list", isOn: Binding(
                        get: { settings.writesPDF },
                        set: { on in edit { $0.writesPDF = on } }
                    ))
                    Toggle("CSV — for other software", isOn: Binding(
                        get: { settings.writesCSV },
                        set: { on in edit { $0.writesCSV = on } }
                    ))
                }
                .toggleStyle(.checkbox)
                .font(Theme.Font.support)
            }

            FormRule()

            FormRow(label: "File name") {
                CommitField(placeholder: AppSettings.defaultFileNamePrefix, value: settings.fileNamePrefix) { value in
                    edit { $0.fileNamePrefix = value }
                }
                .frame(maxWidth: 180)

                Text(exampleFileName)
                    .font(Theme.Font.monoMeta)
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            FormRule()

            FormRow(label: "Folder") {
                Text(folderLabel)
                    .font(Theme.Font.support)
                    .foregroundStyle(settings.exportFolderPath.isEmpty ? Theme.inkTertiary : Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(settings.exportFolderPath.isEmpty ? "Every export asks" : settings.exportFolderPath)

                Button("Choose…") { chooseExportFolder() }
                    .buttonStyle(.philonQuiet)

                if !settings.exportFolderPath.isEmpty {
                    Button("Ask Each Time") { edit { $0.exportFolderPath = "" } }
                        .buttonStyle(.philonQuiet)
                }
            }

            FormRule()

            FormRow(label: "Afterwards") {
                Toggle("Show the written files in the Finder", isOn: Binding(
                    get: { settings.revealsAfterExport },
                    set: { on in edit { $0.revealsAfterExport = on } }
                ))
                .toggleStyle(.checkbox)
                .font(Theme.Font.support)
            }

            FormRule()

            FormCaption("Asking each time is the default deliberately: an export writes people's identity details to disk, and where that lands is worth a moment's thought. Dates in the PDF are printed as the documents print them; the CSV keeps ISO-8601, because software reads it.")
        }
    }

    /// The trip in hand and its own yacht, so the example is a file this
    /// operator could actually be about to write — not one yacht's name beside
    /// another's departure date.
    private var exampleFileName: String {
        let trip = store.selectedTrip
        let boat = trip.flatMap(store.boat(for:)) ?? store.fleet.first ?? Boat(name: "S/Y ELPIDA")
        let voyage = trip ?? Trip(boatID: boat.id, departureDate: .now, returnDate: .now)
        return "\(ExportService.fileNameStem(boat: boat, trip: voyage, prefix: settings.fileNamePrefix)).pdf"
    }

    private var folderLabel: String {
        guard !settings.exportFolderPath.isEmpty else { return "Ask each time" }
        guard store.standingExportFolder != nil else { return "\(settings.exportFolderPath) — not reachable, exports will ask" }
        return settings.exportFolderPath
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose where exported crew lists are written."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        edit { $0.exportFolderPath = url.path(percentEncoded: false) }
    }

    // MARK: - The local model

    private var localModel: some View {
        FormSection(title: "Local AI model") {
            FormRow(label: "Status") {
                Label(store.localModelIsInstalled ? "Installed" : "Not installed",
                      systemImage: store.localModelIsInstalled ? "checkmark.seal.fill" : "circle.dashed")
                    .font(Theme.Font.support)
                    .foregroundStyle(store.localModelIsInstalled ? Theme.verifiedInk : Theme.inkSecondary)

                if store.localModelIsInstalled {
                    Button("Remove") { Task { await store.removeLocalModel() } }
                        .buttonStyle(.philonQuiet(role: .destructive))
                } else {
                    Button("Download \(store.localModelDescription)") { Task { await store.downloadLocalModel() } }
                        .buttonStyle(.philonSecondary)
                }
            }

            FormRule()

            FormCaption("Optional, and only used on a document whose machine-readable zone cannot be read. It offers the document number and nothing else — measured against real passports, its dates were wrong three times in ten and its names were invented, so those are the operator's to type. A value it suggests is marked as having no check digits behind it.")
        }
    }

    // MARK: - Storage

    private var storage: some View {
        FormSection(title: "Storage on this Mac") {
            FormRow(label: "Earlier versions") {
                Stepper(value: Binding(
                    get: { settings.versionsKept },
                    set: { kept in edit { $0.versionsKept = kept } }
                ), in: AppSettings.fewestVersionsKept...AppSettings.mostVersionsKept, step: 5) {
                    Text("Keep \(settings.versionsKept)")
                        .font(Theme.Font.body.monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .frame(width: 64, alignment: .leading)
                }
                .fixedSize()

                Text(versionsHeld)
                    .font(Theme.Font.meta)
                    .foregroundStyle(store.backups.count > settings.versionsKept ? Theme.caution : Theme.inkTertiary)
            }

            FormRule()

            FormRow(label: "Data folder") {
                Button("Show in Finder") { revealDataFolder() }
                    .buttonStyle(.philonQuiet)

                Text("Encrypted database, sealed originals and earlier versions")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
            }

            FormRule()

            FormCaption("A version is kept each time the database changes, and the oldest fall off beyond the number above — at the next save, not the moment you lower it, so a mis-click is recoverable. They hold identity data, so the history is capped rather than endless: the trade is how far back a mistake can be undone against how long that data stays on this Mac. Step back into one from the Trip screen.")
        }
    }

    /// Says plainly what the number above will cost, rather than leaving the
    /// operator to discover it at the next save.
    private var versionsHeld: String {
        let held = store.backups.count
        guard held > settings.versionsKept else {
            return held == 1 ? "1 kept now" : "\(held) kept now"
        }
        let losing = held - settings.versionsKept
        return "\(held) kept now — the oldest \(losing) will be discarded at the next save"
    }

    private func revealDataFolder() {
        guard let folder = SecureStore.dataFolder() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: - What is deliberately not here

    private var notSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Not settings")
            PhilonNote(
                kind: .verified,
                title: "Nothing here can skip the review",
                message: "There is no preference to auto-confirm a field, to trust a clean check digit, or to export a document nobody has looked at. Every value on a crew list is confirmed by a person against the image it came from — that is what the app is for, so it is not a default anyone gets to change."
            )
            PhilonNote(
                kind: .verified,
                title: "Nothing here sends anything anywhere",
                message: "There is no server to configure, no account to sign into and no sync to switch on. Extraction runs on this Mac and the documents never leave it, so there is nothing to set."
            )
        }
    }

    // MARK: - Reset

    private var reset: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Restore Defaults…") { confirmingReset = true }
                .buttonStyle(.philonQuiet)
        }
    }
}
