import AppKit
import AVFoundation
import JellyfinKit
import PlayerCore
import SwiftUI

struct PlayerWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var controlsVisible = true
    @State private var lastActivity = Date()
    @State private var pip = PictureInPictureController()
    @State private var window: NSWindow?
    @FocusState private var focused: Bool
    /// The position being scrubbed to (slider or trackpad), shown in place of the clock.
    @State private var scrubbing: Double?
    /// A trackpad stroke in progress, and the seek waiting for the fingers to stay off the pad.
    @State private var trackpadScrub: TrackpadScrub?
    @State private var trackpadSeek: Task<Void, Never>?
    @State private var scrollMonitor: Any?
    /// While the pointer is over the control bars they stay up.
    @State private var overControls = false
    /// A click that only brings the window forward must not also pause.
    @State private var becameKeyAt = Date.distantPast

    private var player: PlaybackController { model.player }

    var body: some View {
        ZStack {
            Color.black
            if let engine = player.engine {
                VideoLayerView(layer: engine.displayLayer, aspectRatio: player.videoSize)
                    .onAppear { pip.attach(layer: engine.displayLayer, playback: player) }
                    // Double-click: full screen. Single click: pause or play, as in Infuse and IINA
                    // (it waits out the double-click interval to tell them apart).
                    .gesture(TapGesture(count: 2).onEnded { toggleFullScreen() }
                        .exclusively(before: TapGesture().onEnded { clickToPause() }))
                    .id(ObjectIdentifier(engine)) // a new engine (retry, next title) gets PiP too
            }
            SubtitleOverlay(text: player.subtitleText, bitmap: player.subtitleBitmap, videoSize: player.videoSize,
                            bars: player.pictureBars)
            if player.status == .loading || player.status == .buffering {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large).tint(.white)
                    if let detail = player.loadingDetail {
                        Text(detail).font(.callout).foregroundStyle(.white.opacity(0.8))
                    }
                    #if DEBUG
                    if let diagnostics = player.diagnostics {
                        Text(diagnostics)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .frame(maxWidth: 520)
                    }
                    #endif
                }
            }
            if case .failed(let message) = player.status {
                ErrorBanner(message: message) { player.retry() }
            }
            if player.status == .idle && player.item == nil {
                Text("Nothing is playing").foregroundStyle(.secondary)
            }
            if player.status == .ended {
                // The last frame stays up; say so and offer the two things worth doing.
                VStack(spacing: 14) {
                    Label("Watched", systemImage: "checkmark.circle.fill").font(.title2.weight(.semibold))
                    HStack(spacing: 12) {
                        Button("Play Again") { player.togglePlayPause() }.keyboardShortcut(.defaultAction)
                        Button("Close") { window?.close() }
                    }
                }
                .foregroundStyle(.white)
                .padding(24)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            }
            PlayerControls(player: player, pip: pip, scrubbing: $scrubbing, overControls: $overControls,
                           toggleFullScreen: toggleFullScreen)
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        }
        .ignoresSafeArea()
        .background(WindowReader(window: $window))
        .onContinuousHover { _ in noteActivity() }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(keys: [.space, .leftArrow, .rightArrow, .upArrow, .downArrow, .escape, "f", "m", "s",
                           "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]) { press in
            handle(press.key)
            return .handled
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in hideIfIdle() }
        .onChange(of: player.isPlaying) { _, _ in
            pip.invalidate()
            player.nowPlaying.update()
            noteActivity()
        }
        .onDisappear {
            player.stop()
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
        }
        .onAppear { if scrollMonitor == nil { scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: trackpadScrub) } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if (note.object as? NSWindow) === window { becameKeyAt = Date() }
        }
        // The title bar is hidden, but the Window menu and Mission Control still show the title.
        .onChange(of: player.item?.displayName, initial: true) { _, name in window?.title = name ?? "Player" }
        .onChange(of: window) { _, window in window?.title = player.item?.displayName ?? "Player" }
    }

    private func clickToPause() {
        guard Date().timeIntervalSince(becameKeyAt) > 0.3, player.status != .ended else { return }
        player.togglePlayPause()
        noteActivity()
    }

    /// A sideways two-finger swipe on a trackpad scrubs; strokes chain, each going on from where the
    /// last one aimed, and the player seeks once the fingers have been off for a moment. Vertical
    /// scrolls and mouse wheels pass through.
    private func trackpadScrub(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, event.hasPreciseScrollingDeltas, player.duration > 0 else { return event }
        if event.phase == .began { trackpadScrub = nil }
        if trackpadScrub == nil {
            // The first movement decides: sideways scrubs, anything else is left alone.
            guard event.phase == .began || event.phase == .changed,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
            trackpadSeek?.cancel()
            trackpadScrub = TrackpadScrub(start: scrubbing ?? player.currentTime)
        }
        guard var scrub = trackpadScrub else { return event }
        // Fingers to the right move forward, whichever way the system scrolls content.
        scrub.travel += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        trackpadScrub = scrub
        let target = scrub.target(duration: player.duration)
        scrubbing = target
        noteActivity()
        if event.phase == .ended || event.phase == .cancelled {
            trackpadScrub = nil
            trackpadSeek = Task {
                try? await Task.sleep(for: .seconds(TrackpadScrub.settle))
                guard !Task.isCancelled else { return }
                await player.seek(to: target)
                if scrubbing == target { scrubbing = nil }
            }
        }
        return nil
    }

    private func noteActivity() {
        lastActivity = Date()
        if !controlsVisible { controlsVisible = true }
    }

    /// Controls hide after 3 s without mouse movement while playing; they stay while paused.
    private func hideIfIdle() {
        guard player.isPlaying, controlsVisible, !overControls, scrubbing == nil,
              Date().timeIntervalSince(lastActivity) >= 3 else { return }
        controlsVisible = false
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private func handle(_ key: KeyEquivalent) {
        noteActivity()
        switch key {
        case .space: player.togglePlayPause()
        case .leftArrow: player.skip(by: -10)
        case .rightArrow: player.skip(by: 30)
        case .upArrow: player.volume = min(1, player.volume + 0.1)
        case .downArrow: player.volume = max(0, player.volume - 0.1)
        case "f": toggleFullScreen()
        case "m": player.isMuted.toggle()
        case "s": player.cycleSubtitle()
        case _ where key.character.wholeNumberValue != nil: player.jump(toTenth: key.character.wholeNumberValue!)
        case .escape:
            if let window = window ?? NSApp.keyWindow, window.styleMask.contains(.fullScreen) { toggleFullScreen() }
        default: break
        }
    }

    /// Uses the window this view lives in. `NSApp.keyWindow` is not reliable from a button action
    /// (it can be nil or another window), which left the full-screen button doing nothing.
    private func toggleFullScreen() {
        guard let window = window ?? NSApp.keyWindow else {
            PlayerLog.engine("Full screen: no window")
            return
        }
        WindowReader.allowFullScreen(window)
        PlayerLog.engine("Full screen: \(window.styleMask.contains(.fullScreen) ? "leaving" : "entering")"
                         + " (behavior \(window.collectionBehavior.rawValue))")
        window.toggleFullScreen(nil)
    }
}

