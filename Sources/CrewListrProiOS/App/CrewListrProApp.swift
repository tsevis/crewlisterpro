import SwiftUI

/// CrewListr Pro on iPhone and iPad.
///
/// The same application as the Mac build, in the place the passport photograph
/// actually is. A charter agent is sent a page on WhatsApp, and everything that
/// used to sit between that message and a crew list — save it, find it, move it
/// to the Mac, import it — is one press of the share sheet here.
///
/// Nothing about the review is relaxed to fit the smaller screen. Extraction
/// still returns `review` and never `cleared`; every field is still confirmed
/// one at a time against the image it was read from; the export is still shut
/// until it has been. A phone is a reason to lay that out differently, not a
/// reason to trust the OCR more.
@main
struct CrewListrProApp: App {
    @State private var store = CrewStore()
    @State private var intake = DocumentIntake()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(intake)
                // The accent, applied once at the root, so every system control
                // the app has not restyled by hand lands in the palette rather
                // than the user's own system blue.
                .tint(Theme.accentText)
                .task {
                    // Swept first, and everything is swept: a crash between
                    // staging and importing leaves an unsealed passport
                    // photograph on disk, and being killed while the share
                    // sheet is open — which iOS does routinely — leaves an
                    // exported crew list with every passport number on it.
                    Scratch.sweepAll()
                    // And drained here as well as on `.active` below, because
                    // `onChange` fires on a *change* and a cold launch has none
                    // — which is the common case exactly: the operator shares a
                    // passport from WhatsApp with this app not running, taps its
                    // icon, and the app starts up with something already in the
                    // inbox. Without this, that share would sit there unseen
                    // until the app happened to be backgrounded and reopened.
                    intake.drainSharedInbox()
                }
                // "Open in CrewListr Pro", from Files, Mail, or any app that
                // hands a document to another app rather than sharing it.
                .onOpenURL { url in
                    guard intake.stage(securityScoped: url) != nil else { return }
                    // The copy in the app's own Inbox/ is ours to clean up, and
                    // leaving it there would mean an unencrypted passport
                    // photograph in a folder that survives the import.
                    if url.path(percentEncoded: false).contains("/Documents/Inbox/") {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming *back* to the front, for the share that happened while the
            // app was already running behind the messaging app. Draining twice
            // costs nothing: the second pass finds an empty inbox.
            guard phase == .active else { return }
            intake.drainSharedInbox()
        }
    }
}
