#if canImport(AVFoundation)
import CFFmpeg
import CoreMedia
import Foundation

/// One open source: a demuxer with its reader thread, per-stream packet queues, the video
/// format and audio mode, and decoded cues for every embedded text subtitle track.
/// The engine can run two pipelines at once while splicing a quality switch.
final class Pipeline: @unchecked Sendable {
    enum AudioMode {
        case passthrough(CMAudioFormatDescription)
        case decode(AudioDecoder)
    }

    let source: MediaSource
    /// Replaced only on the reader thread (HLS seeks reopen the stream); read under `condition`.
    private var currentDemuxer: Demuxer
    private var demuxer: Demuxer {
        condition.lock(); defer { condition.unlock() }
        return currentDemuxer
    }
    let videoQueue = PacketQueue(maxDuration: 30)
    let audioQueue = PacketQueue(maxDuration: 30)
    private(set) var videoStream: Int?
    private(set) var videoInfo: VideoStreamInfo?
    // Set on the reader thread (first keyframe, an audio track change during a seek) and on the
    // engine's queue (the Dolby Vision fallback), read on both: behind their own lock.
    private let sharedLock = NSLock()
    private var _audioStream: Int?, _videoFormat: VideoFormat?, _audioMode: AudioMode?
    private(set) var audioStream: Int? {
        get { sharedLock.withLock { _audioStream } }
        set { sharedLock.withLock { _audioStream = newValue } }
    }
    var videoFormat: VideoFormat? {
        get { sharedLock.withLock { _videoFormat } }
        set { sharedLock.withLock { _videoFormat = newValue } }
    }
    var audioMode: AudioMode? {
        get { sharedLock.withLock { _audioMode } }
        set { sharedLock.withLock { _audioMode = newValue } }
    }
    private(set) var subtitleStores: [Int: SubtitleTrackStore] = [:]
    private var subtitleDecoders: [Int: SubtitleDecoder] = [:]
    /// Picture subtitles are decoded for the selected track only: a Blu-ray remux can carry
    /// dozens, and each event is an image.
    private var pictureDecoders: [Int: SubtitleDecoder] = [:]
    private var pictureTrackStore: (track: Int, store: BitmapSubtitleStore)?
    private(set) var tracks: [MediaTrack] = []
    private(set) var duration: Double?

    private let condition = NSCondition()
    private var thread: Thread?
    private var stopped = false
    private var pendingSeek: Double?
    /// Another audio stream of the same input, taken by the reader with the next seek.
    private var pendingAudioStream: Int?
    private var seekWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var failure: String?
    private var consecutiveErrors = 0
    /// Set at open: check the first packet's timestamp against this. Progressive transcodes start
    /// their timeline at 0, so the offset is corrected from the first packet. Segmented streams
    /// keep item time plus a known offset (`MediaSource.timelineOffset`), and the segment is
    /// expected to begin at or before the target; a first packet far from that is logged, not
    /// corrected, because the playlist — not the packets — decides where seeks land.
    private var timelineCheck: Double?

    let allowDolbyVision: Bool

    init(source: MediaSource, allowDolbyVision: Bool) {
        self.source = source
        self.allowDolbyVision = allowDolbyVision
        currentDemuxer = Demuxer(url: source.url, factory: DefaultByteSourceFactory(headers: source.headers))
        currentDemuxer.setTimelineOffset(source.timelineOffset)
    }

    deinit { stop() }

