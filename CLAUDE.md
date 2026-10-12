# Tiny Jellyfin — notes for Claude

Native macOS Jellyfin client with an Infuse-style playback engine: FFmpeg demuxes, Apple's
`AVSampleBuffer*` renderers decode and present. See `README.md` for the user-facing description and
`openspec/changes/add-macos-jellyfin-client/` for the specs this was built against.

## Layout

| Path | What | Builds on |
|---|---|---|
| `Packages/JellyfinKit` | API client, session, DeviceProfile, quality logic. Foundation only. | Linux + macOS |
| `Packages/PlayerCore/Sources/PlayerCore/Core` | FFmpeg demuxing, byte sources, audio/subtitle decode. | Linux + macOS |
| `Packages/PlayerCore/Sources/PlayerCore/Apple` | The engine: sample buffers, renderers, splicing. `#if canImport(AVFoundation)`. | macOS |
| `App/` | SwiftUI app, `PlaybackController`, player window. | macOS |

Keep logic that can be portable in `Core/` — it is the only part CI can test on Linux, and it is
much faster to iterate on.

## Commands

```sh
scripts/build-ffmpeg.sh      # Vendor/FFmpeg (git-ignored). ~5 min first time, then a no-op.
xcodegen generate            # TinyJellyfin.xcodeproj (git-ignored; regenerate after editing project.yml)
scripts/make-fixtures.sh     # test videos (git-ignored); needs Homebrew ffmpeg
swift test --package-path Packages/JellyfinKit
swift test --package-path Packages/PlayerCore
xcodebuild test -project TinyJellyfin.xcodeproj -scheme TinyJellyfin -destination 'platform=macOS'
```

If `swift test` fails with `no such module 'XCTest'`, `xcode-select -p` is pointing at the Command
Line Tools. Either `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for the session,
or switch globally with `sudo xcode-select -s /Applications/Xcode.app`.

Run the app from Xcode, or `xcodebuild -scheme TinyJellyfin -configuration Debug build` then open the
product. CI (`.github/workflows/ci.yml`) runs all of the above on Linux and macOS; it must be green.

The change is at 33/48 tasks. The rest need a human looking at the screen or listening; they are
listed, with what each one closes, in `openspec/changes/add-macos-jellyfin-client/manual-checklist.md`.
Tasks 7.7 and 10.1 carry notes on which parts were already verified against a real server.

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
- **`EngineCapabilities` describes decoding, never the display.** It feeds the server's
  DeviceProfile, so anything display-dependent (`AVPlayer.eligibleForHDRPlayback` changes with the
  window) makes the server flip between direct play and a full transcode of the same file. macOS
  tone-maps what the panel cannot show.
- **Probing consumes packets.** After `Demuxer.open(seekBeforeProbe:)` the read position is past the
  target, so unsegmented inputs are repositioned afterwards (cheap) and segmented ones are not —
  the engine instead starts the clock at the first queued packet.
- **Skip packets without timestamps** (`packet.hasTimestamp`) before making sample buffers.
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
  `TJ_AUTOPLAY_QUALITY`) — see `DebugAutoplay`. Run the binary directly to pass them, and watch with
  `log stream --predicate 'subsystem == "app.tinyjellyfin"' --style compact`.
- Quit the app rather than killing it: `stopForTermination` tells the server to stop transcoding,
  and a killed process leaves the server encoding for nothing.

## Conventions

- Every behaviour change needs a test. Engine behaviour is tested headlessly against generated
  fixtures (`EngineTests`), network behaviour against `scripts/test-http-server.py`.
- When a bug only reproduces against a real server, add the test that would have caught it (the
  seekable flag, the park-and-resume read) rather than relying on manual checks.
- Don't add third-party dependencies. FFmpeg is the one exception, LGPL-only and built by our script;
  keep it that way (`THIRD_PARTY_NOTICES.md`).
- Generated and vendored paths are git-ignored: `Vendor/`, `*.xcodeproj/`, the fixtures,
  `App/Resources/Info.plist`.
