import AppKit
import SwiftUI

/// The Philon design language, ported to AppKit colours.
///
/// Philon ships two skins in one stylesheet: a dark "web" theme and, layered
/// over it, a macOS skin built from Apple's system greys with one borrowed
/// accent. The macOS skin is the one that actually renders, so it is the one
/// reproduced here — the values below are read straight out of
/// `philon/src/styles.css`, not approximated by eye.
///
/// Every colour is a *dynamic* NSColor rather than a pair of SwiftUI colours
/// chosen at read time. Appearance on macOS can change under a view that is
/// already on screen (the system switching at sunset, or a window dragged to a
/// display with a different profile), and a value resolved once does not follow.
enum Theme {

    // MARK: - Accent
    //
    // The hue is CrewListr Pro's own: #0E6AFD, sampled from the app icon, so the
    // interface and the icon in the Dock beside it agree.
    //
    // Two values rather than one, because a saturated blue that reads well as a
    // fill is marginal as type: #0E6AFD is 4.67:1 on white — over the AA floor,
    // but with nothing to spare — so accent *text* on light surfaces uses the
    // same hue taken down to 6.47:1, and lifted on dark to 5.74:1.
    //
    // This is the single knob for the whole application's hue, and the status
    // vocabulary below is keyed to it too, by explicit request: the whole
    // interface is one colour.

    /// `--accent` — fills, selected rows, the primary button. The icon's blue.
    static let accent = dynamic(light: 0x0E6AFD, dark: 0x0E6AFD)
    /// `--accent-hover`
    static let accentHover = dynamic(light: 0x3984FD, dark: 0x3984FD)
    /// `--accent-ink` — type *on* an accent fill. White clears 4.67:1 on the blue.
    static let accentInk = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// `--accent-text` — accent used as type, legible on a white panel.
    static let accentText = dynamic(light: 0x0B56CF, dark: 0x5193FD)
    /// `--accent-soft` — the tinted ground under a secondary button.
    static let accentSoft = dynamicAlpha(light: (0x0B56CF, 0.10), dark: (0x5193FD, 0.18))
    /// `--accent-soft-strong` — its hover.
    static let accentSoftStrong = dynamicAlpha(light: (0x0B56CF, 0.16), dark: (0x5193FD, 0.26))

    // MARK: - Surfaces
    //
    // `#f5f5f7` over `#1c1c1e` is the macOS skin's ground; panels sit on it in
    // white / `#2c2c2e`, and the insets inside a panel go one step further to
    // `#fff` / `#3a3a3c`.

    /// The window ground. `.workspace`
    static let ground = dynamic(light: 0xF5F5F7, dark: 0x1C1C1E)
    /// A panel resting on the ground. `.conversion-grid`, `.queue-panel`
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
    /// A secondary panel — Philon's evidence column. `.evidence-panel`
    static let panelRecessed = dynamic(light: 0xF6F6F8, dark: 0x242426)
    /// An inset inside a panel: a field row, a list card. `.queue-list article`
    static let inset = dynamic(light: 0xFFFFFF, dark: 0x3A3A3C)
    /// The sidebar's translucent ground. `.sidebar`
    static let sidebar = dynamic(light: 0xF6F6F8, dark: 0x2C2C2E)
    /// A control's unfilled track — Philon's `rgba(118,118,128,.12)`.
    static let controlTrack = dynamicAlpha(light: (0x767680, 0.12), dark: (0x767680, 0.24))

    // MARK: - Hairlines

    /// `rgba(60,60,67,.16)` over `rgba(235,235,245,.13)` — the panel border.
    static let hairline = dynamicAlpha(light: (0x3C3C43, 0.16), dark: (0xEBEBF5, 0.13))
    /// The slightly stronger rule around an inset. `#d2d2d7`
    static let hairlineStrong = dynamicAlpha(light: (0x3C3C43, 0.22), dark: (0xEBEBF5, 0.16))

    // MARK: - Type
    //
    // Philon's macOS skin uses three text values and nothing else: `#1d1d1f`
    // for titles and body, `#6e6e73` for supporting copy, `#8e8e93` for the
    // smallest metadata.

