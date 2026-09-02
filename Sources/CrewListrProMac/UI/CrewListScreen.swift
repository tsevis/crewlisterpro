import AppKit
import SwiftUI

/// What the port authority is about to be handed, and — when it cannot be
/// handed over yet — every reason why.
///
/// This was a modal sheet. A sheet is the right shape for a question that has
/// to be answered before anything else can happen, and "what does the crew list
/// look like so far" is not that: it is a place an operator moves between while
/// working, which is a screen.
struct CrewListScreen: View {
    @Environment(CrewStore.self) private var store

    private var rows: [CrewListRow] { store.selectedTripID.map(store.crewRows(forTripID:)) ?? [] }
    private var blockers: [String] { store.exportBlockers }

    var body: some View {
        DocumentGrid {
            VStack(spacing: 0) {
                PanelHeader(
                    eyebrow: blockers.isEmpty ? "Ready to export" : "Not ready yet",
                    title: heading
                )

                if blockers.isEmpty {
                    metrics
                    table
                } else {
                    blockerList
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var heading: String {
        guard let boat = store.selectedBoat, let trip = store.selectedTrip else { return "No trip selected" }
        let name = boat.name.isEmpty ? "Untitled yacht" : boat.name
        return "\(name) · \(boat.flag.isEmpty ? "no flag" : boat.flag) · \(VoyageDate.printed(trip.departureDate)) → \(VoyageDate.printed(trip.returnDate))"
    }

    /// `.batch-metrics`
    private var metrics: some View {
        HStack(spacing: 8) {
            PhilonMetric(value: "\(rows.count)", label: "On the list")
            PhilonMetric(
                value: "\(rows.filter { $0.role == .skipper }.count)",
                label: "Skipper",
                tint: rows.contains { $0.role == .skipper } ? Theme.accentText : Theme.caution
            )
            PhilonMetric(
                value: rows.contains(where: \.isClient) ? "1" : "—",
                label: "Client",
                tint: rows.contains(where: \.isClient) ? Theme.accentText : Theme.inkTertiary
            )
            PhilonMetric(value: "2", label: "Files written (CSV, PDF)")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var table: some View {
        Table(rows, columns: {
            TableColumn("Role") { row in
                Text(row.role.label)
                    .font(row.role == .skipper ? Theme.Font.supportEmphasis : Theme.Font.support)
                    .foregroundStyle(row.role == .skipper ? Theme.accentText : Theme.inkSecondary)
            }
            .width(90)
            // Its own column rather than a suffix on the role: the client is a
            // second fact about the person, and a passenger who signs reads as
            // neither "Passenger" nor "Client" alone.
            TableColumn("Client") { row in
                Text(row.isClient ? "Signs" : "")
                    .font(Theme.Font.supportEmphasis)
                    .foregroundStyle(Theme.accentText)
            }
            .width(56)
            TableColumn("Full name") { Text($0.fullName).font(Theme.Font.support).foregroundStyle(Theme.ink) }
            TableColumn("Passport no.") { Text($0.documentNumber).font(Theme.Font.monoMeta) }.width(120)
            TableColumn("Nationality") { Text($0.nationality).font(Theme.Font.support) }.width(120)
            TableColumn("Birthday") { Text($0.printedBirthDate).font(Theme.Font.monoMeta) }.width(104)
            TableColumn("Sex") { Text($0.sex).font(Theme.Font.support) }.width(44)
        })
        // Without this the inset style stripes every row slot in the panel,
        // not just the occupied ones — six crew read as six names followed by
        // twenty empty grey bands.
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    /// Every reason as its own card. A crew list one field short and one missing
    /// the yacht's name are different problems, and one sentence hides that.
    private var blockerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(blockers, id: \.self) { blocker in
                    PhilonNote(kind: .warning, message: blocker)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .contentMargins(.bottom, MakersMark.reservedHeight, for: .scrollContent)
    }
}

/// The primary action for the crew-list screen, in the window's command line.
struct ExportButton: View {
    @Environment(CrewStore.self) private var store
    @State private var exported: URL?

    var body: some View {
        HStack(spacing: 8) {
            if let exported {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([exported])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.philonSecondary)
                .help(exported.path(percentEncoded: false))
            }

            Button {
                export()
            } label: {
                Label("Export CSV and PDF…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.philonPrimary)
            .disabled(!store.exportBlockers.isEmpty)
            .help(store.exportBlockers.isEmpty
                  ? "Write the crew list beside a folder you choose"
                  : store.exportBlockers.joined(separator: "\n"))
        }
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose the folder for the crew list CSV and PDF."
        // A directory picker, not a save panel whose filename was then thrown
        // away in favour of its parent directory.
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            try store.exportSelectedTrip(to: directory)
            exported = directory
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
