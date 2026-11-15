import AppKit
import GameController

/// A game controller drives the app with the keys it already knows: the d-pad and the left stick
/// are the arrows (repeating while held), A is Return, B is Esc (back), X is Space (F in the player:
/// full screen, as Space would only repeat A), Y is Tab (the player's options) and the shoulder
/// buttons are Page Up and Page Down (tabs, chapters). Each press
/// is posted as a key event to the key window, so the browser and the player need nothing of their own.
/// Input arrives only while Tinyfin is the active app.
@MainActor
enum Gamepad {
    enum Key: UInt16 {
        case f = 3, returnKey = 36, tab = 48, space = 49, escape = 53, pageUp = 116, pageDown = 121
        case left = 123, right = 124, down = 125, up = 126

        var characters: String {
            switch self {
            case .f: "f"
            case .returnKey: "\r"
            case .tab: "\t"
            case .pageUp: String(UnicodeScalar(NSPageUpFunctionKey)!)
            case .pageDown: String(UnicodeScalar(NSPageDownFunctionKey)!)
            case .space: " "
            case .escape: "\u{1b}"
            case .left: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
            case .right: String(UnicodeScalar(NSRightArrowFunctionKey)!)
            case .down: String(UnicodeScalar(NSDownArrowFunctionKey)!)
            case .up: String(UnicodeScalar(NSUpArrowFunctionKey)!)
            }
        }

        var modifierFlags: NSEvent.ModifierFlags {
            switch self {
            case .left, .right, .down, .up: [.numericPad, .function]
            case .pageUp, .pageDown: .function
            default: []
            }
        }
    }

    /// The arrow a stick or d-pad points at: its main axis, once pushed past halfway.
    nonisolated static func direction(x: Float, y: Float) -> Key? {
        guard max(abs(x), abs(y)) > 0.5 else { return nil }
        return abs(x) >= abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
    }

    static func event(_ key: Key, _ type: NSEvent.EventType, window: Int, isARepeat: Bool = false) -> NSEvent? {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: key.modifierFlags,
                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window, context: nil,
                                characters: key.characters, charactersIgnoringModifiers: key.characters,
                                isARepeat: isARepeat, keyCode: key.rawValue)
    }

    /// The player's window, which the player sets: X is F there.
    static weak var playerWindow: NSWindow?

    /// What X presses in `window`.
    static func xKey(in window: NSWindow?) -> Key { window != nil && window === playerWindow ? .f : .space }

    private static var started = false
    /// The direction each pad is held in, and the timer repeating it.
    private static var held: [ObjectIdentifier: (key: Key, timer: Timer)] = [:]

    static func start() {
        guard !started else { return }
        started = true
        GCController.controllers().forEach(attach)
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { attach(controller) }
        }
    }

    // Handlers run on the main queue (GCController's default handlerQueue).
    private static func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let buttons = [(pad.buttonA, Key.returnKey), (pad.buttonB, .escape), (pad.buttonY, .tab),
                       (pad.leftShoulder, .pageUp), (pad.rightShoulder, .pageDown)]
        for (button, key) in buttons {
            button.pressedChangedHandler = { _, _, pressed in
                if pressed { MainActor.assumeIsolated { press(key) } }
            }
        }
        pad.buttonX.pressedChangedHandler = { _, _, pressed in
            if pressed { MainActor.assumeIsolated { press(xKey(in: NSApp.keyWindow)) } }
        }
        for stick in [pad.dpad, pad.leftThumbstick] {
            stick.valueChangedHandler = { stick, x, y in
                MainActor.assumeIsolated { point(ObjectIdentifier(stick), direction(x: x, y: y)) }
            }
        }
    }

    /// A new direction presses its arrow, and keeps pressing it after a moment, like a held key.
    private static func point(_ pad: ObjectIdentifier, _ key: Key?) {
        guard held[pad]?.key != key else { return }
        held.removeValue(forKey: pad)?.timer.invalidate()
        guard let key else { return }
        press(key)
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in MainActor.assumeIsolated { press(key, isARepeat: true) } }
        timer.fireDate = Date(timeIntervalSinceNow: 0.4)
        RunLoop.main.add(timer, forMode: .common)
        held[pad] = (key, timer)
    }

    private static func press(_ key: Key, isARepeat: Bool = false) {
        guard NSApp.isActive, let window = NSApp.keyWindow else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = event(key, type, window: window.windowNumber, isARepeat: isARepeat) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }
}
