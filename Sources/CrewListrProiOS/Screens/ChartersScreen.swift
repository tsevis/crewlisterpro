import SwiftUI

/// Every charter, gathered into the days they sail on.
///
/// A charter base plans by the day and not by the vessel: four boats leaving on
/// the same Saturday are one morning's work, and the same boat leaving in
/// September and again in October is two unrelated jobs. The Mac says this with
/// a horizontal strip of days; a phone says it with sections, which is the same
/// statement in the shape a phone reads in.
struct ChartersScreen: View {
    @Environment(CrewStore.self) private var store
    let onShowAbout: () -> Void

    @State private var showingArchive = false

    private var days: [TripDay] {
        TripCalendar.days(of: showingArchive ? store.data.trips : store.activeTrips)
    }

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    PhilonEmptyState(
                        symbol: "calendar.badge.plus",
                        title: showingArchive ? "Nothing put away" : "No charters yet",
                        message: showingArchive
                            ? "Archived charters keep their documents. Nothing has been archived."
                            : "A charter is a yacht and the week it sails. Start one, then add the crew's passports — from Photos, from Files, from the camera, or straight out of WhatsApp."
                    ) {
                        if !showingArchive {
                            Button("New Charter") { store.createTrip() }
                                .buttonStyle(.philonPrimary)
                        }
                    }
                } else {
                    list
                }
            }
            .background(Theme.ground)
            .navigationTitle("Charters")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onShowAbout() } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About CrewListr Pro")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            store.createTrip()
                        } label: {
                            Label("New Charter", systemImage: "plus")
                        }
                        Toggle(isOn: $showingArchive) {
                            Label("Show Archived", systemImage: "archivebox")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(days) { day in
                Section {
                    ForEach(day.trips) { trip in
                        NavigationLink {
                            TripScreen(tripID: trip.id)
                        } label: {
                            TripRow(trip: trip)
                        }
                    }
                } header: {
                    HStack {
                        Text(VoyageDate.printed(day.date))
                        if day.isArchived {
                            Text("· archived").foregroundStyle(Theme.inkTertiary)
                        }
                        Spacer()
                        // A Saturday with four departures is a fact about the
                        // morning, so it is stated on the day and not left for
                        // the operator to count.
                        if day.trips.count > 1 {
                            Text("\(day.trips.count) charters")
                        }
                    }
                    .font(Theme.Font.metaEmphasis)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
