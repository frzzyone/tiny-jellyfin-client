# Tinyfin

A small, native macOS, iPhone and Apple TV client for [Jellyfin](https://jellyfin.org) with an Infuse-style playback
engine and on-the-fly quality switching.

- **Plays files as they are.** FFmpeg reads the container (MKV, MP4, MOV, TS, WebM); video is decoded in
  hardware by macOS, and audio goes to the system audio renderer. Most files play without the server
  converting anything.
- **Native output.** HDR10/HLG on EDR displays, Dolby Vision Profiles 5 and 8, Dolby Atmos (E-AC-3) passed
  through to macOS, Picture in Picture, Now Playing and media keys.
- **Quality switching.** Pick "Original" or a bitrate/resolution preset at any time. The current stream keeps
  playing while the new one loads, then it is spliced in at a keyframe.

The behaviour is specified with [OpenSpec](https://github.com/Fission-AI/OpenSpec) in
[`openspec/specs`](openspec/specs) (built as the change archived in [`openspec/changes/archive`](openspec/changes/archive)).

## Requirements

- macOS 14 Sonoma or later; iPhone with iOS 17 or later; Apple TV 4K with tvOS 17 or later
- Xcode 15 or later (CI uses Xcode 16)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and, for tests, the `ffmpeg` command-line tool:
  `brew install xcodegen ffmpeg`
- A Jellyfin server, version 10.9 or later

## Build and run

First time only:

```sh
brew install xcodegen ffmpeg   # XcodeGen makes the project; ffmpeg generates test fixtures
scripts/build-ffmpeg.sh        # builds Vendor/FFmpeg (LGPL, ~5 min the first time, then cached)
```

Then, from Xcode:

```sh
xcodegen generate              # creates TinyJellyfin.xcodeproj (rerun whenever project.yml changes)
open TinyJellyfin.xcodeproj    # then press ⌘R
```

Or from the command line:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project TinyJellyfin.xcodeproj -scheme TinyJellyfin -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/TinyJellyfin-*/Build/Products/Debug/Tinyfin.app
```

Use `-configuration Release` and the `Release` folder for an optimised build. Release builds are
signed by your team: put `DEVELOPMENT_TEAM = <your team id>` in `App/Signing.local.xcconfig`
(git-ignored), or pass `CODE_SIGNING_ALLOWED=NO` for an unsigned build.

To hand the Mac app to someone else, use **Product › Archive** in Xcode, then **Distribute App ›
Direct Distribution**: Xcode re-signs it with your Developer ID and has Apple notarise it, so it
opens without a Gatekeeper warning. That needs a paid Apple Developer Program membership.
`scripts/release-mac.sh` does the same from the command line and ends with a notarised
`build/release/Tinyfin-<version>.dmg` (one-time setup in the script's header).

A few things worth knowing:

- **Quit with ⌘Q rather than force-quitting.** On the way out the app tells your server to stop
  transcoding; a killed process leaves the server encoding for nobody.
- **Logs** appear in Xcode's console, or from Terminal:
  `log stream --predicate 'subsystem == "app.tinyjellyfin"' --style compact`.
  They show every request with the server's response time, how each file was opened, and each
  player state change. If the spinner stays up for more than 5 s, the player shows its internal
  state underneath it.
- If `swift` or `xcodebuild` complain about a missing `XCTest` or SDK, `xcode-select -p` is pointing
  at the Command Line Tools: either export `DEVELOPER_DIR` as above or run
  `sudo xcode-select -s /Applications/Xcode.app`.

## iPhone

The iPhone app is the `TinyJellyfinPhone` scheme in the same project. It shares the engine, the
browser models and the sign-in with the Mac app; the screens and the player are its own: tabs for
Home, each library and Search, a detail sheet, and a landscape player (tap for controls, double-tap
the sides to skip, swipe sideways to scrub, swipe up and down for brightness on the left and volume
on the right, pinch or the button to fill or fit, hold for 2×, and a lock against stray touches).

To run it on your phone, put your team in `App/Signing.local.xcconfig` (git-ignored):

```
DEVELOPMENT_TEAM = ABCDE12345
```

then `xcodegen generate`, pick the `TinyJellyfinPhone` scheme and your iPhone in Xcode, and run. FFmpeg
is LGPL-only and dynamically linked, with this repository as the source for rebuilding the app
against another FFmpeg build (see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)). iOS has no audio passthrough, so Dolby Atmos is
played as 5.1/7.1 rather than passed to the receiver; DTS and TrueHD are decoded in the app.

## Apple TV

The Apple TV app is the `TinyJellyfinTV` scheme. Like the iPhone app it shares the engine and the
models; its screens are built for the remote: tabs along the top, Home with the hero and shelves,
title pages with a season strip, library grids, the system search screen, and a full-screen player.

- **Signing in:** type the server address once (the iPhone offers its keyboard), then approve the
  code the TV shows in Jellyfin on your phone or the web (profile › Quick Connect). "Use a password
  instead" is there when Quick Connect is off on the server.
- **The remote:** click or Play/Pause to pause, click left or right for −10 s / +30 s, swipe on the
  touch surface to scrub (click to jump there, Back to cancel), swipe or click down for Subtitles,
  Quality, Audio and Info, Back to leave.
- **Matching the TV:** with *Match Content* (Dynamic Range and Frame Rate) on in the Apple TV's
  Video and Audio settings, the TV switches to the film's frame rate and HDR or Dolby Vision mode
  before playback starts.
- **Top Shelf:** Continue watching and Next up above the app's icon; Play starts the item.
- **Sound:** Dolby Digital Plus (and Atmos in it) goes to the system as on the iPhone; TrueHD and DTS
  are decoded in the app and sent as multichannel PCM, as many channels as the receiver takes.

To run it on your Apple TV, the team in `App/Signing.local.xcconfig` is enough: Xcode registers the
App Group and Keychain group the Top Shelf extension shares with the app. Pair the Apple TV in
Xcode (Window › Devices and Simulators) and pick it as the run destination.

## Tests

```sh
scripts/make-fixtures.sh                          # small test videos, generated with the ffmpeg CLI
swift test --package-path Packages/JellyfinKit    # API client, session, profile and quality logic
swift test --package-path Packages/PlayerCore     # demuxing, HTTP/HLS, decoders; engine tests on macOS
xcodebuild test -project TinyJellyfin.xcodeproj -scheme TinyJellyfin -destination 'platform=macOS'
```

`JellyfinKit` and the portable part of `PlayerCore` also build and test on Linux against the system FFmpeg
(see `.github/workflows/ci.yml`).

## Finding something to watch

No sidebar: Home and one tab per video library in the top bar. Home leads with where you left
off (Enter resumes it), then Continue watching, Next up, Added this week, and rows that need no
typing: Surprise me (a random unwatched film), Short tonight, Because you watched, Almost done,
a genre of the day, the oldest unplayed titles, a decade of the day. Library tabs open with two of
the day's rows for that library (the ones Home isn't showing first), then one-click filters, a
genre strip and the grid; typing anywhere searches. Space opens a quick look with Play, Start
over and Mark watched; arrows move between rows and titles.

In the Mac player: click to pause, double-click for full screen, swipe sideways with two fingers on a
trackpad to scrub. Keys: Space play/pause, ← → −10 s / +30 s, ↑ ↓ volume, F full screen, M mute,
S next subtitle (then off), 0–9 jump to that tenth of the film. The control bar also has Audio (when there are several
tracks), Chapters (when the server lists them) and the speed (0.75×–2×).

## Quality presets

| Option | Max video bitrate | Max height |
|---|---|---|
| Original | uncapped | source |
| 4K 40 Mbps | 40 Mbps | 2160 |
| 1080p 20 Mbps | 20 Mbps | 1080 |
| 1080p 10 Mbps | 10 Mbps | 1080 |
| 720p 4 Mbps | 4 Mbps | 720 |
| 480p 1.5 Mbps | 1.5 Mbps | 480 |
| 360p 720 kbps | 720 kbps | 360 |

Presets taller than the video are hidden. The last choice is remembered per server and used for the next
video; before any choice, playback starts at Original.

The player shows how the stream is delivered:

- **Direct Play** — the file as-is.
- **Direct Stream** — video unchanged; the server converts the container or audio.
- **Transcode** — the server re-encodes the video (a lower preset, an unsupported codec, or image subtitles
  the server hasn't extracted, which it burns in).

## Supported formats

Played locally, without server conversion:

- **Containers:** MKV, WebM, MP4, M4V, MOV, MPEG-TS
- **Video:** H.264, HEVC (8- and 10-bit), AV1 on Macs with an AV1 hardware decoder
- **Audio:** AAC, MP3, AC-3, E-AC-3 (incl. Atmos), FLAC, ALAC, Opus, Vorbis, DTS, DTS-HD, TrueHD, PCM
- **Subtitles:** SRT, WebVTT, MP4 timed text, SSA/ASS (shown as plain text); embedded or external.
  Drawn inside the picture (black bars encoded into the frames are detected and skipped), in
  Helvetica Neue sized for the picture. Blu-ray (PGS), DVD and DVB picture subtitles are drawn by
  the app, where the disc places them, so remuxes play as they are. During a transcode the app draws
  the copy the server extracted, so turn on subtitle extraction in Jellyfin; a track without one is
  burnt in

Anything else (for example VC-1, MPEG-2 or VP9 video) is converted by the server,
because the app only advertises what it can play.

## How it fits together

```
App/Shared               All apps: sign-in, browser, Home and series models, PlaybackController, Now Playing, PiP
App/macOS, App/iOS,      Each app's screens and player
  App/tvOS
App/TopShelf             The Apple TV's Top Shelf extension
Packages/JellyfinKit     Jellyfin API client, session state, DeviceProfile, quality logic (Foundation only)
Packages/PlayerCore      Playback engine
  Core/                  FFmpeg demuxing through URLSession byte sources, audio/subtitle decoding (portable)
  Apple/                 AVSampleBufferDisplayLayer / AudioRenderer / RenderSynchronizer engine (macOS, iOS, tvOS)
scripts/                 FFmpeg build, test fixtures, test HTTP server
```

## Licences

Tinyfin dynamically links an LGPL-only build of FFmpeg. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `scripts/build-ffmpeg.sh` for the exact version and
configuration.
