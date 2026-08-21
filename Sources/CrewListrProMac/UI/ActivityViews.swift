import SwiftUI

/// How work in progress is drawn.
///
/// Two presentations, chosen by `Activity.Style` rather than by guessing from
/// how long something has taken so far:
///
/// - `.transient` — a banner over the window. Seconds. It appears, it goes.
/// - `.sustained` — a strip under the command line. Minutes, with a way out.
///   A banner that never leaves stops reading as a banner, and a Cancel that
///   might vanish while you reach for it is worse than no Cancel.

// MARK: - Throttling

/// Coalesces a fast-changing activity down to something worth redrawing.
///
/// The model download reports every 1 MB, which over 5.78 GB is some 5,800
/// updates — bursty on a fast connection rather than evenly spaced, so the
/// coalesce is by elapsed time rather than by count. The store's job is to
/// report what is true; deciding how often to look at it is the view's.
///
/// Appearing, vanishing, changing operation and reaching the end are never
/// throttled: those are the moments the operator is actually watching for.
struct ThrottledActivity<Content: View>: View {
    let activity: Activity?
    var interval: TimeInterval = 0.1
    @ViewBuilder var content: (Activity?) -> Content

    @State private var shown: Activity?
    @State private var lastAccepted = Date.distantPast

    var body: some View {
        content(shown)
            .onChange(of: activity, initial: true) { _, latest in accept(latest) }
    }

    private func accept(_ latest: Activity?) {
        guard let latest else { shown = nil; return }

        let isNewOperation = latest.title != shown?.title
        let isFinished = (latest.clampedFraction ?? 0) >= 1
        let isUnmeasurable = latest.fraction == nil
        let intervalElapsed = Date().timeIntervalSince(lastAccepted) >= interval

        guard shown == nil || isNewOperation || isFinished || isUnmeasurable || intervalElapsed else { return }
        shown = latest
        lastAccepted = Date()
    }
}

// MARK: - Transient

/// Work measured in seconds, over the window. Never takes a click: it floats
/// above the interface, and an overlay that swallows the press meant for what
/// is underneath it is worse than no feedback at all.
struct ActivityBanner: View {
    let activity: Activity?

    var body: some View {
        ThrottledActivity(activity: activity) { shown in
            if let shown, shown.style == .transient {
                HStack(spacing: 10) {
                    if shown.fraction == nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accentText)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(shown.title)
                                .font(Theme.Font.support)
                                .foregroundStyle(Theme.ink)

                            if let percentage = shown.percentage {
                                Text(percentage)
                                    .font(Theme.Font.metaEmphasis.monospacedDigit())
                                    .foregroundStyle(Theme.accentText)
                            }
                        }

                        // `detail` arrives formatted — "3 of 6 · passport.jpeg".
                        // The view never composes position text itself, or it
                        // becomes a second formatter drifting from the first.
                        if let detail = shown.detail {
                            Text(detail)
                                .font(Theme.Font.meta)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        if let fraction = shown.clampedFraction {
                            PhilonProgress(value: fraction, height: 3)
                                .frame(width: 190)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                // It floats; it must not intercept.
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeOut(duration: 0.18), value: activity == nil)
    }
}

// MARK: - Sustained

/// Work measured in minutes, in the chrome. It keeps its place while it runs,
/// on every screen, and carries the way to stop it.
struct SustainedActivityStrip: View {
    @Environment(CrewStore.self) private var store
    let activity: Activity?

    var body: some View {
        ThrottledActivity(activity: activity) { shown in
            if let shown, shown.style == .sustained {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accentText)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(shown.title)
                                .font(Theme.Font.supportEmphasis)
                                .foregroundStyle(Theme.ink)

                            if let detail = shown.detail {
                                Text(detail)
                                    .font(Theme.Font.meta)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            if let percentage = shown.percentage {
                                Text(percentage)
                                    .font(Theme.Font.metaEmphasis.monospacedDigit())
                                    .foregroundStyle(Theme.accentText)
                            }
                        }

                        if let fraction = shown.clampedFraction {
                            PhilonProgress(value: fraction, height: 4)
                        } else {
                            ProgressView().progressViewStyle(.linear).controlSize(.small)
                        }
                    }

                    if shown.isCancellable {
                        Button("Cancel") { store.cancelActivity() }
                            .buttonStyle(.philonQuiet)
                            .font(Theme.Font.meta)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.accentText.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, Theme.Space.workspace)
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: activity == nil)
    }
}
