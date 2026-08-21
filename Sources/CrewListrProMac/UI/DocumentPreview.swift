import AppKit
import SwiftUI

/// The decrypted document image, with the zoom and rotate controls an operator
/// needs to actually read a machine-readable zone off a phone photo.
///
/// Nothing in the app displayed the source image before, which made the
/// verification step meaningless.
struct DocumentPreview: View {
    @Environment(CrewStore.self) private var store
    let document: CrewDocument

    @State private var image: NSImage?
    @State private var loadFailed = false
    @State private var zoom: CGFloat = 1
    @State private var rotation: Angle = .zero
    @State private var confirmingModelDownload = false

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(eyebrow: "Document", title: document.originalName) {
                viewControls
            }
            content
        }
        .background(Theme.panelRecessed)
        .task(id: document.id) { await load() }
        .task { await store.refreshLocalModelState() }
        .confirmationDialog(
            "Download the local AI model?",
            isPresented: $confirmingModelDownload,
            titleVisibility: .visible
        ) {
            Button("Download \(store.localModelDescription)") {
                Task { await store.downloadLocalModel() }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            // The size and the privacy were already here; the accuracy was
            // not, and it is the part that should decide this. Measured on two
            // real passports across three prompt versions: no version read
            // both correctly, and the failures were plausible rather than
            // obvious — a page printing MINCHUK produced MIHCHYK, and a June
            // birth date came back as April. An operator weighing 5.78 GB
            // deserves that more than they deserve the file size.
            Text("""
            A one-time download that stays on this Mac. It is used only for \
            documents whose machine-readable zone could not be read.

            It is often wrong, and wrong in ways that look right: on our test \
            documents it has misread names and dates into values that pass \
            every check this app makes. Treat every suggestion as a guess to \
            verify letter by letter against the image, never as a reading.

            Everything else in \(AppVersion.name) works without it.
            """)
        }
        .task(id: document.imageRevisions.count) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(rotation)
                        // Fit to the pane at 100%, then grow with the zoom so
                        // the machine-readable zone can be read character by
                        // character. No fixed letterbox around the page.
                        .frame(width: proxy.size.width * zoom)
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .center)
                        .padding(zoom > 1 ? 0 : 12)
                }
                .scrollIndicators(.automatic)
            }
        } else if loadFailed {
            PhilonEmptyState(
                symbol: "eye.slash",
                title: "Preview unavailable",
                message: "The encrypted original could not be decoded for display."
            )
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var viewControls: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Button { zoom = max(1, zoom - 0.5) } label: { Image(systemName: "minus") }
                    .disabled(zoom <= 1)
                Text("\(Int(zoom * 100))%")
                    .font(Theme.Font.meta.monospacedDigit())
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 40)
                Button { zoom = min(6, zoom + 0.5) } label: { Image(systemName: "plus") }
                    .disabled(zoom >= 6)
            }
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(Theme.controlTrack, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))

            // View-only rotation: reading a sideways photo should not rewrite
            // the stored evidence.
            Button { rotation -= .degrees(90) } label: { Image(systemName: "rotate.left") }
                .help("Rotate the view (does not change the stored file)")
            Button { rotation += .degrees(90) } label: { Image(systemName: "rotate.right") }
                .help("Rotate the view (does not change the stored file)")
            Button { zoom = 1; rotation = .zero } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Reset the view")

            Spacer(minLength: 0)

            Menu {
                Button("Re-read with OCR") { store.reanalyseSelectedDocument() }
                // The rescue needs a 5.8 GB model that nothing in the app could
                // install, so the item could never succeed. Offer the download
                // in its place, behind a confirmation that states the size.
                if store.localModelIsInstalled {
                    Button("Rescue with Local AI") { store.rescueSelectedDocumentWithLocalAI() }
                } else {
                    Button("Install Local AI…") { confirmingModelDownload = true }
                }
                Divider()
                Section("Edit the stored file") {
                    Button("Rotate 90° and Re-review") {
                        store.editSelectedDocument { try DocumentProcessor.rotate($0, degrees: 90) }
                    }
                    Button("Auto Enhance and Re-review") {
                        store.editSelectedDocument { try DocumentProcessor.enhance($0) }
                    }
                }
            } label: {
                Label("Improve", systemImage: "wand.and.stars")
            }
            // `.menuStyle(.button)` deliberately: `.borderlessButton` renders
            // the label but stops the Menu taking clicks in a bottom bar.
            .menuStyle(.button)
            .fixedSize()
            .font(Theme.Font.metaEmphasis)
            .help("Editing the stored image keeps an encrypted revision and clears every confirmation")
        }
        .buttonStyle(.borderless)
        .tint(Theme.accentText)
        .foregroundStyle(Theme.accentText)
    }

    private func load() async {
        image = nil
        loadFailed = false
        zoom = 1
        rotation = .zero
        guard let data = await store.originalImageData(for: document) else {
            loadFailed = true
            return
        }
        image = NSImage(data: data)
        loadFailed = image == nil
    }
}
