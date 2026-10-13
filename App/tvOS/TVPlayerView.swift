import AVFoundation
import AVKit
import JellyfinKit
import PlayerCore
import SwiftUI

/// The full-screen player, driven by the remote. Click or Play/Pause toggles; clicking left or
/// right skips 10 s back or 30 s on; a swipe scrubs (a click commits, Back cancels); swiping or
/// clicking down opens the panel (Info, Subtitles, Quality, Audio); Back closes the panel, then
/// the player.
struct TVPlayerView: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void
    @State private var transportUntil = Date().addingTimeInterval(4)
    @State private var scrub: (start: Double, target: Double)?
    @State private var panel: PanelTab?
    @FocusState private var focus: PanelTab?

    private var player: PlaybackController { model.player }

    enum PanelTab: String, CaseIterable, Identifiable {
        case info = "Info", subtitles = "Subtitles", quality = "Quality", audio = "Audio"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            TVRemoteSurface(layer: player.engine?.displayLayer, onCommand: handle)
                .focusable(panel == nil)
            SubtitleOverlay(text: player.subtitleText, videoSize: player.videoSize, bars: player.pictureBars)
            if player.status == .loading || player.status == .buffering {
                VStack(spacing: 16) {
                    ProgressView()
                    if let detail = player.loadingDetail {
                        Text(detail).font(.system(size: 24)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .allowsHitTesting(false)
            }
            if case .failed(let message) = player.status {
                VStack(spacing: 20) {
                    Label(message, systemImage: "exclamationmark.triangle.fill").font(.system(size: 28))
                    HStack(spacing: 24) {
                        Button("Retry") { player.retry() }
                        Button("Close", action: onClose)
                    }
                }
                .padding(40)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 24))
            } else {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    if showsTransport(at: context.date) { transport.transition(.opacity) }
                }
                .allowsHitTesting(false)
            }
            if let panel { panelView(panel).transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .ignoresSafeArea()
        .background(.black)
        .playbackAudioSession(player)
        .onDisappear { DisplayMatch.reset() }
        .onChange(of: player.isPlaying) { _, _ in player.nowPlaying.update() }
        .onChange(of: player.status) { _, status in if status == .playing { showTransport() } }
        #if DEBUG
        .task {
            // Screenshot hooks: TJ_TV_PANEL=Info|Subtitles|Quality|Audio opens the panel once playing;
            // TJ_AUTOSTOP=<seconds> closes the player as Back would, so the server stops transcoding.
            let env = ProcessInfo.processInfo.environment
            if let name = env["TJ_TV_PANEL"], let tab = PanelTab(rawValue: name) {
                try? await Task.sleep(for: .seconds(4))
                openPanel(tab)
            }
            if let seconds = env["TJ_AUTOSTOP"].flatMap(Double.init) {
                try? await Task.sleep(for: .seconds(seconds))
                onClose()
            }
        }
        #endif
    }

    // MARK: Remote

    private func handle(_ command: RemoteCommand) {
        switch command {
        case .select, .playPause:
            if let scrub { commit(scrub.target) } else { player.togglePlayPause() }
            showTransport()
        case .left, .right:
            let seconds: Double = command == .left ? -10 : 30
            if let current = scrub {
                // While scrubbing, a click nudges the target instead of jumping the film.
                scrub?.target = min(max(0, current.target + seconds), player.duration)
            } else {
                player.skip(by: seconds)
            }
            showTransport()
        case .up:
            showTransport()
        case .down:
            openPanel(.subtitles)
        case .menu:
            if scrub != nil {
                scrub = nil
                showTransport()
            } else {
                onClose()
            }
        case .panBegan:
            let start = scrub?.target ?? player.currentTime
            scrub = (start, start)
            showTransport()
        case .panChanged(let fraction):
            guard let start = scrub?.start else { return }
            scrub?.target = SwipeScrub.target(start: start, fraction: fraction, duration: player.duration)
            showTransport()
        case .panEnded:
            // The next swipe carries on from here; a click commits, Back cancels.
            if let target = scrub?.target { scrub = (target, target) }
        }
    }

    private func commit(_ target: Double) {
        scrub = nil
        Task { await player.seek(to: target) }
    }

    private func showTransport() { transportUntil = Date().addingTimeInterval(4) }

    private func showsTransport(at date: Date) -> Bool {
        scrub != nil || panel != nil || date < transportUntil || player.status == .paused
    }

    private func openPanel(_ tab: PanelTab) {
        withAnimation(.easeOut(duration: 0.2)) { panel = tab }
        focus = tab
    }

    private func closePanel() {
        withAnimation(.easeIn(duration: 0.2)) { panel = nil }
        focus = nil
    }

    // MARK: Transport

    private var transport: some View {
        let time = scrub?.target ?? player.currentTime
        let duration = max(player.duration, 1)
        return VStack(spacing: 14) {
            Spacer()
            HStack(alignment: .firstTextBaseline) {
                Text(player.item.map(ItemLabels.title) ?? "").font(.system(size: 30, weight: .semibold))
                Spacer()
                if let label = player.qualityLabel {
                    Text(label).font(.system(size: 22)).foregroundStyle(.white.opacity(0.75))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(BrowserStyle.accent).frame(width: geo.size.width * min(1, player.currentTime / duration))
                    if scrub != nil {
                        RoundedRectangle(cornerRadius: 2).fill(.white)
                            .frame(width: 4, height: 30)
                            .offset(x: geo.size.width * min(1, time / duration) - 2)
                    }
                }
                .frame(height: 10)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 30)
            HStack {
                Text(TimeFormat.clock(time))
                Spacer()
                Text(scrub != nil ? "click to jump here · Back to cancel" : "click ◀ −10 s · click ▶ +30 s · swipe to scrub")
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("−" + TimeFormat.clock(max(0, player.duration - time)))
            }
            .font(.system(size: 24).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, TVStyle.side)
        .padding(.bottom, 50)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).frame(height: 360)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Panel

    private func panelView(_ tab: PanelTab) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(PanelTab.allCases) { item in
                    TVPill(title: item.rawValue, on: item == tab) { panel = item }
                        .focused($focus, equals: item)
                }
            }
            Group {
                switch tab {
                case .info: info
                case .subtitles: options { SubtitleMenuItems(player: player) }
                case .quality: options { QualityMenuItems(player: player) }
                case .audio: audio
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(26)
        .frame(width: 980)
        .background(Color(red: 0x26 / 255, green: 0x2b / 255, blue: 0x34 / 255).opacity(0.94), in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.6), radius: 40, y: 30)
        .padding(.top, 40)
        .frame(maxHeight: .infinity, alignment: .top)
        .onExitCommand(perform: closePanel)
        // Focus moves between tabs with left and right; choosing a tab shows it.
        .onChange(of: focus) { _, new in if let new, new != panel { panel = new } }
    }

    private func options<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 26), GridItem(.flexible())], alignment: .leading, spacing: 6) {
            content()
        }
        .font(.system(size: 25))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = player.item {
                Text(item.displayName).font(.system(size: 30, weight: .semibold))
                Text(ItemLabels.facts(item)).font(.system(size: 22)).foregroundStyle(BrowserStyle.dim)
                if let overview = item.overview {
                    Text(overview).font(.system(size: 22)).lineLimit(3).foregroundStyle(BrowserStyle.dim)
                }
            }
            if let label = player.qualityLabel { Text(label).font(.system(size: 22)).foregroundStyle(BrowserStyle.muted) }
        }
        .foregroundStyle(BrowserStyle.text)
        .focusable() // so focus can come down from the tabs and Back still reaches the panel
    }

    /// Shown, not switchable: the engine plays the stream the server recommends.
    private var audio: some View {
        VStack(alignment: .leading, spacing: 10) {
            let tracks = player.engine?.tracks.filter { $0.kind == .audio } ?? []
            ForEach(tracks) { track in
                Text("\(track.displayName) · \(track.codec.uppercased())\(track.isDefault ? " · default" : "")")
                    .font(.system(size: 24)).foregroundStyle(BrowserStyle.text)
            }
            Text("Audio tracks can't be switched yet.").font(.system(size: 20)).foregroundStyle(BrowserStyle.muted)
        }
        .focusable()
    }
}

/// Switches the TV to the video's frame rate and dynamic range (when Match Content is on in the
/// Apple TV's settings) and waits for the HDMI resync, so the opening seconds aren't lost.
enum DisplayMatch {
    @MainActor static func apply(_ engine: PlaybackEngine) async {
        guard let manager = window?.avDisplayManager, let format = engine.videoFormatDescription else { return }
        manager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: Float(engine.frameRate ?? 0), formatDescription: format)
        let deadline = Date().addingTimeInterval(5)
        try? await Task.sleep(for: .milliseconds(150))
        while manager.isDisplayModeSwitchInProgress, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    @MainActor static func reset() { window?.avDisplayManager.preferredDisplayCriteria = nil }

    @MainActor private static var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }
}
