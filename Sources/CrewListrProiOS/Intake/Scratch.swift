import Foundation

/// Somewhere to put a passport, or a crew list, for the few seconds it has to
/// exist in the clear.
///
/// Three places in this app write plaintext to disk on purpose, and each one
/// was doing its own version of it: the staging directory a document waits in
/// before it is sealed, the copy the photo library hands over, and the CSV and
/// PDF on their way to the share sheet. Each had its own idea of whether to set
/// file protection, and each was erased — or not — by its own caller.
///
/// One place instead, with one rule: every scratch directory is protected the
/// way the encrypted store is, and every one of them is swept at launch. The
/// second half matters more than it sounds. An error between writing and
/// erasing is not the only way a file survives — the app being killed while the
/// share sheet is open is a *normal* thing for iOS to do, and it leaves a crew
/// list with five passport numbers on it sitting in a temporary directory the
/// system reclaims whenever it feels like it.
enum Scratch {

    /// The kinds, which are also the directory names. Adding one here is what
    /// gets it swept.
    enum Kind: String, CaseIterable {
        /// A document staged on its way into the encrypted store.
        case intake = "Intake"
        /// The photo library's own copy of a picture, with its name on it.
        case photoPick = "PhotoPick"
        /// The exported crew list, on its way to the share sheet.
        case crewList = "CrewList"
    }

    /// A fresh, empty, protected directory of its own.
    ///
    /// A directory per item rather than a shared one, so two passports
    /// photographed a second apart and both called `IMG_0042.jpg` keep their
    /// own names — the name is what the operator recognises the document by.
    static func make(_ kind: Kind, fileManager: FileManager = .default) throws -> URL {
        let directory = root(kind, fileManager: fileManager)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        protect(directory, fileManager: fileManager)
        return directory
    }

    /// Erases everything left in every scratch directory.
    ///
    /// Called once at launch, when nothing can legitimately be in one of them:
    /// an import that was in flight did not survive the process either.
    static func sweepAll(fileManager: FileManager = .default) {
        for kind in Kind.allCases { sweep(kind, fileManager: fileManager) }
    }

    static func sweep(_ kind: Kind, fileManager: FileManager = .default) {
        let directory = root(kind, fileManager: fileManager)
        guard let leftovers = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for leftover in leftovers { try? fileManager.removeItem(at: leftover) }
    }

    /// Erases one directory made by `make`. Safe to call twice.
    static func discard(_ directory: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: directory)
    }

    /// Erases the directories a set of files were written into.
    ///
    /// The *directories*, because `make` gives each item one of its own — and
    /// deleting only the files named here would leave a partial write beside
    /// them. A crew list that failed halfway is exactly the case this exists
    /// for: `exportSelectedTrip` can write the CSV and then throw on the PDF,
    /// and the CSV it already wrote carries every passport number on the trip.
    static func discardContainers(of files: [URL], fileManager: FileManager = .default) {
        for directory in Set(files.map { $0.deletingLastPathComponent() }) {
            discard(directory, fileManager: fileManager)
        }
    }

    private static func root(_ kind: Kind, fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory.appending(path: kind.rawValue, directoryHint: .isDirectory)
    }

    /// The same class the encrypted store's own directory takes:
    /// `.completeUnlessOpen`, so a file already open when the phone locks stays
    /// readable — a crew list is handed to the share sheet while the screen can
    /// switch off — and a file at rest is encrypted by the system.
    private static func protect(_ directory: URL, fileManager: FileManager) {
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen],
                                       ofItemAtPath: directory.path(percentEncoded: false))
    }
}
