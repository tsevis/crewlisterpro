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
                            isSuggested: document.isSuggested(field),
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
                    crewLibrary
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
            .accessibilityIdentifier("review.role")

            Text("A crew list needs exactly one skipper; naming a new one demotes the previous.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            clientToggle

            // Only where it is asked for. A field that appears for every
            // passenger invites an address to be typed into all of them, and
            // the crew list carries exactly one.
            if role == .skipper { skipperEmail }
        }
    }

    /// Beside the role rather than inside it: the client chartered the yacht
    /// and is aboard as the skipper or as a passenger, so it is a second fact
    /// about the same person and not a third option.
    private var clientToggle: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: Binding(
                get: { store.isClient(personID: document.personID) },
                set: { store.setClient($0, forPersonID: document.personID) }
            )) {
                Text("Client — signs the papers for this charter")
                    .font(Theme.Font.support)
                    .foregroundStyle(Theme.ink)
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("review.client")

            Text("One person per trip. Naming a new client clears the previous one.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
    }

    private var skipperEmail: some View {
        let value = store.email(forPersonID: document.personID)
        let validation = ContactValidator.validate(email: value)

        return VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: "Skipper's email")

            CommitField(
                identifier: "review.skipperEmail",
                placeholder: "skipper@example.com",
                value: value,
                isSuspect: validation.message != nil,
                onCommit: { store.setEmail($0, forPersonID: document.personID) }
            )

            Text(validation.message ?? "Printed on the crew list. The only contact detail this app collects.")
                .font(Theme.Font.meta)
                .foregroundStyle(validation.message == nil ? Theme.inkTertiary : Theme.caution)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    /// Keeps this person for the next charter, scan and all.
    ///
    /// Here rather than only in a context menu because this is the moment it
    /// makes sense: the operator has just finished confirming these seven
    /// fields against that image, and the offer to never do it again for this
    /// person belongs at the end of that work.
    private var crewLibrary: some View {
        let kept = store.isInCrewLibrary(documentID: document.id)

        return VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: "Crew library")

            HStack(spacing: 8) {
                Button(kept ? "Update in Crew Library" : "Keep in Crew Library",
                       systemImage: kept ? "arrow.triangle.2.circlepath" : "person.crop.rectangle.stack.fill") {
                    Task { await store.keepInCrewLibrary(documentID: document.id) }
                }
                .buttonStyle(.philonQuiet)
                .accessibilityIdentifier("review.keepInCrewLibrary")

                Spacer(minLength: 0)
            }

            Text(kept
                 ? "Already kept. Keeping again replaces what the library holds with what is confirmed here now."
                 : "Keeps these values and a copy of this scan in the Crew Library, so the next charter this person sails on does not ask for the photograph again. The copy stays when this trip is deleted.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let isSuggested: Bool
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
        case .valid:
            if focused { Theme.accentText.opacity(0.55) }
            else if isSuggested { Theme.machine.opacity(0.5) }
            else { Theme.hairlineStrong }
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
                    .onChange(of: value) { _, newValue in if !focused { draft = field.presented(newValue) } }
                    .onAppear { draft = field.presented(value) }

                // A model's value looks exactly like a checksum-validated one
                // unless the interface says otherwise. On a damaged document it
                // can be confidently wrong — a June birth date came back as
                // April, which passes every rule here — and the operator
                // checking it is reading the same unreadable line the model
                // guessed from.
                //
                // The example used to be MINCHUK read as MIHCHYK. The rescue
                // offers neither names nor dates now (see `CrewField.rescuable`),
                // so this warning sits on a document number alone — a long
                // alphanumeric string where one transposed character is exactly
                // what nothing downstream can catch.
                if isSuggested {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 9))
                        Text("Read by the local model, not from the machine-readable zone. Check it character by character.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.machine)
                }

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
            .accessibilityIdentifier("review.confirm.\(field.rawValue)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isVerified ? Theme.verifiedFill.opacity(0.5) : Color.clear)
    }

    /// A date typed as `20 oct 1972` is stored as `1972-10-20` and comes back
    /// as `20 OCT 1972`; one that parses as neither is stored as typed, so the
    /// validation line under the field can say what is wrong with it.
    private func commit() {
        let canonical = field.stored(draft)
        guard canonical != value else {
            // Nothing changed, but the operator may have typed a second spelling
            // of the same day. Show it back in the one this app uses.
            draft = field.presented(value)
            return
        }
        onEdit(canonical)
        draft = field.presented(canonical)
    }
}
