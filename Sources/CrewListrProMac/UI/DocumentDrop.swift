import SwiftUI
import UniformTypeIdentifiers

/// What a Finder drag may put on the review pane.
///
/// Importing was a file panel and nothing else: an operator looking at a folder
/// of scans had to open a dialog and navigate back to the folder they were
/// already looking at. Dragging them onto the window is the shorter path, and
/// the only new question it asks is which of the things a drag can carry this
/// app can read.
///
/// Separate from the view that uses it so the rule can be tested without a
/// window — the answer is a pure function of some URLs.
enum DocumentDrop {

    /// The files this app can actually extract from, in a stable order.
    ///
    /// The same set the file panel offers — images and PDFs — because a drop
    /// must not be a way around it: a spreadsheet handed to Vision produces a
    /// document with nothing in it and a row in the list nobody can review.
    ///
    /// A dropped folder is opened one level, which is what someone dragging a
    /// WhatsApp export means. One level and no deeper, deliberately: a drag of
    /// a home directory would otherwise walk all of it and start pulling
    /// passports out of a backup nobody meant to import.
    static func importable(from urls: [URL]) -> [URL] {
        var found: [URL] = []
        var seen: Set<String> = []

        for url in urls {
            for candidate in expand(url) {
                let key = candidate.standardizedFileURL.path(percentEncoded: false)
                // The same file can arrive twice — once on its own and once
                // inside a folder dropped with it. That is one document.
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                found.append(candidate)
            }
        }
        return found
    }

    /// One dropped item as the documents it stands for: itself, or the
    /// documents directly inside it.
    private static func expand(_ url: URL) -> [URL] {
        guard isDirectory(url) else { return isDocument(url) ? [url] : [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            // A `.DS_Store` is not a passport, and neither is anything else the
            // system leaves lying in a folder.
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        return contents
            .filter { !isDirectory($0) && isDocument($0) }
            // Whatever order the file system hands them back in, the operator
            // sees the order they saw in the Finder.
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Judged by the file's own type rather than by its extension alone, so a
    /// `.jpeg` and a `.JPG` and a HEIC photograph all read the same.
    private static func isDocument(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }
}

// MARK: - The drop target

extension View {

    /// Accepts dropped passports, and says so while a drag is over the window.
    ///
    /// The highlight is the whole of the affordance: nothing in a resting
    /// window advertises that it takes a drop, so the moment a drag arrives the
    /// pane has to answer "yes, here" — and, when the drag holds nothing this
    /// app can read, it must not.
    func documentDrop(perform: @escaping ([URL]) -> Void) -> some View {
        modifier(DocumentDropTarget(perform: perform))
    }
}

private struct DocumentDropTarget: ViewModifier {
    let perform: ([URL]) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                let documents = DocumentDrop.importable(from: urls)
                guard !documents.isEmpty else { return false }
                perform(documents)
                return true
            } isTargeted: { targeted in
                withAnimation(.easeOut(duration: 0.12)) { isTargeted = targeted }
            }
            .overlay {
                if isTargeted { highlight }
            }
    }

    private var highlight: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
            .strokeBorder(Theme.accentText, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .background(Theme.accentSoft.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay {
                Label("Drop passports here", systemImage: "doc.badge.plus")
                    .font(Theme.Font.bodyEmphasis)
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.panel, in: Capsule())
            }
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