    /// Opens the container, picks streams, builds formats, positions at `startAt`. Blocking.
    func open(startAt: Double) throws {
        let openStart = Date()
        try demuxer.open(seekBeforeProbe: startAt)
        let opened = Date()
        tracks = demuxer.tracks
        // A playlist's duration is already item time; a progressive transcode's is what remains.
        duration = demuxer.duration.map { $0 + (demuxer.isSegmented ? 0 : source.timelineOffset) }
        videoStream = demuxer.bestStream(AVMEDIA_TYPE_VIDEO).flatMap { index in
            tracks.first { $0.id == index && $0.kind == .video }?.id
        }
        audioStream = source.audioTrack.flatMap { id in tracks.first { $0.id == id && $0.kind == .audio }?.id }
            ?? demuxer.bestStream(AVMEDIA_TYPE_AUDIO)
        if let videoStream, let par = demuxer.codecParameters(videoStream) {
            videoInfo = VideoStreamInfo(parameters: par)
            if let stream = demuxer.stream(videoStream) {
                videoInfo?.frameRate = VideoStreamInfo.frameRate(average: stream.pointee.avg_frame_rate,
                                                                 real: stream.pointee.r_frame_rate)
            }
        }
        if let audioStream, let stream = demuxer.stream(audioStream) {
            audioMode = try makeAudioMode(stream)
        }
        for track in tracks where track.isTextSubtitle {
            guard let stream = demuxer.stream(track.id),
                  let decoder = try? SubtitleDecoder(parameters: stream.pointee.codecpar,
                                                     timeBase: stream.pointee.time_base,
                                                     timelineOffset: source.timelineOffset) else { continue }
            subtitleDecoders[track.id] = decoder
            subtitleStores[track.id] = SubtitleTrackStore()
        }
        for track in tracks where track.isPictureSubtitle {
            guard let stream = demuxer.stream(track.id),
                  let decoder = try? SubtitleDecoder(parameters: stream.pointee.codecpar,
                                                     timeBase: stream.pointee.time_base,
                                                     timelineOffset: source.timelineOffset) else { continue }
            pictureDecoders[track.id] = decoder
        }
        if source.pictureSubtitle != nil { _ = decodePictures(of: source.pictureSubtitle) }
        if startAt > 10 { timelineCheck = startAt }
        PlayerLog.engine(String(format: "Open took %.2f s (header+probe %.2f s, positioning %.2f s), seekable=%@",
                                Date().timeIntervalSince(openStart), opened.timeIntervalSince(openStart),
                                Date().timeIntervalSince(opened), "\(demuxer.isSeekable)"))
        if let info = videoInfo, info.hasConfigurationRecord {
            videoFormat = try VideoFormat.make(info, firstKeyframe: nil, allowDolbyVision: allowDolbyVision)
        }
        let audioDescription: String
        switch audioMode {
        case .passthrough?: audioDescription = "passthrough"
        case .decode?: audioDescription = "decode"
        case nil: audioDescription = "none"
        }
        PlayerLog.engine("Opened \(demuxer.formatName) start=\(startAt) duration=\(duration ?? -1)"
                         + " tracks=\(tracks.map { "\($0.id):\($0.kind.rawValue)/\($0.codec)" }.joined(separator: ","))"
                         + " video=\(videoStream.map(String.init) ?? "-") \(videoInfo.map { "\($0.codec) \($0.width)x\($0.height) \($0.bitDepth)bit transfer=\($0.color.transferKind) dv=\($0.dolbyVision.map { "P\($0.profile)" } ?? "no")" } ?? "")"
                         + " videoFormat=\(videoFormat == nil ? "pending" : (videoFormat!.usesDolbyVision ? "dolby-vision" : "ok"))"
                         + " audio=\(audioStream.map(String.init) ?? "-") \(audioDescription)")
    }

    private func makeAudioMode(_ stream: UnsafeMutablePointer<AVStream>) throws -> AudioMode {
        let par = stream.pointee.codecpar.pointee
        let rate = Int(par.sample_rate), channels = Int(par.ch_layout.nb_channels)
        if par.codec_id == AV_CODEC_ID_EAC3 || par.codec_id == AV_CODEC_ID_AC3,
           let format = SampleBuffers.dolbyFormat(eac3: par.codec_id == AV_CODEC_ID_EAC3,
                                                  sampleRate: rate, channels: channels) {
            return .passthrough(format)
        }
        return .decode(try AudioDecoder(parameters: stream.pointee.codecpar, timeBase: stream.pointee.time_base,
                                        timelineOffset: source.timelineOffset))
    }

    // MARK: Reader thread

