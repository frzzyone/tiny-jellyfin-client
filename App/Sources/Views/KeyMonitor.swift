import AppKit
import SwiftUI

/// Hands every key press in this view's window to `handler`, whatever SwiftUI thinks has focus,
/// saying whether a text field is being edited at the time. A handler that returns true swallows
/// the event; false lets it reach the field or whatever else wanted it.
struct KeyMonitor: NSViewRepresentable {
    let handler: (NSEvent, _ editing: Bool) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.handler = handler
    }

    final class MonitorView: NSView {
        var handler: ((NSEvent, Bool) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil, let window else { return }
            // SwiftUI hands the window's first key focus to the search field; the page should have it.
            DispatchQueue.main.async { if window.firstResponder is NSTextView { window.makeFirstResponder(nil) } }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Events posted to an inactive app arrive without a window; treat them as ours.
                guard let self, let window = self.window, (event.window ?? window) === window else { return event }
                let editing = window.firstResponder is NSTextView
                return self.handler?(event, editing) == true ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

extension NSEvent {
    /// Key codes the browser cares about (layout independent: these are positions).
    var isUpArrow: Bool { keyCode == 126 }
    var isDownArrow: Bool { keyCode == 125 }
    var isLeftArrow: Bool { keyCode == 123 }
    var isRightArrow: Bool { keyCode == 124 }
    var isReturn: Bool { keyCode == 36 || keyCode == 76 }
    var isSpace: Bool { keyCode == 49 }
    var isEscape: Bool { keyCode == 53 }

    /// The typed text when this is a plain character key (letters, digits, punctuation), else nil.
    var typedText: String? {
        // Only the modifiers that change a key's meaning count; events carry other bits too.
        let modifiers: NSEvent.ModifierFlags = [.control, .option, .command, .function, .help]
        guard modifierFlags.isDisjoint(with: modifiers), let text = characters, let scalar = text.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar), !CharacterSet.newlines.contains(scalar),
              scalar.value < 0xF700 else { return nil } // F700+ are the function keys and arrows
        return text
    }
}
