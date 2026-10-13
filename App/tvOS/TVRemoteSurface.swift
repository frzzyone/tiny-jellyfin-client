import AVFoundation
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
/// it takes the remote's presses and touch-surface swipes and hands them to `onCommand`.
struct TVRemoteSurface: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer?
    let onCommand: (RemoteCommand) -> Void

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.onCommand = onCommand
        view.videoLayer = layer
        return view
    }

    func updateUIView(_ view: SurfaceView, context: Context) {
        view.onCommand = onCommand
        if view.videoLayer !== layer { view.videoLayer = layer }
    }

    final class SurfaceView: UIView {
        var onCommand: (RemoteCommand) -> Void = { _ in }
        var videoLayer: AVSampleBufferDisplayLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let videoLayer { layer.addSublayer(videoLayer); setNeedsLayout() }
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            addGestureRecognizer(pan)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override var canBecomeFocused: Bool { true }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer?.frame = bounds
            CATransaction.commit()
        }

        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began: onCommand(.panBegan)
            case .changed: onCommand(.panChanged(pan.translation(in: self).x / max(bounds.width, 1)))
            case .ended, .cancelled, .failed: onCommand(.panEnded)
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
            presses.compactMap { command($0.type) }.forEach(onCommand)
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
