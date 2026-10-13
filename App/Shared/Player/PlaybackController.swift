import CoreVideo
import Foundation
import JellyfinKit
import Observation
import PlayerCore

/// A subtitle choice in the player menu.
struct SubtitleOption: Identifiable, Equatable {
    /// Jellyfin stream index.
    let id: Int
    let label: String
    let isImage: Bool
    let isExternal: Bool
}

/// An audio track in the player menu.
struct AudioOption: Identifiable, Equatable {
    /// Jellyfin stream index (the container's stream index during Direct Play).
    let id: Int
    let label: String
}

/// What is currently being delivered.
struct PlaybackSession: Equatable {
    var itemId: String
    var mediaSourceId: String
    var playSessionId: String?
    var playMethod: PlayMethod
    var quality: QualityPreset
    /// Image subtitle track the server burns in, if any.
    var burnInSubtitle: Int?
    var audio: Int?
    var stoppedReported = false
}

enum PlayerStatus: Equatable {
    case idle, loading, buffering, playing, paused, ended
    case failed(String)
}

/// Owns the engine for one playback at a time: start/resume, controls, server reporting,
/// subtitles, and quality switching (prepare-then-splice via the engine).
@MainActor
@Observable
final class PlaybackController {
    // Published state for the UI.
    private(set) var item: BaseItem?
    private(set) var status: PlayerStatus = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    /// Presentation size of the video, so the window can take its shape.
    private(set) var videoSize: CGSize?
    private(set) var session: PlaybackSession?
    private(set) var qualityOptions: [QualityPreset] = QualityPreset.all
    private(set) var isSwitching = false
    private(set) var switchError: String?
    private(set) var subtitleOptions: [SubtitleOption] = []
    private(set) var selectedSubtitle: Int?
    private(set) var audioOptions: [AudioOption] = []
    private(set) var selectedAudio: Int?
    private(set) var subtitleText: String?
    /// A picture subtitle (PGS, DVD, DVB) the app draws itself during Direct Play.
    private(set) var subtitleBitmap: SubtitleBitmap?
    private(set) var engine: PlaybackEngine?
    /// What the spinner is waiting for ("Getting stream…", "Opening video…").
    private(set) var loadingDetail: String?
    /// Engine internals, shown under the spinner when it has been spinning for a while.
    private(set) var diagnostics: String?
    @ObservationIgnored private var spinnerSince: Date?

    var volume: Float = 1 { didSet { engine?.volume = volume } }
    var isMuted = false { didSet { engine?.isMuted = isMuted } }
    /// Black bars encoded into the frames, once two looks at the picture agree; subtitles sit above them.
    private(set) var pictureBars: PictureBars?
    /// How often the displayed frame is examined for bars while playing.
    @ObservationIgnored var barSampleInterval: TimeInterval = 2
    /// Looks in a row that leave the bars unchanged before the app stops looking for the rest of the item.
    @ObservationIgnored var barSettledLooks = 10
    @ObservationIgnored private var barSamples: (count: Int, unchanged: Int, bars: PictureBars, last: Date)?
    /// True once the bars have held long enough that the frames are no longer examined.
    @ObservationIgnored private(set) var barsSettled = false
    @ObservationIgnored private let letterbox = LetterboxDetector()
    @ObservationIgnored private var barsExplained = false

    /// "720p 4 Mbps · Transcode"
    var qualityLabel: String? {
        guard let session else { return nil }
        return "\(session.quality.label) · \(session.playMethod.label)"
    }

    var isPlaying: Bool { status == .playing || (status == .buffering && wantsToPlay) }

    // Dependencies.
    @ObservationIgnored private let engineFactory: () -> PlaybackEngine
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let capabilities: PlaybackCapabilities
    @ObservationIgnored private var service: PlaybackService?
    @ObservationIgnored var progressInterval: TimeInterval = 10
    @ObservationIgnored var switchTimeout: TimeInterval = 20
    @ObservationIgnored private var mediaSource: MediaSourceInfo?
    @ObservationIgnored private var lastKnownPosition: Double = 0
    @ObservationIgnored private var wantsToPlay = false
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var switchTask: Task<Void, Never>?
    @ObservationIgnored private var subtitleTask: Task<Void, Never>?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var uiTimer: Timer?
    @ObservationIgnored private var externalCues: [Int: [SubtitleCue]] = [:]
    @ObservationIgnored let nowPlaying = NowPlayingPublisher()
    /// Runs once the stream is open, before the clock starts: the Apple TV switches the display
    /// to the video's frame rate and HDR mode here and waits for the TV to resync.
    @ObservationIgnored var beforePlay: (@MainActor (PlaybackEngine) async -> Void)?

