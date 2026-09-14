#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

/// The Philon design language, ported to platform colours.
///
/// Philon ships two skins in one stylesheet: a dark "web" theme and, layered
/// over it, a macOS skin built from Apple's system greys with one borrowed
/// accent. The macOS skin is the one that actually renders, so it is the one
/// reproduced here — the values below are read straight out of
/// `philon/src/styles.css`, not approximated by eye.
///
/// Every colour is a *dynamic* platform colour rather than a pair of SwiftUI
/// colours chosen at read time. Appearance can change under a view that is
/// already on screen — the system switching at sunset, a Mac window dragged to
/// a display with a different profile, an iPhone crossing its own dark-mode
/// schedule — and a value resolved once does not follow.
///
/// The two platforms spell the same idea differently: AppKit asks a block for a
/// colour per `NSAppearance`, UIKit per `UITraitCollection`. `dynamic` below is
/// the only place that difference appears; every value in this file is written
/// once.
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
        /// How much larger the same type is set on a phone.
        ///
        /// The scale below was authored for a Mac, where 13px is the reading
        /// size and the window is two feet from the reader's face. A phone is
        /// held at half that distance on a screen a fifth the width, and iOS
        /// sets its own body text at 17pt for exactly that reason. Carrying the
        /// Mac's numbers across unchanged produced an interface that was
        /// *correct* and unreadable.
        ///
        /// One multiplier rather than a second set of values, so the type scale
        /// stays one design with one set of relationships in it — a heading is
        /// still 1.85× the body on both, and a change to one reaches the other.
        #if os(macOS)
        static let scale: CGFloat = 1
        #else
        static let scale: CGFloat = 1.25
        #endif

        /// A point size somebody with poor eyesight can still read.
        ///
        /// `Font.system(size:)` is a *fixed* size: it does not move with Dynamic
        /// Type, which on a Mac is fine because macOS has no Dynamic Type, and
        /// on a phone means an operator who has set Larger Text gets the same
        /// eleven points as everybody else. This app is read on a pontoon in
        /// July sunlight with a passport in the other hand.
        ///
        /// Scaled against Body so the whole scale moves together — a heading
        /// stays 1.85× the body text at every setting — and capped at 1.6×,
        /// because the accessibility sizes go far enough to put three words on
        /// a line and this interface has tables in it.
        private static func sized(_ points: CGFloat, _ weight: SwiftUI.Font.Weight = .regular,
                                  design: SwiftUI.Font.Design = .default) -> SwiftUI.Font {
            let base = points * scale
            #if canImport(UIKit)
            let scaled = min(UIFontMetrics(forTextStyle: .body).scaledValue(for: base), base * 1.6)
            #else
            let scaled = base
            #endif
            return .system(size: scaled.rounded(), weight: weight, design: design)
        }

        /// `h1` — 24px/700, -.035em.
        static var screenTitle: SwiftUI.Font { sized(24, .bold) }
        /// `.secondary-heading h2` — 22px/610.
        static var dialogTitle: SwiftUI.Font { sized(22, .semibold) }
        /// `.queue-panel h3` — 16px/620.
        static var panelTitle: SwiftUI.Font { sized(15, .semibold) }
        /// `.subpanel-header h2` — 14px.
        static var sectionTitle: SwiftUI.Font { sized(13, .semibold) }
        /// 13px — the default reading size.
        static var body: SwiftUI.Font { sized(13) }
        static var bodyEmphasis: SwiftUI.Font { sized(13, .medium) }
        /// 12px — supporting copy under a heading.
        static var support: SwiftUI.Font { sized(12) }
        static var supportEmphasis: SwiftUI.Font { sized(12, .semibold) }
        /// 11px — metadata, footers, the version stamp.
        static var meta: SwiftUI.Font { sized(11) }
        static var metaEmphasis: SwiftUI.Font { sized(11, .semibold) }
        /// 10px/650 with .035em tracking, uppercased. `.eyebrow`
        static var eyebrow: SwiftUI.Font { sized(10, .semibold) }
        /// `.batch-metrics strong` — 26px/580, -.04em.
        static var metric: SwiftUI.Font { sized(26, .medium) }
        /// `.output-content` — SF Mono at reading size.
        static var mono: SwiftUI.Font { sized(12, design: .monospaced) }
        static var monoMeta: SwiftUI.Font { sized(11, design: .monospaced) }
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
        dynamicAlpha(light: (light, 1), dark: (dark, 1))
    }

    private static func dynamicAlpha(light: (Int, Double), dark: (Int, Double)) -> Color {
        #if canImport(AppKit)
        return Color(platformColor: NSColor(name: nil) { appearance in
            let chosen = appearance.isDark ? dark : light
            return PlatformColor(rgb: chosen.0).withAlphaComponent(chosen.1)
        })
        #else
        return Color(platformColor: UIColor { traits in
            let chosen = traits.userInterfaceStyle == .dark ? dark : light
            return PlatformColor(rgb: chosen.0).withAlphaComponent(chosen.1)
        })
        #endif
    }
}

#if canImport(AppKit)
private extension NSAppearance {
    /// `bestMatch` rather than a name comparison: the accessibility and
    /// high-contrast appearances are distinct names that are still dark.
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
#endif

private extension PlatformColor {
    /// 0xRRGGBB in sRGB, which is the space the CSS values were authored in.
    convenience init(rgb: Int) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        #if canImport(AppKit)
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
        #else
        self.init(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}
