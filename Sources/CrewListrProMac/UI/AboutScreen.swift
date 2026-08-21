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
            // Philon's ink is green-tinted, and its workspace glow is a green
            // radial at 80% 0%. Both are re-based on the app's own blue —
            // borrowed unchanged they left this banner the only green thing in
            // the window once the accent moved.
            LinearGradient(
                colors: [Color(red: 0.043, green: 0.071, blue: 0.125),   // #0B1220
                         Color(red: 0.027, green: 0.043, blue: 0.078)],  // #070B14
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color(red: 0.055, green: 0.267, blue: 0.616).opacity(0.55), .clear],
                center: UnitPoint(x: 0.8, y: 0), startRadius: 0, endRadius: 320
            )

            CrewListMotif()
                .padding(.trailing, 34)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity, alignment: .trailing)

            // `.splash-art::after` — transparent to 50%, then to 35% black, so
            // the lockup keeps its contrast over whatever sits behind it.
            LinearGradient(
                stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.35), location: 1)],
                startPoint: .top, endPoint: .bottom
            )

            lockup
        }
        .frame(height: 250)
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
                // The maker's mark again, at the size Philon's footer credit
                // implies: the same claim as the window corner, spelled out.
                if let mark = Brand.makersMark {
                    Image(nsImage: mark).resizable().interpolation(.high).frame(width: 16, height: 16)
                }

                Text(About.credit)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)

                ForEach(About.links, id: \.address) { link in
                    Button(link.label) { openURL(link.address) }
                        .buttonStyle(.plain)
                        .font(Theme.Font.meta)
                        .foregroundStyle(Theme.accentText)
                        .pointerStyle(.link)
                }

                Spacer(minLength: 8)

                Button("Continue") { dismiss() }
                    .buttonStyle(.philonPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Space.dialog)
            .padding(.vertical, 14)
            .background(Theme.ground)
        }
    }
}

// MARK: - The motif

/// A crew list reduced to its geometry: the boxed header a port authority
/// reads first, then the ruled rows underneath. Drawn from the same shapes
/// `ExportService` prints, at low contrast, as key art rather than a preview.
private struct CrewListMotif: View {
    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 216)
            let scale = width / 216

            VStack(alignment: .leading, spacing: 9 * scale) {
                // Four header boxes: yacht, flag, port of registry, number.
                HStack(spacing: 6 * scale) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2 * scale)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                            .frame(height: 26 * scale)
                            .overlay(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white.opacity(index == 0 ? 0.34 : 0.2))
                                    .frame(width: (index == 0 ? 26 : 16) * scale, height: 3 * scale)
                                    .padding(4 * scale)
                            }
                    }
                }

                // SKIPPER, then the passenger rows.
                ForEach(0..<7, id: \.self) { row in
                    HStack(spacing: 7 * scale) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.accent.opacity(row == 0 ? 0.55 : 0.16))
                            .frame(width: (row == 0 ? 34 : 22) * scale, height: 4 * scale)

                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(row == 0 ? 0.3 : 0.16))
                            .frame(width: CGFloat(74 - (row % 3) * 11) * scale, height: 4 * scale)

                        Spacer(minLength: 0)

                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.13))
                            .frame(width: 30 * scale, height: 4 * scale)
                    }
                    .frame(height: 11 * scale)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                    }
                }
            }
            .frame(width: width)
            .rotation3DEffect(.degrees(17), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .rotationEffect(.degrees(-4))
            .opacity(0.9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(width: 216)
    }
}
