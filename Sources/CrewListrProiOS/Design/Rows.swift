import SwiftUI

/// One charter, as it reads in a list.
///
/// The yacht's own name comes first because that is what an operator is looking
/// for, and the dates second because that is what a port authority asks for.
/// The count on the right is the thing the Mac's strip put on every chip: how
/// many of this charter's documents are actually finished.
struct TripRow: View {
    @Environment(CrewStore.self) private var store
    let trip: Trip

    private var boat: Boat? { store.boat(for: trip) }

    private var documents: [CrewDocument] { store.data.documents.filter { $0.tripID == trip.id } }
    private var cleared: Int { documents.filter { $0.canExport() }.count }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(boat?.displayName ?? "Untitled yacht")
                        .font(Theme.Font.bodyEmphasis)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if trip.isArchived {
                        Text("Archived")
                            .font(Theme.Font.meta)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                Text("\(VoyageDate.printed(trip.departureDate)) – \(VoyageDate.printed(trip.returnDate))")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 6)
            if documents.isEmpty {
                Text("No documents")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
            } else {
                // "3 / 5" and not a percentage: the operator's next action is
                // to finish the two that are not done, and a percentage hides
                // how many that is.
                Text("\(cleared) / \(documents.count)")
                    .font(Theme.Font.meta.monospacedDigit())
                    .foregroundStyle(cleared == documents.count ? Theme.success : Theme.inkSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One document in a charter, showing the status the *operator* has reached —
/// never what a check digit guessed. A freshly imported passport with a perfect
/// machine-readable zone still reads "Awaiting review".
struct DocumentRow: View {
    let document: CrewDocument

    private var status: ReviewStatus { document.reviewStatus() }

    private var kind: StatusMark.Kind {
        switch status {
        case .cleared: .success
        case .rejected: .danger
        case .inProgress: .caution
        case .awaitingReview: .neutral
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            StatusMark(kind: kind, symbol: status.symbol, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(document[.fullName].isEmpty ? document.originalName : document[.fullName])
                    .font(Theme.Font.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(status.label)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 6)
            if status != .cleared, status != .rejected {
                PhilonProgress(value: document.reviewProgress)
                    .frame(width: 54)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The one sentence naming the next thing standing between this charter and a
/// crew list.
///
/// The Mac shows the whole list; a phone shows the first and says how many
/// follow. Either way it is a sentence and not a greyed-out button: "Name the
/// yacht." tells the operator what to do, and a disabled Export does not.
struct ReadinessNote: View {
    let blockers: [String]

    var body: some View {
        if blockers.isEmpty {
            PhilonNote(kind: .verified, title: "Ready", message: "Every field on every document has been confirmed.")
        } else {
            PhilonNote(
                kind: .warning,
                title: blockers.count == 1 ? "One thing left" : "\(blockers.count) things left",
                message: blockers.first ?? ""
            )
        }
    }
}