    func start() {
        let thread = Thread { [weak self] in self?.readLoop() }
        thread.name = "PlayerCore.reader"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    func stop() {
        condition.lock()
        if stopped { condition.unlock(); return }
        stopped = true
        let waiters = seekWaiters
        seekWaiters.removeAll()
        condition.broadcast()
        condition.unlock()
        waiters.forEach { $0.resume() }
        videoQueue.close()
        audioQueue.close()
        demuxer.interrupt()
    }

    /// Repositions the reader at the keyframe before `time` and flushes queued packets.
    func seek(to time: Double, audioStream: Int? = nil) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            condition.lock()
            if stopped {
                condition.unlock()
                continuation.resume()
                return
            }
            pendingSeek = time
            if let audioStream { pendingAudioStream = audioStream }
            seekWaiters.append(continuation)
            condition.broadcast()
            condition.unlock()
            demuxer.interrupt()
            videoQueue.flush()
            audioQueue.flush()
        }
    }

    private var shouldAbortPush: Bool {
        condition.lock(); defer { condition.unlock() }
        return stopped || pendingSeek != nil
    }

    private func readLoop() {
        while true {
            condition.lock()
            if stopped { condition.unlock(); break }
            if let target = pendingSeek {
                pendingSeek = nil
                let newAudio = pendingAudioStream
                pendingAudioStream = nil
                let waiters = seekWaiters
                seekWaiters.removeAll()
                condition.unlock()
                // The engine isn't feeding during a seek, so the audio mode can change here.
                if let newAudio, newAudio != audioStream, tracks.contains(where: { $0.id == newAudio && $0.kind == .audio }),
                   let stream = demuxer.stream(newAudio), let mode = try? makeAudioMode(stream) {
                    audioStream = newAudio
                    audioMode = mode
                    PlayerLog.engine("Audio: track \(newAudio)")
                }
                reposition(to: target)
                videoQueue.flush()
                audioQueue.flush()
                if case .decode(let decoder) = audioMode { decoder.flush() }
                consecutiveErrors = 0
                waiters.forEach { $0.resume() }
                continue
            }
            condition.unlock()

            if videoQueue.endOfStream || audioQueue.endOfStream && videoStream == nil {
                // At the end: idle until a seek or stop.
                condition.lock()
                if !stopped && pendingSeek == nil { _ = condition.wait(until: Date().addingTimeInterval(0.1)) }
                condition.unlock()
                continue
            }

            do {
                guard let packet = try demuxer.readPacket() else {
                    videoQueue.markEndOfStream()
                    audioQueue.markEndOfStream()
                    continue
                }
                consecutiveErrors = 0
                if let expected = timelineCheck {
                    timelineCheck = nil
                    let drift = expected - packet.time
                    if demuxer.isSegmented {
                        if drift < -1 || drift > 30 {
                            PlayerLog.engine(String(format: "Segment starts at %.1f s for a seek to %.1f s:"
                                                    + " timelineOffset %.1f s looks wrong for this server",
                                                    packet.time, expected, demuxer.timelineOffset))
                        }
                    } else if abs(drift) > 10 {
                        // The stream's own timeline starts at 0 (or elsewhere); shift it so
                        // positions match the item, then start again from the target.
                        PlayerLog.engine(String(format: "Timeline starts at %.1f s, expected %.1f s: shifting %+.1f s",
                                                packet.time, expected, drift))
                        demuxer.setTimelineOffset(demuxer.timelineOffset + drift)
                        videoQueue.flush()
                        audioQueue.flush()
                        reposition(to: expected)
                        continue
                    }
                }
                route(packet)
            } catch let error as FFmpegError {
                if error.isExit || shouldAbortPush { continue }
                consecutiveErrors += 1
                // Corrupt data: skip ahead. Repeated I/O failure: give up.
                if error.code == cff_averror_invaliddata() && consecutiveErrors < 200 { continue }
                if consecutiveErrors >= 3 || error.code != cff_averror_invaliddata() {
                    PlayerLog.engine("Reader failed: \(error.description)")
                    condition.lock(); failure = error.description; condition.unlock()
                    videoQueue.markEndOfStream()
                    audioQueue.markEndOfStream()
                }
            } catch {
                PlayerLog.engine("Reader failed: \(error)")
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                condition.lock(); failure = message; condition.unlock()
                videoQueue.markEndOfStream()
                audioQueue.markEndOfStream()
            }
        }
        demuxer.close()
    }

    /// Seeks the reader. HLS streams are reopened instead: interrupting FFmpeg's HLS demuxer
    /// mid-segment can leave it unable to continue.
    private func reposition(to target: Double) {
        let old = demuxer
        old.clearInterrupt()
        guard old.formatName == "hls" else {
            try? old.seek(to: target)
            return
        }
        let fresh = Demuxer(url: source.url, factory: DefaultByteSourceFactory(headers: source.headers))
        fresh.setTimelineOffset(old.timelineOffset)
        do {
            // Opened at the target, as the first open is: probing from the start would make the
            // server encode from 0 before the seek.
            try fresh.open(seekBeforeProbe: target)
            if target > 0.5 { try? fresh.seek(to: target) }
        } catch {
            try? old.seek(to: target)
            return
        }
        condition.lock()
        currentDemuxer = fresh
        condition.unlock()
        old.close()
    }

    private func route(_ packet: Packet) {
        if packet.streamIndex == videoStream {
            if videoFormat == nil, packet.isKeyframe, let info = videoInfo {
                videoFormat = try? VideoFormat.make(info, firstKeyframe: packet.data, allowDolbyVision: allowDolbyVision)
            }
            if videoFormat != nil { videoQueue.push(packet) { [unowned self] in shouldAbortPush } }
        } else if packet.streamIndex == audioStream {
            audioQueue.push(packet) { [unowned self] in shouldAbortPush }
        } else if let decoder = pictureDecoders[packet.streamIndex] {
            condition.lock()
            let store = pictureTrackStore?.track == packet.streamIndex ? pictureTrackStore?.store : nil
            condition.unlock()
            if let store, let event = decoder.decodePicture(packet) {
                store.add(event.bitmap, at: event.time)
                if let bitmap = event.bitmap, store.count == 1 {
                    PlayerLog.engine(String(format: "Picture subtitles: first event at %.1f s, %d×%d, %d piece(s)",
                                            event.time, bitmap.canvasWidth, bitmap.canvasHeight, bitmap.pieces.count))
                }
            }
        } else if let decoder = subtitleDecoders[packet.streamIndex], let store = subtitleStores[packet.streamIndex] {
            decoder.decode(packet).forEach(store.add)
        }
    }

    /// Starts decoding `track`'s picture subtitles into a fresh store; returns false when the track
    /// has no picture subtitles, or is already the one decoded.
    func decodePictures(of track: Int?) -> Bool {
        condition.lock(); defer { condition.unlock() }
        guard let track, pictureDecoders[track] != nil else {
            pictureTrackStore = nil
            return false
        }
        if pictureTrackStore?.track == track { return false }
        PlayerLog.engine("Picture subtitles: decoding track \(track)")
        pictureTrackStore = (track, BitmapSubtitleStore())
        return true
    }

    func pictureSubtitles(of track: Int) -> BitmapSubtitleStore? {
        condition.lock(); defer { condition.unlock() }
        return pictureTrackStore?.track == track ? pictureTrackStore?.store : nil
    }

    var hasFailed: String? { condition.lock(); defer { condition.unlock() }; return failure }

    /// Size the picture is shown at. MPEG-TS and HLS have no header, so the container often says
    /// 0×0 until the first keyframe's parameter sets are parsed; then the format description knows.
    var presentationSize: CGSize? {
        if let info = videoInfo, info.width > 0, info.height > 0 { return info.presentationSize }
        guard let format = videoFormat else { return nil }
        let size = CMVideoFormatDescriptionGetPresentationDimensions(format.description, usePixelAspectRatio: true,
                                                                     useCleanAperture: true)
        return size.width > 0 && size.height > 0 ? size : nil
    }

    /// True once the reader reached the end and the queues are empty.
    var isDrained: Bool {
        (videoStream == nil || videoQueue.isDrained) && (audioStream == nil || audioQueue.isDrained)
    }

    /// Seconds of video (or audio) currently queued.
    var bufferedDuration: Double {
        videoStream != nil ? videoQueue.duration : audioQueue.duration
    }

    var reachedEnd: Bool { videoQueue.endOfStream || (videoStream == nil && audioQueue.endOfStream) }

    /// Earliest packet still queued, across the streams being played.
    var firstQueuedTime: Double? {
        [videoStream != nil ? videoQueue.peek()?.time : nil,
         audioStream != nil ? audioQueue.peek()?.time : nil].compactMap { $0 }.min()
    }
}
#endif
