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

    static func == (lhs: Activity, rhs: Activity) -> Bool {
        lhs.title == rhs.title
            && lhs.detail == rhs.detail
            && lhs.fraction == rhs.fraction
            && lhs.isCancellable == rhs.isCancellable
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
    static func bytes(_ title: String, received: Int64, expected: Int64, cancellable: Bool = true) -> Activity {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let detail = expected > 0
            ? "\(formatter.string(fromByteCount: received)) of \(formatter.string(fromByteCount: expected))"
            : formatter.string(fromByteCount: received)
        return Activity(
            title: title,
            detail: detail,
            fraction: expected > 0 ? Double(received) / Double(expected) : nil,
            isCancellable: cancellable
        )
    }
}