/// One trackpad stroke. Sized in points rather than window widths, so it feels the same in a small
/// window and in full screen: a comfortable stroke (about 1600 points of scrolling) moves two swipe
/// spans, 20 minutes of a long film.
struct TrackpadScrub {
    static let pointsPerSpan = 800.0
    /// How long the fingers stay off before the seek, so the next stroke can carry on instead.
    static let settle = 0.5
    let start: Double
    var travel = 0.0

    func target(duration: Double) -> Double {
        SwipeScrub.target(start: start, fraction: travel / Self.pointsPerSpan, duration: duration)
    }
}

/// Reports the NSWindow a SwiftUI view ends up in, and makes sure it can go full screen.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    /// A SwiftUI `Window` scene marks its NSWindow `fullScreenNone`, and AppKit then ignores
    /// `toggleFullScreen` (a conflicting `fullScreenPrimary` added alongside changes nothing).
    static func allowFullScreen(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        guard behavior.contains(.fullScreenNone) || !behavior.contains(.fullScreenPrimary) else { return }
        behavior.remove(.fullScreenNone)
        behavior.remove(.fullScreenAuxiliary)
        behavior.insert(.fullScreenPrimary)
        window.collectionBehavior = behavior
    }

    func makeNSView(context: Context) -> Reader {
        let reader = Reader()
        reader.onWindow = { window in
            if let window { Self.allowFullScreen(window) }
            DispatchQueue.main.async { self.window = window }
        }
        return reader
    }

    func updateNSView(_ view: Reader, context: Context) {}

    final class Reader: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}

