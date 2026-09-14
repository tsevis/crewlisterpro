import SwiftUI

/// What is known about a document's scan.
///
/// Three states and not an optional, because "still decrypting" and "there is
/// no scan" are different answers that an optional cannot tell apart — and the
/// difference is a spinner that stops versus a spinner that never does. A
/// document kept in the crew library from a store restored without its files,
/// or one seeded for a test, genuinely has no image, and the review pane has to
/// say so rather than appear to be working on it.
enum ScanState: Equatable {
    case loading
    case missing
    case loaded(Data)

    var data: Data? { if case .loaded(let data) = self { data } else { nil } }
}

/// The decrypted page, beside the fields read off it.
///
/// The whole review rests on this being legible: the operator is not checking
/// the app's arithmetic, they are reading a passport. So the image is decoded
/// from the sealed bytes, held in memory only while this screen is on it, and
/// can be opened full-screen and magnified — a machine-readable zone is six-
/// point type, and on a phone that is unreadable at page scale.
struct DocumentImageView: View {
    let state: ScanState
    var onOpenFullScreen: (() -> Void)?

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 140)

        case .missing:
            note(symbol: "doc.badge.ellipsis",
                 message: "There is no scan stored for this document.")

        case .loaded(let data):
            if let decoded = PlatformImageCodec.decode(data) {
                Image(platformImage: PlatformImage.from(cgImage: decoded))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if onOpenFullScreen != nil {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.accentInk)
                                .padding(8)
                                .background(Circle().fill(Theme.accent))
                                .padding(6)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenFullScreen?() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("The scanned document. Open it full screen.")
            } else {
                // Bytes that were never an image, or a PDF this device cannot
                // render. The fields are still reviewable; what is lost is the
                // thing to check them against, and saying so is the only honest
                // answer.
                note(symbol: "doc.questionmark",
                     message: "This file cannot be shown as an image.")
            }
        }
    }

    private func note(symbol: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.inkTertiary)
            Text(message)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

/// The page on its own, magnifiable.
struct DocumentImageFullScreen: View {
    let state: ScanState
    let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private var image: PlatformImage? {
        guard let data = state.data, let decoded = PlatformImageCodec.decode(data) else { return nil }
        return PlatformImage.from(cgImage: decoded)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoom)
                        .offset(offset)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    // Clamped at both ends: below 1 the page
                                    // shrinks into the middle of a black screen
                                    // with no way to tell it is still there, and
                                    // past 12× a phone photograph is enlarged
                                    // pixels and nothing else.
                                    zoom = min(max(committedZoom * value.magnification, 1), 12)
                                }
                                .onEnded { _ in
                                    committedZoom = zoom
                                    if zoom == 1 { reset() }
                                }
                                .simultaneously(with: DragGesture()
                                    .onChanged { value in
                                        guard zoom > 1 else { return }
                                        offset = CGSize(width: committedOffset.width + value.translation.width,
                                                        height: committedOffset.height + value.translation.height)
                                    }
                                    .onEnded { _ in committedOffset = offset })
                        )
                        .onTapGesture(count: 2) {
                            // The one gesture everybody tries first.
                            withAnimation(.easeOut(duration: 0.2)) {
                                if zoom > 1 { reset() } else { zoom = 3; committedZoom = 3 }
                            }
                        }
                } else {
                    Text("There is no scan to show for this document.")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func reset() {
        zoom = 1
        committedZoom = 1
        offset = .zero
        committedOffset = .zero
    }
}
