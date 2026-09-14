import SwiftUI

/// Defaults for this device, grouped by the moment each one applies.
///
/// And two sections about what is deliberately not configurable. Nothing here
/// can skip the review — there is no preference to auto-confirm a field, to
/// trust a clean check digit, or to export a document nobody has looked at. And
/// nothing sends anything anywhere: no server, no account, no sync.
struct SettingsScreen: View {
    @Environment(CrewStore.self) private var store
    let onShowAbout: () -> Void

    @State private var showingVersions = false

    private var settings: AppSettings { store.settings }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Charters start on", selection: binding(\.charterStartWeekday)) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(AppSettings.weekdayName(weekday)).tag(weekday)
                        }
                    }
                    Stepper("Charter runs \(settings.charterLengthDays) day\(settings.charterLengthDays == 1 ? "" : "s")",
                            value: binding(\.charterLengthDays),
                            in: 1...AppSettings.longestCharterDays)
                } header: {
                    Text("When a charter is made")
                } footer: {
                    Text("A new charter already runs \(AppSettings.weekdayName(settings.charterStartWeekday)) to \(AppSettings.weekdayName(settings.charterStartWeekday)). Moving the departure moves the return with it.")
                }

                Section {
                    LabeledContent("Flag") {
                        CommitTextField(placeholder: "GRC", value: settings.defaultFlag,
                                        uppercased: true, alignment: .trailing) {
                            commit(\.defaultFlag, $0)
                        }
                    }
                    LabeledContent("Port of registry") {
                        CommitTextField(placeholder: "PIRAEUS", value: settings.defaultRegistrationPort,
                                        uppercased: true, alignment: .trailing) {
                            commit(\.defaultRegistrationPort, $0)
                        }
                    }
                } header: {
                    Text("When a yacht is added")
                } footer: {
                    Text("Most fleets share both, and typing them per yacht is typing them every time.")
                }

                Section {
                    Toggle("Printed crew list (PDF)", isOn: binding(\.writesPDF))
                    Toggle("Spreadsheet (CSV)", isOn: binding(\.writesCSV))
                    LabeledContent("File name starts with") {
                        CommitTextField(placeholder: AppSettings.defaultFileNamePrefix,
                                        value: settings.fileNamePrefix, uppercased: false,
                                        alignment: .trailing) {
                            commit(\.fileNamePrefix, $0)
                        }
                    }
                } header: {
                    Text("What an export writes")
                } footer: {
                    Text("Named for the yacht and the departure date, so two charters leaving the same day cannot overwrite each other. On iPhone the files go to the share sheet rather than to a folder — Mail, WhatsApp, AirDrop, or Save to Files.")
                }

                Section {
                    Stepper("Keep \(settings.versionsKept) earlier versions",
                            value: binding(\.versionsKept),
                            in: AppSettings.fewestVersionsKept...AppSettings.mostVersionsKept)
                    Button("Take a Version Now") {
                        Task { await store.takeSnapshot() }
                    }
                    Button("Earlier Versions…") {
                        showingVersions = true
                        Task { await store.refreshBackups() }
                    }
                } header: {
                    Text("Versions")
                } footer: {
                    Text("A version is written before every save, so a mistaken delete is one restore away rather than gone. The cap takes effect at the next save — dragging it down does not destroy the history you already have.")
                }

                Section {
                    Label("Everything stays on \(About.deviceName)", systemImage: "iphone.and.arrow.forward.inward")
                    Label("Sealed with AES-GCM under a key in the Keychain", systemImage: "lock.fill")
                    Label("Not included in iCloud or iTunes backups", systemImage: "icloud.slash")
                } header: {
                    Text("Where the documents live")
                } footer: {
                    Text("The key is marked for this device only, so it never travels to a restored one — and documents that travelled without it would land unreadable. What survives a lost or stolen device is the crew list you already exported. Nothing is sent anywhere: the app has no server, no account and no sync.")
                }

                Section {
                    Label("No field confirms itself", systemImage: "hand.raised.fill")
                    Label("A clean check digit is not a review", systemImage: "number")
                    Label("No export of a document nobody has looked at", systemImage: "eye.fill")
                } header: {
                    Text("What cannot be turned off")
                } footer: {
                    Text("Extraction always returns a document for review, whatever its machine-readable zone said. Only an operator moves one to cleared.")
                }

                Section {
                    Button { onShowAbout() } label: {
                        LabeledContent("About", value: "\(AppVersion.short) (\(AppVersion.build))")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(Theme.ground)
            .navigationTitle("Settings")
            .sheet(isPresented: $showingVersions) { VersionsSheet() }
        }
    }

    /// A binding straight onto one setting, normalised on the way in by
    /// `updateSettings`.
    private func binding<Value>(_ path: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: path] },
            set: { newValue in
                var updated = store.settings
                updated[keyPath: path] = newValue
                store.updateSettings(updated)
            }
        )
    }

    private func commit<Value>(_ path: WritableKeyPath<AppSettings, Value>, _ value: Value) {
        var updated = store.settings
        updated[keyPath: path] = value
        store.updateSettings(updated)
    }
}

/// Earlier versions of the store, each described by what it actually contains
/// rather than by a timestamp alone.
struct VersionsSheet: View {
    @Environment(CrewStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var restoring: SecureStore.Backup?

    var body: some View {
        NavigationStack {
            List {
                if store.backups.isEmpty {
                    Text("No earlier versions yet.")
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    Section {
                        ForEach(store.backups, id: \.id) { backup in
                            Button {
                                restoring = backup
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(backup.created.formatted(date: .abbreviated, time: .shortened))
                                        .font(Theme.Font.bodyEmphasis)
                                        .foregroundStyle(Theme.ink)
                                    Text(CrewStore.describe(backup))
                                        .font(Theme.Font.meta)
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                            }
                        }
                    } footer: {
                        Text("Restoring snapshots the current state first, so it is undoable too.")
                    }
                }
            }
            .navigationTitle("Earlier versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await store.refreshBackups() }
            .confirmationDialog("Restore this version?",
                                isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                                titleVisibility: .visible) {
                Button("Restore", role: .destructive) {
                    if let backup = restoring {
                        Task { await store.restoreBackup(backup.id) }
                    }
                    restoring = nil
                }
                Button("Cancel", role: .cancel) { restoring = nil }
            } message: {
                Text(restoring.map { "This replaces everything with \(CrewStore.describe($0)) as of \($0.created.formatted(date: .abbreviated, time: .shortened))." } ?? "")
            }
        }
    }
}
