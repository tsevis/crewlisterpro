import SwiftUI

/// The fields read out of the document, each one editable and confirmed
/// individually, beside the image they came from.
///
/// A panel of Philon's `.conversion-grid` now. Confirm All Valid and Reject
/// moved to the window's command line — every action in this window is on one
/// line, and a panel that carried its own buttons would break that.
struct FieldReviewPane: View {
    @Environment(CrewStore.self) private var store
    let document: CrewDocument

    private var role: CrewRole { store.role(forPersonID: document.personID) }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(eyebrow: "Review", title: document.reviewStatus().label) {
                StatusMark(
                    kind: document.canExport() ? .success : (document.reviewStatus() == .rejected ? .danger : .caution),
                    symbol: document.reviewStatus().symbol,
                    size: 22
                )
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    progress

                    VStack(spacing: 0) {
                        ForEach(CrewField.reviewOrder) { field in
                            FieldRow(
                                field: field,
                                value: document[field],
                                validation: document.validation(of: field),
                                isVerified: document.isVerified(field),
                                onEdit: { store.setField(field, to: $0, on: document.id) },
                                onToggleVerified: { store.setVerified($0, field: field, on: document.id) }
                            )
                            if field != CrewField.reviewOrder.last {
                                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 130)
                            }
                        }
                    }
                    .philonInset(radius: Theme.Radius.panel)

                    rolePicker
                    extractionNotes
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
            .contentMargins(.bottom, MakersMark.reservedHeight, for: .scrollContent)
        }
        .background(Theme.panelRecessed)
    }

    /// `.task-progress` — how far this document has got, and what is left.
    private var progress: some View {
        let remaining = document.blockingFields()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PhilonProgress(value: document.reviewProgress)
                Text("\(Int(document.reviewProgress * 100))%")
                    .font(Theme.Font.metaEmphasis.monospacedDigit())
                    .foregroundStyle(Theme.accentText)
                    .fixedSize()
            }

            Text(remaining.isEmpty
                 ? "Every required field confirmed against the image."
                 : "Still to confirm: \(remaining.map(\.label).joined(separator: ", "))")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(document.originalName)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(document.originalName)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .philonInset()
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: "Role on this trip")

            Picker("Role", selection: Binding(
                get: { role },
                set: { store.setRole($0, forPersonID: document.personID) }
            )) {
                ForEach(CrewRole.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("A crew list needs exactly one skipper; naming a new one demotes the previous.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `.warning-list` — what extraction could not settle, said plainly rather
    /// than smoothed into the fields as if it had been read.
    @ViewBuilder
    private var extractionNotes: some View {
        if !document.riskReasons.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow(text: "Extraction notes")
                ForEach(document.riskReasons, id: \.self) { reason in
                    PhilonNote(kind: noteKind(for: reason), message: reason)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A note that reports a clean checksum is not a warning; everything else
    /// is something the operator has to act on.
    private func noteKind(for reason: String) -> PhilonNote.Kind {
        reason.localizedCaseInsensitiveContains("checksum-valid") ? .verified : .warning
    }
}

// MARK: - One field

/// Label, editable value, validation feedback and a confirm control. Editing a
/// value clears its confirmation, so a correction is always re-checked.
///
/// The confirm control is a filled disc against an empty ring. A ring and a
/// disc differ in shape as well as fill, so the state survives being read by
/// someone who cannot separate the two tints.
private struct FieldRow: View {
    let field: CrewField
    let value: String
    let validation: FieldValidation
    let isVerified: Bool
    let onEdit: (String) -> Void
    let onToggleVerified: (Bool) -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    private var messageTint: Color {
        switch validation {
        case .valid: Theme.inkTertiary
        case .warning: Theme.caution
        case .invalid: Theme.danger
        }
    }

    private var borderTint: Color {
        switch validation {
        case .invalid: Theme.danger.opacity(0.55)
        case .warning: Theme.caution.opacity(0.5)
        case .valid: focused ? Theme.accentText.opacity(0.55) : Theme.hairlineStrong
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(field.label)
                .font(Theme.Font.support)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 110, alignment: .trailing)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                TextField(field.placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .font(field == .documentNumber ? Theme.Font.mono : Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                            .strokeBorder(borderTint, lineWidth: 1)
                    )
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                    .onChange(of: value) { _, newValue in if !focused { draft = newValue } }
                    .onAppear { draft = value }

                if let message = validation.message {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: validation.isBlocking ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(message).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Theme.Font.meta)
                    .foregroundStyle(messageTint)
                }
            }

            Button {
                onToggleVerified(!isVerified)
            } label: {
                Image(systemName: isVerified ? "checkmark" : "circle")
                    .font(.system(size: isVerified ? 11 : 9, weight: .bold))
                    .foregroundStyle(isVerified ? Theme.accentInk : Theme.inkTertiary)
                    .frame(width: 22, height: 22)
                    .background {
                        if isVerified {
                            Circle().fill(Theme.success)
                        } else {
                            Circle().strokeBorder(Theme.hairlineStrong, lineWidth: 1.5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(validation.isBlocking)
            .opacity(validation.isBlocking ? 0.4 : 1)
            .padding(.top, 4)
            .help(validation.isBlocking
                  ? "Fix this value before confirming it."
                  : (isVerified ? "Confirmed against the document image" : "Confirm this matches the document image"))
            .accessibilityLabel("\(field.label) confirmed")
            .accessibilityAddTraits(isVerified ? [.isSelected] : [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isVerified ? Theme.verifiedFill.opacity(0.5) : Color.clear)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != value else { return }
        onEdit(trimmed)
    }
}
