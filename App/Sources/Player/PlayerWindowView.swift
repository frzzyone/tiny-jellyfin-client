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
    @FocusState private var focused: Bool

    private var player: PlaybackController { model.player }

    var body: some View {
        ZStack {
            Color.black
            if let engine = player.engine {
                VideoLayerView(layer: engine.displayLayer)
                    .onAppear { pip.attach(layer: engine.displayLayer, playback: player) }
            }
            SubtitleOverlay(text: player.subtitleText)
            if player.status == .loading || player.status == .buffering {
                ProgressView().controlSize(.large).tint(.white)
            }
            if case .failed(let message) = player.status {
                ErrorBanner(message: message) { player.retry() }
            }
            if player.status == .idle && player.item == nil {
                Text("Nothing is playing").foregroundStyle(.secondary)
            }
            PlayerControls(player: player, pip: pip)
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        }
        .ignoresSafeArea()
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
        case "f": NSApp.keyWindow?.toggleFullScreen(nil)
        case "m": player.isMuted.toggle()
        case .escape:
            if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        default: break
        }
    }
}

/// Hosts the engine's AVSampleBufferDisplayLayer in a layer-backed view.
struct VideoLayerView: NSViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.videoLayer = layer
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        if view.videoLayer !== layer { view.videoLayer = layer }
    }

    final class HostView: NSView {
        var videoLayer: AVSampleBufferDisplayLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let videoLayer {
                    videoLayer.wantsExtendedDynamicRangeContent = true
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

struct SubtitleOverlay: View {
    let text: String?

    var body: some View {
        GeometryReader { geo in
            if let text, !text.isEmpty {
                Text(text)
                    .font(.system(size: max(14, geo.size.height * 0.045), weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black, radius: 2, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.8), radius: 6)
                    .padding(.horizontal, geo.size.width * 0.08)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                    .padding(.bottom, geo.size.height * 0.07)
            }
        }
        .allowsHitTesting(false)
    }
}

struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.white)
            Button("Retry", action: retry).keyboardShortcut(.defaultAction)
        }
        .padding(18)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PlayerControls: View {
    @Bindable var player: PlaybackController
    let pip: PictureInPictureController
    @State private var scrubbing: Double?

    var body: some View {
        VStack {
            HStack(spacing: 10) {
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
                QualityMenu(player: player)
                SubtitleMenu(player: player)
                Button { pip.toggle() } label: { Image(systemName: "pip.enter") }
                    .help("Picture in Picture")
            }
            .padding(14)
            .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))

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
                    Text("-" + TimeFormat.clock(max(0, player.duration - (scrubbing ?? player.currentTime))))
                        .monospacedDigit()
                }
                HStack(spacing: 18) {
                    Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title)
                    }
                    Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30") }
                    Spacer()
                    Button { player.isMuted.toggle() } label: {
                        Image(systemName: player.isMuted || player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    Slider(value: $player.volume, in: 0...1).frame(width: 110)
                    Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Full Screen (F)")
                }
                .font(.title3)
            }
            .padding(16)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

struct QualityMenu: View {
    @Bindable var player: PlaybackController

    var body: some View {
        Menu {
            ForEach(player.qualityOptions) { option in
                Button {
                    player.selectQuality(option)
                } label: {
                    if option == player.session?.quality { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                }
            }
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
    }
}

struct SubtitleMenu: View {
    @Bindable var player: PlaybackController

    var body: some View {
        Menu {
            Button {
                player.selectSubtitle(nil)
            } label: {
                if player.selectedSubtitle == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
            }
            ForEach(player.subtitleOptions) { option in
                Button {
                    player.selectSubtitle(option.id)
                } label: {
                    if option.id == player.selectedSubtitle { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Subtitles")
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
