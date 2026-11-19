import AVFoundation
import GameController
import SwiftUI
import UIKit

/// What the Siri Remote did. Clicks arrive as presses; a swipe on the touch surface as a pan.
enum RemoteCommand: Equatable {
    case select, playPause, left, right, up, down, menu
    case panBegan
    /// Horizontal travel so far, as a fraction of the screen's width.
    case panChanged(Double)
    case panEnded
}

/// The picture, full screen, and the one focusable thing on it while the player has no panel up:
/// it takes the remote's presses and touch-surface swipes and hands them to `onCommand`. A game
/// controller's buttons are read from GameController too: tvOS turns a controller's B into Back, but
/// its A and d-pad never reached the surface as presses (an Xbox controller could only close the player).
///
/// The view itself takes focus (`takesFocus`, false while a panel is up), not a SwiftUI `.focusable()`
/// around it: that focused SwiftUI's wrapper, and presses travel up from the focused view, never down,
/// so on a real Apple TV only Back (handled further up) did anything.
struct TVRemoteSurface: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer?
    var takesFocus = true
    let onCommand: (RemoteCommand) -> Void

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.onCommand = onCommand
        view.videoLayer = layer
        view.takesFocus = takesFocus
        return view
    }

    func updateUIView(_ view: SurfaceView, context: Context) {
        view.onCommand = onCommand
        if view.videoLayer !== layer { view.videoLayer = layer }
        view.takesFocus = takesFocus
    }

    final class SurfaceView: UIView {
        var onCommand: (RemoteCommand) -> Void = { _ in }
        var videoLayer: AVSampleBufferDisplayLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let videoLayer { layer.addSublayer(videoLayer); setNeedsLayout() }
            }
        }

        /// The last command and where it came from, so one button that arrives both as a press and
        /// from GameController acts once.
        private var last: (command: RemoteCommand, fromGamepad: Bool, at: Date)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            addGestureRecognizer(pan)
            // The notification can come on any thread; the block runs on the main queue.
            connectObserver = NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil,
                                                                     queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    if let self, self.window != nil, let controller = note.object as? GCController { self.attach(controller) }
                }
            }
        }

        private var connectObserver: NSObjectProtocol?

        deinit {
            if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        var takesFocus = true {
            didSet {
                guard takesFocus != oldValue else { return }
                // Back from a panel: focus returns here once the panel's buttons are gone.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.takesFocus else { return }
                    self.window?.windowScene?.focusSystem?.requestFocusUpdate(to: self)
                }
            }
        }

        override var canBecomeFocused: Bool { takesFocus }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            GCController.controllers().forEach { window == nil ? detach($0) : attach($0) }
        }

        // Only full gamepads: the Siri Remote is a micro gamepad, and its presses already arrive.
        // The handlers hop to the main queue rather than assume they are on it (GCController's
        // default), which would stop the app if a reconnecting controller ever called from elsewhere.
        private func attach(_ controller: GCController) {
            guard let pad = controller.extendedGamepad else { return }
            // Y opens the panel, as △ opens the options on the Mac.
            for (button, command) in [(pad.buttonA, RemoteCommand.select), (pad.buttonX, .playPause), (pad.buttonY, .down)] {
                button.pressedChangedHandler = { [weak self] _, _, pressed in
                    if pressed { DispatchQueue.main.async { self?.gamepad(command) } }
                }
            }
            for stick in [pad.dpad, pad.leftThumbstick] {
                var held: RemoteCommand?
                stick.valueChangedHandler = { [weak self] _, x, y in
                    let command = Self.direction(x: x, y: y)
                    DispatchQueue.main.async {
                        if command != held, let command { self?.gamepad(command) }
                        held = command
                    }
                }
            }
        }

        private func detach(_ controller: GCController) {
            guard let pad = controller.extendedGamepad else { return }
            [pad.buttonA, pad.buttonX, pad.buttonY].forEach { $0.pressedChangedHandler = nil }
            [pad.dpad, pad.leftThumbstick].forEach { $0.valueChangedHandler = nil }
        }

        /// A stick or d-pad pushed past halfway, along its main axis.
        nonisolated static func direction(x: Float, y: Float) -> RemoteCommand? {
            guard max(abs(x), abs(y)) > 0.5 else { return nil }
            return abs(x) >= abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
        }

        /// While a panel is up the surface isn't focused, and the controller moves through the panel.
        private func gamepad(_ command: RemoteCommand) {
            if isFocused { deliver(command, fromGamepad: true) }
        }

        private func deliver(_ command: RemoteCommand, fromGamepad: Bool) {
            let now = Date()
            if let last, last.command == command, last.fromGamepad != fromGamepad, now.timeIntervalSince(last.at) < 0.15 { return }
            last = (command, fromGamepad, now)
            onCommand(command)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer?.frame = bounds
            CATransaction.commit()
        }

        /// The swipe under way is up or down: a press of that arrow, not a scrub.
        private var swipingVertically = false

        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                let velocity = pan.velocity(in: self)
                swipingVertically = abs(velocity.y) > abs(velocity.x)
                onCommand(swipingVertically ? (velocity.y > 0 ? .down : .up) : .panBegan)
            case .changed:
                if !swipingVertically { onCommand(.panChanged(pan.translation(in: self).x / max(bounds.width, 1))) }
            case .ended, .cancelled, .failed:
                if !swipingVertically { onCommand(.panEnded) }
            default: break
            }
        }

        private func command(_ type: UIPress.PressType) -> RemoteCommand? {
            switch type {
            case .select: .select
            case .playPause: .playPause
            case .leftArrow: .left
            case .rightArrow: .right
            case .upArrow: .up
            case .downArrow: .down
            case .menu: .menu
            default: nil
            }
        }

        // Handled presses never reach super, so Back doesn't also dismiss the screen behind our back.
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let unhandled = presses.filter { command($0.type) == nil }
            presses.compactMap { command($0.type) }.forEach { deliver($0, fromGamepad: false) }
            if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let unhandled = presses.filter { command($0.type) == nil }
            if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let unhandled = presses.filter { command($0.type) == nil }
            if !unhandled.isEmpty { super.pressesCancelled(unhandled, with: event) }
        }
    }
}
