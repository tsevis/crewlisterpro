import SwiftUI

/// The people this operator keeps, apart from any charter.
///
/// The same shape as the Fleet, because it is the same job: a list of things
/// you own on the left, the one you are looking at on the right. A yacht is
/// described once and chartered all season; so is a skipper, and until now the
/// app made an operator photograph and re-upload the same passport every week —
/// then erased it with the trip.
///
/// The scan is the part that matters. A remembered set of fields with no
/// document behind it would put a name on a crew list nobody could check
/// against anything, and this app does not do that. So the library keeps the
/// image too, and a person added to a trip arrives with it.
struct CrewLibraryScreen: View {
    @Environment(CrewStore.self) private var store
    @Binding var selection: UUID?

    @State private var pendingRemoval: SavedCrewMember?

    var body: some View {
        DocumentGrid {
            if store.crewLibrary.isEmpty {
                PhilonEmptyState(
                    symbol: "person.crop.rectangle.stack",
                    title: "Nobody kept yet",
                    message: "Confirm a passport on a trip, then choose Keep in Crew Library. The person and their scan stay here after the charter is over, so the next trip they sail on does not ask for the photograph again."
                )
                .frame(maxWidth: .infinity)
            } else {
                list
                    .frame(minWidth: 250, idealWidth: 290, maxWidth: 330)

                GridDivider()

                if let saved = selected {
                    CrewLibraryDetail(saved: saved, onRemove: { pendingRemoval = saved })
                        .frame(maxWidth: .infinity)
                } else {
                    PhilonEmptyState(
                        symbol: "person.crop.rectangle.stack",
                        title: "Select someone",
                        message: "Choose a person on the left to see what was confirmed about them, and the scan it was confirmed against."
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { if selection == nil { selection = store.crewLibrary.first?.id } }
        .confirmationDialog(
            "Remove this person from the library?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove and Erase the Scan", role: .destructive) {
                if let saved = pendingRemoval {
                    Task {
                        await store.removeFromCrewLibrary(saved.id)
                        selection = store.crewLibrary.first?.id
                    }
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(removalMessage)
        }
    }

    private var selected: SavedCrewMember? { selection.flatMap(store.savedCrewMember(withID:)) }

    /// An app that holds passport scans has to be able to forget them, and this
    /// is the sentence that says what forgetting one does.
    private var removalMessage: String {
        guard let saved = pendingRemoval else { return "" }
        return """
        \(saved.displayName) leaves the library and the library's copy of their scan is erased from this Mac.

        Trips they are already on keep their own copies and are not touched.
        """
    }

    // MARK: - The library

    private var list: some View {
        VStack(spacing: 0) {
            PanelHeader(eyebrow: "Crew library", title: title)

            List(selection: $selection) {
                ForEach(store.crewLibrary) { saved in
                    CrewLibraryRow(saved: saved, isSelected: selection == saved.id)
                        .tag(saved.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .contextMenu {
                            Button("Add to This Trip") {
                                Task { await store.addFromCrewLibrary(saved.id) }
                            }
                            .disabled(store.selectedTripID == nil)
                            Divider()
                            Button("Remove…", role: .destructive) { pendingRemoval = saved }
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, MakersMark.reservedHeight, for: .scrollContent)
        }
        .background(Theme.panelRecessed)
    }

    private var title: String {
        let count = store.crewLibrary.count
        guard count > 0 else { return "Nobody kept yet" }
        return count == 1 ? "1 person" : "\(count) people"
    }
}

// MARK: - One person in the list

private struct CrewLibraryRow: View {
    let saved: SavedCrewMember
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: saved.role == .skipper ? "sailboat.circle" : "person.crop.circle")
                .font(.system(size: 15))
                .foregroundStyle(isSelected ? Theme.accentText : Theme.inkTertiary)
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(saved.displayName)
                    .font(Theme.Font.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(saved.documentNumber.isEmpty ? "No number" : saved.documentNumber)
                    .font(Theme.Font.monoMeta)
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .philonInset(highlighted: isSelected)
    }

    /// What this person usually is, and when they were last aboard — the two
    /// things that tell four regulars apart from a long tail of one-offs.
    private var subtitle: String {
        let role = saved.role == .skipper ? "Skipper" : "Passenger"
        guard let used = saved.lastUsedAt else { return "\(role) · not used yet" }
        return "\(role) · last used \(VoyageDate.printed(used))"
    }
}
