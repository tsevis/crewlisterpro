import SwiftUI

/// Every charter day in one horizontal row, in the window's command line.
///
/// This was a dropdown, then a chip per trip labelled with a yacht. The
/// dropdown was wrong because a charter operator switches between trips all day
/// and a menu showed one of them at a time. The chip per yacht was wrong for a
/// subtler reason: a base with four boats going out on the same Saturday read
/// as four unrelated charters, and the date every one of them was working to
/// — the thing the whole morning is planned around — appeared nowhere at all.
///
/// So the row is a calendar. One chip per departure day, earliest first, and
/// the boats leaving that day hang off it: a day with one charter selects it,
/// a day with several opens a menu of them. The things you can *do* to a trip —
/// make one, put one away, erase one — stay in a menu at the end, because those
/// are the ones you look for only when you want them.
struct TripStrip: View {
    @Environment(CrewStore.self) private var store
    /// Charters the yacht named, or lets the store decide when it is nil.
    let onNewTrip: (UUID?) -> Void
    let onDeleteTrip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // The menu comes first and stays put. It was after the strip, and
            // the strip expands to fill the command line — so on a window with
            // two trips the menu sat marooned against the Import button with a
            // hand's width of nothing between it and the chips it belongs to.
            actions

            if store.data.trips.isEmpty {
                Button("New Trip", systemImage: "plus") { onNewTrip(nil) }
                    .buttonStyle(.philonSecondary)
            } else {
                strip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The strip

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Put-away charters keep their day rather than being
                    // gathered at the end: a trip nothing can reach is a trip
                    // whose passport scans can be neither restored nor erased,
                    // and a date is where an operator looks for one.
                    ForEach(store.tripDays) { day in
                        chip(for: day).id(day.id)
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
        guard let day = selectedDay else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(day.id, anchor: .center) }
    }

    private var selectedDay: TripDay? {
        guard let id = store.selectedTripID else { return nil }
        return store.tripDays.first { $0.trips.contains { $0.id == id } }
    }

    @ViewBuilder
    private func chip(for day: TripDay) -> some View {
        let selected = day.trips.first { $0.id == store.selectedTripID }

        // One charter that day is not a choice, so it is a button and clicking
        // it opens the trip. Asking "which boat" of a day with one boat on it
        // would be a menu with a single item in it.
        if day.trips.count == 1, let only = day.trips.first {
            Button { select(only) } label: {
                TripDayFace(day: day, detail: detail(of: only), isSelected: selected != nil)
            }
            .buttonStyle(.plain)
            .help("\(VoyageDate.printed(day.date)) · \(detail(of: only))")
        } else {
            Menu {
                ForEach(day.trips) { trip in
                    Button {
                        select(trip)
                    } label: {
                        Text("\(name(of: trip)) — \(detail(of: trip))")
                    }
                }
            } label: {
                // The face alone, never a Button: a Button inside a Menu's
                // label takes the click the menu needs to open with, and the
                // chip stops responding at all.
                TripDayFace(day: day,
                            detail: selected.map(detail(of:)) ?? "\(day.trips.count) boats",
                            isSelected: selected != nil,
                            showsMenuHint: true)
            }
            // `.menuStyle(.button)` deliberately, as on the actions menu:
            // `.borderlessButton` renders the label but stops the menu taking
            // clicks.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("\(VoyageDate.printed(day.date)) · \(day.trips.count) boats")
        }
    }

    private func select(_ trip: Trip) {
        store.selectedTripID = trip.id
        store.selectedDocumentID = store.data.documents.first { $0.tripID == trip.id }?.id
    }

    // MARK: - What can be done to a trip

    private var actions: some View {
        Menu {
            // A submenu only where there is a choice to make. With one yacht in
            // the fleet, or none yet, "which yacht" is not a question and
            // asking it would be ceremony.
            if store.fleet.count > 1 {
                Menu("New Trip") {
                    ForEach(store.fleet) { boat in
                        Button(boat.displayName) { onNewTrip(boat.id) }
                    }
                }
            } else {
                Button("New Trip") { onNewTrip(nil) }
            }
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
        store.boat(for: trip)?.displayName ?? "Untitled yacht"
    }

    /// The boat and the one number an operator is tracking for it. The date is
    /// on the face of the chip; this is the line under it.
    func detail(of trip: Trip) -> String {
        let prefix = trip.isArchived ? "Archived · " : ""
        return "\(prefix)\(name(of: trip)) · \(readiness(of: trip))"
    }

    func readiness(of trip: Trip) -> String {
        let documents = store.data.documents.filter { $0.tripID == trip.id }
        guard !documents.isEmpty else { return "No documents" }
        return "\(documents.filter { $0.canExport() }.count)/\(documents.count) cleared"
    }
}

// MARK: - One charter day

private struct TripDayFace: View {
    let day: TripDay
    let detail: String
    let isSelected: Bool
    var showsMenuHint: Bool = false

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Theme.accentText : Theme.inkTertiary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(VoyageDate.short(day.date))
                        .font(Theme.Font.supportEmphasis.monospacedDigit())
                        .foregroundStyle(isSelected || hovering ? Theme.ink : Theme.inkSecondary)
                        .lineLimit(1)

                    if showsMenuHint {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }

                Text(detail)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        // Capped so a long yacht name cannot push every other day off the
        // row — the strip exists to show them all at once.
        .frame(maxWidth: 190, alignment: .leading)
        .contentShape(Rectangle())
        .philonInset(highlighted: isSelected)
        // A day with nothing live on it reads as put away without leaving the
        // row.
        .opacity(day.isArchived && !isSelected ? 0.55 : 1)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
