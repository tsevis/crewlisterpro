import AppKit
import SwiftUI

/// The info screen, kept to the measurements of Philon's splash rather than to
/// something that merely resembles them: 640 wide, 250pt of full-bleed key art,
/// 26pt margins, 36/13/11pt in the lockup, 12.5pt body and 10.5pt legal.
///
/// One deliberate departure. Philon's licences live in a `<details>` pinned to
/// the bottom of a fixed 580pt panel, which works because a web panel can grow.
/// Here the body and the disclosure share a scroll view under a pinned footer,
/// so opening the licences does not push Continue off the bottom edge.
struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingLegal = false

    var body: some View {
        VStack(spacing: 0) {
            keyArt

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(About.paragraphs(of: About.story), id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.system(size: 12.5))
                            .lineSpacing(2.5)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    legalDisclosure
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.dialog)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .frame(width: 640, height: 548)
        .background(Theme.panel)
        // Escape and Return both mean "I have read it", matching the close box
        // and the Continue button.
        .onExitCommand { dismiss() }
    }

    // MARK: - Key art
    //
    // Philon's banner is a photograph of its own output, on the principle that
    // the only honest thing to put on the front of a converter is a document it
    // converted. The equivalent here is drawn rather than photographed — a
    // crew list's own geometry, header boxes and ruled rows, over the ink and
    // accent glow of Philon's workspace. Drawn, so it claims to be a diagram
    // and not a specimen: no invented names sit on the front of this program.

    private var keyArt: some View {
        ZStack(alignment: .bottomLeading) {
            // The lockup sits on the photograph, so it needs its own ground:
            // dark at the bottom-left where the type is, clear at the top right
            // where the wake is worth seeing.
            LinearGradient(
                stops: [.init(color: .black.opacity(0.72), location: 0),
                        .init(color: .black.opacity(0.30), location: 0.5),
                        .init(color: .clear, location: 1)],
                startPoint: .bottom, endPoint: .top
            )

            lockup
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        // The photograph goes in the BACKGROUND, not into the stack. A
        // scaledToFill image inside the ZStack drives the stack to the image's
        // own height, and the lockup then lays out against that oversized frame
        // and lands below the 250pt the frame actually shows — which cut the
        // title and icon in half. A background never affects its host's size.
        .background {
            if let banner = Brand.unionBanner {
                // Union Yachting's own aerial: a wake that draws their mark on
                // the water. A photograph of the sea these crew lists are for
                // beats a diagram of a crew list.
                Image(nsImage: banner)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color(red: 0.043, green: 0.071, blue: 0.125),
                             Color(red: 0.027, green: 0.043, blue: 0.078)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .clipped()
    }

    private var lockup: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Group {
                if let mark = Brand.appMark {
                    Image(nsImage: mark).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.accent)
                }
            }
            .frame(width: 49, height: 49)

            VStack(alignment: .leading, spacing: 2) {
                Text(About.title)
                    .font(.system(size: 36, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.accent)

                Text(About.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.bottom, 3)

            Spacer(minLength: 12)

            Text(About.version)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 3)
        }
        .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
        .padding(.horizontal, Theme.Space.dialog)
        .padding(.bottom, 20)
    }

    // MARK: - Licences

    private var legalDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { showingLegal.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showingLegal ? 90 : 0))
                    Text("Sources, licences and credits")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.inkSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingLegal {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(About.paragraphs(of: About.legal), id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.system(size: 10.5))
                            .lineSpacing(2)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack(spacing: 14) {
                credit(mark: Brand.makersMark, text: About.credit,
                       site: Brand.makerSite, label: Brand.makerName)

                credit(mark: Brand.unionMark, text: About.partnerCredit,
                       site: Brand.unionSite, label: Brand.unionName)

                Spacer(minLength: 8)

                Button("Continue") { dismiss() }
                    .buttonStyle(.philonPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Space.dialog)
            .padding(.vertical, 12)
            .background(Theme.ground)
        }
    }

    /// A mark and the line beside it, the whole pair opening the site it names.
    private func credit(mark: NSImage?, text: String, site: URL, label: String) -> some View {
        Button { openURL(site) } label: {
            HStack(spacing: 7) {
                if let mark {
                    Image(nsImage: mark)
                        .resizable().interpolation(.high)
                        .frame(width: 17, height: 17)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text(text)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(site.absoluteString)
        .accessibilityLabel("\(text). Opens \(label)'s website.")
    }
}