/// Hosts the engine's AVSampleBufferDisplayLayer in a layer-backed view.
struct VideoLayerView: NSViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    /// Presentation size of the video; the window takes this shape so nothing is letterboxed.
    let aspectRatio: CGSize?

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.videoLayer = layer
        view.aspectRatio = aspectRatio
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        if view.videoLayer !== layer { view.videoLayer = layer }
        if view.aspectRatio != aspectRatio { view.aspectRatio = aspectRatio }
    }

    final class HostView: NSView {
        var aspectRatio: CGSize? {
            didSet { if aspectRatio != oldValue { applyAspectRatio() } }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAspectRatio()
        }

        /// Resizes the window to the video's shape (keeping its width and top edge) and locks the
        /// resize handles to that shape, the way QuickTime and IINA do. Not in full screen.
        private func applyAspectRatio() {
            guard let window, let aspect = aspectRatio, aspect.width > 0, aspect.height > 0 else { return }
            window.contentAspectRatio = aspect
            guard !window.styleMask.contains(.fullScreen) else { return }
            let content = window.contentRect(forFrameRect: window.frame)
            let height = (content.width * aspect.height / aspect.width).rounded()
            PlayerLog.engine(String(format: "Window %.0f×%.0f, video %.0f×%.0f: %@", content.width, content.height,
                                    aspect.width, aspect.height,
                                    abs(height - content.height) > 1 ? "resizing to \(Int(content.width))×\(Int(height))" : "already fits"))
            guard abs(height - content.height) > 1 else { return }
            let resized = NSRect(x: content.minX, y: content.maxY - height, width: content.width, height: height)
            var frame = window.frameRect(forContentRect: resized)
            if let screen = window.screen { frame = window.constrainFrameRect(frame, to: screen) }
            window.setFrame(frame, display: true, animate: true)
        }

        var videoLayer: AVSampleBufferDisplayLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let videoLayer {
                    layer?.addSublayer(videoLayer)
                    needsLayout = true
                }
            }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer?.frame = bounds
            CATransaction.commit()
        }
    }
}

