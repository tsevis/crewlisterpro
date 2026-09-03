import AppKit
import SwiftUI
import XCTest
@testable import CrewListrProMac

/// Drives a real SwiftUI view with real AppKit input, so a control can be
/// clicked and typed into rather than have its closure called directly.
///
/// There is no XCUITest here to do it properly: a Swift package cannot host a
/// UI-testing bundle, and restructuring the app into an `.xcodeproj` to get one
/// would take `swift test` away from every other suite in this file. What is
/// possible in-process turns out to be most of the value, because SwiftUI on
/// macOS is backed by real AppKit controls — a `Button` is an `NSButton` that
/// answers `performClick`, and a `TextField` has a real field editor that
/// answers `insertText`.
///
/// **Nothing appears on screen.** The window is borderless, positioned far
/// outside any display, never ordered front, and the process sets its
/// activation policy to `.prohibited` so it cannot reach the Dock either.
///
/// Two things this cannot do, and does not pretend to. It cannot find a control
/// by name — SwiftUI does not pass `.accessibilityIdentifier` down to the
/// backing `NSView`, and the buttons' `title` is empty because SwiftUI draws
/// its own label — so each test hosts the smallest view containing the control
/// it means, and addresses it by position. And it cannot drive a sheet or a
/// `confirmationDialog`, which are presented by the window server.
@MainActor
final class Harness<Content: View> {
    let window: NSWindow
    let host: NSHostingView<Content>

    init(_ view: Content, size: CGSize = CGSize(width: 620, height: 520)) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: size),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        settle()
    }

    deinit {
        window.contentView = nil
        window.close()
    }

    /// Lets SwiftUI apply state changes and AppKit finish its layout. SwiftUI
    /// updates on the main run loop, so an assertion made in the same turn as
    /// the input reads the state from before it.
    func settle(_ turns: Int = 3) {
        for _ in 0..<turns { RunLoop.current.run(until: Date().addingTimeInterval(0.06)) }
        host.layoutSubtreeIfNeeded()
    }

    // MARK: - Finding controls

    func all<T: NSView>(_ type: T.Type) -> [T] {
        func walk(_ view: NSView) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap(walk)
        }
        return walk(host)
    }

    func buttons() -> [NSButton] { all(NSButton.self) }
    func fields() -> [NSTextField] { all(NSTextField.self).filter(\.isEditable) }

    // MARK: - Acting

    /// Presses a button by sending its action, which is what AppKit does when
    /// one is clicked.
    ///
    /// This reaches fewer controls than it looks like it should, and the limits
    /// are worth writing down because both dead ends cost an afternoon.
    ///
    /// A SwiftUI `Button` with a custom `ButtonStyle` — which is nearly every
    /// button in this app — is not an `NSButton` at all. SwiftUI draws it and
    /// tracks the mouse itself, so there is nothing here to find: the review
    /// pane offers exactly one `NSButton`, the client checkbox, and none of its
    /// seven confirm controls.
    ///
    /// And that checkbox cannot be pressed either. It carries no target or
    /// action, so `performClick` is silently a no-op — a test built on one
    /// passes while pressing nothing. Sending it a real `leftMouseDown` instead
    /// does not work: `mouseDown` enters AppKit's modal tracking loop and waits
    /// for a mouse-up from an event queue that no `NSApplication` is running,
    /// so the test hangs until it is killed.
    ///
    /// Driving those needs a UI-testing bundle, which a Swift package cannot
    /// host. What is left — text fields — is where the interaction bugs in this
    /// app have actually been.
    func click(buttonAt index: Int, file: StaticString = #filePath, line: UInt = #line) {
        let found = buttons()
        guard index < found.count else {
            return XCTFail("no button at \(index); the view has \(found.count)", file: file, line: line)
        }
        guard found[index].action != nil else {
            return XCTFail("the button at \(index) has no action to send; see the note on this method",
                           file: file, line: line)
        }
        found[index].performClick(nil)
        settle()
    }

    /// Types into a field the way a person does — into its field editor — then
    /// leaves it, which is what commits the value.
    func type(_ text: String, intoFieldAt index: Int, file: StaticString = #filePath, line: UInt = #line) {
        let found = fields()
        guard index < found.count else {
            return XCTFail("no editable field at \(index); the view has \(found.count)", file: file, line: line)
        }
        let field = found[index]
        window.makeFirstResponder(field)
        settle()
        guard let editor = field.currentEditor() as? NSTextView else {
            return XCTFail("field \(index) would not begin editing", file: file, line: line)
        }
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        settle()
        blur()
    }

    /// Leaves whatever is being edited, exactly as tabbing away does.
    func blur() {
        window.makeFirstResponder(nil)
        settle()
    }

    /// What a field is showing now.
    func text(ofFieldAt index: Int) -> String? {
        let found = fields()
        guard index < found.count else { return nil }
        return found[index].stringValue
    }
}
