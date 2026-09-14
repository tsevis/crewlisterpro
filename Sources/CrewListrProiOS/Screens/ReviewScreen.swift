import SwiftUI

/// One document, checked field by field against its own image.
///
/// This is the screen the whole application exists to make honest, and it is
/// the one place where the phone's layout genuinely differs from the Mac's. The
/// Mac puts the image and the fields side by side. A phone has no side, so the
/// page sits at the top, tappable to full screen, and the fields run under it —
/// and every field still carries its own confirm control, still refuses to be
/// confirmed while it is invalid, and still loses its confirmation the moment
/// it is edited.
struct ReviewScreen: View {
    @Environment(CrewStore.self) private var store
    let documentID: UUID

    @State private var scan: ScanState = .loading
    @State private var showingFullScreen = false
    @State private var rejecting = false
    @State private var rejectionReason = ""

    private var document: CrewDocument? { store.data.documents.first { $0.id == documentID } }

    var body: some View {
        Group {
            if let document {
                content(document)
            } else {
                PhilonEmptyState(symbol: "doc.badge.ellipsis", title: "This document is gone",
                                 message: "It was deleted while this screen was open.")
            }
        }
        .background(Theme.ground)
        .navigationTitle(document?[.fullName].isEmpty == false ? document![.fullName] : (document?.originalName ?? "Document"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.selectedDocumentID = documentID }
        .task(id: document?.imageRevisions.count) { await loadImage() }
        .fullScreenCover(isPresented: $showingFullScreen) {
            DocumentImageFullScreen(state: scan, title: document?.originalName ?? "Document")
        }
        .alert("Reject this document?", isPresented: $rejecting) {
            TextField("Why", text: $rejectionReason)
            Button("Reject", role: .destructive) {
                store.rejectDocument(documentID, reason: rejectionReason.isEmpty ? "Rejected by the operator." : rejectionReason)
                rejectionReason = ""
            }
            Button("Cancel", role: .cancel) { rejectionReason = "" }
        } message: {
            Text("A rejected document clears every confirmation and keeps the charter off a crew list until it is dealt with.")
        }
    }

    @ViewBuilder
    private func content(_ document: CrewDocument) -> some View {
        List {
            Section {
                DocumentImageView(state: scan, onOpenFullScreen: scan.data == nil ? nil : { showingFullScreen = true })
                    .frame(maxHeight: 300)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } header: {
                Text(document.originalName)
            } footer: {
                if scan.data != nil {
                    Text("Tap the page to open it full screen. The machine-readable zone is six-point type — read it magnified, not at page scale.")
                } else if scan == .missing {
                    // Said plainly rather than left to be inferred from a blank
                    // panel. Confirming a field is confirming it *against* the
                    // document, and there is nothing here to confirm it against.
                    Text("Without the scan there is nothing on this screen to check these values against. Import the passport again before confirming them.")
                }
            }

            progressSection(document)

            Section("The crew list's fields") {
                ForEach(CrewField.reviewOrder) { field in
                    ReviewFieldRow(
                        field: field,
                        value: document[field],
                        validation: document.validation(of: field),
                        isVerified: document.isVerified(field),
                        isSuggested: document.isSuggested(field),
                        onEdit: { store.setField(field, to: $0, on: documentID) },
                        onToggleVerified: { store.setVerified($0, field: field, on: documentID) }
                    )
                }
            }

            rolesSection(document)
            librarySection(document)
            notesSection(document)
            actionsSection(document)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - How far this has got

    @ViewBuilder
    private func progressSection(_ document: CrewDocument) -> some View {
        let remaining = document.blockingFields()
        Section {
            VStack(alignment: .leading, spacing: 8) {
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
            }
            .padding(.vertical, 4)

            // Confirms what already passes validation — never what does not,
            // and never a field the operator has not been able to see. It is a
            // shortcut through the tapping, not through the looking.
            Button {
                store.verifyAllValidFields(on: documentID)
            } label: {
                Label("Confirm Every Valid Field", systemImage: "checkmark.circle")
            }
            .disabled(remaining.isEmpty)
        }
    }

    // MARK: - Who this person is on this charter

    @ViewBuilder
    private func rolesSection(_ document: CrewDocument) -> some View {
        let role = store.role(forPersonID: document.personID)
        Section {
            Picker("Role", selection: Binding(
                get: { role },
                set: { store.setRole($0, forPersonID: document.personID) }
            )) {
                ForEach(CrewRole.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("Client — signs for this charter", isOn: Binding(
                get: { store.isClient(personID: document.personID) },
                set: { store.setClient($0, forPersonID: document.personID) }
            ))

            if role == .skipper {
                let email = store.email(forPersonID: document.personID)
                let validation = ContactValidator.validate(email: email)
                VStack(alignment: .leading, spacing: 4) {
                    // `prompt:` rather than the plain title, so the hint is
                    // grey. A bare title inherits the row's tint and renders
                    // the placeholder in the accent colour, which reads as a
                    // link, or worse as an address somebody actually typed.
                    TextField("", text: Binding(
                        get: { email },
                        set: { store.setEmail($0, forPersonID: document.personID) }
                    ), prompt: Text("skipper@example.com").foregroundStyle(Theme.inkTertiary))
                    .foregroundStyle(Theme.ink)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Text(validation.message ?? "Printed on the crew list. The only contact detail this app collects.")
                        .font(Theme.Font.meta)
                        .foregroundStyle(validation.message == nil ? Theme.inkTertiary : Theme.caution)
                }
            }
        } header: {
            Text("On this charter")
        } footer: {
            Text("A crew list needs exactly one skipper and names one client; setting either clears the previous one.")
        }
    }

    // MARK: - Keeping this person

    @ViewBuilder
    private func librarySection(_ document: CrewDocument) -> some View {
        let kept = store.isInCrewLibrary(documentID: documentID)
        Section {
            Button {
                Task { await store.keepInCrewLibrary(documentID: documentID) }
            } label: {
                Label(kept ? "Update in Crew Library" : "Keep in Crew Library",
                      systemImage: kept ? "arrow.triangle.2.circlepath" : "person.crop.rectangle.stack.fill")
            }
        } footer: {
            Text(kept
                 ? "Already kept. Keeping again replaces what the library holds with what is confirmed here now."
                 : "Keeps these values and a copy of this scan, so the next charter this person sails on does not ask for the photograph again. The copy stays when this charter is deleted.")
        }
    }

    @ViewBuilder
    private func notesSection(_ document: CrewDocument) -> some View {
        if !document.riskReasons.isEmpty {
            Section("What extraction could not settle") {
                ForEach(document.riskReasons, id: \.self) { reason in
                    PhilonNote(kind: reason.localizedCaseInsensitiveContains("checksum-valid") ? .verified : .warning,
                               message: reason)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
        }
    }

    // MARK: - Doing something to the file itself

    @ViewBuilder
    private func actionsSection(_ document: CrewDocument) -> some View {
        Section {
            Button {
                store.editSelectedDocument { try DocumentProcessor.rotate($0, degrees: 90) }
            } label: {
                Label("Rotate Right and Re-read", systemImage: "rotate.right")
            }
            Button {
                store.editSelectedDocument { try DocumentProcessor.rotate($0, degrees: -90) }
            } label: {
                Label("Rotate Left and Re-read", systemImage: "rotate.left")
            }
            Button {
                store.editSelectedDocument { try DocumentProcessor.enhance($0) }
            } label: {
                Label("Lift the Contrast and Re-read", systemImage: "wand.and.stars")
            }
            Button {
                store.reanalyseSelectedDocument()
            } label: {
                Label("Read It Again", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("If the page cannot be read")
        } footer: {
            Text("A passport photographed sideways gives Vision a machine-readable zone running up the side of the image, where it finds nothing. Turning the page and reading it again is usually the whole fix.")
        }

        Section {
            Button("Reject This Document", role: .destructive) { rejecting = true }
            Button("Delete This Document", role: .destructive) {
                store.deleteDocument(documentID)
            }
        } footer: {
            Text("Deleting erases the encrypted original and every revision of it from \(About.deviceName).")
        }
    }

    private func loadImage() async {
        guard let document else { return }
        scan = .loading
        if let data = await store.originalImageData(for: document) {
            scan = .loaded(data)
        } else {
            scan = .missing
        }
    }
}

/// Label, value, what is wrong with it, and a confirm control.
///
/// Laid out down the screen rather than across it, because a phone has no
/// across. The confirm control is a filled disc against an empty ring: a ring
/// and a disc differ in shape as well as tint, so the state survives being read
/// by someone who cannot separate the two colours.
struct ReviewFieldRow: View {
    let field: CrewField
    let value: String
    let validation: FieldValidation
    let isVerified: Bool
    let isSuggested: Bool
    let onEdit: (String) -> Void
    let onToggleVerified: (Bool) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var messageTint: Color {
        switch validation {
        case .valid: Theme.inkTertiary
        case .warning: Theme.caution
        case .invalid: Theme.danger
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)

                TextField("", text: $draft,
                          prompt: Text(field.placeholder).foregroundStyle(Theme.inkTertiary))
                    .font(field == .documentNumber ? Theme.Font.mono : Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    // A passport is printed in capitals and every field here is
                    // read off one, so the keyboard opens in the alphabet the
                    // page is in — except the document type, which is stored
                    // lowercase and is the app's own word rather than the
                    // page's.
                    .textInputAutocapitalization(field == .documentType ? .never : .characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                    .onChange(of: value) { _, newValue in if !focused { draft = field.presented(newValue) } }
                    .onAppear { draft = field.presented(value) }

                if isSuggested {
                    Label("Read by the local model, not from the machine-readable zone. Check it character by character.",
                          systemImage: "sparkles")
                        .font(Theme.Font.meta)
                        .foregroundStyle(Theme.machine)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message = validation.message {
                    Label(message, systemImage: validation.isBlocking ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(Theme.Font.meta)
                        .foregroundStyle(messageTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                onToggleVerified(!isVerified)
            } label: {
                Image(systemName: isVerified ? "checkmark" : "circle")
                    .font(.system(size: isVerified ? 14 : 11, weight: .bold))
                    .foregroundStyle(isVerified ? Theme.accentInk : Theme.inkTertiary)
                    .frame(width: 30, height: 30)
                    .background {
                        if isVerified {
                            Circle().fill(Theme.success)
                        } else {
                            Circle().strokeBorder(Theme.hairlineStrong, lineWidth: 1.5)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(validation.isBlocking)
            .opacity(validation.isBlocking ? 0.4 : 1)
            .padding(.top, 14)
            .accessibilityLabel("\(field.label) confirmed")
            .accessibilityAddTraits(isVerified ? [.isSelected] : [])
        }
        .padding(.vertical, 2)
        .listRowBackground(isVerified ? Theme.verifiedFill.opacity(0.5) : nil)
    }

    /// A date typed as `20 oct 1972` is stored as `1972-10-20` and comes back
    /// as `20 OCT 1972`; one that parses as neither is stored as typed, so the
    /// line under the field can say what is wrong with it.
    private func commit() {
        let canonical = field.stored(draft)
        guard canonical != value else {
            draft = field.presented(value)
            return
        }
        onEdit(canonical)
        draft = field.presented(canonical)
    }
}
