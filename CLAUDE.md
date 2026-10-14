# Tiny Jellyfin — notes for Claude

Native macOS, iPhone and Apple TV Jellyfin client with an Infuse-style playback engine: FFmpeg demuxes, Apple's
`AVSampleBuffer*` renderers decode and present. See `README.md` for the user-facing description and
`openspec/specs/` for the requirements it meets (finished changes are under
`openspec/changes/archive/`, each with a `manual-checklist.md` of what still needs a person).
`BACKLOG.md` holds known gaps.

## Layout

| Path | What | Builds on |
|---|---|---|
| `Packages/JellyfinKit` | API client, session, DeviceProfile, quality logic. Foundation only. | Linux + macOS + iOS + tvOS |
| `Packages/PlayerCore/Sources/PlayerCore/Core` | FFmpeg demuxing, byte sources, audio/subtitle decode. | Linux + macOS + iOS + tvOS |
| `Packages/PlayerCore/Sources/PlayerCore/Apple` | The engine: sample buffers, renderers, splicing. `#if canImport(AVFoundation)`. | macOS + iOS + tvOS |
| `App/Shared` | Models and pieces the apps share: `HomeModel`/`BrowserModel`/`LibraryGridModel`/`SeriesModel`, `PlaybackController`, Now Playing, PiP, subtitle layout, the audio session (iPhone and TV), cards and colours. No AppKit or UIKit beyond `#if`. | macOS + iOS + tvOS |
| `App/macOS` | The Mac app: `BrowserView` (tabs, keys, quick look), player window, menus. | macOS |
| `App/iOS` | The iPhone app: tabs, detail sheet, landscape touch player (gestures, device volume). | iOS |
| `App/tvOS` | The Apple TV app: Quick Connect sign-in, focus UI, remote player (`TVRemoteSurface` takes presses and touch-surface swipes), display matching. | tvOS |
| `App/TopShelf` | The Top Shelf extension; shares the App Group defaults and the Keychain group with the TV app. | tvOS |

Keep logic that can be portable in `Core/` — it is the only part CI can test on Linux, and it is
much faster to iterate on.

## Commands

```sh
scripts/build-ffmpeg.sh      # Vendor/FFmpeg/FFmpeg.xcframework (git-ignored), macOS + iOS + tvOS. ~10 min first time.
xcodegen generate            # TinyJellyfin.xcodeproj (git-ignored; regenerate after editing project.yml)
scripts/make-fixtures.sh     # test videos (git-ignored); needs Homebrew ffmpeg
swift test --package-path Packages/JellyfinKit
swift test --package-path Packages/PlayerCore
scripts/test-ios.sh          # both packages on an iPhone simulator (or: scripts/test-ios.sh "Apple TV 4K (3rd generation)")
xcodebuild test -project TinyJellyfin.xcodeproj -scheme TinyJellyfin -destination 'platform=macOS'
```

If `swift test` fails with `no such module 'XCTest'`, `xcode-select -p` is pointing at the Command
Line Tools. Either `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for the session,
or switch globally with `sudo xcode-select -s /Applications/Xcode.app`.

Run the app from Xcode, or `xcodebuild -scheme TinyJellyfin -configuration Debug build` then open the
product. CI (`.github/workflows/ci.yml`) runs all of the above on Linux and macOS; it must be green.

The first change was archived with 33/48 tasks verified. The rest need a human looking at the screen
or listening; they are listed in the archived change's `manual-checklist.md`. New work starts as its
own change (`/opsx:new`), and the specs in `openspec/specs/` are the contract to keep green.

## Engine invariants

These cost real debugging time. Breaking one usually shows up as "the spinner never stops".

- **HTTP inputs must stay seekable.** `MediaIO.makeContext` always sets `AVIO_SEEKABLE_NORMAL`. An
  HTTP source only learns its size from the first response, so deriving the flag from the size marks
  remote input unseekable and FFmpeg then emulates every seek by downloading everything in between.
  `testSeekOverHTTP` guards this.
- **Buffering keys off the demuxer queues, not the renderers.** The renderers stop accepting data
  while the synchronizer's rate is 0, so "wait until the renderers hold 1 s" deadlocks. See
  `readyToRun`/`sourceStarved` in `FFmpegEngine`.
- **Our FFmpeg build has no video decoders** (VideoToolbox does that). So the pixel format is often
  unknown: bit depth comes from the hvcC record, and colour info is inferred from the SPS via
  `CMVideoFormatDescriptionCreateFromHEVCParameterSets`. Probing is capped at 2 MB / 2 s, except for
  MPEG-TS and HLS, which have no header.
- **Only the `http` protocol is compiled in, with no TLS.** FFmpeg is handed `http://` URLs so its
  HLS demuxer accepts them; `MediaIO` swaps the real scheme back and every request goes through
  URLSession. Never let FFmpeg open a socket itself.
