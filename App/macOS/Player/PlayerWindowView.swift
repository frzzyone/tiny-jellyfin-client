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

    private var player: PlaybackController { model.player }

    var body: some View {
        ZStack {
            Color.black
            if let engine = player.engine {
                VideoLayerView(layer: engine.displayLayer, aspectRatio: player.videoSize)
                    .onAppear { pip.attach(layer: engine.displayLayer, playback: player) }
                    .onTapGesture(count: 2) { toggleFullScreen() }
                    .id(ObjectIdentifier(engine)) // a new engine (retry, next title) gets PiP too
            }
            SubtitleOverlay(text: player.subtitleText, videoSize: player.videoSize, bars: player.pictureBars)
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
            PlayerControls(player: player, pip: pip, toggleFullScreen: toggleFullScreen)
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
        .onKeyPress(keys: [.space, .leftArrow, .rightArrow, .upArrow, .downArrow, .escape, "f", "m"]) { press in
            handle(press.key)
            return .handled
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in hideIfIdle() }
        .onChange(of: player.isPlaying) { _, _ in
            pip.invalidate()
            player.nowPlaying.update()
            noteActivity()
        }
        .onDisappear { player.stop() }
        .navigationTitle(player.item?.displayName ?? "Player")
    }

    private func noteActivity() {
        lastActivity = Date()
        if !controlsVisible { controlsVisible = true }
    }

    /// Controls hide after 3 s without mouse movement while playing; they stay while paused.
    private func hideIfIdle() {
        guard player.isPlaying, controlsVisible, Date().timeIntervalSince(lastActivity) >= 3 else { return }
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
    var toggleFullScreen: () -> Void = {}
    @State private var scrubbing: Double?

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Spacer()
                if let error = player.switchError {
                    Text(error)
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.red.opacity(0.75), in: Capsule())
                        .onTapGesture { player.dismissSwitchError() }
                        .task(id: error) {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            player.dismissSwitchError()
                        }
                }
                if let label = player.qualityLabel {
                    Text(label).font(.callout.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                }
                HStack(spacing: 14) {
                    QualityMenu(player: player)
                    SubtitleMenu(player: player)
                    Button { pip.toggle() } label: { Image(systemName: "pip.enter") }
                        .help("Picture in Picture")
                        .accessibilityLabel("Picture in Picture")
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.black.opacity(0.45), in: Capsule())
            }
            .padding(.horizontal, 12).padding(.top, 10)
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
            if player.isSwitching {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "dial.medium")
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Quality")
        .accessibilityLabel("Quality")
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
