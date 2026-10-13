import AVFoundation
import JellyfinKit
import PlayerCore
import SwiftUI
import UIKit

/// The full-screen landscape player: video, subtitles inside the picture, and touch controls.
/// A tap shows or hides the controls; a double-tap on the left or right third skips 10 s / 30 s.
struct PhonePlayerView: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void
    @State private var controlsVisible = true
    @State private var lastActivity = Date()
    @State private var scrubbing: Double?
    @State private var skipFlash: (text: String, leading: Bool)?
    @State private var pip = PictureInPictureController()

    private var player: PlaybackController { model.player }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let engine = player.engine {
                    PhoneVideoLayer(layer: engine.displayLayer)
                        .onAppear { pip.attach(layer: engine.displayLayer, playback: player) }
                }
                SubtitleOverlay(text: player.subtitleText, videoSize: player.videoSize, bars: player.pictureBars)
                    .padding(.bottom, controlsVisible ? 56 : 0)
                    .animation(.easeOut(duration: 0.2), value: controlsVisible)
                touchLayer(width: geo.size.width)
                if player.status == .loading || player.status == .buffering {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large).tint(.white)
                        if let detail = player.loadingDetail {
                            Text(detail).font(.callout).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .allowsHitTesting(false)
                }
                if case .failed(let message) = player.status {
                    ErrorBanner(message: message) { player.retry() }
                }
                if let flash = skipFlash {
                    Text(flash.text)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(.white.opacity(0.12), in: Circle())
                        .frame(maxWidth: .infinity, alignment: flash.leading ? .leading : .trailing)
                        .padding(.horizontal, geo.size.width * 0.12)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if controlsVisible { controls.transition(.opacity) }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            PhoneOrientation.lock(.landscape)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback)
            // 5.1/7.1 PCM and Dolby reach the system whole, so AirPods can render them spatially.
            try? session.setSupportsMultichannelContent(true)
            try? session.setActive(true)
        }
        .onDisappear {
            player.stop()
            PhoneOrientation.lock(.portrait)
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            // Only real playback hides them: a slow start (buffering counts as "playing") must not.
            if player.status == .playing, controlsVisible, scrubbing == nil, Date().timeIntervalSince(lastActivity) >= 3 {
                withAnimation { controlsVisible = false }
            }
        }
        .onChange(of: player.isPlaying) { _, _ in pip.invalidate(); player.nowPlaying.update() }
        .onChange(of: player.status) { _, status in
            // Show the controls for 3 s once the picture is moving.
            if status == .playing { lastActivity = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            // Headphones unplugged or disconnected: pause, as every player does.
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            if reason == .oldDeviceUnavailable { player.pause() }
        }
    }

    /// Single tap toggles the controls; double tap on a side third skips.
    private func touchLayer(width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2).onEnded { tap in
                    let x = tap.location.x
                    if x < width / 3 { skip(-10, leading: true) } else if x > width * 2 / 3 { skip(30, leading: false) }
                }
                .exclusively(before: TapGesture().onEnded {
                    withAnimation { controlsVisible.toggle() }
                    lastActivity = Date()
                })
            )
    }

    private func skip(_ seconds: Double, leading: Bool) {
        player.skip(by: seconds)
        lastActivity = Date()
        withAnimation(.easeOut(duration: 0.15)) { skipFlash = (seconds > 0 ? "+\(Int(seconds))" : "\(Int(seconds))", leading) }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeIn(duration: 0.25)) { skipFlash = nil }
        }
    }

    private var controls: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black.opacity(0.6), location: 0), .init(color: .clear, location: 0.3),
                                   .init(color: .clear, location: 0.6), .init(color: .black.opacity(0.7), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 20)
            // Hidden while the spinner holds the centre.
            if player.status != .loading && player.status != .buffering {
            HStack(spacing: 72) {
                round("gobackward.10", size: 52, label: "Back 10 seconds") { skip(-10, leading: true) }
                round(player.isPlaying ? "pause.fill" : "play.fill", size: 68, label: player.isPlaying ? "Pause" : "Play") {
                    player.togglePlayPause()
                    lastActivity = Date()
                }
                round("goforward.30", size: 52, label: "Forward 30 seconds") { skip(30, leading: false) }
            }
            }
        }
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            round("xmark", size: 44, label: "Close", action: onClose)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.item.map(ItemLabels.title) ?? "").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                if let label = player.qualityLabel {
                    Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                }
            }
            Spacer()
            Menu { QualityMenuItems(player: player) } label: { chip(player.isSwitching ? "Switching…" : "Quality") }
            Menu { SubtitleMenuItems(player: player) } label: { chip("Subtitles") }
                .disabled(player.subtitleOptions.isEmpty)
            round("pip.enter", size: 44, label: "Picture in Picture") { pip.toggle() }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text(TimeFormat.clock(scrubbing ?? player.currentTime)).monospacedDigit()
            Slider(value: Binding(get: { scrubbing ?? player.currentTime }, set: { scrubbing = $0 }),
                   in: 0...max(player.duration, 1)) { editing in
                lastActivity = Date()
                if !editing, let target = scrubbing {
                    Task {
                        await player.seek(to: target)
                        scrubbing = nil
                    }
                }
            }
            .tint(BrowserStyle.accent)
            Text("-" + TimeFormat.clock(max(0, player.duration - (scrubbing ?? player.currentTime)))).monospacedDigit()
        }
        .font(.system(size: 12.5))
    }

    private func round(_ icon: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel(label)
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.black.opacity(0.45), in: Capsule())
    }
}

/// Hosts the engine's display layer in a UIView.
struct PhoneVideoLayer: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.videoLayer = layer
        return view
    }

    func updateUIView(_ view: HostView, context: Context) {
        if view.videoLayer !== layer { view.videoLayer = layer }
    }

    final class HostView: UIView {
        var videoLayer: AVSampleBufferDisplayLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let videoLayer { layer.addSublayer(videoLayer); setNeedsLayout() }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer?.frame = bounds
            CATransaction.commit()
        }
    }
}

/// Browsing is portrait, the player is landscape: the app delegate answers with whatever is
/// locked here, and a lock change asks the scene to rotate.
enum PhoneOrientation {
    @MainActor static var locked: UIInterfaceOrientationMask = .portrait

    @MainActor static func lock(_ mask: UIInterfaceOrientationMask) {
        locked = mask
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        PhoneOrientation.locked
    }
}