- **Transcoding asks Jellyfin for MPEG-TS segments**, not fMP4: FFmpeg 7.1 cannot seek HLS with fMP4
  segments.
- **Jellyfin's MPEG-TS segments are stamped 10 s late.** The server runs FFmpeg with
  `-max_delay 5000000` and the MPEG-TS muxer adds twice that to every timestamp, so the picture at
  30 s says 40 s. `JellyfinClient.hlsSegmentTimestampDelay` undoes it via `MediaSource.timelineOffset`.
  Seeks on segmented input ignore the offset (`Demuxer.seek`): FFmpeg picks the segment from the
  playlist, which runs from 0, and then returns the whole segment, so the engine hides the lead-in.
  Symptom when this is wrong: a quality switch jumps the picture back 10 s while subtitles and the
  progress bar carry on. `hls-jellyfin/` fixtures reproduce it.
- **`EngineCapabilities` describes decoding, never the display.** It feeds the server's
  DeviceProfile, so anything display-dependent (`AVPlayer.eligibleForHDRPlayback` changes with the
  window) makes the server flip between direct play and a full transcode of the same file. macOS
  tone-maps what the panel cannot show.
- **Transcodes don't know their picture size at open.** MPEG-TS/HLS report 0×0 until the first
  keyframe's parameter sets are parsed; `Pipeline.presentationSize` then reads the format
  description and the engine tick refreshes `videoSize`. Anything that keys off the size (window
  shape, subtitle layout) must cope with it arriving a second or two after `prepare`.
- **Probing consumes packets.** After `Demuxer.open(seekBeforeProbe:)` the read position is past the
  target, so unsegmented inputs are repositioned afterwards (cheap) and segmented ones are not —
  the engine instead starts the clock at the first queued packet.
- **A request that fails for good stops FFmpeg.** `MediaIO.fail` records it and sets the
  interrupt; otherwise FFmpeg's HLS demuxer skips the segment and tries every next one (each
  failing the same way) while the spinner turns. Only 408, 429 and 502–504 are retried: a 500 is
  Jellyfin's FFmpeg failing to start. `testFailingSegmentsFailTheOpenFast` guards this.
- **Asking for no subtitle in particular lets the server burn in its default.** Read
  `ResolvedStream.burnedInSubtitle`, and send `-1` for Off. A burnt-in picture track is asked for
  again with `-1` (PlaybackInfo starts no encode) and drawn from the server's `.sup`; only a track
  the server hasn't extracted (no bytes within `pictureFileWait`) is burnt in. The request still starts
  the extraction, which Jellyfin finishes after we give up (11 min for a 43-track 4K remux), so
  the next play draws it.
- **Picture subtitles are decoded for the selected track only** (a remux can carry dozens), into
  a store that keeps the latest 80 events. Selecting a track re-reads from the clock, or the
  events between the clock and the reader are missed. PGS events have no end time: each lasts
  until the next event or clear.
- **Skip packets without timestamps** (`packet.hasTimestamp`) before making sample buffers.
- **Never read a displayed pixel buffer as rows.** `displayedPixelBuffer()` hands back VideoToolbox's
  lossless-compressed layout (`&8v0`) on Apple Silicon; its memory is smaller than rows × stride and
  reading it that way segfaults. `LetterboxDetector` copies such frames through
  `VTPixelTransferSession` into a plain small 4:2:0 buffer first.
- **Threading:** all `FFmpegEngine` mutable state lives on its `queue`; each `Pipeline` owns a reader
  thread. `Pipeline.currentDemuxer` is replaced on the reader thread (HLS seeks reopen the stream).

## Debugging playback

- `PlayerLog` writes to subsystem `app.tinyjellyfin`, categories `engine` and `network`: every HTTP
  request with the server's response time, probe and open timings, how the file was opened, and each
  state change. Visible in Xcode's console and Console.app.
