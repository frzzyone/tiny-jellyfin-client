#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import Foundation

/// Infuse-style engine: FFmpeg demuxes, VideoToolbox decodes video inside
/// `AVSampleBufferDisplayLayer`, audio goes to `AVSampleBufferAudioRenderer` (AC-3/E-AC-3
/// passed through, everything else decoded to PCM), and one `AVSampleBufferRenderSynchronizer`
/// owns the clock.
///
/// Threading: all mutable state lives on `queue`; public methods hop onto it.
public final class FFmpegEngine: PlaybackEngine, @unchecked Sendable {
    public let displayLayer = AVSampleBufferDisplayLayer()
    let audioRenderer = AVSampleBufferAudioRenderer()
    let synchronizer = AVSampleBufferRenderSynchronizer()
    var videoRenderer: AVSampleBufferVideoRenderer { displayLayer.sampleBufferRenderer }

    /// Set on the main thread, read on the engine's queue.
    public var onEvent: (@MainActor (EngineEvent) -> Void)? {
        get { snapshotLock.withLock { _onEvent } }
        set { snapshotLock.withLock { _onEvent = newValue } }
    }
    private var _onEvent: (@MainActor (EngineEvent) -> Void)?

    /// Seconds buffered ahead before (re)starting playback, and the low-water mark that pauses it.
    var startThreshold = 1.0
    /// How long opening a stream may take before giving up. A server that never answers would
    /// otherwise hold the spinner for minutes (each request waits 60 s, and is retried).
    var openTimeout: TimeInterval = 60
    var stallThreshold = 0.1
    /// How far ahead of the clock samples are handed to the renderers. Bounding this keeps a
    /// quality switch able to splice right after what is already enqueued.
    var feedAhead = 2.0

