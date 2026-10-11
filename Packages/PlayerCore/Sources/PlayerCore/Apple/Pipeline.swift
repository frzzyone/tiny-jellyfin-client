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
    let demuxer: Demuxer
    let videoQueue = PacketQueue(maxDuration: 30)
    let audioQueue = PacketQueue(maxDuration: 30)
    private(set) var videoStream: Int?
    private(set) var audioStream: Int?
    private(set) var videoInfo: VideoStreamInfo?
    var videoFormat: VideoFormat?
    var audioMode: AudioMode?
    private(set) var subtitleStores: [Int: SubtitleTrackStore] = [:]
    private var subtitleDecoders: [Int: SubtitleDecoder] = [:]
    private(set) var tracks: [MediaTrack] = []
    private(set) var duration: Double?

    private let condition = NSCondition()
    private var thread: Thread?
    private var stopped = false
    private var pendingSeek: Double?
    private var seekWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var failure: String?
    private var consecutiveErrors = 0

    let allowDolbyVision: Bool

    init(source: MediaSource, allowDolbyVision: Bool) {
        self.source = source
        self.allowDolbyVision = allowDolbyVision
        demuxer = Demuxer(url: source.url, factory: DefaultByteSourceFactory(headers: source.headers))
        demuxer.setTimelineOffset(source.timelineOffset)
    }

    deinit { stop() }

    /// Opens the container, picks streams, builds formats, positions at `startAt`. Blocking.
    func open(startAt: Double) throws {
        try demuxer.open()
        tracks = demuxer.tracks
        duration = demuxer.duration.map { $0 + source.timelineOffset }
        videoStream = demuxer.bestStream(AVMEDIA_TYPE_VIDEO).flatMap { index in
            tracks.first { $0.id == index && $0.kind == .video }?.id
        }
        audioStream = demuxer.bestStream(AVMEDIA_TYPE_AUDIO)
        if let videoStream, let par = demuxer.codecParameters(videoStream) {
            videoInfo = VideoStreamInfo(parameters: par)
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
        if startAt > 0.5 { try? demuxer.seek(to: startAt) }
        try alignTimeline(near: startAt)
        if let info = videoInfo, info.hasConfigurationRecord {
            videoFormat = try VideoFormat.make(info, firstKeyframe: nil, allowDolbyVision: allowDolbyVision)
        }
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

    /// Server transcodes may restart timestamps; if the first packet after positioning is far
    /// from where we asked to start, shift the timeline so positions match the item.
    private func alignTimeline(near startAt: Double) throws {
        guard startAt > 10, let first = try demuxer.readPacket() else { return }
        let drift = startAt - first.time
        if abs(drift) > 10 {
            demuxer.setTimelineOffset(source.timelineOffset + drift)
        }
        try? demuxer.seek(to: startAt)
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
    func seek(to time: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            condition.lock()
            if stopped {
                condition.unlock()
                continuation.resume()
                return
            }
            pendingSeek = time
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
                let waiters = seekWaiters
                seekWaiters.removeAll()
                condition.unlock()
                demuxer.clearInterrupt()
                try? demuxer.seek(to: target)
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
                route(packet)
            } catch let error as FFmpegError {
                if error.isExit || shouldAbortPush { continue }
                consecutiveErrors += 1
                // Corrupt data: skip ahead. Repeated I/O failure: give up.
                if error.code == cff_averror_invaliddata() && consecutiveErrors < 200 { continue }
                if consecutiveErrors >= 3 || error.code != cff_averror_invaliddata() {
                    condition.lock(); failure = error.description; condition.unlock()
                    videoQueue.markEndOfStream()
                    audioQueue.markEndOfStream()
                }
            } catch {
                condition.lock(); failure = String(describing: error); condition.unlock()
                videoQueue.markEndOfStream()
                audioQueue.markEndOfStream()
            }
        }
        demuxer.close()
    }

    private func route(_ packet: Packet) {
        if packet.streamIndex == videoStream {
            if videoFormat == nil, packet.isKeyframe, let info = videoInfo {
                videoFormat = try? VideoFormat.make(info, firstKeyframe: packet.data, allowDolbyVision: allowDolbyVision)
            }
            if videoFormat != nil { videoQueue.push(packet) { [unowned self] in shouldAbortPush } }
        } else if packet.streamIndex == audioStream {
            audioQueue.push(packet) { [unowned self] in shouldAbortPush }
        } else if let decoder = subtitleDecoders[packet.streamIndex], let store = subtitleStores[packet.streamIndex] {
            decoder.decode(packet).forEach(store.add)
        }
    }

    var hasFailed: String? { condition.lock(); defer { condition.unlock() }; return failure }

    /// True once the reader reached the end and the queues are empty.
    var isDrained: Bool {
        (videoStream == nil || videoQueue.isDrained) && (audioStream == nil || audioQueue.isDrained)
    }

    /// Seconds of video (or audio) currently queued.
    var bufferedDuration: Double {
        videoStream != nil ? videoQueue.duration : audioQueue.duration
    }

    var reachedEnd: Bool { videoQueue.endOfStream || (videoStream == nil && audioQueue.endOfStream) }
}
#endif