    init(engineFactory: @escaping () -> PlaybackEngine, preferences: AppPreferences, capabilities: PlaybackCapabilities) {
        self.engineFactory = engineFactory
        self.preferences = preferences
        self.capabilities = capabilities
    }

    // MARK: Start / stop

    /// Where playback begins: from the server's saved position, from zero, or at a given time.
    enum StartPosition: Equatable {
        case resume, beginning, at(Double)
    }

    func start(item: BaseItem, resume: Bool, service: PlaybackService) {
        stop()
        self.service = service
        self.item = item
        status = .loading
        startUITimer()
        startTask = Task { await begin(item: item, from: resume ? .resume : .beginning, quality: nil) }
    }

    /// Retry after a playback error, from the last known position.
    func retry() {
        guard let item, let service else { return }
        let quality = session?.quality
        let position = lastKnownPosition
        stopEngine(report: false)
        status = .loading
        self.service = service
        startUITimer()
        startTask = Task { await begin(item: item, from: .at(position), quality: quality) }
    }

    /// What a restart keeps from the stream it replaces (see `restart`).
    private struct Carryover {
        var burnIn: Int?
        var subtitle: Int?
        var audio: Int?
        var paused: Bool
    }

    private func begin(item: BaseItem, from position: StartPosition, quality requested: QualityPreset?,
                       carry: Carryover? = nil) async {
        guard let service else { return }
        do {
            // Always ask the server for the item: a card can be minutes old, and its saved
            // position is what Resume means.
            let full = try await service.item(id: item.id)
            try Task.checkCancellation()
            let start: Double
            switch position {
            case .resume: start = full.resumePositionSeconds ?? 0
            case .beginning: start = 0
            case .at(let time): start = time
            }
            let sourceHeight = full.mediaSources?.first?.videoStream?.height
            qualityOptions = QualitySelection.visibleOptions(sourceHeight: sourceHeight)
            let quality = requested ?? QualitySelection.startingQuality(
                preferredId: preferences.preferredQualityId(server: service.serverURL), sourceHeight: sourceHeight)

            loadingDetail = "Getting stream from the server…"
            PlayerLog.engine("Capabilities: av1=\(capabilities.av1) hevc10=\(capabilities.hevc10Bit) "
                             + "dolbyVision=\(capabilities.dolbyVision)")
            PlayerLog.engine("Controller: requesting stream for \(item.id) at \(quality.label), start \(start)")
            let stream = try await service.resolveStream(itemId: item.id, quality: quality, capabilities: capabilities,
                                                         startSeconds: start,
                                                         mediaSourceId: full.mediaSources?.first?.id,
                                                         subtitleStreamIndex: carry.map { $0.burnIn ?? -1 },
                                                         audioStreamIndex: carry?.audio)
            try Task.checkCancellation()
            mediaSource = stream.mediaSource
            subtitleOptions = Self.subtitleOptions(stream.mediaSource)
            audioOptions = Self.audioOptions(stream.mediaSource)
            // The server's pick for the user's language, which the file's own default may not be.
            let audio = carry?.audio ?? stream.mediaSource.defaultAudioStreamIndex ?? audioOptions.first?.id
            selectedAudio = audio

            PlayerLog.engine("Controller: \(stream.playMethod.label) \(stream.url.path)?\(Self.redactedQuery(stream.url))")
            loadingDetail = "Opening video (\(stream.playMethod.label))…"
            let engine = engineFactory()
            engine.volume = volume
            engine.isMuted = isMuted
            engine.onEvent = { [weak self] event in self?.handle(event) }
            self.engine = engine
            try await engine.prepare(source: MediaSource(url: stream.url, headers: service.streamHeaders,
                                                         timelineOffset: stream.timelineOffset,
                                                         audioTrack: stream.playMethod == .directPlay ? audio : nil),
                                     startAt: start)
            try Task.checkCancellation()
            loadingDetail = nil
            duration = engine.duration ?? Ticks.seconds(full.runTimeTicks ?? 0)
            videoSize = engine.videoSize.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
            session = PlaybackSession(itemId: item.id, mediaSourceId: stream.mediaSourceId,
                                      playSessionId: stream.playSessionId, playMethod: stream.playMethod,
                                      quality: quality, burnInSubtitle: stream.burnedInSubtitle, audio: audio)
            lastKnownPosition = start
            currentTime = start
            await beforePlay?(engine)
            try Task.checkCancellation()
            if carry?.paused != true {
                wantsToPlay = true
                engine.play()
            }
            send(.start)
            startTimers()
            nowPlaying.begin(controller: self, item: full, artworkURL: service.primaryImageURL(for: full))

            PlayerLog.engine("Controller: server's default subtitle \(stream.mediaSource.defaultSubtitleStreamIndex.map(String.init) ?? "none"), burnt in \(stream.burnedInSubtitle.map(String.init) ?? "none")")
            if let carry {
                if let subtitle = carry.subtitle { selectSubtitle(subtitle) }
            } else if let track = SubtitleSelection.defaultTrack(for: stream.mediaSource) ?? stream.burnedInSubtitle.flatMap({ index in
                stream.mediaSource.subtitleStreams.first { $0.index == index }
            }) {
                // The server's default for the user's preferences. A picture track is already burnt
                // into the stream (`burnedInSubtitle`), so selecting it starts no second stream.
                selectSubtitle(track.index)
            }
        } catch is CancellationError {
        } catch {
            PlayerLog.engine("Controller: playback failed to start: \(error)")
            loadingDetail = nil
            status = .failed(describe(error))
            engine?.stop()
        }
    }

