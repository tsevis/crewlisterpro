import Foundation
import Observation
import UniformTypeIdentifiers

/// One document on its way in, before it belongs to a charter.
///
/// A document arriving from the share sheet has no trip: the operator was in
/// WhatsApp, not in this app, and nothing about a picture says which charter it
/// is for. So it waits here — staged on disk, named, but not yet sealed into
/// the store — until somebody says where it goes. The Mac never needed this
/// because on a Mac the import begins inside a trip that is already open.
struct PendingDocument: Identifiable, Hashable {
    let id = UUID()
    /// Where the bytes are, in this app's own temporary directory.
    let url: URL
    /// What the operator will see in the document list.
    let name: String
    /// Where it came from, so the banner can say "from the share sheet" rather
    /// than making the operator guess why four passports appeared.
    let origin: Origin

    enum Origin: String {
        case shareSheet, photos, files, camera

        var label: String {
            switch self {
            case .shareSheet: "shared to this app"
            case .photos: "from Photos"
            case .files: "from Files"
            case .camera: "scanned"
            }
        }
    }
}

/// Everything that can put a document into this app, and the one place they all
/// end up.
///
/// Four routes in — the share sheet, Photos, Files, the camera — and one route
/// out: stage the bytes as a real file, then hand the file to
/// `CrewStore.importDocuments`, which is the same call the Mac app makes. The
/// pipeline underneath is not forked: the same OCR reads it, the same MRZ
/// parser checks the same check digits, and the same review gate holds it back
/// until a person has confirmed every field.
@MainActor
@Observable
final class DocumentIntake {

    /// Staged and waiting for a charter.
    private(set) var pending: [PendingDocument] = []
    /// What went wrong with something the operator tried to bring in. Shown
    /// once and cleared, rather than logged where nobody looks.
    var problem: String?

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var hasPending: Bool { !pending.isEmpty }

    /// What the banner says. Written out rather than templated from a count
    /// alone, because "1 documents" is how an app tells you nobody read it.
    var pendingSummary: String {
        guard !pending.isEmpty else { return "" }
        let origins = Set(pending.map(\.origin.label))
        let where_ = origins.count == 1 ? origins.first! : "waiting"
        return pending.count == 1
            ? "One document \(where_)"
            : "\(pending.count) documents \(where_)"
    }

    // MARK: - The share sheet

    /// Takes everything the share extension left in the group inbox.
    ///
    /// Called every time the app comes to the front, because that is exactly
    /// when a share has just happened: the operator pressed "Add to CrewListr
    /// Pro" in WhatsApp and the next thing they do is open this app. Moving
    /// rather than copying — the staged file is erased from the shared folder
    /// as it is taken, so a passport photograph sits in a folder two processes
    /// can read for seconds and not for the life of the installation.
    @discardableResult
    func drainSharedInbox() -> Int {
        let waiting = SharedInbox.waiting(fileManager: fileManager)
        guard !waiting.isEmpty else { return 0 }
        var taken = 0
        for staged in waiting {
            let name = SharedInbox.originalName(of: staged)
            do {
                let destination = try stagingURL(for: name)
                // Moved, so the shared copy is gone the instant this one exists.
                try fileManager.moveItem(at: staged, to: destination)
                pending.append(PendingDocument(url: destination, name: name, origin: .shareSheet))
                taken += 1
            } catch {
                problem = "\(name) was shared to CrewListr Pro but could not be read: \(error.localizedDescription)"
                SharedInbox.discard(staged, fileManager: fileManager)
            }
        }
        return taken
    }

    // MARK: - Photos, Files and the camera

    /// Stages bytes the operator picked out of Photos, or a page the camera
    /// scanner produced.
    @discardableResult
    func stage(_ data: Data, named name: String, origin: PendingDocument.Origin) -> PendingDocument? {
        do {
            let safe = SharedInbox.safeName(name, type: nil)
            let destination = try stagingURL(for: safe)
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
            let document = PendingDocument(url: destination, name: safe, origin: origin)
            pending.append(document)
            return document
        } catch {
            problem = "\(name) could not be read: \(error.localizedDescription)"
            return nil
        }
    }

    /// Stages a file the operator chose in the Files browser.
    ///
    /// A file picked out of iCloud Drive or another app's container arrives as
    /// a security-scoped URL: readable only between `startAccessing` and
    /// `stopAccessing`, and not at all by the time the import task gets to it.
    /// Copying it here is what makes the rest of the pipeline able to treat it
    /// as an ordinary file.
    @discardableResult
    func stage(securityScoped source: URL) -> PendingDocument? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: source)
            guard data.count <= SharedInbox.mostBytesPerItem else {
                throw SharedInbox.InboxError.tooLarge(name: source.lastPathComponent, bytes: data.count)
            }
            return stage(data, named: source.lastPathComponent, origin: .files)
        } catch {
            problem = "\(source.lastPathComponent) could not be read: \(CrewStore.explain(error))"
            return nil
        }
    }

    // MARK: - Handing them to a charter

    /// Seals every waiting document into one trip, then erases the staged
    /// copies.
    ///
    /// The temporary files go whatever happened: the store either has its own
    /// sealed copy or has reported why it has not, and in both cases an
    /// unencrypted passport photograph must not be left in a temporary
    /// directory for the operating system to clean up whenever it feels like
    /// it.
    func deliver(to tripID: UUID, store: CrewStore) async {
        guard !pending.isEmpty else { return }
        let delivering = pending
        pending.removeAll()
        // `importDocuments` seals into "the selected trip", which is the Mac's
        // idea of where the operator is. Moving the selection here is not a
        // side effect to apologise for: the operator has just said which
        // charter these belong to, and that charter is where they are going
        // next.
        store.selectedTripID = tripID
        await store.importDocuments(delivering.map(\.url))
        Scratch.discardContainers(of: delivering.map(\.url), fileManager: fileManager)
    }

    /// Throws away what is waiting without importing it.
    func discardPending() {
        for document in pending { Scratch.discard(document.url.deletingLastPathComponent(), fileManager: fileManager) }
        pending.removeAll()
    }

    func discard(_ document: PendingDocument) {
        Scratch.discard(document.url.deletingLastPathComponent(), fileManager: fileManager)
        pending.removeAll { $0.id == document.id }
    }

    // MARK: - Staging

    /// This app's own scratch directory, which nothing else can reach. See
    /// `Scratch` for why every plaintext file in this app goes through one.
    private func stagingURL(for name: String) throws -> URL {
        try Scratch.make(.intake, fileManager: fileManager)
            .appending(path: name, directoryHint: .notDirectory)
    }
}