    private let queue = DispatchQueue(label: "PlayerCore.engine", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Bool>()
    private var onQueue: Bool { DispatchQueue.getSpecific(key: queueKey) == true }
    private let capabilities = EngineCapabilities.current()

    // Guarded by `queue`.
    private var active: Pipeline?
    private var incoming: Pipeline?
    private var spliceTime: Double?
    private var videoSwitched = false
    private var audioSwitched = false
    private var desiredRate: Float = 0
    /// The rate `play()` runs at.
    private var speedValue: Float = 1
    private var preRollTarget: Double?
    private var lastVideoEnd: Double = 0
    private var lastAudioEnd: Double = 0
    private var pendingAudio: [CMSampleBuffer] = []
    private var pcmFormat: (key: String, format: CMAudioFormatDescription)?
    private var requestingVideo = false
    private var requestingAudio = false
    private var audioUsable = true
    private var allowDolbyVision = true
    private var timer: DispatchSourceTimer?
    private var bufferingSince: Date?
    private var lastStallLog = Date.distantPast
    private var audioSampleFailures = 0
    private var selectedSubtitle: Int?
    private var externalSubtitles: SubtitleTrackStore?
    /// Bumped by `stop()`, so a `prepare` that finishes afterwards knows it was abandoned.
    private var generation = 0
    /// Counts seeks: only the newest one resets the clock, and a switch started before one is abandoned.
    private var seekSerial = 0

    // Snapshot for main-thread readers.
    private let snapshotLock = NSLock()
    private var snapshotState: EngineState = .idle
    private var snapshotTracks: [MediaTrack] = []
    private var snapshotAudioTrack: Int?
    private var snapshotDuration: Double?
    private var snapshotVideoSize: CGSize?
    private var snapshotVideoFormat: CMVideoFormatDescription?
    private var snapshotFrameRate: Double?
    /// Position set by a seek while the clock is stopped. The synchronizer applies a new paused
    /// time slightly late, so report this until the clock runs again.
    private var heldTime: Double?

    public init() {
        queue.setSpecific(key: queueKey, value: true)
        synchronizer.addRenderer(videoRenderer)
        synchronizer.addRenderer(audioRenderer)
        displayLayer.videoGravity = .resizeAspect
        audioRenderer.audioTimePitchAlgorithm = .spectral   // keep voices' pitch away from 1×
        allowDolbyVision = capabilities.dolbyVision
    }

    deinit {
        timer?.cancel()
        active?.stop()
        incoming?.stop()
    }

    // MARK: Public state

    public var state: EngineState { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotState }
    public var tracks: [MediaTrack] { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotTracks }
    /// The audio stream being played.
    public var audioTrack: Int? { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotAudioTrack }
    public var duration: Double? { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotDuration }
    public func copyDisplayedFrame() -> CVPixelBuffer? {
        if #available(macOS 14.4, iOS 17.4, tvOS 17.4, *) { return videoRenderer.displayedPixelBuffer() }
        return nil
    }

    public var videoSize: CGSize? { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotVideoSize }
    public var videoFormatDescription: CMVideoFormatDescription? {
        snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotVideoFormat
    }
    public var frameRate: Double? { snapshotLock.lock(); defer { snapshotLock.unlock() }; return snapshotFrameRate }
    public var currentTime: Double {
        snapshotLock.lock()
        let held = heldTime
        snapshotLock.unlock()
        if let held { return held }
        let t = synchronizer.currentTime().seconds
        return t.isFinite ? max(0, t) : 0
    }

    private func setHeldTime(_ time: Double?) {
        snapshotLock.lock(); heldTime = time; snapshotLock.unlock()
    }
    public var isPlaying: Bool { state == .playing || (state == .buffering && desiredRateSnapshot > 0) }
    private var desiredRateSnapshot: Float { queue.sync { desiredRate } }

    public var volume: Float {
        get { audioRenderer.volume }
        set { audioRenderer.volume = newValue }
    }

    public var isMuted: Bool {
        get { audioRenderer.isMuted }
        set { audioRenderer.isMuted = newValue }
    }

    /// Playback speed, 1 being normal; takes effect at once when playing.
    public var speed: Float {
        get { queue.sync { speedValue } }
        set {
            queue.async { [self] in
                speedValue = newValue
                guard desiredRate > 0 else { return }
                desiredRate = newValue
                if synchronizer.rate > 0 { synchronizer.setRate(newValue, time: SampleBuffers.time(currentTime)) }
            }
        }
    }

    private func setState(_ newState: EngineState) {
        snapshotLock.lock()
        let changed = snapshotState != newState
        snapshotState = newState
        snapshotLock.unlock()
        if changed {
            PlayerLog.engine("State \(newState)" + (onQueue ? " — \(summaryOnQueue())" : ""))
            emit(.state(newState))
        }
    }

    private func emit(_ event: EngineEvent) {
        guard let onEvent else { return }
        Task { @MainActor in onEvent(event) }
    }

    // MARK: Lifecycle

    public func prepare(source: MediaSource, startAt: Double) async throws {
        stop()
        setState(.loading)
        let pipeline = Pipeline(source: source, allowDolbyVision: allowDolbyVision)
        let generation = queue.sync { self.generation }
        do {
            try await open(pipeline, startAt: startAt)
            pipeline.start()
            try await waitForBuffer(pipeline, seconds: startThreshold, timeout: 30, generation: generation)
        } catch {
            pipeline.stop()
            if !(error is CancellationError) {
                setState(.failed((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            }
            throw error
        }
        try queue.sync {
            // stop() ran or the task was cancelled while this was loading (the player closed).
            guard self.generation == generation, !Task.isCancelled else {
                pipeline.stop()
                throw CancellationError()
            }
            active = pipeline
            // Segmented streams start at a segment boundary, and probing consumes packets, so the
            // media can begin after the requested position. Start the clock where it actually
            // begins, otherwise the player shows nothing until the clock catches up.
            resetTimeline(at: max(startAt, pipeline.firstQueuedTime ?? startAt))
            snapshotLock.lock()
            snapshotTracks = pipeline.tracks
            snapshotAudioTrack = pipeline.audioStream
            snapshotDuration = pipeline.duration
            snapshotVideoSize = pipeline.presentationSize
            snapshotVideoFormat = pipeline.videoFormat?.description
            snapshotFrameRate = pipeline.videoInfo?.frameRate
            snapshotLock.unlock()
            startFeeding()
            startTimer()
            if desiredRate == 0 { setState(.paused) }
        }
    }

    public func play() {
        queue.async { [self] in
            desiredRate = speedValue
            if case .ended = state {
                return
            }
            tick()
        }
    }

    public func pause() {
        queue.async { [self] in
            desiredRate = 0
            synchronizer.rate = 0
            if active != nil, state != .ended { setState(.paused) }
        }
    }

    public func stop() {
        queue.sync {
            generation += 1
            timer?.cancel()
            timer = nil
            stopFeeding()
            synchronizer.rate = 0
            desiredRate = 0
            videoRenderer.flush()
            audioRenderer.flush()
            active?.stop()
            incoming?.stop()
            active = nil
            incoming = nil
            spliceTime = nil
            pendingAudio.removeAll()
            externalSubtitles = nil
            selectedSubtitle = nil
        }
        setState(.idle)
    }

    // MARK: Seeking

    public func seek(to time: Double) async {
        await seek(to: time, audioTrack: nil)
    }

    /// Plays another audio track of the file, from where the clock is: the reader takes it while it
    /// repositions (a short pause, like a seek, and no second download).
    public func selectAudioTrack(_ id: Int) async {
        await seek(to: currentTime, audioTrack: id)
        let track = queue.sync { active?.audioStream }
        snapshotLock.withLock { snapshotAudioTrack = track }
    }

    private func seek(to time: Double, audioTrack: Int?) async {
        let target = max(0, time)
        guard let (pipeline, serial) = queue.sync(execute: { () -> (Pipeline, Int)? in
            guard let active else { return nil }
            seekSerial += 1
            stopFeeding()
            synchronizer.rate = 0
            videoRenderer.flush()
            audioRenderer.flush()
            cancelSplice()
            pendingAudio.removeAll()
            if case .decode(let decoder) = active.audioMode { decoder.flush() }
            setHeldTime(target)   // the position shows the target while the reader repositions
            setState(.buffering)
            return (active, seekSerial)
        }) else { return }
        await pipeline.seek(to: target, audioStream: audioTrack)
        // Two quick skips finish in either order: only the newest sets the clock.
        let latest = queue.sync { () -> Bool in
            guard active === pipeline, seekSerial == serial else { return false }
            resetTimeline(at: target)
            startFeeding()
            if desiredRate == 0 { setState(.paused) }
            return true
        }
        if latest { emit(.jumped(target)) }
    }

    private func resetTimeline(at time: Double) {
        preRollTarget = time
        lastVideoEnd = time
        lastAudioEnd = time
        synchronizer.setRate(0, time: SampleBuffers.time(time))
        setHeldTime(time)
    }

    // MARK: Quality switch (prepare-then-splice)

    public func switchSource(_ source: MediaSource, startAt: Double) async throws {
        let (allowDV, serial) = queue.sync { (allowDolbyVision, seekSerial) }
        let pipeline = Pipeline(source: source, allowDolbyVision: allowDV)
        do {
            try await open(pipeline, startAt: startAt)
            pipeline.start()
            try await waitForBuffer(pipeline, seconds: 3, timeout: 20)
        } catch {
            pipeline.stop()
            throw error
        }
        // A seek since the switch began moved the clock away from where the new stream starts:
        // give the switch up (the controller restarts at the new position, as after a timeout).
        let interrupted = EngineError("A seek interrupted the switch.", isTimeout: true)

        // Splice at the first keyframe of the new stream that comes after everything already
        // handed to the renderers; wait briefly for the new stream to reach one.
        let searchDeadline = Date().addingTimeInterval(10)
        var spliced = false
        while true {
            if Task.isCancelled { pipeline.stop(); throw CancellationError() }
            let outcome: Bool? = try queue.sync {
                guard seekSerial == serial else { pipeline.stop(); throw interrupted }
                guard let active else { pipeline.stop(); throw EngineError("Nothing is playing.") }
                let bound = max(currentTime + 0.3, hasVideo ? lastVideoEnd : 0, hasAudio ? lastAudioEnd : 0)
                let keyframe = pipeline.videoStream == nil
                    ? pipeline.audioQueue.first { $0.time >= bound }
                    : pipeline.videoQueue.first { $0.isKeyframe && $0.time >= bound }
                if let keyframe {
                    PlayerLog.engine(String(format: "Splice at %.3f s (clock %.3f s, new stream queued from %.3f s)",
                                            keyframe.time, currentTime, pipeline.firstQueuedTime ?? -1))
                    cancelSplice()
                    incoming = pipeline
                    spliceTime = keyframe.time
                    videoSwitched = active.videoStream == nil || pipeline.videoStream == nil
                    audioSwitched = active.audioStream == nil || pipeline.audioStream == nil || !audioUsable
                    checkSpliceDone()
                    return true
                }
                if Date() > searchDeadline || pipeline.reachedEnd || pipeline.hasFailed != nil {
                    // No usable keyframe ahead of the clock: hard swap at the current position.
                    cancelSplice()
                    hardSwap(to: pipeline, at: currentTime)
                    return false
                }
                return nil
            }
            if let outcome {
                spliced = outcome
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if spliced {
            let deadline = Date().addingTimeInterval(30)
            waiting: while true {
                let cancelled = Task.isCancelled
                let backedOut: Bool? = try queue.sync {
                    guard seekSerial == serial else { pipeline.stop(); throw interrupted }
                    // Done when the new stream is the playing one; anything else gave the switch up.
                    guard incoming === pipeline else {
                        if active === pipeline { return false }
                        pipeline.stop()
                        throw interrupted
                    }
                    if let failure = pipeline.hasFailed {
                        // The new stream broke before the splice: keep playing the old one.
                        cancelSplice()
                        throw EngineError(failure)
                    }
                    // The caller gave up (the controller's timeout): keep the old stream rather than
                    // finish the switch after it has said the switch failed.
                    if cancelled { cancelSplice(); return true }
                    if Date() > deadline {
                        // The old stream never reached the splice point (stalled); swap now.
                        hardSwap(to: pipeline, at: currentTime)
                        return false
                    }
                    return nil
                }
                switch backedOut {
                case true?: throw CancellationError()
                case false?: break waiting
                case nil: try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        }
        emit(.switched)
    }

    private func hardSwap(to pipeline: Pipeline, at time: Double) {
        stopFeeding()
        let rate = desiredRate
        synchronizer.rate = 0
        videoRenderer.flush()
        audioRenderer.flush()
        pendingAudio.removeAll()
        active?.stop()
        active = pipeline
        incoming = nil
        spliceTime = nil
        // The new stream starts at its first keyframe; frames before `time` decode hidden.
        resetTimeline(at: time)
        snapshotLock.lock(); snapshotTracks = pipeline.tracks; snapshotAudioTrack = pipeline.audioStream; snapshotLock.unlock()
        startFeeding()
        desiredRate = rate
    }

    private func cancelSplice() {
        incoming?.stop()
        incoming = nil
        spliceTime = nil
        videoSwitched = false
        audioSwitched = false
    }

    private func checkSpliceDone() {
        guard let incoming, videoSwitched, audioSwitched else { return }
        let old = active
        active = incoming
        self.incoming = nil
        spliceTime = nil
        snapshotLock.lock(); snapshotTracks = incoming.tracks; snapshotAudioTrack = incoming.audioStream; snapshotLock.unlock()
        DispatchQueue.global(qos: .utility).async { old?.stop() }
    }

    // MARK: Subtitles

    public func selectEmbeddedSubtitle(trackId: Int?) {
        queue.async { [self] in
            selectedSubtitle = trackId
            // The reader is ahead of the clock: re-read from here, or the events in between are missed.
            guard active?.decodePictures(of: trackId) == true, state != .loading else { return }
            let time = currentTime
            Task { await self.seek(to: time) }
        }
    }

    public func setExternalSubtitles(_ cues: [SubtitleCue]?) {
        let store = cues.map { SubtitleTrackStore(cues: $0) }
        queue.async { [self] in externalSubtitles = store }
    }

    public func subtitleText(at time: Double) -> String? {
        let (external, store) = queue.sync { () -> (SubtitleTrackStore?, SubtitleTrackStore?) in
            (externalSubtitles, selectedSubtitle.flatMap { active?.subtitleStores[$0] })
        }
        return (external ?? store)?.text(at: time)
    }

    public func subtitleBitmap(at time: Double) -> SubtitleBitmap? {
        let store = queue.sync { selectedSubtitle.flatMap { active?.pictureSubtitles(of: $0) } }
        return store?.bitmap(at: time)
    }

    // MARK: Feeding

    private func startFeeding() {
        if !requestingVideo {
            requestingVideo = true
            videoRenderer.requestMediaDataWhenReady(on: queue) { [weak self] in self?.feedVideo() }
        }
        if !requestingAudio && audioUsable {
            requestingAudio = true
            audioRenderer.requestMediaDataWhenReady(on: queue) { [weak self] in self?.feedAudio() }
        }
    }

    private func stopFeeding() {
        if requestingVideo { videoRenderer.stopRequestingMediaData(); requestingVideo = false }
        if requestingAudio { audioRenderer.stopRequestingMediaData(); requestingAudio = false }
    }

    private func feedVideo() {
        while videoRenderer.isReadyForMoreMediaData {
            guard let sample = nextVideoSample() else {
                // Nothing queued: stop the ready callbacks and poll again shortly.
                videoRenderer.stopRequestingMediaData()
                requestingVideo = false
                queue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    guard let self, self.active != nil, !self.requestingVideo else { return }
                    self.requestingVideo = true
                    self.videoRenderer.requestMediaDataWhenReady(on: self.queue) { [weak self] in self?.feedVideo() }
                }
                return
            }
            videoRenderer.enqueue(sample)
        }
    }

    private func feedAudio() {
        while audioRenderer.isReadyForMoreMediaData {
            guard let sample = nextAudioSample() else {
                audioRenderer.stopRequestingMediaData()
                requestingAudio = false
                queue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    guard let self, self.active != nil, self.audioUsable, !self.requestingAudio else { return }
                    self.requestingAudio = true
                    self.audioRenderer.requestMediaDataWhenReady(on: self.queue) { [weak self] in self?.feedAudio() }
                }
                return
            }
            audioRenderer.enqueue(sample)
        }
    }

    private func nextVideoSample() -> CMSampleBuffer? {
        guard let active else { return nil }
        if let incoming, let splice = spliceTime, !videoSwitched {
            if let head = active.videoQueue.peek() {
                if (head.dts ?? head.time) >= splice { switchVideo(to: incoming, at: splice) }
            } else if active.reachedEnd || active.hasFailed != nil {
                switchVideo(to: incoming, at: splice)
            }
        }
        let source = videoSwitched ? (incoming ?? active) : active
        if lastVideoEnd > currentTime + feedAhead { return nil }
        while let packet = source.videoQueue.pop() {
            guard let format = source.videoFormat, packet.hasTimestamp else { continue }
            let pts = packet.pts ?? packet.dts ?? 0
            var hidden = false
            if let target = preRollTarget, pts < target - 0.001 { hidden = true }
            if source === active, !videoSwitched, let splice = spliceTime, incoming != nil, pts >= splice { hidden = true }
            let payload = format.payload(packet.data)
            guard let sample = SampleBuffers.video(payload, format: format.description, pts: pts, dts: packet.dts,
                                                   duration: packet.duration, isKeyframe: packet.isKeyframe,
                                                   doNotDisplay: hidden) else { continue }
            lastVideoEnd = max(lastVideoEnd, pts + max(packet.duration, 0.001))
            return sample
        }
        return nil
    }

    private func switchVideo(to pipeline: Pipeline, at splice: Double) {
        pipeline.videoQueue.dropWhile { !($0.isKeyframe && $0.time >= splice - 0.001) }
        videoSwitched = true
        checkSpliceDone()
    }

    private func nextAudioSample() -> CMSampleBuffer? {
        if !pendingAudio.isEmpty { return pendingAudio.removeFirst() }
        guard let active else { return nil }
        if let incoming, let splice = spliceTime, !audioSwitched {
            if let head = active.audioQueue.peek() {
                if head.time >= splice { switchAudio(to: incoming, at: splice) }
            } else if active.reachedEnd || active.hasFailed != nil {
                switchAudio(to: incoming, at: splice)
            }
        }
        let source = audioSwitched ? (incoming ?? active) : active
        if lastAudioEnd > currentTime + feedAhead { return nil }
        let cutoff: Double? = (source === active && !audioSwitched && incoming != nil) ? spliceTime : nil
        let notBefore = max(preRollTarget ?? -1, (audioSwitched && source !== active) ? (spliceTime ?? -1) : -1)

        while let packet = source.audioQueue.pop() {
            guard packet.hasTimestamp else { continue }
            if let cutoff, packet.time >= cutoff { continue }
            switch source.audioMode {
            case .passthrough(let format)?:
                if packet.time + packet.duration <= notBefore { continue }
                guard let sample = SampleBuffers.compressedAudio(Data(buffer: packet.data), format: format,
                                                                 pts: packet.time) else {
                    noteAudioFailure("compressed sample")
                    continue
                }
                audioSampleFailures = 0
                lastAudioEnd = max(lastAudioEnd, packet.time + max(packet.duration, 0.032))
                return sample
            case .decode(let decoder)?:
                for frame in decoder.decode(packet) {
                    if let cutoff, frame.pts >= cutoff { continue }
                    if frame.pts + frame.duration <= notBefore { continue }
                    guard let format = pcmFormat(for: frame),
                          let sample = SampleBuffers.pcm(frame, format: format, notBefore: notBefore > 0 ? notBefore : nil)
                    else {
                        noteAudioFailure("PCM sample \(frame.channels)ch \(frame.sampleRate)Hz mask=\(frame.channelMask)")
                        continue
                    }
                    audioSampleFailures = 0
                    pendingAudio.append(sample)
                    lastAudioEnd = max(lastAudioEnd, frame.pts + frame.duration)
                }
                if !pendingAudio.isEmpty { return pendingAudio.removeFirst() }
            case nil:
                return nil
            }
        }
        return nil
    }

    /// Audio that can't be turned into sample buffers must not hold up video forever.
    private func noteAudioFailure(_ what: String) {
        audioSampleFailures += 1
        if audioSampleFailures == 1 || audioSampleFailures % 50 == 0 {
            PlayerLog.engine("Could not create audio \(what) (\(audioSampleFailures) in a row)")
        }
        if audioSampleFailures >= 30 && audioUsable {
            PlayerLog.engine("Disabling audio after repeated failures; continuing with video only")
            audioUsable = false
            audioSwitched = true
        }
    }

    private func switchAudio(to pipeline: Pipeline, at splice: Double) {
        pipeline.audioQueue.dropWhile { $0.time + $0.duration <= splice }
        if case .decode(let decoder) = pipeline.audioMode { decoder.flush() }
        audioSwitched = true
        checkSpliceDone()
    }

    private func pcmFormat(for frame: AudioFrame) -> CMAudioFormatDescription? {
        let key = "\(frame.sampleRate)-\(frame.channels)-\(frame.channelMask)"
        if let cached = pcmFormat, cached.key == key { return cached.format }
        guard let format = SampleBuffers.pcmFormat(sampleRate: frame.sampleRate, channels: frame.channels,
                                                   channelMask: frame.channelMask) else { return nil }
        pcmFormat = (key, format)
        return format
    }

    // MARK: Clock, buffering, end and errors

    private func startTimer() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private var hasAudio: Bool { audioUsable && active?.audioStream != nil }
    private var hasVideo: Bool { active?.videoStream != nil }

    /// Seconds of media handed to the renderers beyond the current time.
    private var bufferedAhead: Double {
        let now = currentTime
        var ends: [Double] = []
        if hasVideo { ends.append(lastVideoEnd) }
        if hasAudio { ends.append(lastAudioEnd) }
        return (ends.min() ?? now) - now
    }

    private var videoSource: Pipeline? { videoSwitched ? (incoming ?? active) : active }
    private var audioSource: Pipeline? { audioSwitched ? (incoming ?? active) : active }

    /// The demuxer has nothing queued for a stream the renderers are waiting on.
    private var sourceStarved: Bool {
        guard let active, !active.reachedEnd else { return false }
        if hasVideo, videoSource?.videoQueue.isEmpty ?? true { return true }
        if hasAudio, pendingAudio.isEmpty, audioSource?.audioQueue.isEmpty ?? true { return true }
        return false
    }

    /// Enough data is queued to (re)start the clock. Renderers stop accepting data while the
    /// clock is stopped, so this looks at the demuxer's queues, not at what was enqueued.
    private func readyToRun(_ active: Pipeline, drained: Bool) -> Bool {
        if drained || active.reachedEnd { return true }
        let rendererHasData = bufferedAhead > 0.05
        return rendererHasData && (active.bufferedDuration >= startThreshold || !sourceStarved && bufferedAhead >= startThreshold)
    }

    private func tick() {
        guard let active else { return }
        if videoSize == nil, let size = active.presentationSize {
            snapshotLock.lock()
            snapshotVideoSize = size
            snapshotLock.unlock()
            PlayerLog.engine(String(format: "Video size known after open: %.0f×%.0f", size.width, size.height))
        }
        // Known after the first keyframe for MPEG-TS, and a quality switch can change it.
        if let format = active.videoFormat?.description, format !== videoFormatDescription {
            snapshotLock.lock()
            snapshotVideoFormat = format
            snapshotFrameRate = active.videoInfo?.frameRate
            snapshotLock.unlock()
        }
        handleRendererFailures()
        if case .failed = state { return }

        let drained = active.isDrained && incoming == nil && pendingAudio.isEmpty
        if drained, let failure = active.hasFailed, bufferedAhead <= 0.05 {
            synchronizer.rate = 0
            setState(.failed(failure))
            return
        }
        let now = currentTime
        let mediaEnd = max(hasVideo ? lastVideoEnd : 0, hasAudio ? lastAudioEnd : 0)
        if drained && active.hasFailed == nil && now >= mediaEnd - 0.05 && active.reachedEnd {
            if state != .ended {
                synchronizer.rate = 0
                desiredRate = 0
                setState(.ended)
            }
            return
        }
        guard desiredRate > 0 else { bufferingSince = nil; return }
        if synchronizer.rate == 0 {
            let since = bufferingSince ?? Date()
            bufferingSince = since
            let waited = Date().timeIntervalSince(since)
            if waited > 2, Date().timeIntervalSince(lastStallLog) > 2 {
                lastStallLog = Date()
                PlayerLog.engine("Still buffering after \(Int(waited)) s — \(summaryOnQueue())")
            }
            // Watchdog: plenty is queued and the video renderer has frames, yet the start
            // condition never became true. Start anyway rather than spin forever.
            let forceStart = waited > 8 && active.bufferedDuration >= 3 && (!hasVideo || lastVideoEnd > currentTime + 0.05)
            if forceStart { PlayerLog.engine("Watchdog: starting playback despite buffering state — \(summaryOnQueue())") }
            if forceStart || readyToRun(active, drained: drained) {
                bufferingSince = nil
                synchronizer.setRate(desiredRate, time: SampleBuffers.time(currentTime))
                setHeldTime(nil)
                setState(.playing)
            } else {
                setState(.buffering)
            }
        } else if bufferedAhead < stallThreshold && sourceStarved {
            synchronizer.rate = 0
            setState(.buffering)
        } else if state != .playing {
            setState(.playing)
        }
    }

    /// One-line internal state, for diagnosing stalls in tests, logs and the player overlay.
    public var debugSummary: String { onQueue ? summaryOnQueue() : queue.sync { summaryOnQueue() } }

    private func summaryOnQueue() -> String {
        do {
            let a = active
            return String(format: "t=%.3f rate=%.1f state=%@ vEnd=%.3f aEnd=%.3f vQ=%.2fs aQ=%.2fs pend=%ld eof=%@ "
                          + "vReady=%@ aReady=%@ vStatus=%d aStatus=%d audioUsable=%@ splice=%@",
                          currentTime, synchronizer.rate, "\(state)", lastVideoEnd, lastAudioEnd,
                          a?.videoQueue.duration ?? -1, a?.audioQueue.duration ?? -1, pendingAudio.count,
                          "\(a?.reachedEnd ?? false)", "\(videoRenderer.isReadyForMoreMediaData)",
                          "\(audioRenderer.isReadyForMoreMediaData)", videoRenderer.status.rawValue,
                          audioRenderer.status.rawValue, "\(audioUsable)", spliceTime.map { "\($0)" } ?? "-")
        }
    }

    private func handleRendererFailures() {
        if audioUsable, audioRenderer.status == .failed {
            // No usable audio output (or an unsupported format): continue with video only.
            audioUsable = false
            if requestingAudio { audioRenderer.stopRequestingMediaData(); requestingAudio = false }
            audioSwitched = true
        }
        guard videoRenderer.status == .failed, let active else { return }
        if (videoRenderer.error as NSError?)?.code == -11847 {   // AVErrorOperationInterrupted (iOS, tvOS)
            // The app left the screen without Picture in Picture: the layer stopped drawing. Not a
            // broken video; the player pauses, and redraws by seeking when it is back.
            videoRenderer.flush()
            return
        }
        if allowDolbyVision, active.videoFormat?.usesDolbyVision == true, let info = active.videoInfo,
           let fallback = try? VideoFormat.make(info, firstKeyframe: nil, allowDolbyVision: false) {
            // The renderer rejected Dolby Vision: replay the HDR10 base layer from here.
            allowDolbyVision = false
            active.videoFormat = fallback
            let now = currentTime
            Task { await self.seek(to: now) }
            return
        }
        synchronizer.rate = 0
        setState(.failed(videoRenderer.error?.localizedDescription ?? "The video could not be decoded."))
    }

    /// Opens `pipeline` (blocking, off the main thread), stopping it after `openTimeout`.
    private func open(_ pipeline: Pipeline, startAt: Double) async throws {
        let limit = openTimeout
        let watchdog = Task.detached {
            try await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
            pipeline.stop()
        }
        defer { watchdog.cancel() }
        let started = Date()
        do {
            // The detached open ignores cancellation; stopping the pipeline interrupts FFmpeg.
            try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) { try pipeline.open(startAt: startAt) }.value
            } onCancel: {
                pipeline.stop()
            }
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            guard Date().timeIntervalSince(started) >= limit else { throw error }
            throw EngineError("The server took too long to start the video.", isTimeout: true)
        }
    }

    /// With `generation`, gives up as soon as `stop()` runs.
    private func waitForBuffer(_ pipeline: Pipeline, seconds: Double, timeout: TimeInterval,
                               generation: Int? = nil) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while pipeline.bufferedDuration < seconds && !pipeline.reachedEnd {
            if let generation, queue.sync(execute: { self.generation }) != generation { throw CancellationError() }
            if let failure = pipeline.hasFailed { throw EngineError(failure) }
            if Date() > deadline { throw EngineError("Timed out while loading the stream.", isTimeout: true) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if pipeline.reachedEnd && pipeline.bufferedDuration == 0, let failure = pipeline.hasFailed {
            throw EngineError(failure)
        }
    }
}
#endif