    /// Stops playback (window closed or a new item started): reports the stop and ends any
    /// server transcode for the session.
    func stop() {
        startTask?.cancel()
        switchTask?.cancel()
        subtitleTask?.cancel()
        stopEngine(report: true)
        item = nil
        status = .idle
        nowPlaying.end()
    }

    private func stopEngine(report shouldReport: Bool) {
        if shouldReport { reportStopOnce() }
        progressTimer?.invalidate()
        uiTimer?.invalidate()
        progressTimer = nil
        uiTimer = nil
        engine?.onEvent = nil
        engine?.stop()
        engine = nil
        session = nil
        wantsToPlay = false
        isSwitching = false
        switchError = nil
        subtitleText = nil
        subtitleBitmap = nil
        selectedSubtitle = nil
        selectedAudio = nil
        externalCues = [:]
        loadingDetail = nil
        diagnostics = nil
        spinnerSince = nil
        videoSize = nil
        pictureBars = nil
        barSamples = nil
        barsSettled = false
        barsExplained = false
    }

    /// Stops and waits for the server to hear about it. Detached tasks do not survive process
    /// exit, so quitting mid-playback would otherwise leave the server transcoding.
    func stopForTermination(timeout: TimeInterval = 3) {
        guard let service, var session, !session.stoppedReported else {
            stop()
            return
        }
        let stopped = report(for: session, position: position)
        let encoding = session.playMethod == .directPlay ? nil : session.playSessionId
        session.stoppedReported = true
        self.session = session
        let done = DispatchSemaphore(value: 0)
        PlayerLog.engine("Quitting: telling the server to stop\(encoding != nil ? " and end transcoding" : "")")
        Task.detached {
            try? await service.reportStopped(stopped)
            if let encoding { try? await service.endEncoding(playSessionId: encoding) }
            done.signal()
        }
        let timedOut = done.wait(timeout: .now() + timeout) == .timedOut
        if timedOut { PlayerLog.engine("Quitting: server cleanup timed out") }
        stop()
    }

    private func reportStopOnce() {
        guard var session, !session.stoppedReported else { return }
        session.stoppedReported = true
        self.session = session
        let stop = report(for: session, position: position)
        let encoding = session.playMethod == .directPlay ? nil : session.playSessionId
        guard let service else { return }
        Task.detached {
            try? await service.reportStopped(stop)
            if let encoding { try? await service.endEncoding(playSessionId: encoding) }
        }
    }

    // MARK: Controls

