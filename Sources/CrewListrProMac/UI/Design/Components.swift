import SwiftUI

/// The pieces Philon's stylesheet builds its screens out of, as SwiftUI views
/// and modifiers.
///
/// Philon's interface is narrow on purpose: a panel, an inset inside it, two
/// button weights, an eyebrow, a status mark and two tinted notes. Everything
/// on screen is one of those. Keeping the list short here is what keeps the
/// ported interface coherent rather than merely recoloured.

// MARK: - Surfaces

/// `.conversion-grid` / `.queue-panel` — a white card on the window ground,
/// hairline border, soft shadow in light and none in dark.
struct PanelBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var recessed = false

    func body(content: Content) -> some View {
        content
            .background(recessed ? Theme.panelRecessed : Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(Theme.panelShadowOpacity(scheme)),
                radius: Theme.panelShadowRadius(scheme),
                y: scheme == .dark ? 0 : 4
            )
    }
}

/// `.queue-list article` — an inset card *inside* a panel. No shadow: a shadow
/// inside a shadowed panel reads as a second surface and flattens both.
struct InsetBackground: ViewModifier {
    var radius: CGFloat = Theme.Radius.control
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(highlighted ? Theme.accentSoft : Theme.inset)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(highlighted ? Theme.accentText.opacity(0.28) : Theme.hairlineStrong, lineWidth: 1)
            )
    }
}

extension View {
    func philonPanel(recessed: Bool = false) -> some View {
        modifier(PanelBackground(recessed: recessed))
    }

    func philonInset(radius: CGFloat = Theme.Radius.control, highlighted: Bool = false) -> some View {
        modifier(InsetBackground(radius: radius, highlighted: highlighted))
    }
}

// MARK: - Buttons

/// `.primary-button` — the accent fill. Philon presses it 1px down and scales
/// it to .985 rather than dimming it, so the control keeps its colour under the
/// pointer.
struct PhilonPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.supportEmphasis)
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Theme.accentHover : Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// `.secondary-button` — accent type on a soft accent ground, no border.
struct PhilonSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.supportEmphasis)
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Theme.accentSoftStrong : Theme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// `.repair-button` — the quietest weight, for an action that is available but
/// should not compete: Reject, Cancel, a destructive confirm.
struct PhilonQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.supportEmphasis)
            .foregroundStyle(role == .destructive ? Theme.danger : Theme.inkSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Theme.controlTrack : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.hairlineStrong, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.48)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// `.icon-button` — a 30pt square on the control track, for a toolbar glyph.
struct PhilonIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.47))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(configuration.isPressed ? Theme.accentSoft : Theme.controlTrack)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.48)
    }
}

extension ButtonStyle where Self == PhilonPrimaryButtonStyle {
    static var philonPrimary: Self { PhilonPrimaryButtonStyle() }
}

extension ButtonStyle where Self == PhilonSecondaryButtonStyle {
    static var philonSecondary: Self { PhilonSecondaryButtonStyle() }
}

extension ButtonStyle where Self == PhilonQuietButtonStyle {
    static var philonQuiet: Self { PhilonQuietButtonStyle() }
    static func philonQuiet(role: ButtonRole?) -> Self { PhilonQuietButtonStyle(role: role) }
}

extension ButtonStyle where Self == PhilonIconButtonStyle {
    static var philonIcon: Self { PhilonIconButtonStyle() }
}

// MARK: - Type ornaments

/// `.eyebrow` — the uppercase label above a screen title. Tracking is set on
/// the view rather than baked into the string so it can be localised.
struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.eyebrow)
            .tracking(0.35)
            .foregroundStyle(Theme.inkTertiary)
    }
}

/// `.status-mark` — a filled disc carrying a glyph. Philon uses exactly two,
/// success and caution; CrewListr adds danger for a rejected document.
struct StatusMark: View {
    enum Kind { case success, caution, danger, neutral }

    let kind: Kind
    let symbol: String
    var size: CGFloat = 22

    private var fill: Color {
        switch kind {
        case .success: Theme.success
        case .caution: Theme.caution
        case .danger: Theme.danger
        case .neutral: Theme.inkTertiary
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
    }
}

/// `.asset-shelf header b` — a small count on a tinted pill.
struct CountBadge: View {
    let count: Int
    var tint: Color = Theme.accentText

    var body: some View {
        Text("\(count)")
            .font(Theme.Font.meta.monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 18)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// `.system-status` — the persistent "Local only" chip in Philon's top bar.
/// It is the one piece of chrome that states the app's central promise, so it
/// stays visible rather than living in a menu.
struct SystemStatusChip: View {
    let symbol: String
    let text: String
    var tint: Color = Theme.success

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).foregroundStyle(Theme.inkSecondary)
        }
        .font(Theme.Font.meta)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.controlTrack, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

// MARK: - Notes

/// `.verified-note` and `.warning-item` — the two tinted cards Philon uses to
/// say "this was checked" and "this could not be". Both carry a glyph, because
/// the tint alone is the only difference between them and tint alone is not
/// something every operator can read.
struct PhilonNote: View {
    enum Kind { case verified, warning }

    let kind: Kind
    var title: String?
    let message: String

