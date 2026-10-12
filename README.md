# Tiny Jellyfin

A small, native macOS client for [Jellyfin](https://jellyfin.org) with an Infuse-style playback engine and
on-the-fly quality switching.

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

- macOS 14 Sonoma or later
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
open ~/Library/Developer/Xcode/DerivedData/TinyJellyfin-*/Build/Products/Debug/TinyJellyfin.app
```

Use `-configuration Release` and the `Release` folder for an optimised build.

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
a genre of the day, the oldest unplayed titles, a decade of the day. Library tabs have one-click
filters and a genre strip; typing anywhere searches. Space opens a quick look with Play, Start
over and Mark watched; arrows move between rows and titles.

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
- **Transcode** — the server re-encodes the video (a lower preset, an unsupported codec, or burned-in image
  subtitles).

## Supported formats

Played locally, without server conversion:

- **Containers:** MKV, WebM, MP4, M4V, MOV, MPEG-TS
- **Video:** H.264, HEVC (8- and 10-bit), AV1 on Macs with an AV1 hardware decoder
- **Audio:** AAC, MP3, AC-3, E-AC-3 (incl. Atmos), FLAC, ALAC, Opus, Vorbis, DTS, DTS-HD, TrueHD, PCM
- **Subtitles:** SRT, WebVTT, MP4 timed text, SSA/ASS (shown as plain text); embedded or external.
  Drawn inside the picture (black bars encoded into the frames are detected and skipped), in
  Helvetica Neue sized for the picture

Anything else (for example VC-1, MPEG-2 or VP9 video, or PGS/VobSub subtitles) is converted by the server,
because the app only advertises what it can play.

## How it fits together

```
App/                     SwiftUI app: sign-in, library, player window, PlaybackController
Packages/JellyfinKit     Jellyfin API client, session state, DeviceProfile, quality logic (Foundation only)
Packages/PlayerCore      Playback engine
  Core/                  FFmpeg demuxing through URLSession byte sources, audio/subtitle decoding (portable)
  Apple/                 AVSampleBufferDisplayLayer / AudioRenderer / RenderSynchronizer engine (macOS)
scripts/                 FFmpeg build, test fixtures, test HTTP server
```

## Licences

Tiny Jellyfin dynamically links an LGPL-only build of FFmpeg. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `scripts/build-ffmpeg.sh` for the exact version and
configuration.
