import SwiftUI
import UIKit

/// The system share sheet, for handing the finished crew list to whatever the
/// operator sends paperwork with.
///
/// This is the counterpart of the share *extension*: a passport comes into the
/// app through the sheet and the crew list goes back out through it. On a Mac
/// the export ends at a folder, because a Mac has folders an operator opens; on
/// a phone the useful question is not "where on the disk" but "to whom" — the
/// charter base, the port agent, the skipper — and Save to Files is one of the
/// answers in the same list rather than the only one.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
