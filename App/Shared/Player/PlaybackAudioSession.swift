#if !os(macOS)
import AVFoundation
import SwiftUI

extension View {
    /// The audio session around a player screen (iPhone and Apple TV).
    func playbackAudioSession(_ player: PlaybackController) -> some View { modifier(PlaybackAudioSession(player: player)) }
}

/// Claims playback while the player shows and stops it when it goes, letting music or a podcast the
/// film interrupted carry on. Pauses when headphones go or a call comes in.
private struct PlaybackAudioSession: ViewModifier {
    let player: PlaybackController

    func body(content: Content) -> some View {
        content
            .onAppear {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .moviePlayback)
                // 5.1/7.1 PCM and Dolby reach the system whole, so AirPods can render them spatially.
                try? session.setSupportsMultichannelContent(true)
                try? session.setActive(true)
                // Over HDMI, every channel the receiver takes, so decoded 5.1/7.1 isn't folded to stereo.
                try? session.setPreferredOutputNumberOfChannels(session.maximumOutputNumberOfChannels)
            }
            .onDisappear {
                player.stop()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
                // Headphones unplugged or disconnected: pause, as every player does.
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
                if reason == .oldDeviceUnavailable { player.pause() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
                // A call or an alarm: pause, and carry on afterwards if the system says to.
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                switch type {
                case .began:
                    player.pause()
                case .ended:
                    let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
                    if options?.contains(.shouldResume) == true {
                        try? AVAudioSession.sharedInstance().setActive(true)
                        player.play()
                    }
                @unknown default:
                    break
                }
            }
    }
}
#endif
