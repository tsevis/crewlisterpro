import Foundation

/// A long-running operation, described well enough to render honestly.
///
/// The app previously reported work as a single sentence — "Reading documents…"
/// — with no sense of how much, how far, or whether it could be stopped. That is
/// tolerable for something that takes a second and unacceptable for importing
/// twenty passports or downloading a 5.78 GB model.
///
/// `fraction` is nil when the work genuinely cannot be measured. An indeterminate
/// spinner is the honest answer there; a bar that invents a percentage is not.
struct Activity: Equatable, Sendable, Identifiable {
    let id = UUID()

    /// What is happening, in the operator's terms. "Reading documents".
    var title: String

    /// The specific thing being worked on right now, if there is one.
    /// "3 of 6 · WhatsApp Image 2026-08-19.jpeg"
    var detail: String?

    /// 0...1, or nil when the work cannot be measured.
    var fraction: Double?

    /// Whether stopping is possible and safe. A multi-gigabyte download must be
    /// stoppable; a two-second image rotation need not be.
    var isCancellable: Bool = false

    /// How long the operator should expect this to last, which decides where it
    /// is drawn. Stated rather than inferred from `isCancellable`: the two
    /// happen to coincide today and there is no reason they must.
    enum Style: Sendable, Equatable {
        /// Seconds. A transient banner that comes and goes.
        case transient
        /// Minutes. Deserves a persistent place and a way out.
        case sustained
    }

    var style: Style = .transient

    static func == (lhs: Activity, rhs: Activity) -> Bool {
        lhs.title == rhs.title
            && lhs.detail == rhs.detail
            && lhs.fraction == rhs.fraction
            && lhs.isCancellable == rhs.isCancellable
            && lhs.style == rhs.style
    }

    /// Clamped, so a miscounted step cannot drive a bar past its end or
    /// backwards past its start.
    var clampedFraction: Double? {
        fraction.map { min(max($0, 0), 1) }
    }

    /// "45%" for a measurable operation, nil otherwise.
    var percentage: String? {
        clampedFraction.map { "\(Int(($0 * 100).rounded()))%" }
    }

    // MARK: - Common shapes

    static func indeterminate(_ title: String, detail: String? = nil) -> Activity {
        Activity(title: title, detail: detail, fraction: nil)
    }

    /// Step `completed` of `total`, counted from zero.
    static func step(_ title: String, completed: Int, total: Int, detail: String? = nil) -> Activity {
        guard total > 0 else { return .indeterminate(title, detail: detail) }
        let position = "\(min(completed + 1, total)) of \(total)"
        return Activity(
            title: title,
            detail: detail.map { "\(position) · \($0)" } ?? position,
            fraction: Double(completed) / Double(total)
        )
    }

    /// Bytes transferred out of an expected total.
    /// One formatter, not one per update. The download reports roughly 5,800
    /// times over 5.78 GB, and building a `ByteCountFormatter` each time is
    /// pure waste on a path that runs that often.
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func bytes(_ title: String, received: Int64, expected: Int64,
                      cancellable: Bool = true, style: Style = .sustained) -> Activity {
        let formatter = Self.byteFormatter
        let detail = expected > 0
            ? "\(formatter.string(fromByteCount: received)) of \(formatter.string(fromByteCount: expected))"
            : formatter.string(fromByteCount: received)
        return Activity(
            title: title,
            detail: detail,
            fraction: expected > 0 ? Double(received) / Double(expected) : nil,
            isCancellable: cancellable,
            style: style
        )
    }
}
