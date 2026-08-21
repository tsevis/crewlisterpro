import AppKit
import SwiftUI

/// The two marks the interface shows, loaded once.
///
/// `Bundle.module` resolves differently under `swift run` (a bundle beside the
/// executable) and inside a packaged `.app` (a bundle in `Contents/Resources`,
/// put there by `scripts/release.sh`). Both are handled by the generated
/// accessor; what is *not* handled is the bundle being absent, which is why
/// these are optional and every call site degrades rather than traps.
enum Brand {
    /// Charis Tsevis's maker's mark. Shown at 20pt, so the 40pt asset is its @2x.
    static let makersMark: NSImage? = load("TsevisMark")

    /// CrewListr Pro's own icon, masked to the macOS shape.
    static let appMark: NSImage? = load("AppMark")

    static let makerName = "Charis Tsevis"
    static let makerSite = URL(string: "https://tsevis.com")!

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }
}

/// Philon's `.makers-mark`: fixed to the lower-left of the window, 20pt, at
/// 55% until the pointer is over it.
///
/// It sits in a window-level overlay rather than inside a column, because a
/// sidebar can be collapsed and the mark should not go with it.
struct MakersMark: View {
    /// Art, padding and bottom inset. Any layout sharing the corner reserves
    /// this much so the mark never lands on a control.
    static let reservedHeight: CGFloat = 20 + 3 * 2 + 9

    @State private var hovering = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(Brand.makerSite)
        } label: {
            Group {
                if let mark = Brand.makersMark {
                    Image(nsImage: mark).resizable().interpolation(.high)
                } else {
                    // The bundle is missing: keep the affordance, drop the art.
                    Text("CT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .frame(width: 20, height: 20)
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                    .fill(hovering ? Theme.controlTrack : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0.55)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
        .help("Made by \(Brand.makerName) — tsevis.com")
        .accessibilityLabel("Made by \(Brand.makerName). Opens tsevis.com.")
        .padding(.leading, 13)
        .padding(.bottom, 9)
    }
}
