import SwiftUI

/// One yacht: the four values a port authority reads, what they will look like
/// printed, and what can be done with the vessel.
///
/// The preview is the point of this pane. These four fields are printed into
/// four boxes across the top of every crew list made for this yacht, and an
/// operator filling in a form has no way to know that unless the form shows
/// them. A blank box in the preview is a blank box on the paper.
struct FleetDetail: View {
    @Environment(CrewStore.self) private var store
    let boat: Boat
    let onRetire: () -> Void
    let onRestore: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var trips: Int { store.tripCount(forBoatID: boat.id) }
    private var isDefault: Bool { store.settings.defaultBoatID == boat.id }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(eyebrow: boat.isRetired ? "Retired yacht" : "Yacht",
                        title: boat.displayName) {
                if trips > 0 {
                    Text(trips == 1 ? "1 trip" : "\(trips) trips")
                        .font(Theme.Font.meta.monospacedDigit())
                        .foregroundStyle(Theme.inkTertiary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if boat.isRetired { retiredNote }

                    FormSection(title: "In this app") {
                        field("Your name for it", placeholder: boat.isComplete ? boat.name : "The blue one", \.nickname)
                        FormRule()
                        FormCaption("What the fleet list, the trip strip and the document panel call this yacht. Nothing here is printed — a port authority reads the registered name below. Leave it empty to be shown that name everywhere.")
                    }

                    FormSection(title: "Printed on every crew list") {
                        field("Name", placeholder: "S/Y ELPIDA", \.name)
                        FormRule()
                        field("Flag", placeholder: "GRC", \.flag, uppercased: true)
                        FormRule()
                        field("Port of registry", placeholder: "PIRAEUS", \.registrationPort, uppercased: true)
                        FormRule()
                        field("Registration no.", placeholder: "GR-1187-P", \.registrationNumber, uppercased: true)
                    }

                    preview
                    useForNewTrips
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
    }

    // MARK: - Editing

    /// Saves through the store when the field is left, so an emptied name
    /// cannot overwrite a real one: `CrewStore.updateBoat` refuses a blank.
    ///
    /// A key path rather than a binding into `boat`, which is a `let` copy of
    /// a store record — writing to it would change nothing and look like it had.
    private func field(
        _ label: String,
        placeholder: String,
        _ keyPath: WritableKeyPath<Boat, String>,
        uppercased: Bool = false
    ) -> some View {
        FormRow(label: label) {
            CommitField(
                identifier: "fleet.field.\(label.lowercased().replacingOccurrences(of: " ", with: "-"))",
                placeholder: placeholder,
                value: boat[keyPath: keyPath],
                normalise: uppercased ? { $0.uppercased() } : { $0 }
            ) { typed in
                var updated = boat
                updated[keyPath: keyPath] = typed
                store.updateBoat(updated)
            }
        }
    }

    // MARK: - What it looks like printed

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "On the crew list")

            HStack(spacing: 0) {
                previewBox("YACHT", boat.isComplete ? boat.name : "")
                previewBox("FLAG", boat.flag)
                previewBox("PORT OF REGISTRY", boat.registrationPort)
                previewBox("REG NO", boat.registrationNumber, isLast: true)
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                .strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))

            if !missing.isEmpty {
                PhilonNote(kind: .warning, message: "\(missing.joined(separator: " and ")) would print blank. Export is blocked until the yacht has a name and a flag.")
            }
        }
    }

    private var missing: [String] {
        var blanks: [String] = []
        if !boat.isComplete { blanks.append("The name") }
        if boat.flag.trimmingCharacters(in: .whitespaces).isEmpty { blanks.append("the flag") }
        return blanks
    }

    private func previewBox(_ caption: String, _ value: String, isLast: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption)
                .font(Theme.Font.eyebrow)
                .tracking(0.3)
                .foregroundStyle(Theme.inkTertiary)
            Text(value.isEmpty ? "—" : value)
                .font(Theme.Font.support)
                .foregroundStyle(value.isEmpty ? Theme.inkTertiary : Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Theme.panel)
        // Between the boxes, not after the last one — the panel's own border
        // is already there.
        .overlay(alignment: .trailing) {
            if !isLast { Rectangle().fill(Theme.hairline).frame(width: 1) }
        }
    }

    // MARK: - Defaults and actions

    private var useForNewTrips: some View {
        FormSection(title: "New trips") {
            FormRow(label: "Default", labelWidth: 118) {
                Toggle(isOn: Binding(
                    get: { isDefault },
                    set: { setDefault($0) }
                )) {
                    Text("New trips are for this yacht")
                        .font(Theme.Font.support)
                        .foregroundStyle(Theme.ink)
                }
                .toggleStyle(.checkbox)
                .disabled(boat.isRetired)
            }
            FormRule()
            // Says what actually happens rather than what the checkbox is
            // called. Without a default a new trip takes the yacht last
            // chartered, which the old wording did not mention at all.
            FormCaption(isDefault
                ? "Every new trip is for this yacht until another is made the default. A retired yacht is never chosen, and retiring the default clears it."
                : "With no default set, a new trip is for the yacht last chartered. A retired yacht is never chosen.")
        }
    }

    private func setDefault(_ wanted: Bool) {
        var settings = store.settings
        settings.defaultBoatID = wanted ? boat.id : nil
        store.updateSettings(settings)
    }

    private var retiredNote: some View {
        PhilonNote(
            kind: .warning,
            message: "This yacht is retired. It is not offered for new trips, and the \(trips) charter\(trips == 1 ? "" : "s") already made for it are unchanged."
        )
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: "This yacht")

            HStack(spacing: 8) {
                Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                    .buttonStyle(.philonQuiet)
                    .accessibilityIdentifier("fleet.duplicate")
                    .help("A sister ship: everything but the name and the registration number")

                if boat.isRetired {
                    Button("Return to Fleet", systemImage: "arrow.uturn.backward", action: onRestore)
                        .buttonStyle(.philonSecondary)
                        .accessibilityIdentifier("fleet.restore")
                } else {
                    Button("Retire", systemImage: "archivebox", action: onRetire)
                        .buttonStyle(.philonQuiet)
                        .accessibilityIdentifier("fleet.retire")
                        .help("Out of the fleet, still named on its past crew lists")
                }

                Spacer(minLength: 8)

                Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
                    .buttonStyle(.philonQuiet(role: .destructive))
                    .accessibilityIdentifier("fleet.delete")
                    .disabled(trips > 0)
                    .help(trips > 0
                          ? "\(trips) trip\(trips == 1 ? " uses" : "s use") this yacht. Retire it instead, or delete those trips first."
                          : "No trip uses this yacht")
            }
        }
    }
}
