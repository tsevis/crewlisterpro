import SwiftUI

/// The four places this app has, and the things that can appear over all of
/// them.
///
/// A tab bar rather than the Mac's screen row, for the ordinary reason: a
/// thumb reaches the bottom of a phone and not the top of it. The four are the
/// same four the Mac has — the charters, the fleet, the crew library, the
/// defaults — because they are the four things a charter agent's work is made
/// of, not four things a wide window had room for.
struct RootView: View {
    @Environment(CrewStore.self) private var store
    @Environment(DocumentIntake.self) private var intake

    @State private var tab = Tab.charters
    @State private var showAbout = false
    /// The trip a set of shared documents is being aimed at.
    @State private var choosingDestination = false

    enum Tab: Hashable { case charters, fleet, crew, settings }

    var body: some View {
        @Bindable var store = store
        @Bindable var intake = intake

        Group {
            if let failure = store.storageFailure {
                StorageFailureView(message: failure)
            } else if store.isOpening {
                OpeningView()
            } else {
                tabs
            }
        }
        .background(Theme.ground)
        .sheet(isPresented: $showAbout, onDismiss: { AboutPresentation.remember() }) { AboutSheet() }
        .sheet(isPresented: $choosingDestination) { IntakeDestinationSheet() }
        .task { if AboutPresentation.wanted() { showAbout = true } }
        // Everything the store could not do, said once and cleared. The Mac
        // shows the same sentence in the same words.
        .alert("CrewListr Pro", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert("CrewListr Pro", isPresented: Binding(
            get: { intake.problem != nil },
            set: { if !$0 { intake.problem = nil } }
        )) {
            Button("OK", role: .cancel) { intake.problem = nil }
        } message: {
            Text(intake.problem ?? "")
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            ChartersScreen(onShowAbout: { showAbout = true })
                .modifier(BottomBars(onChoose: { choosingDestination = true }))
                .tabItem { Label("Charters", systemImage: "calendar") }
                .tag(Tab.charters)
                // A share can land while a sheet is open, and the banner is
                // behind that sheet. The badge is not: it is what tells an
                // operator who just came back from WhatsApp that the passport
                // actually arrived.
                .badge(intake.pending.count)

            FleetScreen()
                .modifier(BottomBars(onChoose: { choosingDestination = true }))
                .tabItem { Label("Fleet", systemImage: "sailboat") }
                .tag(Tab.fleet)

            CrewLibraryScreen()
                .modifier(BottomBars(onChoose: { choosingDestination = true }))
                .tabItem { Label("Crew", systemImage: "person.2") }
                .tag(Tab.crew)

            SettingsScreen(onShowAbout: { showAbout = true })
                .modifier(BottomBars(onChoose: { choosingDestination = true }))
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}

/// The two strips that belong to the whole app rather than to one screen: what
/// is running, and what has arrived.
///
/// Applied to each tab's own content rather than once to the `TabView`. A
/// bottom inset on the tab view itself is laid out *below* the floating tab
/// bar, which on a phone means on top of it — the banner covered the four tabs
/// completely, so an operator with a passport waiting could not reach the fleet
/// or the settings until they had dealt with it.
struct BottomBars: ViewModifier {
    @Environment(CrewStore.self) private var store
    let onChoose: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                ActivityStrip(activity: store.activity, onCancel: { store.cancelActivity() })
                IntakeBanner(onChoose: onChoose)
            }
        }
    }
}

/// What is waiting to be put on a charter, and the way to do it.
///
/// It appears because something arrived from outside the app — the share sheet,
/// or "Open in" — and the operator has not said where it goes. It does not
/// import anything by itself. Guessing the charter would be guessing which
/// crew list a stranger's passport belongs on, which is not a guess this app
/// gets to make.
struct IntakeBanner: View {
    @Environment(DocumentIntake.self) private var intake
    @Environment(\.dynamicTypeSize) private var typeSize
    let onChoose: () -> Void

    /// Side by side normally; stacked at the accessibility sizes, where the
    /// sentence and the button cannot both have a usable width on a phone —
    /// side by side, "Choose…" broke across two lines inside its own fill.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    var body: some View {
        if intake.hasPending {
            layout {
                HStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundStyle(Theme.accentText)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(intake.pendingSummary)
                            .font(Theme.Font.supportEmphasis)
                            .foregroundStyle(Theme.ink)
                        Text("Choose the charter they belong to.")
                            .font(Theme.Font.meta)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .lineLimit(2)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Button("Choose…", action: onChoose)
                        .buttonStyle(.philonPrimary)
                        .fixedSize()
                    Button {
                        intake.discardPending()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.philonIcon)
                    .accessibilityLabel("Discard the shared documents")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.panel)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: 0.18), value: intake.pending.count)
        }
    }
}

/// A long operation, with a way out of the ones that deserve one.
struct ActivityStrip: View {
    let activity: Activity?
    let onCancel: () -> Void

    var body: some View {
        if let activity {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(Theme.Font.supportEmphasis)
                        .foregroundStyle(Theme.ink)
                    if let detail = activity.detail {
                        Text(detail)
                            .font(Theme.Font.meta)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                    if let fraction = activity.clampedFraction {
                        PhilonProgress(value: fraction)
                    }
                }
                Spacer(minLength: 8)
                if activity.isCancellable {
                    Button("Stop", action: onCancel).buttonStyle(.philonQuiet)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.panelRecessed)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }
}

/// Where the shared documents are going.
///
/// Every live charter, plus the way to start a new one — because the usual case
/// for a passport arriving on WhatsApp is a charter that has just been booked
/// and does not exist in the app yet.
struct IntakeDestinationSheet: View {
    @Environment(CrewStore.self) private var store
    @Environment(DocumentIntake.self) private var intake
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(intake.pending) { document in
                        HStack {
                            Image(systemName: "doc.text.image").foregroundStyle(Theme.inkSecondary)
                            Text(document.name).lineLimit(1)
                            Spacer()
                            Text(document.origin.label)
                                .font(Theme.Font.meta)
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        .swipeActions {
                            Button("Discard", role: .destructive) { intake.discard(document) }
                        }
                    }
                } header: {
                    Text(intake.pending.count == 1 ? "The document" : "The documents")
                }

                Section {
                    ForEach(store.activeTrips.sorted(by: { $0.departureDate < $1.departureDate })) { trip in
                        Button {
                            deliver(to: trip.id)
                        } label: {
                            TripRow(trip: trip)
                        }
                    }
                    Button {
                        deliver(to: store.createTrip())
                    } label: {
                        Label("New charter", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Put them on")
                } footer: {
                    Text("Every field still arrives unconfirmed. Adding a passport to a charter is not reviewing it.")
                }
            }
            .navigationTitle("Where do these go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func deliver(to tripID: UUID) {
        dismiss()
        Task { await intake.deliver(to: tripID, store: store) }
    }
}

/// The store is opening. Shown rather than an empty list, which would read as
/// lost data.
struct OpeningView: View {
    var body: some View {
        PhilonEmptyState(
            symbol: "lock.rotation",
            title: "Opening the encrypted store",
            message: "The documents are decrypted with a key held in the Keychain on \(About.deviceName)."
        ) {
            ProgressView().controlSize(.small)
        }
    }
}

/// A Keychain that will not answer or a disk that is full is a condition to
/// explain, not a crash. There is no Quit button here: iOS has no quitting, and
/// offering one would be offering something the app cannot do.
struct StorageFailureView: View {
    let message: String

    var body: some View {
        PhilonEmptyState(
            symbol: "lock.trianglebadge.exclamationmark",
            title: "Encrypted storage is unavailable",
            message: message
        )
    }
}