/// Subtitle text over the bottom of the picture. Laid out against the image rather than the view
/// (the aspect-fitted video minus bars encoded into it), so the text sits inside the image, not
/// in the black bar under it.
struct PlayerControls: View {
    @Bindable var player: PlaybackController
    let pip: PictureInPictureController
    @Binding var scrubbing: Double?
    @Binding var overControls: Bool
    var toggleFullScreen: () -> Void = {}

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Spacer()
                SwitchErrorCapsule(player: player)
                if let label = player.qualityLabel {
                    Text(label).font(.body.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                }
                HStack(spacing: 14) {
                    QualityMenu(player: player)
                    if player.audioOptions.count > 1 { AudioMenu(player: player) }
                    SubtitleMenu(player: player)
                    if !player.chapters.isEmpty {
                        PlayerMenu(icon: "list.bullet", help: "Chapters") { ChapterMenuItems(player: player) }
                    }
                    Menu {
                        SpeedMenuItems(player: player)
                    } label: {
                        Text(SpeedLabel.text(player.speed)).font(.callout.monospacedDigit())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Speed")
                    .accessibilityLabel("Speed \(SpeedLabel.text(player.speed))")
                    Button { pip.toggle() } label: { Image(systemName: "pip.enter") }
                        .help("Picture in Picture")
                        .accessibilityLabel("Picture in Picture")
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.black.opacity(0.45), in: Capsule())
            }
            // What is playing: the title centred on the window, level with the controls, at twice
            // their text size (13 pt, like the times at the bottom); the line under it starts where the title starts.
            .overlay {
                if let item = player.item {
                    Text(ItemLabels.title(item))
                        .font(.system(size: 26, weight: .bold))
                        .overlay(alignment: .bottomLeading) {
                            Text(ItemLabels.playing(item, remaining: player.duration - player.currentTime, speed: player.speed))
                                .font(.body.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                                .fixedSize()
                                .alignmentGuide(.bottom) { $0[.top] - 1 }
                        }
                        .lineLimit(1)
                        .frame(maxWidth: 480) // a long title stops short of the controls
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 12).padding(.top, 10)
            .onHover { overControls = $0 }
            // Just enough shade for the traffic lights and the pill to read on a bright scene.
            .background(LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 70), alignment: .top)

            Spacer()

            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Text(TimeFormat.clock(scrubbing ?? player.currentTime)).monospacedDigit()
                    Slider(value: Binding(get: { scrubbing ?? player.currentTime }, set: { scrubbing = $0 }),
                           in: 0...max(player.duration, 1)) { editing in
                        if !editing, let target = scrubbing {
                            Task {
                                await player.seek(to: target)
                                scrubbing = nil
                            }
                        }
                    }
                    .accessibilityLabel("Position")
                    .accessibilityValue(TimeFormat.clock(scrubbing ?? player.currentTime))
                    Text("-" + TimeFormat.clock(max(0, player.duration - (scrubbing ?? player.currentTime))))
                        .monospacedDigit()
                }
                HStack(spacing: 18) {
                    Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                        .accessibilityLabel("Back 10 seconds")
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title)
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30") }
                        .accessibilityLabel("Forward 30 seconds")
                    Spacer()
                    Button { player.isMuted.toggle() } label: {
                        Image(systemName: player.isMuted || player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .accessibilityLabel(player.isMuted ? "Unmute" : "Mute")
                    Slider(value: $player.volume, in: 0...1).frame(width: 110)
                        .accessibilityLabel("Volume")
                    Button(action: toggleFullScreen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Full Screen (F)")
                    .accessibilityLabel("Full Screen")
                }
                .font(.title3)
            }
            .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 12)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            .onHover { overControls = $0 }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

struct QualityMenu: View {
    @Bindable var player: PlaybackController

    var body: some View {
        Menu {
            QualityMenuItems(player: player)
        } label: {
            // Always the icon: AppKit draws a borderless menu's label once, so swapping it for the
            // spinner left an empty (still clickable) space after a switch.
            Image(systemName: "dial.medium")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(player.isSwitching ? 0 : 1)
        .overlay { if player.isSwitching { ProgressView().controlSize(.small).allowsHitTesting(false) } }
        .help("Quality")
        .accessibilityLabel("Quality")
    }
}

/// An icon in the control bar that opens a menu.
struct PlayerMenu<Items: View>: View {
    let icon: String
    let help: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu { items() } label: { Image(systemName: icon) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(help)
            .accessibilityLabel(help)
    }
}

struct AudioMenu: View {
    @Bindable var player: PlaybackController

    var body: some View {
        Menu {
            AudioMenuItems(player: player)
        } label: {
            Image(systemName: "waveform")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Audio")
        .accessibilityLabel("Audio")
    }
}

struct SubtitleMenu: View {
    @Bindable var player: PlaybackController

    var body: some View {
        Menu {
            SubtitleMenuItems(player: player)
        } label: {
            Image(systemName: "captions.bubble")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Subtitles")
        .accessibilityLabel("Subtitles")
        .disabled(player.subtitleOptions.isEmpty)
    }
}

/// Playback ▸ Quality / Subtitles in the menu bar, for keyboard access.
struct PlaybackCommands: Commands {
    let controller: PlaybackController

    var body: some Commands {
        CommandMenu("Playback") {
            Button(controller.isPlaying ? "Pause" : "Play") { controller.togglePlayPause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(controller.engine == nil)
            Button("Skip Back 10 Seconds") { controller.skip(by: -10) }.disabled(controller.engine == nil)
            Button("Skip Forward 30 Seconds") { controller.skip(by: 30) }.disabled(controller.engine == nil)
            Divider()
            Menu("Quality") {
                ForEach(controller.qualityOptions) { option in
                    Toggle(option.label, isOn: Binding(
                        get: { controller.session?.quality == option },
                        set: { if $0 { controller.selectQuality(option) } }))
                }
            }
            .disabled(controller.session == nil)
            Menu("Audio") {
                ForEach(controller.audioOptions) { option in
                    Toggle(option.label, isOn: Binding(get: { controller.selectedAudio == option.id },
                                                       set: { if $0 { controller.selectAudio(option.id) } }))
                }
            }
            .disabled(controller.audioOptions.count < 2)
            Menu("Speed") {
                ForEach(PlaybackController.speeds, id: \.self) { speed in
                    Toggle(SpeedLabel.text(speed), isOn: Binding(get: { controller.speed == speed },
                                                                 set: { if $0 { controller.speed = speed } }))
                }
            }
            .disabled(controller.engine == nil)
            Menu("Chapters") {
                ForEach(controller.chapters) { chapter in
                    Button("\(chapter.name)  \(TimeFormat.clock(chapter.start))") { controller.jump(to: chapter) }
                }
            }
            .disabled(controller.chapters.isEmpty)
            Menu("Subtitles") {
                Toggle("Off", isOn: Binding(get: { controller.selectedSubtitle == nil },
                                            set: { if $0 { controller.selectSubtitle(nil) } }))
                ForEach(controller.subtitleOptions) { option in
                    Toggle(option.label, isOn: Binding(get: { controller.selectedSubtitle == option.id },
                                                       set: { if $0 { controller.selectSubtitle(option.id) } }))
                }
            }
            .disabled(controller.subtitleOptions.isEmpty)
        }
    }
}
