import AVKit
import CoreMedia
import Foundation

/// System Picture in Picture for the engine's sample-buffer display layer.
@MainActor
final class PictureInPictureController: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
    private weak var playback: PlaybackController?
    private var pip: AVPictureInPictureController?

    var isPossible: Bool { pip?.isPictureInPicturePossible ?? false }
    var isActive: Bool { pip?.isPictureInPictureActive ?? false }

    func attach(layer: AVSampleBufferDisplayLayer, playback: PlaybackController) {
        self.playback = playback
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        pip = AVPictureInPictureController(contentSource: source)
        #if os(iOS)
        // Swiping home during playback carries on in a PiP window.
        pip?.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
    }

    func toggle() {
        guard let pip else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() } else { pip.startPictureInPicture() }
    }

    /// Call when play/pause or duration changes so the PiP window's controls stay correct.
    func invalidate() { pip?.invalidatePlaybackState() }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor in playing ? self.playback?.play() : self.playback?.pause() }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        MainActor.assumeIsolated {
            let duration = playback?.duration ?? 0
            return CMTimeRange(start: .zero, duration: CMTime(seconds: max(duration, 0.1), preferredTimescale: 600))
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { !(playback?.isPlaying ?? false) }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            self.playback?.skip(by: skipInterval.seconds)
            completionHandler()
        }
    }
}