    static let ink = dynamic(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let inkSecondary = dynamic(light: 0x6E6E73, dark: 0xAEAEB2)
    static let inkTertiary = dynamic(light: 0x8E8E93, dark: 0x8E8E93)

    // MARK: - Status
    //
    // `.status-mark.success` / `.caution`, and the notes beneath them. Philon
    // uses Apple's system green and orange for the marks, and a tinted card
    // with its own border for the note.

    // Three values of the icon hue rather than three hues. Because they no
    // longer differ in colour, the states have to stay apart some other way:
    // each is a distinct lightness (4.67 / 8.10 / 15.35 against white), and the
    // marks that carry them already differ in shape — a filled seal, a hollow
    // triangle, a crossed octagon. Shape does the work colour used to.
    //
    // The cost is real and worth stating: green/amber/red is a convention an
    // operator reads without thinking, and one blue family is not. The symbols
    // and the wording beside them are now the whole signal.

    /// Confirmed against the image — the brand blue at full strength.
    static let success = dynamic(light: 0x0E6AFD, dark: 0x5CA0FF)
    /// Could not be settled — the hue muted and darkened, so it reads as held back.
    static let caution = dynamic(light: 0x2C4E8F, dark: 0x9DBBEA)
    /// Rejected — near-navy, the heaviest value in the family.
    static let danger = dynamic(light: 0x0A2547, dark: 0xC7D9F5)
    /// `.candidate-shelf` — the second accent, used only for machine proposals.
    static let machine = dynamic(light: 0x5856D6, dark: 0xA9A7FF)

    // The two note cards are the largest blocks of colour in the window, so they
    // carry the same family. They separate by weight rather than hue: the
    // verified card is a pale wash of the accent, the warning card a deeper,
    // greyer blue that sits back. Their ink clears 7:1 on its own ground.

    /// `.verified-note` — ground, border, ink.
    static let verifiedFill = dynamic(light: 0xEDF4FF, dark: 0x11294B)
    static let verifiedBorder = dynamic(light: 0xBDD5F8, dark: 0x255089)
    static let verifiedInk = dynamic(light: 0x0B4FA8, dark: 0xB8D4F7)

    /// `.warning-item` — ground, border, ink.
    static let warningFill = dynamic(light: 0xF0F3F8, dark: 0x232A36)
    static let warningBorder = dynamic(light: 0xC3CEDE, dark: 0x3C4759)
    static let warningInk = dynamic(light: 0x2C4E8F, dark: 0xA9C0E2)

    // MARK: - Metrics
    //
    // Philon's macOS skin rounds panels at 10, controls at 7, and the small
    // things inside a control at 6. Nothing in the interface uses a radius that
    // is not one of these.

    enum Radius {
        /// `.conversion-grid`, `.queue-panel`, `.splash`
        static let panel: CGFloat = 10
        /// `.primary-button`, `.icon-button`, `.tabs`, `.system-status`
        static let control: CGFloat = 7
        /// A segment inside a segmented control, a badge.
        static let inner: CGFloat = 6
        /// `.asset-thumbnail`
        static let thumbnail: CGFloat = 4
    }

    enum Space {
        /// `.source-panel` padding.
        static let panel: CGFloat = 16
        /// `.workspace` horizontal padding.
        static let workspace: CGFloat = 28
        /// `.splash-body` horizontal padding.
        static let dialog: CGFloat = 26
    }

    // MARK: - Typography
    //
    // The macOS skin's scale, in points: 24/700 for the screen title, 15 for a
    // panel heading, 14 for a subpanel, 13 body, 12 supporting, 11 metadata,
    // 10 for the uppercase eyebrow. Weights are Philon's, rounded to the
    // nearest weight AppKit actually ships.

    enum Font {
        /// `h1` — 24px/700, -.035em.
        static let screenTitle = SwiftUI.Font.system(size: 24, weight: .bold)
        /// `.secondary-heading h2` — 22px/610.
        static let dialogTitle = SwiftUI.Font.system(size: 22, weight: .semibold)
        /// `.queue-panel h3` — 16px/620.
        static let panelTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        /// `.subpanel-header h2` — 14px.
        static let sectionTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        /// 13px — the default reading size.
        static let body = SwiftUI.Font.system(size: 13)
        static let bodyEmphasis = SwiftUI.Font.system(size: 13, weight: .medium)
        /// 12px — supporting copy under a heading.
        static let support = SwiftUI.Font.system(size: 12)
        static let supportEmphasis = SwiftUI.Font.system(size: 12, weight: .semibold)
        /// 11px — metadata, footers, the version stamp.
        static let meta = SwiftUI.Font.system(size: 11)
        static let metaEmphasis = SwiftUI.Font.system(size: 11, weight: .semibold)
        /// 10px/650 with .035em tracking, uppercased. `.eyebrow`
        static let eyebrow = SwiftUI.Font.system(size: 10, weight: .semibold)
        /// `.batch-metrics strong` — 26px/580, -.04em.
        static let metric = SwiftUI.Font.system(size: 26, weight: .medium)
        /// `.output-content` — SF Mono at reading size.
        static let mono = SwiftUI.Font.system(size: 12, design: .monospaced)
        static let monoMeta = SwiftUI.Font.system(size: 11, design: .monospaced)
    }

    // MARK: - Shadow
    //
    // `0 8px 24px rgba(0,0,0,.06)` in light; the dark skin drops shadows
    // entirely and relies on the border, because a black shadow on `#1c1c1e`
    // only muddies the edge it is meant to define.

    static func panelShadowRadius(_ scheme: ColorScheme) -> CGFloat { scheme == .dark ? 0 : 12 }
    static func panelShadowOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0 : 0.06 }

    // MARK: - Building dynamic colours

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
    }

    private static func dynamicAlpha(light: (Int, Double), dark: (Int, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(rgb: dark.0).withAlphaComponent(dark.1)
                : NSColor(rgb: light.0).withAlphaComponent(light.1)
        })
    }
}

private extension NSAppearance {
    /// `bestMatch` rather than a name comparison: the accessibility and
    /// high-contrast appearances are distinct names that are still dark.
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

private extension NSColor {
    /// 0xRRGGBB in sRGB, which is the space the CSS values were authored in.
    convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