    var position: Double { engine?.currentTime ?? currentTime }

    func togglePlayPause() { isPlaying ? pause() : play() }

    func play() {
        guard let engine else { return }
        if status == .ended { Task { await seek(to: 0) } }
        wantsToPlay = true
        engine.play()
        send(.progress, eventName: "Unpause")
    }

    func pause() {
        guard let engine else { return }
        wantsToPlay = false
        engine.pause()
        send(.progress, eventName: "Pause")
    }

    func seek(to time: Double) async {
        guard let engine else { return }
        let target = min(max(0, time), duration > 0 ? duration : time)
        currentTime = target
        await engine.seek(to: target)
        if wantsToPlay { engine.play() }
        lastKnownPosition = target
        send(.progress, eventName: "TimeUpdate")
    }

    func skip(by seconds: Double) {
        Task { await seek(to: position + seconds) }
    }

    /// The Mac's digit keys: 0 is the start, 9 is nine tenths through.
    func jump(toTenth tenth: Int) {
        guard duration > 0 else { return }
        Task { await seek(to: duration * Double(min(max(tenth, 0), 9)) / 10) }
    }

    // MARK: Quality

    func selectQuality(_ quality: QualityPreset) {
        guard let session, quality != session.quality else { return }
        performSwitch(quality: quality, burnIn: selectedPictureSubtitle, audio: selectedAudio, persistQuality: true)
    }

    /// Another audio track: in place during Direct Play (a short pause, like a seek), otherwise a
    /// new stream from the server, switched seamlessly like a quality change.
    func selectAudio(_ index: Int) {
        guard let session, index != session.audio else { return }
        selectedAudio = index   // checked in the menu at once; a failed switch puts it back
        if session.playMethod == .directPlay, let engine {
            // Every track is in the file being read: switch in place rather than download it twice.
            self.session?.audio = index
            Task { await engine.selectAudioTrack(index) }
            return
        }
        performSwitch(quality: session.quality, burnIn: selectedPictureSubtitle, audio: index, persistQuality: false)
    }

    static func audioOptions(_ source: MediaSourceInfo) -> [AudioOption] {
        source.audioStreams.map { AudioOption(id: $0.index, label: $0.displayTitle ?? $0.title ?? $0.language ?? "Track \($0.index)") }
    }

    /// The selected picture subtitle, asked for with every new stream: the server embeds it when it
    /// can send the file as is (the app draws it), and burns it in when it transcodes.
    private var selectedPictureSubtitle: Int? {
        subtitleOptions.first { $0.id == selectedSubtitle && $0.isImage }?.id
    }

    private func performSwitch(quality: QualityPreset, burnIn: Int?, audio: Int?, persistQuality: Bool,
                               then completion: (@MainActor () -> Void)? = nil) {
        guard let session, let service, let engine, let item else { return }
        if quality == session.quality && burnIn == session.burnInSubtitle && audio == session.audio { return }
        switchTask?.cancel()
        isSwitching = true
        switchError = nil
        let timeout = switchTimeout
        switchTask = Task { [weak self] in
            guard let self else { return }
            // A stream asked for but never adopted: the server is transcoding it for nobody.
            var unused: String?
            do {
                let start = self.position + 2
                let stream = try await service.resolveStream(itemId: item.id, quality: quality,
                                                             capabilities: self.capabilities, startSeconds: start,
                                                             mediaSourceId: session.mediaSourceId,
                                                             subtitleStreamIndex: burnIn ?? -1,
                                                             audioStreamIndex: audio)
                if stream.playMethod != .directPlay { unused = stream.playSessionId }
                try Task.checkCancellation()
                let source = MediaSource(url: stream.url, headers: service.streamHeaders,
                                         timelineOffset: stream.timelineOffset,
                                         audioTrack: stream.playMethod == .directPlay ? audio : nil)
                try await withTimeout(timeout) { try await engine.switchSource(source, startAt: start) }
                try Task.checkCancellation()
                guard self.engine === engine, var old = self.session else { return }
                unused = nil

                // Retire the old session on the server, start the new one.
                let stopOld = self.report(for: old, position: self.position)
                let oldEncoding = old.playMethod == .directPlay ? nil : old.playSessionId
                old.stoppedReported = true
                let newSession = PlaybackSession(itemId: item.id, mediaSourceId: stream.mediaSourceId,
                                                 playSessionId: stream.playSessionId, playMethod: stream.playMethod,
                                                 quality: quality, burnInSubtitle: stream.burnedInSubtitle, audio: audio)
                self.session = newSession
                self.mediaSource = stream.mediaSource
                let startNew = self.report(for: newSession, position: self.position)
                Task.detached {
                    try? await service.reportStopped(stopOld)
                    if let oldEncoding { try? await service.endEncoding(playSessionId: oldEncoding) }
                    try? await service.reportStart(startNew)
                }
                if persistQuality { self.preferences.setPreferredQualityId(quality.id, server: service.serverURL) }
                self.isSwitching = false
                self.applySubtitleSource()
                completion?()
            } catch is CancellationError {
                // A newer switch replaced this one; it owns the spinner.
            } catch where Self.isTimeout(error) && self.engine === engine {
                // The new stream couldn't catch up with the playing one (a busy server). Switch the
                // way a seek works instead: a short wait, and the server only encodes one stream.
                PlayerLog.engine("Controller: \(quality.label) didn't catch up in time; restarting at it from here")
                self.restart(quality: quality, burnIn: burnIn, audio: audio, persistQuality: persistQuality)
            } catch {
                self.isSwitching = false
                self.selectedAudio = session.audio
                self.switchError = audio != session.audio ? "Couldn't switch the audio track."
                    : "Couldn't switch quality. Playing at \(session.quality.label)."
            }
            if let unused { Task.detached { try? await service.endEncoding(playSessionId: unused) } }
        }
    }

