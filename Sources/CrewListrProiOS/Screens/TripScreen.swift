import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// One charter: the yacht, the week, the documents, and the crew list at the
/// end of it.
struct TripScreen: View {
    @Environment(CrewStore.self) private var store
    @Environment(DocumentIntake.self) private var intake
    @Environment(\.dismiss) private var dismiss

    let tripID: UUID

    @State private var pickingPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var pickingFiles = false
    @State private var scanning = false
    @State private var showingCrewList = false
    @State private var addingFromLibrary = false
    @State private var confirmingDelete = false

    private var trip: Trip? { store.data.trips.first { $0.id == tripID } }
    private var boat: Boat? { trip.flatMap(store.boat(for:)) }
    private var documents: [CrewDocument] { store.data.documents.filter { $0.tripID == tripID } }

    /// The four printed values, or the first one that is missing.
    private var registrationSummary: String {
        guard let boat else { return "No yacht" }
        guard boat.isComplete else { return "Needs a name" }
        let printed = [boat.flag, boat.registrationPort, boat.registrationNumber]
        return printed.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            ? "Some boxes would print blank"
            : printed.joined(separator: "  ·  ")
    }

    private var registrationIsComplete: Bool {
        guard let boat, boat.isComplete else { return false }
        return ![boat.flag, boat.registrationPort, boat.registrationNumber]
            .contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        Group {
            if let trip {
                content(trip)
            } else {
                // The charter was deleted from under this screen — from the
                // other half of an iPad split, or by a restore.
                PhilonEmptyState(symbol: "calendar.badge.minus", title: "This charter is gone",
                                 message: "It was deleted or restored away while this screen was open.")
            }
        }
        // Most of the store's review API works on "the selected trip", which is
        // the Mac's idea of where the operator is. On a phone the screen the
        // operator pushed *is* that, so it says so on the way in.
        .onAppear { store.selectedTripID = tripID }
        .background(Theme.ground)
        .navigationTitle(boat?.displayName ?? "Charter")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The charter

    @ViewBuilder
    private func content(_ trip: Trip) -> some View {
        List {
            Section {
                ReadinessNote(blockers: store.exportBlockers)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker("Yacht", selection: Binding(
                    get: { trip.boatID },
                    set: { newValue in
                        var updated = trip
                        updated.boatID = newValue
                        store.updateTrip(updated)
                    }
                )) {
                    ForEach(store.fleet) { candidate in
                        Text(candidate.displayName).tag(candidate.id)
                    }
                }
                NavigationLink {
                    if let boat { FleetDetailScreen(boatID: boat.id) }
                } label: {
                    HStack {
                        Text("Registration")
                        Spacer()
                        // The four values that actually print, summarised —
                        // and the warning when one of them would print blank,
                        // which is the whole reason this row is here rather
                        // than only in the Fleet tab.
                        Text(registrationSummary)
                            .font(Theme.Font.meta)
                            .foregroundStyle(registrationIsComplete ? Theme.inkSecondary : Theme.caution)
                            .lineLimit(1)
                    }
                }
            } header: {
                Text("The yacht")
            } footer: {
                Text("Name, flag, port of registry and registration number are facts about the vessel. They are held on the yacht and printed on every crew list made for it.")
            }

            Section("The week") {
                DatePicker("Departure", selection: Binding(
                    get: { trip.departureDate },
                    set: { store.setDepartureDate($0, onTripWith: trip.id) }
                ), displayedComponents: .date)
                DatePicker("Return", selection: Binding(
                    get: { trip.returnDate },
                    set: { store.setReturnDate($0, onTripWith: trip.id) }
                ), displayedComponents: .date)
                LabeledContent("Boarding time") {
                    CommitTextField(placeholder: "08:00", value: trip.embarkationTime, alignment: .trailing) { value in
                        store.setEmbarkationTime(value, onTripWith: trip.id)
                    }
                    .keyboardType(.numbersAndPunctuation)
                }
                LabeledContent("Boarding port") {
                    CommitTextField(placeholder: "PIRAEUS", value: trip.embarkationPort,
                                    uppercased: true, alignment: .trailing) { value in
                        store.setEmbarkationPort(value, onTripWith: trip.id)
                    }
                }
            }

            documentsSection

            Section {
                Button {
                    showingCrewList = true
                } label: {
                    Label("Crew List", systemImage: "doc.text")
                }
                .disabled(documents.isEmpty)
            } footer: {
                Text(store.selectedTripCanExport
                     ? "Every field has been confirmed against its document. The crew list can be written."
                     : "The crew list stays shut until every field on every document has been confirmed against the image it came from.")
            }

            Section {
                Button(trip.isArchived ? "Restore Charter" : "Archive Charter") {
                    trip.isArchived ? store.restoreTrip(trip.id) : store.archiveTrip(trip.id)
                }
                Button("Delete Charter and Documents", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Archiving keeps the charter and its sealed scans. Deleting erases \(documents.count) encrypted document\(documents.count == 1 ? "" : "s") from \(About.deviceName), and cannot be undone.")
            }
        }
        .listStyle(.insetGrouped)
        .photosPicker(isPresented: $pickingPhotos, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, picked in
            guard !picked.isEmpty else { return }
            photoSelection = []
            Task {
                await intake.stage(photos: picked)
                await intake.deliver(to: tripID, store: store)
            }
        }
        .fileImporter(isPresented: $pickingFiles,
                      allowedContentTypes: [.image, .pdf],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls { intake.stage(securityScoped: url) }
                Task { await intake.deliver(to: tripID, store: store) }
            case .failure(let error):
                intake.problem = "Import cancelled: \(error.localizedDescription)"
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { pages in
                scanning = false
                guard !pages.isEmpty else { return }
                for (index, page) in pages.enumerated() {
                    intake.stage(page, named: "Scan \(index + 1).jpg", origin: .camera)
                }
                Task { await intake.deliver(to: tripID, store: store) }
            } onCancel: {
                scanning = false
            } onFailure: { error in
                scanning = false
                intake.problem = "The scanner stopped: \(error.localizedDescription)"
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingCrewList) { CrewListSheet(tripID: tripID) }
        .sheet(isPresented: $addingFromLibrary) { AddFromLibrarySheet(tripID: tripID) }
        .confirmationDialog("Delete this charter?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Charter and Documents", role: .destructive) {
                store.deleteTrip(tripID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently erases \(documents.count) encrypted document\(documents.count == 1 ? "" : "s"). It cannot be undone.")
        }
    }

    // MARK: - Documents

    @ViewBuilder
    private var documentsSection: some View {
        Section {
            ForEach(documents) { document in
                NavigationLink {
                    ReviewScreen(documentID: document.id)
                } label: {
                    DocumentRow(document: document)
                }
            }
            .onDelete { offsets in
                for index in offsets { store.deleteDocument(documents[index].id) }
            }

            Menu {
                Button {
                    pickingPhotos = true
                } label: {
                    Label("From Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    pickingFiles = true
                } label: {
                    Label("From Files", systemImage: "folder")
                }
                if DocumentScanner.isAvailable {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan a Passport", systemImage: "doc.viewfinder")
                    }
                }
                if !store.crewLibrary.isEmpty {
                    Button {
                        addingFromLibrary = true
                    } label: {
                        Label("From the Crew Library", systemImage: "person.2")
                    }
                }
            } label: {
                Label("Add Documents", systemImage: "plus")
            }
        } header: {
            Text(documents.isEmpty ? "Documents" : "Documents · \(documents.filter { $0.canExport() }.count) of \(documents.count) cleared")
        } footer: {
            if documents.isEmpty {
                Text("A passport sent on WhatsApp or Viber can go straight to CrewListr Pro from that app's share sheet — it arrives here waiting to be checked.")
            }
        }
    }
}