- `engine.debugSummary` is one line of internal state (clock, rate, queue depths, renderer status).
  The player overlay shows it under the spinner after 5 s, and test failures include it.
- A stall before any video arrives (`state=loading`, `vQ=0`) is the open path: look at `Open took …`.
  A stall with queues full is the start condition; with empty queues it is the network or the server.
- Debug builds can start playback without clicking, which is how the open path was measured against
  a real server: `TJ_AUTOPLAY=1` (plus `TJ_AUTOPLAY_ITEM`, `TJ_AUTOPLAY_FROM_START`,
  `TJ_AUTOPLAY_QUALITY`, `TJ_AUTOPLAY_SWITCH`, `TJ_AUTOPLAY_AUDIO`, `TJ_AUTOPLAY_SEARCH`, `TJ_AUTOPLAY_SUBTITLE`) — see `DebugAutoplay`. Run the binary directly to pass them, and watch with
  `log stream --predicate 'subsystem == "app.tinyjellyfin"' --style compact`.
- The test host skips session restore (`XCTestConfigurationFilePath` is set): the debug binary is
  ad-hoc signed, so every build is a new app to the Keychain and reading the token would put an
  access prompt on the screen and hang the test runner ("hung before establishing connection").
- `screencapture` works once the terminal running Claude has Screen Recording permission (it does
  on this Mac). Capture just the app with `screencapture -x -l <windowID>` (window id from
  `CGWindowListCopyWindowInfo`), and pose the browser with the DEBUG hooks `TJ_BROWSER_TAB`,
  `TJ_BROWSER_SEARCH`, `TJ_BROWSER_QUICKLOOK=hero|<id>`, `TJ_BROWSER_SELECT=<row>,<index>`.
  `TJ_AUTOPLAY=1 TJ_MAC_CHECKS=<file>` drives the player with in-app clicks and keys (pause, full
  screen, S, digits, the end screen) and writes PASS/FAIL lines to the file (`DebugChecks`).
- The Apple TV simulator: `xcrun simctl launch "Apple TV 4K (3rd generation)" app.tinyjellyfin.TinyJellyfin.tv`
  with `SIMCTL_CHILD_` variables. `TJ_SERVER=<address>` connects without typing (then Quick Connect
  shows a code to approve), `TJ_BROWSER_TAB`, `TJ_TV_OPEN=hero|series`, `TJ_AUTOPLAY=1` and `TJ_TV_PANEL=Subtitles` pose it
  (add `TJ_AUTOSTOP=10` so the player closes properly and the server stops transcoding), and
  `xcrun simctl io … screenshot` captures it. Display matching and HDMI audio only exist on a real
  Apple TV. The iPhone simulator takes the same `SIMCTL_CHILD_` hooks, plus
  `TJ_PHONE_MENU=Quality|Subtitles` and `TJ_AUTOSTOP` in the player.
- `Picture bars: x% top, y% bottom` is the letterbox detector finding black bars inside the frames;
  subtitles sit above them. It needs macOS 14.4 (`displayedPixelBuffer`), only ever narrows, and
  stops looking once the bars have held for ten looks (`Picture bars settled …`). A reading that is
  off centre or wider than 2.8:1 is a dark scene and is ignored; one once settled at 31%/25% and
  lifted the subtitles into the picture.
- Running `xcodebuild` from a terminal while Xcode has the project open: pass `-derivedDataPath`
  somewhere else. Sharing Xcode's DerivedData has produced stale test bundles, stale package
  frameworks, and a code-sign failure while the app was running from Xcode.
- Quit the app rather than killing it: `stopForTermination` tells the server to stop transcoding,
  and a killed process leaves the server encoding for nothing.

## Conventions

- Every behaviour change needs a test. Engine behaviour is tested headlessly against generated
  fixtures (`EngineTests`), network behaviour against `scripts/test-http-server.py`.
- When a bug only reproduces against a real server, add the test that would have caught it (the
  seekable flag, the park-and-resume read) rather than relying on manual checks.
- No settings screen. The app stays lean: pick a sensible default instead of adding an option.
- Don't add third-party dependencies. FFmpeg is the one exception, LGPL-only and built by our script;
  keep it that way (`THIRD_PARTY_NOTICES.md`).
- Generated and vendored paths are git-ignored: `Vendor/`, `*.xcodeproj/`, the fixtures,
  `App/Resources/Info.plist`.
