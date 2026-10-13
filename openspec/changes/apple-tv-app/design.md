# Design

## Context

The iPhone port split the app into `App/Shared`, `App/macOS` and `App/iOS`, made PlayerCore link
FFmpeg as an XCFramework, and proved the engine on a non-Mac platform (system Dolby decode, PCM for
the rest, audio session, PiP). tvOS is UIKit-based like iOS and has every framework the engine
uses. What is new on the TV: no touch screen (focus and the Siri Remote), no keyboard worth typing
on, an HDMI display whose mode can change, a receiver behind it, and the Top Shelf extension.

Mockups: the "Tiny Jellyfin · Apple TV" rows of https://claude.ai/artifact/N34ygeBdXoi63aVu2vADfB
(Home, series page, Movies, player with the panel, sign-in, Top Shelf).

## Goals / Non-Goals

- Play what the Mac plays, on the TV, without the server transcoding, with the TV in the film's
  frame rate and HDR mode.
- Remote handling a person who uses Infuse would expect.
- Non-goals: server discovery, user profiles, downloads, screensaver/aerial integration, Siri
  search ("play Troy"), App Store distribution.

## Decisions

### D1. FFmpeg slices
`build-ffmpeg.sh` adds `tvos arm64` (`appletvos`, `-mappletvos-version-min=17.0`) and
`tvsim arm64` (`appletvsimulator`) to `SLICES`, same configure flags, frameworks shaped like the
iOS ones; `-create-xcframework` takes six slices. Risk: FFmpeg's configure may need
`--target-os=darwin` plus disabling a few tvOS-forbidden calls (it has built for tvOS before).

### D2. Packages and shared code
`.tvOS(.v17)` on both packages. In PlayerCore and `App/Shared`, `#if os(iOS)` checks that mean
"not the Mac" become `#if !os(macOS)` or `os(iOS) || os(tvOS)`. `EngineCapabilities` on tvOS:
HEVC, 10-bit and Dolby Vision from VideoToolbox as on the phone; AV1 only where the hardware says.
`canStartPictureInPictureAutomaticallyFromInline` stays iOS-only.

### D3. Quick Connect sign-in
JellyfinKit: `quickConnectEnabled()` (`GET /QuickConnect/Enabled`), `initiateQuickConnect()`
(`POST /QuickConnect/Initiate` → code and secret), `quickConnectState(secret:)`
(`GET /QuickConnect/Connect`), `authenticate(quickConnectSecret:)`
(`POST /Users/AuthenticateWithQuickConnect`). `SessionModel` gains `startQuickConnect()` that polls
every 3 s until approved, then stores the token as a password sign-in does; leaving the screen
cancels the poll. The TV shows the code after the server address is accepted; "Use a password
instead" opens the existing username/password form. Tested against the fake server in
JellyfinKit's tests.

### D4. Browsing with focus
SwiftUI on tvOS: `TabView` (renders as the top tab bar), `NavigationStack` per tab. Home: the hero
with focused Resume / Start over / Details, then `HomeModel.visibleRows` as horizontal shelves of
`.buttonStyle(.card)` cards (the system lift and parallax). Titles open a pushed page (not a sheet)
built from the same pieces as the iPhone sheet: facts, badges, overview, Resume/Play, Start over,
Mark watched; series add a season strip and an episode shelf. Library tabs reuse
`LibraryGridModel` with pills and a `LazyVGrid` of posters; Search uses `.searchable`, which on
tvOS is the system search screen with its keyboard and dictation. Sizes: posters 220 pt wide,
stills 400 pt, 90 pt side margins (tvOS safe area), text from 20 pt.

### D5. Remote player
A `UIViewRepresentable` hosting the display layer, full screen. Commands:
- Play/Pause button and a centre click: toggle.
- Left/right click (`onMoveCommand` while the transport bar is not being scrubbed): −10 s / +30 s,
  as on the other apps.
- Touch-surface pan: a `UIPanGestureRecognizer` on the host view (indirect touches) scrubs while
  the transport bar is up; a click commits, Back cancels.
- Swipe down / down click: the panel (Info, Subtitles, Quality, Audio). Subtitles and Quality reuse
  `SubtitleMenuItems`/`QualityMenuItems` data; Audio lists the tracks for display only until audio
  track switching exists (a stated non-goal of the engine today).
- Back (`onExitCommand`): closes the panel, else stops and leaves the player.
The transport bar shows for 4 s after any command, like the system player.

### D6. Matching the display
When the engine knows the video format (after `prepare`), the player sets
`window.avDisplayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate:formatDescription:)`
with the stream's frame rate and the format description the engine already builds (which carries
HDR10/HLG/Dolby Vision). Playback waits for `isDisplayModeSwitchInProgress` to clear (bounded to
5 s) before the clock runs, so the first seconds are not lost to the HDMI resync. Leaving the player
sets the criteria to nil. PlayerCore exposes the frame rate (`avg_frame_rate`) and the current
`CMVideoFormatDescription` on the engine; both are testable headlessly.

### D7. Audio over HDMI
AC-3/E-AC-3 go to the audio renderer compressed, as on iOS; tvOS passes Dolby Digital Plus (with
Atmos) to the receiver when the output supports it. TrueHD/DTS are decoded to PCM with their
layout; the session asks for `maximumOutputNumberOfChannels` so 5.1/7.1 PCM reach the receiver.
The DeviceProfile is unchanged.

### D8. Top Shelf
`App/TopShelf`: a `TVTopShelfContentProvider` extension returning `TVTopShelfSectionedContent`
with Continue watching (resume items, with `playbackProgress`) and Next up, `.hdtv` images from
the server's backdrop/thumb URLs (Jellyfin serves images without a token). Each item's
`displayAction` is `tinyjellyfin://item/<id>` and `playAction` `tinyjellyfin://play/<id>`; the app
handles both with `onOpenURL`. The extension needs the session: the server address and user id go
into an App Group's defaults (the TV app keeps all its preferences there), and the token into a
Keychain access group shared with the extension. Both list that group first in
`keychain-access-groups`, which makes it the default group for new items and searched by queries,
so `KeychainTokenStore` is unchanged and the Mac and iPhone keep their tokens where they are. The system asks the extension
again when the app calls `TVTopShelfContentProvider.topShelfContentDidChange()`, which it does when
playback stops.

### D9. Signing and targets
`TinyJellyfinTV` (tvOS 17, bundle `app.tinyjellyfin.TinyJellyfin.tv`) and `TinyJellyfinTopShelf`
(app extension) both use `App/Signing.xcconfig` for the team; the App Group and Keychain group need
it. The TV icon is a layered image stack (back: graphite, front: the amber mark) plus the Top Shelf
image, generated from the same SVG by `scripts/make-icon.sh`.

## Risks / Trade-offs

- **Simulator limits:** the tvOS simulator has no HDMI, no display switching and no hardware HEVC;
  D6 and D7 are verified only on a real Apple TV. The rest (UI, sign-in, Top Shelf content) is
  checked on the simulator.
- **Indirect touch scrubbing** in SwiftUI needs the UIKit gesture; focus can fight it. The player
  hosts the picture in a focusable UIKit view (`TVRemoteSurface`) that takes the remote's presses and
  touch-surface pans itself; SwiftUI only draws the transport bar and the panel. Fallback if that
  misbehaves on hardware: scrub with left/right holds.
- **Quick Connect off on the server:** the TV then goes straight to the password form, typed with
  the remote or the iPhone keyboard.
- Three UIs on shared models: anything a TV page needs that a model lacks goes into the model, not
  the view.
