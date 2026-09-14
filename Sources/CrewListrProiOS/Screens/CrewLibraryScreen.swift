import SwiftUI

/// The people kept for the next charter, with their scans.
///
/// The same skippers sail all season, and every charter used to ask for the
/// same passport again — the photograph, the upload, the seven fields — and
/// then erased it along with the trip it belonged to, so the work was not
/// merely repeated, it was repeated from nothing.
///
/// What it deliberately does not do is skip the review. Someone added from here
/// arrives with their document attached and every field waiting to be
/// confirmed, exactly as an imported one does. The saving is the upload, not
/// the checking.
struct CrewLibraryScreen: View {
    @Environment(CrewStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.crewLibrary.isEmpty {
                    PhilonEmptyState(
                        symbol: "person.crop.rectangle.stack",
                        title: "Nobody kept yet",
                        message: "Finish reviewing a passport and choose “Keep in Crew Library”. The next charter that person sails on will not ask for the photograph again."
                    )
                } else {
                    List {
                        Section {
                            ForEach(store.crewLibrary) { saved in
                                NavigationLink { CrewLibraryDetailScreen(savedID: saved.id) } label: { SavedCrewRow(saved: saved) }
                            }
                        } footer: {
                            Text("Removing someone erases the library's copy of their scan. An app that holds passport photographs has to be able to forget them.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Theme.ground)
            .navigationTitle("Crew Library")
        }
    }
}

struct SavedCrewRow: View {
    let saved: SavedCrewMember

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(saved.displayName)
                    .font(Theme.Font.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                Text([saved.documentNumber, saved.nationality, saved.role.label]
                        .filter { !$0.isEmpty }
                        .joined(separator: "  ·  "))
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let used = saved.lastUsedAt {
                Text(VoyageDate.short(used))
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One kept person: what the library holds, when it was confirmed, and the way
/// onto a charter.
struct CrewLibraryDetailScreen: View {
    @Environment(CrewStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let savedID: UUID

    @State private var scan: ScanState = .loading
    @State private var showingFullScreen = false
    @State private var choosingTrip = false
    @State private var confirmingRemoval = false

    private var saved: SavedCrewMember? { store.savedCrewMember(withID: savedID) }

    var body: some View {
        Group {
            if let saved {
                content(saved)
            } else {
                PhilonEmptyState(symbol: "person.slash", title: "This person is gone",
                                 message: "They were removed from the library while this screen was open.")
            }
        }
        .background(Theme.ground)
        .navigationTitle(saved?.displayName ?? "Crew")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let saved else { return }
            scan = await store.crewLibraryImageData(for: saved).map(ScanState.loaded) ?? .missing
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            DocumentImageFullScreen(state: scan, title: saved?.displayName ?? "Scan")
        }
        .sheet(isPresented: $choosingTrip) { AddToTripSheet(savedID: savedID) }
        .confirmationDialog("Remove from the crew library?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove and Erase the Scan", role: .destructive) {
                Task {
                    await store.removeFromCrewLibrary(savedID)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases the library's copy of their passport scan. Charters they are already on keep their own copies.")
        }
    }

    @ViewBuilder
    private func content(_ saved: SavedCrewMember) -> some View {
        List {
            Section {
                DocumentImageView(state: scan, onOpenFullScreen: scan.data == nil ? nil : { showingFullScreen = true })
                    .frame(maxHeight: 260)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } footer: {
                Text(saved.confirmedAt.map { "Every crew-list field was confirmed against this scan on \(VoyageDate.printed($0))." }
                     ?? "Kept mid-review: not every field on this person was confirmed.")
            }

            Section("What the library holds") {
                ForEach(CrewField.reviewOrder) { field in
                    let value = saved[field]
                    if !value.isEmpty {
                        HStack {
                            Text(field.label).foregroundStyle(Theme.inkSecondary)
                            Spacer()
                            Text(field.presented(value)).multilineTextAlignment(.trailing)
                        }
                        .font(Theme.Font.support)
                    }
                }
                if !saved.email.isEmpty {
                    HStack {
                        Text("Email").foregroundStyle(Theme.inkSecondary)
                        Spacer()
                        Text(saved.email)
                    }
                    .font(Theme.Font.support)
                }
            }

            Section {
                Button {
                    choosingTrip = true
                } label: {
                    Label("Put on a Charter", systemImage: "arrow.right.circle")
                }
                Button("Remove from the Library", role: .destructive) { confirmingRemoval = true }
            } footer: {
                Text("They arrive with their scan attached and every field waiting to be confirmed, exactly as an imported document does. The saving is the upload, not the checking.")
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// Which charter this person is joining.
struct AddToTripSheet: View {
    @Environment(CrewStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let savedID: UUID

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.activeTrips.sorted(by: { $0.departureDate < $1.departureDate })) { trip in
                        Button {
                            dismiss()
                            Task { await store.addFromCrewLibrary(savedID, toTripWith: trip.id) }
                        } label: {
                            TripRow(trip: trip)
                        }
                    }
                } header: {
                    Text("Charters")
                } footer: {
                    Text("Every field arrives unconfirmed. A crew list is still a document a person has looked at.")
                }
            }
            .navigationTitle("Put on a charter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// The other direction: from inside a charter, pick somebody out of the library.
struct AddFromLibrarySheet: View {
    @Environment(CrewStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.crewLibrary) { saved in
                        Button {
                            dismiss()
                            Task { await store.addFromCrewLibrary(saved.id, toTripWith: tripID) }
                        } label: {
                            SavedCrewRow(saved: saved)
                        }
                    }
                } footer: {
                    Text("Their scan comes with them, and every field arrives waiting to be confirmed.")
                }
            }
            .navigationTitle("From the crew library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