    func dismissSwitchError() { switchError = nil }

    static func isTimeout(_ error: Error) -> Bool {
        error is TimeoutError || (error as? EngineError)?.isTimeout == true
    }

    /// Stops the playing stream and starts `quality` from the same position, keeping the
    /// subtitle and paused state: the fallback when a seamless switch can't be made.
    private func restart(quality: QualityPreset, burnIn: Int?, audio: Int?, persistQuality: Bool) {
        guard let item, let service else { return }
        let carry = Carryover(burnIn: burnIn, subtitle: selectedSubtitle, audio: audio, paused: !wantsToPlay)
        let position = self.position
        if persistQuality { preferences.setPreferredQualityId(quality.id, server: service.serverURL) }
        stopEngine(report: true)
        status = .loading
        startUITimer()
        startTask = Task { await begin(item: item, from: .at(position), quality: quality, carry: carry) }
    }

    // MARK: Subtitles

    static func subtitleOptions(_ source: MediaSourceInfo) -> [SubtitleOption] {
        source.subtitleStreams.map { stream in
            var parts = [stream.displayTitle ?? stream.title ?? stream.language ?? "Track \(stream.index)"]
            if stream.isForced == true && !(parts[0].localizedCaseInsensitiveContains("forced")) { parts.append("Forced") }
            if stream.isExternal == true { parts.append("External") }
            return SubtitleOption(id: stream.index, label: parts.joined(separator: " · "),
                                  isImage: stream.isImageSubtitle, isExternal: stream.isExternal == true)
        }
    }

    /// nil turns subtitles off.
    /// The Mac's S key: each text subtitle in turn, then Off. Image tracks are left out, since each
    /// would make the server start a new transcode to burn it in.
    func cycleSubtitle() {
        let text = subtitleOptions.filter { !$0.isImage }.map(\.id)
        guard !text.isEmpty else { return }
        if let current = selectedSubtitle, let index = text.firstIndex(of: current) {
            selectSubtitle(index + 1 < text.count ? text[index + 1] : nil)
        } else {
            selectSubtitle(text[0])
        }
    }

    func selectSubtitle(_ index: Int?) {
        guard let session else { return }
        let option = subtitleOptions.first { $0.id == index }
        if let option, option.isImage {
            selectedSubtitle = index
            if session.playMethod == .directPlay && !option.isExternal {
                // The file plays as it is: the app draws the pictures itself.
                applySubtitleSource()
            } else {
                // Otherwise the server burns them in (a stream switch at the same quality).
                engine?.selectEmbeddedSubtitle(trackId: nil)
                engine?.setExternalSubtitles(nil)
                performSwitch(quality: session.quality, burnIn: index, audio: selectedAudio, persistQuality: false)
            }
            return
        }
        selectedSubtitle = index
        if session.burnInSubtitle != nil {
            // Leaving burn-in: back to the delivery the quality allows, then show text cues.
            performSwitch(quality: session.quality, burnIn: nil, audio: selectedAudio, persistQuality: false)
        }
        applySubtitleSource()
    }

