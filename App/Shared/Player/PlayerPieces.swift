import JellyfinKit
import PlayerCore
import SwiftUI

struct SubtitleOverlay: View {
    let text: String?
    let videoSize: CGSize?
    let bars: PictureBars?

    var body: some View {
        GeometryReader { geo in
            if let text, !text.isEmpty {
                let picture = SubtitleLayout.pictureRect(video: videoSize, in: geo.size, bars: bars)
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

    var body: some View {
        ForEach(player.qualityOptions) { option in
            Button {
                player.selectQuality(option)
            } label: {
                if option == player.session?.quality { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
            }
        }
    }
}

/// Off plus every subtitle track, the current one checked.
struct SubtitleMenuItems: View {
    let player: PlaybackController

    var body: some View {
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
