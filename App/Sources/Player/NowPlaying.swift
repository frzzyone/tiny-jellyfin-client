import AppKit
import JellyfinKit
import MediaPlayer

/// Publishes the current item to macOS Now Playing and handles system media controls
/// (media keys, Control Center, headphones).
@MainActor
final class NowPlayingPublisher {
    private weak var controller: PlaybackController?
    private var info: [String: Any] = [:]
    private var commandsInstalled = false

    func begin(controller: PlaybackController, item: BaseItem, artworkURL: URL?) {
        self.controller = controller
        info = [
            MPMediaItemPropertyTitle: item.displayName,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let series = item.seriesName {
            info[MPMediaItemPropertyArtist] = series
            info[MPMediaItemPropertyAlbumTitle] = item.episodeLabel ?? series
        }
        installCommands()
        update()
        if let artworkURL {
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                      let image = NSImage(data: data) else { return }
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                update()
            }
        }
    }

    func update() {
        guard let controller, controller.item != nil else { return }
        info[MPMediaItemPropertyPlaybackDuration] = controller.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = controller.position
        info[MPNowPlayingInfoPropertyPlaybackRate] = controller.isPlaying ? 1.0 : 0.0
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = controller.isPlaying ? .playing : .paused
    }

    func end() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    private func installCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let commands = MPRemoteCommandCenter.shared()
        // Remote commands are delivered on the main thread.
        commands.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.run { $0.play() } ?? .commandFailed }
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.run { $0.pause() } ?? .commandFailed }
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.run { $0.togglePlayPause() } ?? .commandFailed }
        }
        commands.skipForwardCommand.preferredIntervals = [30]
        commands.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.run { $0.skip(by: 30) } ?? .commandFailed }
        }
        commands.skipBackwardCommand.preferredIntervals = [10]
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.run { $0.skip(by: -10) } ?? .commandFailed }
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            return MainActor.assumeIsolated {
                self?.run { controller in Task { await controller.seek(to: position) } } ?? .commandFailed
            }
        }
    }

    private func run(_ action: (PlaybackController) -> Void) -> MPRemoteCommandHandlerStatus {
        guard let controller, controller.item != nil else { return .noActionableNowPlayingItem }
        action(controller)
        update()
        return .success
    }
}
