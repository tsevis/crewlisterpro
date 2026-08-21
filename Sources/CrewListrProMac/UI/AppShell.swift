import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct CrewListrProMacApp: App {
    @State private var store = CrewStore()

    init() {
        // `--export` / `--list` finish the process before any window exists.
        HeadlessExport.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .frame(minWidth: 1180, minHeight: 760)
                // The accent, applied once at the root so every system control
                // the app has not restyled by hand still lands in the palette
                // rather than defaulting to the user's system blue.
                .tint(Theme.accentText)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        // The title bar carries the app's name and nothing else. Philon does
        // not put the current document there, and neither should this: the
        // document is named in the panel that shows it, where it belongs.
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppVersion.name)") {
                    NotificationCenter.default.post(name: .requestAbout, object: nil)
                }
            }
            CommandGroup(after: .newItem) {
                Button("New Trip") { store.createTrip() }.keyboardShortcut("n")
                Button("Import Documents…") { NotificationCenter.default.post(name: .requestImport, object: nil) }
                    .keyboardShortcut("i")
                    .disabled(store.selectedTripID == nil)
            }
        }
    }
}

extension Notification.Name {
    static let requestImport = Notification.Name("CrewListrRequestImport")
    static let requestAbout = Notification.Name("CrewListrRequestAbout")
}

/// The window: the app's name in the title bar, the screens under it, one line
/// of commands under that, and the document below.
struct RootView: View {
    @Environment(CrewStore.self) private var store
    // Persisted, so the window reopens on the screen it was left on. A trip
    // being reviewed over two sittings should not start again at Review, and
    // it makes the screens reachable to anything that drives the app without a
    // pointer.
    @AppStorage("crewlistr.screen") private var screen: Screen = .people
    @State private var importing = false
    @State private var showAbout = false
    @State private var pendingTripDeletion: Trip?

