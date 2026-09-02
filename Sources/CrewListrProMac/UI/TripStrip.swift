import SwiftUI

/// Every yacht in one horizontal row, in the window's command line.
///
/// This was a dropdown. A dropdown is the right shape for a list nobody looks
/// at until they need it, and a charter operator's trips are not that — they
/// switch between them all day, and the readiness count on each is the number
/// they are actually tracking. A menu hid all of that behind a click: one
/// yacht visible, the rest and their counts only findable by opening it.
///
/// So the trips are laid out flat and always readable, and the things you can
/// *do* to a trip — make one, put one away, erase one — stay in a menu at the
/// end, because those are the ones you look for only when you want them.
struct TripStrip: View {
    @Environment(CrewStore.self) private var store
    let onNewTrip: () -> Void
    let onDeleteTrip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if store.data.trips.isEmpty {
                Button("New Trip", systemImage: "plus", action: onNewTrip)
                    .buttonStyle(.philonSecondary)
            } else {
                strip
            }

            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The strip

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.activeTrips) { trip in
                        chip(for: trip)
                    }

                    // Put-away charters keep their place at the end of the row
                    // rather than vanishing: a trip nothing can reach is a trip
                    // whose passport scans can be neither restored nor erased.
                    ForEach(store.archivedTrips) { trip in
                        chip(for: trip)
                    }
                }
                // Room for the selected chip's border, which a tight clip
                // would shave a pixel off at either end of the row.
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
            .onAppear { scroll(proxy) }
            .onChange(of: store.selectedTripID) { _, _ in scroll(proxy) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Switching trips from a keyboard shortcut or from deleting the current
    /// one can select a chip that is scrolled out of sight. Bring it back.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let id = store.selectedTripID else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
    }

    private func chip(for trip: Trip) -> some View {
        TripChip(
            name: name(of: trip),
            readiness: readiness(of: trip),
            isSelected: store.selectedTripID == trip.id,
            isArchived: trip.isArchived
        ) {
            store.selectedTripID = trip.id
            store.selectedDocumentID = store.data.documents.first { $0.tripID == trip.id }?.id
        }
        .id(trip.id)
    }

    // MARK: - What can be done to a trip

    private var actions: some View {
        Menu {
            Button("New Trip", action: onNewTrip)
            Divider()
            if store.selectedTrip?.isArchived == true {
                Button("Restore This Trip") {
                    if let id = store.selectedTripID { store.restoreTrip(id) }
                }
            } else {
                Button("Archive This Trip") {
                    if let id = store.selectedTripID { store.archiveTrip(id) }
                }
                .disabled(store.selectedTripID == nil)
            }
            Button("Delete This Trip…", role: .destructive, action: onDeleteTrip)
                .disabled(store.selectedTripID == nil)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        // `.menuStyle(.button)` deliberately: `.borderlessButton` renders the
        // label but stops the menu taking clicks.
        .menuStyle(.button)
        .buttonStyle(.philonQuiet)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New trip, archive or delete")
    }

    // MARK: - What a chip says

    func name(of trip: Trip) -> String {
        let boat = store.boat(for: trip)
        return boat.map { $0.isComplete ? $0.name : "Untitled yacht" } ?? "Untitled yacht"
    }

    /// The one number an operator is tracking per trip. It lived in the sidebar,
    /// then in the dropdown's second line; here it is on the face of every chip
    /// at once, which is the whole point of laying them out flat.
    func readiness(of trip: Trip) -> String {
        let documents = store.data.documents.filter { $0.tripID == trip.id }
        guard !documents.isEmpty else { return "No documents" }
        return "\(documents.filter { $0.canExport() }.count)/\(documents.count) cleared"
    }
}

// MARK: - One yacht

private struct TripChip: View {
    let name: String
    let readiness: String
    let isSelected: Bool
    let isArchived: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "sailboat")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.accentText : Theme.inkTertiary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(Theme.Font.supportEmphasis)
                        .foregroundStyle(isSelected ? Theme.ink : (hovering ? Theme.ink : Theme.inkSecondary))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(isArchived ? "Archived · \(readiness)" : readiness)
                        .font(Theme.Font.meta)
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            // Capped so a long yacht name cannot push every other trip off the
            // row — the strip exists to show them all at once.
            .frame(maxWidth: 190, alignment: .leading)
            .contentShape(Rectangle())
            .philonInset(highlighted: isSelected)
            // An archived charter reads as put away without leaving the row.
            .opacity(isArchived && !isSelected ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isArchived ? "\(name) — archived · \(readiness)" : "\(name) · \(readiness)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
