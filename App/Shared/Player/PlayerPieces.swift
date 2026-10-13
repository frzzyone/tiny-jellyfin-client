import JellyfinKit
import PlayerCore
import SwiftUI

struct SubtitleOverlay: View {
    let text: String?
    var bitmap: SubtitleBitmap? = nil
    let videoSize: CGSize?
    let bars: PictureBars?
    /// The picture fills the view, cropped (the iPhone's fill mode): text goes in the view, and
    /// picture subtitles follow the cropped picture.
    var fill = false

    var body: some View {
        GeometryReader { geo in
            if let bitmap {
                PictureSubtitle(bitmap: bitmap,
                                frame: SubtitleLayout.frameRect(video: videoSize, in: geo.size, fill: fill))
                    .equatable()
            }
            if let text, !text.isEmpty {
                let picture = SubtitleLayout.pictureRect(video: fill ? nil : videoSize, in: geo.size, bars: bars)
                Text(text)
                    .font(Font(SubtitleFont.font(forPictureHeight: picture.height)))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black, radius: 2, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.8), radius: 6)
                    .padding(.horizontal, picture.width * 0.08)
                    .padding(.bottom, picture.height * 0.07)
                    .frame(width: picture.width, height: picture.height, alignment: .bottom)
                    .offset(x: picture.minX, y: picture.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A PGS/DVD/DVB event: its images placed where the disc put them on the frame. The images are
/// made once per event (the view only redraws when the event changes).
private struct PictureSubtitle: View, Equatable {
    let bitmap: SubtitleBitmap
    let frame: CGRect

    static func == (a: Self, b: Self) -> Bool {
        a.bitmap.start == b.bitmap.start && a.bitmap.end == b.bitmap.end && a.frame == b.frame
    }

    var body: some View {
        let sx = frame.width / CGFloat(max(1, bitmap.canvasWidth))
        let sy = frame.height / CGFloat(max(1, bitmap.canvasHeight))
        ForEach(Array(bitmap.pieces.enumerated()), id: \.offset) { _, piece in
            if let image = Self.image(piece) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: CGFloat(piece.width) * sx, height: CGFloat(piece.height) * sy)
                    .offset(x: frame.minX + CGFloat(piece.x) * sx, y: frame.minY + CGFloat(piece.y) * sy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static func image(_ piece: SubtitleBitmap.Piece) -> CGImage? {
        let data = piece.argb().withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        // 0xAARRGGBB words: BGRA bytes, alpha not premultiplied.
        return CGImage(width: piece.width, height: piece.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: piece.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.white)
            Button("Retry", action: retry)
                #if !os(tvOS)
                .keyboardShortcut(.defaultAction)
                #endif
        }
        .padding(18)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The quality choices, checked against the current one; both players wrap these in their own Menu.
struct QualityMenuItems: View {
    let player: PlaybackController
    /// After a choice: the iPhone closes its popover (a Menu closes by itself).
    var onPick: () -> Void = {}

    var body: some View {
        ForEach(player.qualityOptions) { option in
            Button {
                player.selectQuality(option)
                onPick()
            } label: {
                if option == player.session?.quality { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
            }
        }
    }
}

/// Off plus every subtitle track, the current one checked.
struct SubtitleMenuItems: View {
    let player: PlaybackController
    var onPick: () -> Void = {}

    var body: some View {
        Button {
            player.selectSubtitle(nil)
            onPick()
        } label: {
            if player.selectedSubtitle == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
        }
        ForEach(player.subtitleOptions) { option in
            Button {
                player.selectSubtitle(option.id)
                onPick()
            } label: {
                if option.id == player.selectedSubtitle { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
            }
        }
    }
}

/// When the iPhone's controls fade: 3 s after the last touch, during real playback, and never while
/// the user is scrubbing or has a Quality or Subtitles popover open (only they close it).
enum ControlsAutoHide {
    static func due(playing: Bool, scrubbing: Bool, menuOpen: Bool, idle: TimeInterval) -> Bool {
        playing && !scrubbing && !menuOpen && idle >= 3
    }
}

/// A level (brightness, volume) dragged up or down: a drag over 80% of the screen's height covers
/// the whole range, so a thumb's reach is enough.
enum SwipeLevel {
    static func adjusted(start: Double, translation: Double, height: Double) -> Double {
        guard height > 0 else { return start }
        return min(1, max(0, start - translation / (height * 0.8)))
    }
}

/// Scrubbing with a sideways swipe (the iPhone's screen, the Siri Remote's touch surface): a swipe
/// across the whole width moves a tenth of the film, at least a minute and at most ten, so short
/// and long titles both feel right.
enum SwipeScrub {
    static func target(start: Double, fraction: Double, duration: Double) -> Double {
        let span = min(600, max(60, duration * 0.1))
        return min(max(0, start + fraction * span), max(duration, 0))
    }
}
