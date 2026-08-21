import SwiftUI

/// The documents on this trip, with the one thing the old list got wrong:
/// status reflects what the operator has confirmed, not what the MRZ check
/// digit guessed.
///
/// A panel now, not a column with its own chrome — every action it used to
/// carry moved to the window's command line, so what is left is a header and
/// the list it names.
struct DocumentColumn: View {
    @Environment(CrewStore.self) private var store
    @Binding var importing: Bool
    @State private var pendingDeletion: CrewDocument?

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            PanelHeader(eyebrow: "Documents", title: title) {
                if !store.selectedTripDocuments.isEmpty {
                    HStack(spacing: 5) {
                        CountBadge(count: cleared, tint: cleared == store.selectedTripDocuments.count ? Theme.success : Theme.accentText)
                        Text("of \(store.selectedTripDocuments.count)")
                            .font(Theme.Font.meta.monospacedDigit())
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
            }

            List(selection: $store.selectedDocumentID) {
                ForEach(store.selectedTripDocuments) { document in
                    DocumentRow(
                        document: document,
                        role: store.role(forPersonID: document.personID),
                        isSelected: store.selectedDocumentID == document.id
                    )
                    .tag(document.id)
                    .listRowSeparator(.hidden)
                    // The card is opaque, so the List's own selection highlight
                    // would draw behind it and never be seen. Selection is drawn
                    // on the card instead; the row background is cleared so
                    // nothing shows through the gaps between cards.
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .contextMenu {
                        Button("Make Skipper") { store.setRole(.skipper, forPersonID: document.personID) }
                        Button("Make Passenger") { store.setRole(.passenger, forPersonID: document.personID) }
                        Divider()
                        Button("Delete Document…", role: .destructive) { pendingDeletion = document }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            // The maker's mark sits in the window's bottom-left corner, which
            // this panel reaches. The scroll content ends above it rather than
            // running under it.
            .contentMargins(.bottom, MakersMark.reservedHeight, for: .scrollContent)
            .overlay { emptyState }
        }
        .background(Theme.panelRecessed)
        .confirmationDialog(
            "Delete this document?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let document = pendingDeletion { store.deleteDocument(document.id) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The encrypted original and every revision are erased from this Mac.")
        }
    }

    private var title: String {
        store.selectedBoat.map { $0.name.isEmpty ? "Untitled yacht" : $0.name } ?? "No trip selected"
    }

    private var cleared: Int {
        store.selectedTripDocuments.filter { $0.canExport() }.count
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.selectedTripID == nil {
            PhilonEmptyState(
                symbol: "sailboat",
                title: "No trip selected",
                message: "Choose a trip from the picker in the command line above."
            )
        } else if store.selectedTripDocuments.isEmpty {
            PhilonEmptyState(
                symbol: "doc.text.viewfinder",
                title: "No documents",
                message: "Import a photo or scan of each crew member's passport. Everything stays encrypted on this Mac."
            ) {
                Button("Import Documents…") { importing = true }
                    .buttonStyle(.philonPrimary)
            }
        }
    }
}

/// `.queue-list article` — a status mark, the identity, and how far the review
/// has got, as one card.
private struct DocumentRow: View {
    let document: CrewDocument
    let role: CrewRole
    let isSelected: Bool

    private var status: ReviewStatus { document.reviewStatus() }

    private var mark: StatusMark.Kind {
        switch status {
        case .cleared: .success
        case .inProgress: .neutral
        case .awaitingReview: .caution
        case .rejected: .danger
        }
    }

    private var tint: Color {
        switch mark {
        case .success: Theme.success
        case .caution: Theme.caution
        case .danger: Theme.danger
        case .neutral: Theme.accentText
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusMark(kind: mark, symbol: status.symbol, size: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(document[.fullName].isEmpty ? document.originalName : document[.fullName])
                        .font(Theme.Font.bodyEmphasis)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if role == .skipper {
                        Text("SKIPPER")
                            .font(Theme.Font.eyebrow)
                            .tracking(0.4)
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
                    }
                }

                Text(document[.documentNumber].isEmpty ? "No number" : document[.documentNumber])
                    .font(Theme.Font.monoMeta)
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Text(status.label)
                        .font(Theme.Font.eyebrow)
                        .tracking(0.3)
                        .foregroundStyle(tint)

                    if status != .cleared, status != .rejected {
                        PhilonProgress(value: document.reviewProgress, height: 4)
                            .frame(maxWidth: 54)
                        Text("\(Int(document.reviewProgress * 100))%")
                            .font(Theme.Font.eyebrow.monospacedDigit())
                            .foregroundStyle(Theme.inkTertiary)
                            .fixedSize()
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .philonInset(highlighted: isSelected)
    }
}
