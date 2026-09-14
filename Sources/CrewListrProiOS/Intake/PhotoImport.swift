import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// One picture taken out of the photo library, with the name the library gave
/// it.
///
/// `PhotosPickerItem` will hand over raw `Data` readily enough, and that is
/// what most code does — but `Data` has no name, and the name is what an
/// operator recognises a passport by in a list of six of them. A file
/// representation carries `IMG_4471.HEIC` across with the pixels.
struct PickedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            // The received file is deleted the moment this closure returns, so
            // the bytes are copied out now, keeping the name. Into a `Scratch`
            // directory like every other plaintext this app writes, so it is
            // protected at rest and swept at the next launch if this one does
            // not get as far as erasing it.
            let directory = try Scratch.make(.photoPick)
            let destination = directory.appending(path: received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedPhoto(url: destination)
        }
    }
}

extension DocumentIntake {
    /// Stages everything the operator selected in the photo picker.
    ///
    /// HEIC included, and not converted on the way in: Vision reads HEIC as
    /// happily as JPEG, and re-encoding a passport photograph to import it
    /// would lose detail in exactly the strip of the page — the machine-
    /// readable zone — that the whole extraction depends on.
    func stage(photos: [PhotosPickerItem]) async {
        for item in photos {
            do {
                if let picked = try await item.loadTransferable(type: PickedPhoto.self) {
                    // `defer`, not a line after the read: a picture still
                    // downloading from iCloud fails that read, and the copy the
                    // library just made would be left behind by the throw —
                    // which is a passport photograph, in the clear, that
                    // nothing points at any more.
                    defer { Scratch.discard(picked.url.deletingLastPathComponent()) }
                    let data = try Data(contentsOf: picked.url)
                    stage(data, named: picked.url.lastPathComponent, origin: .photos)
                    continue
                }
                // Some library items — a screenshot synced from another device,
                // an image still downloading from iCloud — refuse the file
                // representation and offer only bytes. A document with a
                // made-up name still beats no document.
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    problem = "One of the pictures could not be read from the photo library."
                    continue
                }
                let suffix = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                stage(data, named: "Photo \(Self.stamp()).\(suffix)", origin: .photos)
            } catch {
                problem = "A picture could not be read from the photo library: \(error.localizedDescription)"
            }
        }
    }

    /// A name that sorts and reads, for a picture the library would not name.
    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}
