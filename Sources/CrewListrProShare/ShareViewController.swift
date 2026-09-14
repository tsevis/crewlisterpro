import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share → CrewListr Pro", from WhatsApp, Viber, Telegram, Signal, Mail,
/// Messages, Photos, Files, or anything else that offers a picture to another
/// app.
///
/// It deliberately does almost nothing. It does not open the encrypted store,
/// it does not run OCR, and it does not ask which charter the passport belongs
/// to — an extension is a short-lived process with a memory budget a fraction
/// of the app's, and a page of Vision recognition inside one is a spinner that
/// ends in a jetsam kill. What it does is take the bytes, put them in the
/// shared inbox, and say so. The work happens in the app, where there is time
/// for it and where the operator is choosing the trip anyway.
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private var model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        model.onCancel = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CancellationError())
        }
        model.onFinish = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }

        let sheet = UIHostingController(rootView: ShareSheetView(model: model))
        sheet.view.backgroundColor = .clear
        addChild(sheet)
        sheet.view.frame = view.bounds
        sheet.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(sheet.view)
        sheet.didMove(toParent: self)

        let attachments = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        Task { await model.load(attachments) }
    }
}

/// What the sheet knows: how many documents arrived, and what went wrong with
/// any of them.
@MainActor
@Observable
final class ShareModel {
    private(set) var isLoading = true
    private(set) var accepted: [String] = []
    private(set) var problems: [String] = []
    private(set) var saved = false

    /// Exactly what *this* share put in the inbox.
    ///
    /// Tracked, rather than emptying the inbox on cancel: the inbox is shared
    /// with every other share that has not been collected yet, so "I picked the
    /// wrong chat" would have silently thrown away three passports somebody
    /// sent from Viber ten seconds earlier.
    private var staged: [URL] = []

    var onCancel: () -> Void = {}
    var onFinish: () -> Void = {}

    var headline: String {
        if isLoading { return "Reading what was shared…" }
        if accepted.isEmpty { return "Nothing here to add" }
        return accepted.count == 1 ? "One document ready" : "\(accepted.count) documents ready"
    }

    /// Reads each attachment and stages it.
    ///
    /// Staged as it is read rather than gathered and written at the end: the
    /// extension can be terminated at any moment, and eight passports held in
    /// memory waiting for the ninth is eight passports lost when it is.
    func load(_ attachments: [NSItemProvider]) async {
        for provider in attachments {
            do {
                guard let type = Self.acceptableType(of: provider) else {
                    problems.append("One attachment was not an image or a PDF.")
                    continue
                }
                let url = try await stage(provider, as: type)
                staged.append(url)
                accepted.append(SharedInbox.originalName(of: url))
            } catch {
                problems.append(Self.explain(error))
            }
        }
        isLoading = false
        // Nothing usable arrived. There is no decision left for the operator to
        // make, so the sheet says why and gets out of the way rather than
        // offering a button that would do nothing.
        if accepted.isEmpty, problems.isEmpty {
            problems.append("Nothing that could be read as a document was shared.")
        }
    }

    /// Tapping outside the sheet. The same as Cancel, because the documents
    /// were staged as they were read — an extension can be killed at any
    /// moment, so waiting until a button is pressed would lose them — and a
    /// share the operator backed out of must not arrive in the app anyway.
    func dismiss() {
        guard saved else { return cancelAndErase() }
        onFinish()
    }

    func confirm() {
        saved = true
        onFinish()
    }

    /// What this share staged is erased, for the operator who realises they
    /// shared the wrong chat. Anything else waiting in the inbox is left alone.
    func cancelAndErase() {
        for url in staged { SharedInbox.discard(url) }
        staged.removeAll()
        accepted.removeAll()
        onCancel()
    }

    // MARK: - Reading one attachment

    private func stage(_ provider: NSItemProvider, as type: UTType) async throws -> URL {
        // `loadFileRepresentation` gives a real file with the sender's own name
        // on it, which is the name the operator will recognise in the document
        // list. `loadDataRepresentation` gives bytes and no name at all.
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: SharedInbox.InboxError.unsupported(name: provider.suggestedName ?? "the attachment"))
                    return
                }
                // The URL is valid only inside this callback, so the bytes are
                // copied here and not after.
                do {
                    let name = provider.suggestedName ?? url.lastPathComponent
                    // Measured before it is read. `SharedInbox.stage` enforces
                    // the same cap, but by then the whole attachment is in
                    // memory — and an extension has a fraction of an app's
                    // budget, so a shared video would be killed loading rather
                    // than refused, which reads to the operator as a share that
                    // did nothing and said nothing.
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    guard size <= SharedInbox.mostBytesPerItem else {
                        throw SharedInbox.InboxError.tooLarge(name: name, bytes: size)
                    }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    continuation.resume(returning: try SharedInbox.stage(data, named: name, type: type))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// The first type this attachment offers that is an image or a PDF.
    ///
    /// Asked in that order on purpose. A photograph shared from WhatsApp is
    /// offered as several types at once, and taking the first one listed can
    /// mean taking a thumbnail or a URL to a file the extension cannot reach.
    private static func acceptableType(of provider: NSItemProvider) -> UTType? {
        let offered = provider.registeredTypeIdentifiers.compactMap(UTType.init)
        if let pdf = offered.first(where: { $0.conforms(to: .pdf) }) { return pdf }
        return offered.first { $0.conforms(to: .image) }
    }

    private static func explain(_ error: Error) -> String {
        guard let local = error as? LocalizedError, let description = local.errorDescription else {
            return error.localizedDescription
        }
        return description
    }
}

/// The sheet itself: what arrived, what did not, and two ways out.
struct ShareSheetView: View {
    @Bindable var model: ShareModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
                .onTapGesture { model.dismiss() }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: model.accepted.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(model.accepted.isEmpty ? Color.orange : Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.headline).font(.headline)
                        Text("CrewListr Pro").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !model.accepted.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.accepted.prefix(6), id: \.self) { name in
                            Label(name, systemImage: "doc.text.image")
                                .font(.callout)
                                .lineLimit(1)
                        }
                        if model.accepted.count > 6 {
                            Text("and \(model.accepted.count - 6) more")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Open CrewListr Pro to put them on a charter. Every field still has to be checked against the document — sharing a passport does not review it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(model.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Cancel", role: .cancel) { model.cancelAndErase() }
                    Spacer()
                    Button(model.accepted.isEmpty ? "Close" : "Add to CrewListr Pro") { model.confirm() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isLoading)
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background))
            .padding(24)
            .frame(maxWidth: 460)
        }
    }
}
