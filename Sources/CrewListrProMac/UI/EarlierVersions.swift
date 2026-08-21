import SwiftUI

/// The snapshots the store keeps of itself, and the way back to one.
///
/// The store snapshots the state it is about to replace before every write, so
/// a bad write is recoverable. That was only reachable from the command line,
/// which is not a recovery path for an operator who has just watched their
/// crew list empty itself — the moment you need it is the moment you are least
/// likely to go looking for a terminal.
///
/// Each entry is named by what it contains as well as when it was taken, since
/// "1 trip, 6 documents" is what an operator recognises and a timestamp is not.
struct EarlierVersions: View {
    @Environment(CrewStore.self) private var store

    @State private var backups: [SecureStore.Backup] = []
    @State private var pendingRestore: SecureStore.Backup?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Eyebrow(text: "Earlier versions")
                Spacer(minLength: 0)
                Button("Save a Version Now") {
                    Task { await store.snapshot(); await reload() }
                }
                .buttonStyle(.philonQuiet)
                .font(Theme.Font.meta)
            }

            if loading {
                row { ProgressView().controlSize(.small) }
            } else if backups.isEmpty {
                row {
                    Text("No earlier versions yet. One is kept automatically before each change.")
                        .font(Theme.Font.meta)
                        .foregroundStyle(Theme.inkTertiary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(backups.enumerated()), id: \.element.id) { index, backup in
                        BackupRow(backup: backup) { pendingRestore = backup }
                        if index != backups.count - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 12)
                        }
                    }
                }
                .philonInset(radius: Theme.Radius.panel)
            }

            Text("A version is saved before every change, and restoring saves one too — so coming back is undoable as well.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await reload() }
        .confirmationDialog(
            "Restore this version?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore") {
                if let backup = pendingRestore {
                    Task { await store.restore(backup.id); await reload() }
                }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            if let backup = pendingRestore {
                Text("""
                     This replaces everything on this Mac with \(backup.summary), as it was on \
                     \(backup.created.formatted(date: .abbreviated, time: .shortened)).

                     The current state is saved as a version first, so you can come back to it.
                     """)
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content(); Spacer(minLength: 0) }
            .padding(11)
            .philonInset(radius: Theme.Radius.panel)
    }

    private func reload() async {
        loading = true
        backups = await store.backups()
        loading = false
    }
}

private struct BackupRow: View {
    let backup: SecureStore.Backup
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accentText)

            VStack(alignment: .leading, spacing: 2) {
                Text(backup.created.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Font.supportEmphasis)
                    .foregroundStyle(Theme.ink)
                Text(backup.summary)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer(minLength: 8)

            Button("Restore…", action: onRestore)
                .buttonStyle(.philonSecondary)
                .font(Theme.Font.meta)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

extension SecureStore.Backup {
    /// What an operator recognises. A timestamp alone does not say which of two
    /// versions is the one with the crew still in it.
    var summary: String {
        let trip = trips == 1 ? "1 trip" : "\(trips) trips"
        let document = documents == 1 ? "1 document" : "\(documents) documents"
        return "\(trip), \(document)"
    }
}
