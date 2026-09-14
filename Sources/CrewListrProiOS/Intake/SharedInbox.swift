import Foundation
import UniformTypeIdentifiers

/// The letterbox between the share sheet and the app.
///
/// This is the whole reason the iOS build exists. A charter agent is sent a
/// passport on WhatsApp, and on a Mac the next four steps are: save it, find
/// it, move it to the Mac, import it. On a phone the picture is already in the
/// hand holding the phone, and the only thing standing between it and a crew
/// list is a way out of the messaging app. That way is the share sheet, and a
/// share extension cannot open the app's encrypted store — extensions are
/// separate processes with their own sandbox, and giving one the key would put
/// the key in two places.
///
/// So it puts the file down here instead: a directory in the App Group
/// container that both processes can reach, and nothing else can. The extension
/// only ever writes; the app only ever drains, and draining means *moving* —
/// every file is sealed into the store and erased from here in the same pass,
/// so the staging area holds a passport photograph for seconds rather than for
/// as long as the app is installed.
///
/// Compiled into both targets from this one file, because a contract written
/// down twice is a contract that will disagree with itself.
enum SharedInbox {

    /// The App Group both halves of the app are members of.
    static let appGroup = "group.com.tsevis.crewlisterpro"

    /// Nothing larger than this is accepted from the share sheet.
    ///
    /// A passport photograph off any phone is a few megabytes and a scanned PDF
    /// a few more. The cap is not about disk space — it is that an extension
    /// runs on a very short leash and a share of a 400 MB video would be killed
    /// halfway through, leaving a truncated file the app would then try to read
    /// as a document.
    static let mostBytesPerItem = 64 * 1024 * 1024

    /// What may be put in. An image or a PDF, because those are the two things
    /// an identity document arrives as — and because accepting everything would
    /// mean a share extension that appears in the sheet for a spreadsheet and
    /// then quietly fails.
    static let acceptedTypes: [UTType] = [.image, .pdf]

    static func accepts(_ type: UTType) -> Bool {
        acceptedTypes.contains { type.conforms(to: $0) }
    }

    enum InboxError: LocalizedError {
        case noContainer
        case tooLarge(name: String, bytes: Int)
        case unsupported(name: String)

        var errorDescription: String? {
            switch self {
            case .noContainer:
                "CrewListr Pro could not reach its shared folder, so the document could not be handed to the app."
            case .tooLarge(let name, let bytes):
                "\(name) is \(bytes / 1_048_576) MB, which is larger than a document this app will take."
            case .unsupported(let name):
                "\(name) is not an image or a PDF."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .noContainer: "Reinstalling CrewListr Pro restores it."
            case .tooLarge: "Send the passport as a photograph rather than as a video or an archive."
            case .unsupported: "Share the passport as a photograph or a PDF scan."
            }
        }
    }

    /// Where the staged files live. Created on first use by whichever side gets
    /// there first.
    static func directory(fileManager: FileManager = .default) throws -> URL {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw InboxError.noContainer
        }
        let inbox = container.appending(path: "Inbox", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
        // Encrypted by the system while the phone is locked. `.completeUnlessOpen`
        // and not `.complete`, because a share can arrive from a notification
        // while the screen is off and a write that fails silently is a passport
        // the operator thinks they sent.
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen],
                                       ofItemAtPath: inbox.path(percentEncoded: false))
        return inbox
    }

    // MARK: - The extension's side

    /// Stages one shared file. Returns where it landed.
    ///
    /// The name is kept because it is what the operator will see in the
    /// document list, and "IMG_4471.jpg" is how they will recognise which
    /// passport this was. It is sanitised first: a name arriving from another
    /// application is untrusted input, and a "../" in it would write outside
    /// the container.
    @discardableResult
    static func stage(_ data: Data, named suggestedName: String, type: UTType?,
                      fileManager: FileManager = .default) throws -> URL {
        if let type, !accepts(type) { throw InboxError.unsupported(name: suggestedName) }
        guard data.count <= mostBytesPerItem else {
            throw InboxError.tooLarge(name: suggestedName, bytes: data.count)
        }
        let inbox = try directory(fileManager: fileManager)
        // The UUID prefix, not the name alone: two people can send "photo.jpg"
        // in the same minute, and the second must not replace the first.
        let url = inbox.appending(path: "\(UUID().uuidString)__\(safeName(suggestedName, type: type))")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }

    @discardableResult
    static func stage(contentsOf source: URL, type: UTType? = nil,
                      fileManager: FileManager = .default) throws -> URL {
        let resolved = type ?? UTType(filenameExtension: source.pathExtension)
        return try stage(try Data(contentsOf: source), named: source.lastPathComponent, type: resolved,
                         fileManager: fileManager)
    }

    // MARK: - The app's side

    /// Everything waiting, oldest first, so a run of shares arrives in the
    /// order it was sent.
    static func waiting(fileManager: FileManager = .default) -> [URL] {
        guard let inbox = try? directory(fileManager: fileManager),
              let names = try? fileManager.contentsOfDirectory(at: inbox,
                                                               includingPropertiesForKeys: [.creationDateKey],
                                                               options: [.skipsHiddenFiles])
        else { return [] }
        return names.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if leftDate == rightDate { return left.lastPathComponent < right.lastPathComponent }
            return leftDate < rightDate
        }
    }

    /// Erases a staged file. Called once its contents are sealed into the store.
    static func discard(_ url: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: url)
    }

    /// Erases everything waiting. For the operator who shared four passports to
    /// the wrong app and does not want them sitting there.
    static func discardEverything(fileManager: FileManager = .default) {
        for url in waiting(fileManager: fileManager) { discard(url, fileManager: fileManager) }
    }

    /// The name an operator sees, recovered from the staged file name.
    static func originalName(of url: URL) -> String {
        let component = url.lastPathComponent
        guard let separator = component.range(of: "__") else { return component }
        return String(component[separator.upperBound...])
    }

    // MARK: - Names

    /// A file name that cannot escape the directory it is written into, and
    /// cannot be empty.
    static func safeName(_ suggested: String, type: UTType?) -> String {
        let stripped = suggested
            .components(separatedBy: CharacterSet(charactersIn: "/\\:\0"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A leading dot is dropped, not merely the two names "." and "..": a
        // separator replaced by a dash turns "../../evil.jpg" into
        // "..-..-evil.jpg", which escapes nothing but does make a hidden file
        // the operator cannot see in any file browser. A document they cannot
        // see is a document they cannot delete.
        let unhidden = String(stripped.drop(while: { $0 == "." }))
        let cleaned = unhidden.isEmpty ? "Shared document" : unhidden
        let limited = String(cleaned.prefix(120))
        guard let type, URL(fileURLWithPath: limited).pathExtension.isEmpty,
              let suffix = type.preferredFilenameExtension else { return limited }
        return "\(limited).\(suffix)"
    }
}
