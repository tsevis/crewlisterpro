import SwiftUI

/// Philon's window chrome: the app's name in the title bar, a row of screens
/// under it, one line of commands under that, and the work itself below.
///
/// The shape matters more than the pixels. Philon has exactly one place where
/// an action can be — the command line — and exactly one place where you change
/// what you are looking at — the screen row. Nothing is in a footer, nothing is
/// in a sheet, and no panel carries its own private set of buttons. That is
/// what makes a window with five screens and a dozen actions still read as
/// simple, and it is the part worth copying.

// MARK: - Screens

/// The top-level screens, in the order the work happens: name the yacht, put
/// the people aboard, hand over the list. The first two are also the order the
/// export blockers appear in — an unnamed yacht blocks before an unconfirmed
/// field does — so the tabs read left to right as the thing still to do.
///
/// Crew List and Trip were modal sheets. A sheet is the right shape for a
/// question that must be answered before anything else can happen, and neither
/// of these is that — both are places an operator moves between while working,
/// which is a screen.
enum Screen: String, CaseIterable, Identifiable {
    case fleet
    case trip
    case people
    case crewList
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fleet: "Fleet"
        case .trip: "Trip"
        case .people: "People"
        case .crewList: "Crew List"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .fleet: "sailboat"
        case .trip: "calendar"
        case .people: "person.2"
        case .crewList: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }

    /// Settings sits apart from the four screens the work moves through. It is
    /// not a step — nobody passes through it on the way to a crew list — so the
    /// row puts it after a gap rather than at the end of the sequence.
    var isWorkflowStep: Bool { self != .settings }
}

// MARK: - The screen row

/// `.tabs` — text tabs with the active one underlined in the accent. Philon
/// carries a count on the screen whose contents vary (Library 9); here that is
/// the crew list, whose length is the one number an operator is tracking.
struct ScreenRow: View {
    @Binding var selection: Screen
    let crewCount: Int
    let onShowInfo: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Screen.allCases.filter(\.isWorkflowStep)) { screen in
                ScreenTab(
                    screen: screen,
                    isActive: selection == screen,
                    count: screen == .crewList ? crewCount : nil
                ) {
                    selection = screen
                }
            }

            Spacer(minLength: 16)

            ScreenTab(screen: .settings, isActive: selection == .settings, count: nil) {
                selection = .settings
            }

            SystemStatusChip(symbol: "lock.shield.fill", text: "On this Mac only")
                .help("Documents, extracted fields and the database never leave this machine.")

            Button(action: onShowInfo) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.philonIcon)
            .help("About \(AppVersion.name)")
            .padding(.leading, 8)
        }
        .padding(.horizontal, Theme.Space.workspace)
        .frame(height: 52)
        .background(Theme.panel)
    }
}

private struct ScreenTab: View {
    let screen: Screen
    let isActive: Bool
    let count: Int?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(screen.label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? Theme.accentText : (hovering ? Theme.ink : Theme.inkSecondary))

                if let count, count > 0 {
                    CountBadge(count: count, tint: isActive ? Theme.accentText : Theme.inkTertiary)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 52)
            // The active marker is a rule under the tab, not a pill around it:
            // at this size a pill crowds the count badge beside it.
            //
            // An overlay rather than a VStack sibling, because a Rectangle has
            // no intrinsic width — stacked under the label it expanded to fill
            // the row and dragged the tabs apart across the whole window.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isActive ? Theme.accentText : .clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - The command line

/// `.job-toolbar` — one full-width line holding every action available on the
/// current screen. Philon puts the inputs on the left and the thing the app is
/// for on the right, as the only filled control in the window.
/// Named `CommandBar` rather than `CommandLine`: the latter is a Swift
/// standard-library type, and shadowing it breaks `CommandLine.arguments`
/// in `HeadlessExport`.
struct CommandBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 16)
            trailing
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, Theme.Space.workspace)
        .frame(height: 56)
        .background(Theme.ground)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

// MARK: - The document grid

/// `.conversion-grid` — the panels that make up a screen, side by side inside
/// one bordered surface with hairlines between them, rather than three separate
/// cards each with its own border and shadow.
struct DocumentGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .philonPanel()
            .padding(.horizontal, Theme.Space.workspace)
            .padding(.top, 14)
            // The maker's mark sits in this corner; the panel stops above it.
            .padding(.bottom, MakersMark.reservedHeight + 6)
    }
}

/// The hairline between two panels of a grid.
struct GridDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1).frame(maxHeight: .infinity)
    }
}

/// `.subpanel-header` — an eyebrow, what the panel is showing, and whatever
/// small control belongs to the panel itself rather than to the window.
struct PanelHeader<Accessory: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: eyebrow)
                Text(title)
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            accessory
        }
        .frame(minHeight: 42, alignment: .top)
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }
}

extension PanelHeader where Accessory == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

// MARK: - Banner

/// `.notice-banner` / `.error-banner` — a full-width line under the command
/// line saying what is standing between this trip and a crew list. It sits in
/// the chrome rather than inside a panel because it is about the whole window.
struct ReadinessBanner: View {
    let blockers: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: blockers.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(blockers.isEmpty ? Theme.success : Theme.caution)

            Text(blockers.isEmpty ? "Crew list is ready to export." : blockers[0])
                .font(Theme.Font.meta)
                .foregroundStyle(blockers.isEmpty ? Theme.verifiedInk : Theme.warningInk)
                .lineLimit(1)
                .truncationMode(.tail)

            if blockers.count > 1 {
                CountBadge(count: blockers.count - 1, tint: Theme.warningInk)
                    .help(blockers.dropFirst().joined(separator: "\n"))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(blockers.isEmpty ? Theme.verifiedFill : Theme.warningFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(blockers.isEmpty ? Theme.verifiedBorder : Theme.warningBorder, lineWidth: 1)
        )
        .padding(.horizontal, Theme.Space.workspace)
        .padding(.top, 12)
    }
}