    var body: some View {
        @Bindable var store = store

        if let failure = store.storageFailure {
            StorageFailureView(message: failure)
        } else {
            VStack(spacing: 0) {
                ScreenRow(
                    selection: $screen,
                    crewCount: store.selectedTripID.map { store.crewRows(forTripID: $0).count } ?? 0,
                    onShowInfo: { showAbout = true }
                )

                commandLine

                // A long operation keeps its place on every screen while it
                // runs; the readiness banner belongs to People alone.
                SustainedActivityStrip(activity: store.activity)

                if screen == .people, store.selectedTripID != nil {
                    ReadinessBanner(blockers: store.exportBlockers)
                }

                content
            }
            .background(Theme.ground)
            .navigationTitle(AppVersion.name)
            // Philon's `.makers-mark`, pinned to the window rather than to a
            // panel, so no layout change can take it away.
            .overlay(alignment: .bottomLeading) { MakersMark() }
            .overlay(alignment: .top) { ActivityBanner(activity: store.activity) }
            // Presentations hang off this concrete view. Attached to a Group
            // wrapping an if/else they bind to a view whose identity changes
            // and silently never present.
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    Task { await store.importDocuments(urls) }
                case .failure(let error):
                    store.errorMessage = "Import cancelled: \(error.localizedDescription)"
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestImport)) { _ in
                if store.selectedTripID != nil { importing = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestAbout)) { _ in showAbout = true }
            .sheet(isPresented: $showAbout, onDismiss: { AboutPresentation.remember() }) { AboutScreen() }
            .task { if AboutPresentation.wanted() { showAbout = true } }
            .confirmationDialog(
                "Delete this trip?",
                isPresented: Binding(get: { pendingTripDeletion != nil }, set: { if !$0 { pendingTripDeletion = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Trip and Documents", role: .destructive) {
                    if let trip = pendingTripDeletion { store.deleteTrip(trip.id) }
                    pendingTripDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingTripDeletion = nil }
            } message: {
                let count = store.data.documents.filter { $0.tripID == pendingTripDeletion?.id }.count
                Text("This permanently erases \(count) encrypted document\(count == 1 ? "" : "s") from this Mac. It cannot be undone.")
            }
            .alert("CrewListr Pro", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .people:
            PeopleScreen(importing: $importing)
        case .crewList:
            CrewListScreen()
        case .trip:
            TripScreen()
        }
    }

    // MARK: - Commands
    //
    // One line, and its contents change with the screen — the same way Philon's
    // toolbar carries Single Job/Batch and Convert on the workspace and nothing
    // at all on Diagnostics.

    @ViewBuilder
    private var commandLine: some View {
        switch screen {
        case .people: peopleCommands
        case .crewList: crewListCommands
        case .trip: tripCommands
        }
    }

    private var peopleCommands: some View {
        CommandBar {
            TripPicker(onNewTrip: { store.createTrip(); screen = .trip },
                       onDeleteTrip: { pendingTripDeletion = store.selectedTrip })

            Button { importing = true } label: {
                Label("Import", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.philonQuiet)
            .disabled(store.selectedTripID == nil)
            .help("Add passport photos or scans (⌘I)")
        } trailing: {
            if let document = store.selectedDocument {
                Button {
                    store.verifyAllValidFields(on: document.id)
                } label: {
                    Label("Confirm All Valid", systemImage: "checkmark.seal")
                }
                .buttonStyle(.philonSecondary)
                .disabled(document.canExport())
                .help("Marks every field that passes validation as checked against the image")

                Button {
                    store.rejectDocument(document.id, reason: "Rejected by operator: the document is not usable.")
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                }
                .buttonStyle(.philonQuiet(role: .destructive))
                .disabled(document.risk == .high)
            }

            Button {
                store.reanalyseSelectedDocument()
            } label: {
                Label("Analyze", systemImage: "text.magnifyingglass")
            }
            .buttonStyle(.philonPrimary)
            .disabled(store.selectedDocument == nil)
            .help("Read this document again with Vision and re-parse its machine-readable zone")
        }
    }

    // No back button on either of these: the screen row above is the way back,
    // and a second control that does the same thing only invites the question
    // of how they differ.
    private var crewListCommands: some View {
        CommandBar {
            TripPicker(onNewTrip: { store.createTrip(); screen = .trip },
                       onDeleteTrip: { pendingTripDeletion = store.selectedTrip })
        } trailing: {
            ExportButton()
        }
    }

    private var tripCommands: some View {
        CommandBar {
            TripPicker(onNewTrip: { store.createTrip(); screen = .trip },
                       onDeleteTrip: { pendingTripDeletion = store.selectedTrip })
        } trailing: {
            Button { screen = .people } label: {
                Label("People", systemImage: "person.2")
            }
            .buttonStyle(.philonPrimary)
            .disabled(store.selectedTripID == nil)
            .help("Import and review this trip's passports")
        }
    }
}

// MARK: - Trip picker

/// The trip, its readiness, and the two things you can do to it. Trip switching
/// lost its column when the sidebar went; the count that column carried has to
/// survive, because it is the one number that says which charter is behind.
struct TripPicker: View {
    @Environment(CrewStore.self) private var store
    let onNewTrip: () -> Void
    let onDeleteTrip: () -> Void

    var body: some View {
        Menu {
            ForEach(store.data.trips) { trip in
                Button {
                    store.selectedTripID = trip.id
                    store.selectedDocumentID = store.data.documents.first { $0.tripID == trip.id }?.id
                } label: {
                    Text("\(tripLabel(trip))  ·  \(readinessLabel(trip))")
                }
            }
            Divider()
            Button("New Trip", action: onNewTrip)
            Button("Delete This Trip…", role: .destructive, action: onDeleteTrip)
                .disabled(store.selectedTripID == nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sailboat").foregroundStyle(Theme.accentText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.selectedTrip.map(tripLabel) ?? "No trip")
                        .font(Theme.Font.supportEmphasis)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let trip = store.selectedTrip {
                        Text(readinessLabel(trip))
                            .font(Theme.Font.meta)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: 210, alignment: .leading)
        }
        // `.menuStyle(.button)` deliberately: `.borderlessButton` renders the
        // label but stops the menu taking clicks.
        .menuStyle(.button)
        .buttonStyle(.philonQuiet)
        .fixedSize()
        .help("Switch between trips")
    }

    func tripLabel(_ trip: Trip) -> String {
        let boat = store.boat(for: trip)
        return boat.map { $0.isComplete ? $0.name : "Untitled yacht" } ?? "Untitled yacht"
    }

    func readinessLabel(_ trip: Trip) -> String {
        let documents = store.data.documents.filter { $0.tripID == trip.id }
        guard !documents.isEmpty else { return "No documents" }
        return "\(documents.filter { $0.canExport() }.count)/\(documents.count) cleared"
    }
}

// MARK: - Review

/// Philon's `.conversion-grid`: the documents, the one under review, and what
/// was read out of it — three panels in a single bordered surface, in the order
/// the operator works.
private struct PeopleScreen: View {
    @Environment(CrewStore.self) private var store
    @Binding var importing: Bool

    var body: some View {
        DocumentGrid {
            DocumentColumn(importing: $importing)
                .frame(minWidth: 230, idealWidth: 270, maxWidth: 300)

            GridDivider()

            if let document = store.selectedDocument {
                DocumentPreview(document: document)
                    .frame(minWidth: 280)

                GridDivider()

                // The review pane is where the operator actually works — seven
                // editable fields, each with its own confirm control — so it
                // gets the width. The document list only ever holds a name, a
                // number and a status, and the preview scrolls and zooms.
                FieldReviewPane(document: document)
                    .frame(minWidth: 440, idealWidth: 580, maxWidth: 760)
            } else {
                PhilonEmptyState(
                    symbol: "doc.text.viewfinder",
                    title: "Select a document",
                    message: "CrewListr Pro keeps every source document encrypted on this Mac, and shows it beside the fields read from it."
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Replaces the old `fatalError` at launch. A locked Keychain or a full disk is
/// a condition to explain, not a crash.
private struct StorageFailureView: View {
    let message: String

    var body: some View {
        PhilonEmptyState(
            symbol: "lock.trianglebadge.exclamationmark",
            title: "Encrypted storage is unavailable",
            message: message
        ) {
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.philonPrimary)
        }
    }
}
