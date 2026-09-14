import SwiftUI

/// What this application is, what it refuses to do, and who owes what to whom.
///
/// Shown once per version on first launch, because the promise it makes is the
/// reason an operator would put passport photographs into it at all, and a
/// promise nobody reads is not one.
struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    ForEach(About.paragraphs(of: About.story), id: \.self) { paragraph in
                        Text(paragraph)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Licences and sources")
                        ForEach(About.paragraphs(of: About.legal), id: \.self) { paragraph in
                            Text(paragraph)
                                .font(Theme.Font.meta)
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(About.credit)
                            .font(Theme.Font.supportEmphasis)
                            .foregroundStyle(Theme.ink)
                        Text(About.partnerCredit)
                            .font(Theme.Font.support)
                            .foregroundStyle(Theme.inkSecondary)
                        HStack(spacing: 14) {
                            ForEach(About.links, id: \.label) { link in
                                Button(link.label) { openURL(link.address) }
                                    .font(Theme.Font.meta)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(20)
            }
            .background(Theme.ground)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            if let mark = Brand.appMark {
                Image(platformImage: mark)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(About.title)
                    .font(Theme.Font.screenTitle)
                    .foregroundStyle(Theme.ink)
                Text(About.subtitle)
                    .font(Theme.Font.support)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(About.version)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
    }
}
