import AppKit
import SwiftUI

/// One kept person: what was confirmed about them, the scan it was confirmed
/// against, and the way onto the trip in hand.
///
/// Read-only, deliberately. These values were confirmed against the image
/// beside them by an operator who was looking at both; a box here that could be
/// typed into would let that pairing come apart silently, and the corrected
/// value would carry the authority of the confirmed one. A passport that has
/// been renewed is imported as the new document it is, and keeping that person
/// again replaces this entry.
struct CrewLibraryDetail: View {
    @Environment(CrewStore.self) private var store
    let saved: SavedCrewMember
    let onRemove: () -> Void

    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(eyebrow: saved.role == .skipper ? "Skipper" : "Passenger",
                        title: saved.displayName) {
                Text(confirmed)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    addToTrip

                    FormSection(title: "Confirmed on the crew list") {
                        ForEach(Array(Self.shown.enumerated()), id: \.element) { index, field in
                            if index > 0 { FormRule() }
                            FormRow(label: field.label) {
                                Text(value(of: field))
                                    .font(Theme.Font.support)
                                    .foregroundStyle(saved[field].isEmpty ? Theme.inkTertiary : Theme.ink)
                                    .textSelection(.enabled)
                            }
                        }
                        if !saved.email.isEmpty {
                            FormRule()
                            FormRow(label: "Skipper's email") {
                                Text(saved.email)
                                    .font(Theme.Font.support)
                                    .foregroundStyle(Theme.ink)
                                    .textSelection(.enabled)
                            }
                        }
                        FormRule()
                        FormCaption("These are read from the scan below, not editable here — they were confirmed against that image by someone looking at both. A renewed passport is imported as the new document it is, and keeping that person again replaces this entry.")
                    }

                    scan
                    actions
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
            .contentMargins(.bottom, MakersMark.reservedHeight, for: .scrollContent)
        }
        .background(Theme.panelRecessed)
        .task(id: saved.id) { await load() }
    }

    /// Everything a crew list prints, plus the document type — the same seven
    /// the review pane shows, in the same order.
    private static let shown: [CrewField] = [
        .fullName, .documentNumber, .documentType, .nationality, .birthDate, .sex, .expiryDate,
    ]

    private func value(of field: CrewField) -> String {
        let stored = saved[field]
        guard !stored.isEmpty else { return "—" }
        // Dates are stored ISO and read by a person, exactly as they are in the
        // review pane and on the printed form.
        guard field == .birthDate || field == .expiryDate else { return stored }
        return DocumentDate.display(stored)
    }

    private var confirmed: String {
        guard let confirmedAt = saved.confirmedAt else { return "Kept before every field was confirmed" }
        return "Confirmed \(VoyageDate.printed(confirmedAt))"
    }

    // MARK: - Onto a trip

    private var addToTrip: some View {
        PhilonNote(
            kind: store.selectedTripID == nil ? .warning : .verified,
            message: store.selectedTripID == nil
                ? "Pick a trip in the strip above to put \(saved.displayName) on it."
                : "Adding \(saved.displayName) to \(tripDescription) puts these values and this scan on that trip. Every field still has to be confirmed there — the saving is the upload, not the checking."
        )
    }

    private var tripDescription: String {
        guard let trip = store.selectedTrip else { return "this trip" }
        let boat = store.boat(for: trip)?.displayName ?? "Untitled yacht"
        return "\(boat) on \(VoyageDate.printed(trip.departureDate))"
    }

    // MARK: - The scan

    @ViewBuilder
    private var scan: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "The scan this was read from")

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 380)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                        .strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            } else if loadFailed {
                PhilonNote(kind: .warning, message: "The kept scan could not be read. This person can still be added to a trip, but their fields will have no image to check against — import the passport again and keep them afresh.")
            } else if saved.encryptedFileName.isEmpty {
                PhilonNote(kind: .warning, message: "No scan was kept for this person. Adding them fills in the fields, and the trip will have nothing to check them against.")
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    private func load() async {
        image = nil
        loadFailed = false
        guard !saved.encryptedFileName.isEmpty else { return }
        guard let data = await store.crewLibraryImageData(for: saved), let decoded = NSImage(data: data) else {
            loadFailed = true
            return
        }
        image = decoded
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: "This person")

            HStack(spacing: 8) {
                Button("Add to This Trip", systemImage: "person.badge.plus") {
                    Task { await store.addFromCrewLibrary(saved.id) }
                }
                .buttonStyle(.philonPrimary)
                .accessibilityIdentifier("crew.add")
                .disabled(store.selectedTripID == nil)

                Spacer(minLength: 8)

                Button("Remove…", systemImage: "trash", role: .destructive, action: onRemove)
                    .buttonStyle(.philonQuiet(role: .destructive))
                    .accessibilityIdentifier("crew.remove")
                    .help("Leaves the library and erases the library's copy of the scan")
            }
        }
    }
}
