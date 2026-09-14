import SwiftUI

/// The crew list: what it will say, what is still stopping it, and the way to
/// send it.
///
/// The preview is not decoration. A crew list is a document a port authority
/// reads, and the operator should see the rows exactly as they will print
/// before they hand them to anybody — including whose name ends up on the
/// signature line.
struct CrewListSheet: View {
    @Environment(CrewStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let tripID: UUID

    @State private var exported: [URL] = []
    @State private var sharing = false

    private var trip: Trip? { store.data.trips.first { $0.id == tripID } }
    private var boat: Boat? { trip.flatMap(store.boat(for:)) }
    private var rows: [CrewListRow] { store.crewRows(forTripID: tripID) }
    private var blockers: [String] { store.exportBlockers }

    var body: some View {
        NavigationStack {
            List {
                if let trip, let boat {
                    Section("The header a port authority reads") {
                        headerValue("Yacht", boat.name, blank: !boat.isComplete)
                        headerValue("Flag", boat.flag)
                        headerValue("Port of registry", boat.registrationPort)
                        headerValue("Reg no", boat.registrationNumber)
                        headerValue("Voyage", "\(VoyageDate.printed(trip.departureDate)) – \(VoyageDate.printed(trip.returnDate))")
                        let email = store.skipperEmail(forTripID: tripID)
                        if !email.isEmpty { headerValue("Skipper email", email) }
                    }
                }

                Section("Skipper") {
                    let skippers = rows.filter { $0.role == .skipper }
                    if skippers.isEmpty {
                        Text("Nobody is named as skipper.")
                            .font(Theme.Font.support)
                            .foregroundStyle(Theme.caution)
                    } else {
                        ForEach(skippers) { CrewListRowView(row: $0) }
                    }
                }

                let passengers = rows.filter { $0.role == .passenger }
                if !passengers.isEmpty {
                    Section("Passengers") {
                        ForEach(passengers) { CrewListRowView(row: $0) }
                    }
                }

                Section {
                    if let client = rows.first(where: \.isClient) {
                        Text(client.fullName)
                    } else {
                        Text("Nobody named. The form prints an empty line.")
                            .font(Theme.Font.support)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                } header: {
                    Text("Client — signs for this charter")
                }

                if blockers.isEmpty {
                    Section {
                        Button {
                            export()
                        } label: {
                            Label("Export and Share", systemImage: "square.and.arrow.up")
                        }
                    } footer: {
                        Text("Writes \(store.settings.exportFilesDescription) and hands them to the share sheet — Mail, WhatsApp, AirDrop, or Save to Files.")
                    }
                } else {
                    Section {
                        ForEach(blockers, id: \.self) { blocker in
                            Label(blocker, systemImage: "exclamationmark.triangle.fill")
                                .font(Theme.Font.support)
                                .foregroundStyle(Theme.caution)
                        }
                    } header: {
                        Text(blockers.count == 1 ? "One thing is stopping this" : "\(blockers.count) things are stopping this")
                    } footer: {
                        Text("Nothing here can be waved through. Every value on a crew list is confirmed by a person against the document it was read from.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Crew List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $sharing) {
                ShareSheet(items: exported) {
                    // The written files are an unencrypted crew list with five
                    // people's passport numbers on it. They go as soon as the
                    // share sheet has finished with them, rather than waiting
                    // for iOS to decide the directory is stale — and if this
                    // app is killed with the sheet still open, the sweep at the
                    // next launch catches what this never got to.
                    Scratch.discardContainers(of: exported)
                    exported = []
                }
            }
        }
    }

    @ViewBuilder
    private func headerValue(_ label: String, _ value: String, blank: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.inkSecondary)
            Spacer()
            if value.trimmingCharacters(in: .whitespaces).isEmpty || blank {
                Text("would print blank")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.caution)
            } else {
                Text(value).multilineTextAlignment(.trailing)
            }
        }
        .font(Theme.Font.support)
    }

    private func export() {
        store.selectedTripID = tripID
        var directory: URL?
        do {
            let scratch = try Scratch.make(.crewList)
            directory = scratch
            exported = try store.exportSelectedTrip(to: scratch)
            sharing = !exported.isEmpty
            // Two files are written and the second can fail. Nothing to share
            // means nothing to clean up later, so the folder goes now.
            if !sharing { Scratch.discard(scratch) }
        } catch {
            // The settings can ask for both a CSV and a PDF, and the export
            // writes them one after the other: a failure on the second leaves
            // the first on disk — a crew list with every passport number on the
            // trip in it, in the clear, that nobody is going to come back for.
            if let directory { Scratch.discard(directory) }
            exported = []
            store.errorMessage = CrewStore.explain(error)
        }
    }
}

/// One printed line, as it will appear.
struct CrewListRowView: View {
    let row: CrewListRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(row.fullName.isEmpty ? "—" : row.fullName)
                    .font(Theme.Font.bodyEmphasis)
                if row.isClient {
                    Text("CLIENT")
                        .font(Theme.Font.eyebrow)
                        .foregroundStyle(Theme.accentText)
                }
            }
            // The four values a port authority checks against the passport in
            // their hand, in the order the printed form puts them.
            Text([row.documentNumber, row.nationality, row.printedBirthDate, row.sex]
                    .filter { !$0.isEmpty }
                    .joined(separator: "  ·  "))
                .font(Theme.Font.meta.monospacedDigit())
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.vertical, 2)
    }
}