    private var symbol: String { kind == .verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill" }
    private var fill: Color { kind == .verified ? Theme.verifiedFill : Theme.warningFill }
    private var border: Color { kind == .verified ? Theme.verifiedBorder : Theme.warningBorder }
    private var ink: Color { kind == .verified ? Theme.verifiedInk : Theme.warningInk }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(kind == .verified ? Theme.success : Theme.caution)

            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title.uppercased())
                        .font(Theme.Font.eyebrow)
                        .tracking(0.45)
                }
                Text(message)
                    .font(Theme.Font.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(ink)

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
    }
}

// MARK: - Empty states

/// `.secondary-empty` — a dashed well rather than SwiftUI's centred grey
/// `ContentUnavailableView`, which does not belong to this palette.
struct PhilonEmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.accentText)

            Text(title)
                .font(Theme.Font.panelTitle)
                .foregroundStyle(Theme.ink)

            Text(message)
                .font(Theme.Font.support)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260)

            actions.padding(.top, 4)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
    }
}

extension PhilonEmptyState where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Bars

/// The footer strip under a column. Philon's `.source-footer` is a hairline and
/// the panel ground, not SwiftUI's `.bar` material — a blurred material inside
/// an already-layered window reads as a third surface.
struct PhilonBar<Content: View>: View {
    /// Which side of the bar the dividing rule falls on. A bar at the top of a
    /// pane needs its hairline underneath; at the bottom, above. Getting this
    /// wrong leaves a rule floating with nothing on the far side of it.
    enum Edge { case top, bottom }

    var edge: Edge = .bottom
    @ViewBuilder var content: Content

    private var bar: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Theme.sidebar)
    }

    private var rule: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            if edge == .bottom { rule }
            bar
            if edge == .top { rule }
        }
    }
}

// MARK: - Progress

/// `.task-progress-track` — a 5pt capsule on the control track, filled with
/// accent *text* rather than the accent fill, because at 5pt the mint alone is
/// too light to read as a quantity on a white panel.
struct PhilonProgress: View {
    let value: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.controlTrack)
                Capsule()
                    .fill(Theme.accentText)
                    .frame(width: max(proxy.size.width * min(max(value, 0), 1), value > 0 ? 4 : 0))
                    .animation(.easeOut(duration: 0.28), value: value)
            }
        }
        .frame(height: height)
    }
}

/// `.batch-metrics div` — one number and its label, for a readiness summary.
struct PhilonMetric: View {
    let value: String
    let label: String
    var tint: Color = Theme.accentText

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.Font.metric)
                .tracking(-0.8)
                .foregroundStyle(tint)
            Text(label)
                .font(Theme.Font.eyebrow)
                .tracking(0.3)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 13)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}


// MARK: - A field that saves when you leave it

/// One line of text that reports its value when the field gives up focus.
///
/// Value in, callback out, rather than a `Binding`: every screen here saves
/// through the store, and a binding straight into a model would let a
/// half-typed value reach the database on every keystroke. Normalising on every
/// keystroke also fights the field — uppercasing a flag as it is typed moves
/// the caret — so the value is held as typed and squared up on the way out.
///
/// Three near-identical copies of this existed, one per screen. They drifted:
/// one of them forgot to put the trimmed value back in the box.
struct CommitField: View {
    /// A stable name for a UI test to find this field by. Optional, because
    /// most fields are reachable by position within their own panel.
    var identifier: String?
    let placeholder: String
    let value: String
    var isSuspect = false
    var font: Font = Theme.Font.body
    /// Applied to what was typed before it is compared and saved — uppercasing
    /// a flag, say. Identity by default.
    var normalise: (String) -> String = { $0 }
    let onCommit: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            // Return leaves the field rather than saving in place, so there is
            // exactly one commit path and it always runs unfocused. That is
            // what lets the observer below be trusted to put the stored value
            // back in the box.
            .onSubmit { focused = false }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            // Only while unfocused: a value arriving from elsewhere must not
            // overwrite what the operator is in the middle of typing.
            .onChange(of: value) { _, newValue in if !focused { draft = newValue } }
            .onAppear { draft = value }
            .accessibilityIdentifier(identifier ?? "")
    }

    private var border: Color {
        if focused { return Theme.accentText.opacity(0.55) }
        return isSuspect ? Theme.caution.opacity(0.5) : Theme.hairlineStrong
    }

    /// Saves, then shows back whatever the store actually kept.
    ///
    /// Not what was typed, and not even what was cleaned: a store is allowed to
    /// refuse an edit or rewrite it. `CrewStore.updateBoat` restores a name
    /// emptied by accident, and `AppSettings.normalised()` turns "crew list"
    /// back into "crew-list". Both leave `value` unchanged, so nothing fires —
    /// and the field sat there showing a value that was never stored, next to a
    /// preview showing the one that was.
    ///
    /// Assigning `value` covers exactly that case. When the edit *is* accepted,
    /// `value` changes and the observer above replaces this a moment later with
    /// the new one.
    private func commit() {
        let cleaned = normalise(draft.trimmingCharacters(in: .whitespacesAndNewlines))
        if cleaned != value { onCommit(cleaned) }
        draft = value
    }
}

/// Label on the left, field on the right — the row shape both the trip and the
/// fleet forms are built from.
struct FormRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 118
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.Font.support)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: labelWidth, alignment: .trailing)

            content

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// A caption inside a form panel, for the sentence that explains the rows above
/// it.
struct FormCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.meta)
            .foregroundStyle(Theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }
}

/// The hairline between two rows of a form panel.
struct FormRule: View {
    var inset: CGFloat = 138

    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, inset)
    }
}

/// An eyebrow over a bordered stack of form rows.
struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
            VStack(spacing: 0) { content }.philonInset(radius: Theme.Radius.panel)
        }
    }
}