    /// Text cues come from the running demuxer during Direct Play (instant), otherwise from the
    /// server as SRT (transcoded HLS streams don't carry text subtitles).
    private func applySubtitleSource() {
        guard let engine, let session else { return }
        subtitleTask?.cancel()
        guard let index = selectedSubtitle, let option = subtitleOptions.first(where: { $0.id == index }) else {
            engine.selectEmbeddedSubtitle(trackId: nil)
            engine.setExternalSubtitles(nil)
            return
        }
        if option.isImage {
            // Drawn by the app from the file during Direct Play; burnt into the picture otherwise.
            engine.setExternalSubtitles(nil)
            let drawn = session.playMethod == .directPlay && !option.isExternal && session.burnInSubtitle != index
            PlayerLog.engine("Controller: subtitle \(index) (\(option.label)) \(drawn ? "drawn by the app" : "burnt in by the server")")
            engine.selectEmbeddedSubtitle(trackId: drawn ? index : nil)
            return
        }
        if session.playMethod == .directPlay && !option.isExternal {
            engine.setExternalSubtitles(nil)
            engine.selectEmbeddedSubtitle(trackId: index)
            return
        }
        engine.selectEmbeddedSubtitle(trackId: nil)
        if let cues = externalCues[index] {
            engine.setExternalSubtitles(cues)
            return
        }
        guard let service else { return }
        let itemId = session.itemId, mediaSourceId = session.mediaSourceId
        subtitleTask = Task { [weak self] in
            do {
                let data = try await service.subtitleData(itemId: itemId, mediaSourceId: mediaSourceId, streamIndex: index)
                let cues = try ExternalSubtitles.parse(data)
                guard let self, !Task.isCancelled, self.selectedSubtitle == index else { return }
                self.externalCues[index] = cues
                self.engine?.setExternalSubtitles(cues)
            } catch {}
        }
    }

    // MARK: Engine events and timers

    private func handle(_ event: EngineEvent) {
        switch event {
        case .state(let state):
            switch state {
            case .idle: break
            case .loading: status = .loading
            case .buffering: status = .buffering
            case .playing: status = .playing
            case .paused: status = .paused
            case .ended:
                status = .ended
                wantsToPlay = false
                lastKnownPosition = duration
                currentTime = duration
                reportStopOnce()
            case .failed(let message):
                status = .failed(message)
                lastKnownPosition = max(lastKnownPosition, engine?.currentTime ?? 0)
                reportStopOnce()
            }
            nowPlaying.update()
        case .jumped(let time):
            currentTime = time
            nowPlaying.update()
        case .switched:
            break
        }
    }

    private func startTimers() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: progressInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session != nil, self.status != .ended else { return }
                if case .failed = self.status { return }
                self.send(.progress, eventName: "TimeUpdate")
            }
        }
        startUITimer()
    }

    /// Drives the time display, subtitles and the spinner diagnostics; runs from the moment
    /// playback is requested so the overlay can explain a slow start.
    private func startUITimer() {
        guard uiTimer == nil else { return }
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        let spinning = status == .loading || status == .buffering
        if spinning {
            let since = spinnerSince ?? Date()
            spinnerSince = since
            if Date().timeIntervalSince(since) > 5 {
                diagnostics = engine?.debugSummary ?? loadingDetail
            }
        } else {
            spinnerSince = nil
            diagnostics = nil
        }
        guard let engine else { return }
        if status == .playing || status == .buffering || status == .paused {
            currentTime = engine.currentTime
            if currentTime > 0 { lastKnownPosition = currentTime }
        }
        if let d = engine.duration, d > 0 { duration = d }
        // Transcoded streams learn their picture size from the first keyframe, after open.
        if videoSize == nil, let size = engine.videoSize, size.width > 0, size.height > 0 { videoSize = size }
        subtitleText = engine.subtitleText(at: currentTime)
        let bitmap = engine.subtitleBitmap(at: currentTime)
        if bitmap?.start != subtitleBitmap?.start || bitmap?.end != subtitleBitmap?.end { subtitleBitmap = bitmap }
        // Burned-in subtitles are the server's pixels; there is nothing of ours to place.
        if status == .playing, session?.burnInSubtitle == nil { sampleBars(engine) }
    }

    /// Looks at the displayed frame now and then for letterbox bars baked into the picture. Each
    /// look can only narrow the bars (a dark scene shows bigger ones, never smaller), the result
    /// is used once two looks agree so a single fade cannot move the subtitles, and once the bars
    /// have held for `barSettledLooks` looks in a row the frames are left alone.
    private func sampleBars(_ engine: PlaybackEngine) {
        let now = Date()
        guard !barsSettled else { return }
        if let last = barSamples?.last, now.timeIntervalSince(last) < barSampleInterval { return }
        guard let frame = engine.copyDisplayedFrame() else {
            if !barsExplained { PlayerLog.engine("Picture bars: the renderer has no displayed frame to look at") }
            barsExplained = true
            return
        }
        guard let seen = letterbox.bars(in: frame) else {
            if !barsExplained {
                let format = fourCC(CVPixelBufferGetPixelFormatType(frame))
                PlayerLog.engine("Picture bars: \(LetterboxDetector.canRead(frame) ? "nothing found in" : "could not copy") a "
                                 + "\(CVPixelBufferGetWidth(frame))×\(CVPixelBufferGetHeight(frame)) \(format) frame")
            }
            barsExplained = true
            return
        }
        let bars = barSamples.map { $0.bars.narrowed(by: seen) } ?? seen
        let count = (barSamples?.count ?? 0) + 1
        let unchanged = bars == barSamples?.bars ? (barSamples?.unchanged ?? 0) + 1 : 0
        barSamples = (count, unchanged, bars, now)
        if unchanged >= barSettledLooks {
            barsSettled = true
            PlayerLog.engine(String(format: "Picture bars settled at %.1f%% top, %.1f%% bottom after %d looks", bars.top * 100, bars.bottom * 100, count))
        }
        guard count >= 2, pictureBars != bars else { return }
        pictureBars = bars
        PlayerLog.engine(String(format: "Picture bars: %.1f%% top, %.1f%% bottom", bars.top * 100, bars.bottom * 100))
    }

    private func fourCC(_ type: OSType) -> String {
        String((0..<4).map { Character(UnicodeScalar(UInt8(truncatingIfNeeded: type >> (8 * (3 - $0))))) })
    }

    /// The query string with the access token blanked, for the log.
    static func redactedQuery(_ url: URL) -> String {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { item in
            let secret = ["apikey", "api_key"].contains(item.name.lowercased())
            return "\(item.name)=\(secret ? "…" : item.value ?? "")"
        }.joined(separator: "&")
    }

    // MARK: Reporting

    private func report(eventName: String?) -> PlaybackReport {
        guard let session else {
            return PlaybackReport(itemId: item?.id ?? "", mediaSourceId: "", playSessionId: nil, positionSeconds: 0,
                                  isPaused: true, playMethod: .directPlay)
        }
        var report = self.report(for: session, position: position)
        report.eventName = eventName
        return report
    }

    private func report(for session: PlaybackSession, position: Double) -> PlaybackReport {
        PlaybackReport(itemId: session.itemId, mediaSourceId: session.mediaSourceId, playSessionId: session.playSessionId,
                       positionSeconds: position, isPaused: !wantsToPlay, playMethod: session.playMethod,
                       subtitleStreamIndex: selectedSubtitle)
    }

    enum ReportKind { case start, progress }

    /// Fire-and-forget server reporting: failures never interrupt playback.
    private func send(_ kind: ReportKind, eventName: String? = nil) {
        guard let service, session != nil else { return }
        let payload = report(eventName: eventName)
        Task.detached {
            switch kind {
            case .start: try? await service.reportStart(payload)
            case .progress: try? await service.reportProgress(payload)
            }
        }
    }
}

struct TimeoutError: Error {}

/// Runs `operation`, throwing `TimeoutError` if it takes longer than `seconds`.
func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
