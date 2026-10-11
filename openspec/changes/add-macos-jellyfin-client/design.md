# Design

## Context

Greenfield repository: nothing exists besides OpenSpec scaffolding. See proposal.md for motivation and specs/
for required behavior. Constraints that shape the design:

- Native macOS 14+ app in Swift/SwiftUI. The target experience is Infuse: files play as-is through Apple's own
  media pipeline, so HDR, Dolby Vision, Atmos, PiP and power efficiency come from the OS.
- AVPlayer cannot open MKV/WebM and lacks DTS/TrueHD/text-in-MKV support, so it is not the engine. Apple's
  lower-level renderers (`AVSampleBufferDisplayLayer`, `AVSampleBufferAudioRenderer`,
  `AVSampleBufferRenderSynchronizer`) accept compressed samples from any source, decode video in hardware via
  VideoToolbox, and keep the same HDR/DV/PiP integration. Feeding them is our job: FFmpeg demuxes the container.
- Jellyfin decides how to deliver a stream from a client-supplied **DeviceProfile** and **MaxStreamingBitrate**
  via `POST /Items/{id}/PlaybackInfo`. Its HLS output has a single variant, so quality switching is always a
  new request to the server, never player-side adaptive bitrate.
- The server is a safety net: whatever our profile does not declare, the server converts. The engine can start
  narrow and grow without breaking playback.
- Development happens partly in a Linux container. Only `JellyfinKit` builds there; the engine and app need a
  Mac or a macOS CI runner.

## Goals / Non-Goals

**Goals:**
- Play common Jellyfin files (MKV/MP4 with H.264/HEVC/AV1 and any common audio) as-is with hardware video
  decoding, HDR/DV and Atmos passthrough.
- Seamless quality switches: old stream keeps playing, new stream is buffered in the background and spliced in.
- Keep the engine behind a small protocol so the app, tests and future engines don't depend on FFmpeg types.
- Keep networking, models and quality logic platform-agnostic and unit-testable without a server or UI.

**Non-Goals:**
- Software video decoding, deinterlacing, image-subtitle rendering, styled ASS rendering, DV Profile 7 FEL —
  all delegated to the server in v1 via the DeviceProfile.
- Audio-track selection UI, adaptive bitrate, offline downloads, Jellyfin servers older than 10.9.

## Decisions

### D1. Project layout: three modules + XcodeGen
- `Packages/JellyfinKit` (Foundation only, builds on Linux): API client, models, auth header, DeviceProfile
  builder, quality presets and selection, play-method classification, reporting payloads.
- `Packages/PlayerCore` (macOS only): the playback engine. Depends on the FFmpeg xcframework and Apple
  media frameworks; exposes no FFmpeg types publicly.
- `App/` (macOS app target): SwiftUI views, view models, Keychain store, player UI, and `PlaybackController`
  that wires PlayerCore to JellyfinKit.
- `project.yml` (XcodeGen) generates `TinyJellyfin.xcodeproj`; the generated project is git-ignored.

*Alternatives:* a committed `.xcodeproj` (unreadable diffs, conflicts); one big package (engine changes would
force macOS-only builds of the API layer and lose Linux testability).

### D2. FFmpeg packaging: our own pinned, LGPL-only, demux+audio build
`scripts/build-ffmpeg.sh` builds a pinned FFmpeg release for macOS 14 (arm64 + x86_64) as an xcframework with
only `libavformat`, `libavcodec`, `libavutil`, `libswresample`, configured `--disable-gpl --disable-nonfree
--disable-network --disable-programs --disable-encoders --disable-muxers` and only the needed demuxers,
parsers, and audio/subtitle decoders. Network access is disabled because all I/O goes through URLSession (D4).
The result is published as a GitHub release asset of this repo and consumed as a SwiftPM `binaryTarget` with a
checksum. Dynamic frameworks satisfy LGPL; the app ships a licence notice and a link to the build script.

*Alternatives:* MPVKit/KSPlayer FFmpeg builds (tied to their release cadence, options not ours, some GPL);
Homebrew (non-relocatable dylibs, GPL-enabled); the retired ffmpeg-kit project.

### D3. Engine architecture (PlayerCore)
Public surface: `protocol PlaybackEngine` — `prepare(source:startAt:) async throws -> PreparedMedia`,
`play()`, `pause()`, `seek(to:) async`, `currentTime`, `state` (idle/buffering/playing/paused/failed/ended),
`tracks`, `selectSubtitle(_:)`, an `AsyncStream<EngineEvent>`, plus `displayLayer` for the UI and PiP.
`FFmpegEngine` implements it as a pipeline:

1. **Demux thread** (one dedicated `Thread`, since FFmpeg I/O blocks): `avformat_open_input` →
   `avformat_find_stream_info` → read loop pushing `AVPacket`s into per-stream queues. Queues are bounded by
   duration (≈30 s ahead) and bytes (≈200 MB); the reader blocks when full. An `interrupt_callback` aborts
   blocking reads on close, seek, or switch.
2. **Video**: build a `CMVideoFormatDescription` from codec parameters — `avcC`/`hvcC`/`av1C` extradata,
   colour primaries/transfer/matrix, mastering display and content light level side data as format
   description extensions (this is what turns on HDR/EDR). Each packet becomes a `CMSampleBuffer` (PTS/DTS/
   duration, sync-sample attachments) enqueued to an `AVSampleBufferDisplayLayer`'s `sampleBufferRenderer`
   from `requestMediaDataWhenReady`. VideoToolbox decodes in hardware.
3. **Dolby Vision**: read the `AV_PKT_DATA_DOVI_CONF` record. Profiles 5 and 8 use codec type `dvh1` with the
   `dvcC`/`dvvC` atom in `SampleDescriptionExtensionAtoms` (Profile 8 keeps HEVC compatibility). Profile 7
   drops the enhancement-layer NAL units and plays the HDR10 base layer as plain HEVC.
4. **Audio**: AAC, AC-3 and E-AC-3 (incl. JOC/Atmos) are passed through compressed to an
   `AVSampleBufferAudioRenderer` with the proper `CMAudioFormatDescription` and magic cookie. Everything else
   (DTS, TrueHD, FLAC, Opus, Vorbis, MP3, PCM variants) is decoded with libavcodec, converted with
   libswresample to interleaved Float32 keeping the channel layout, and enqueued as LPCM.
5. **Sync**: both renderers are attached to one `AVSampleBufferRenderSynchronizer`; `setRate(_:time:)` starts,
   pauses and repositions the shared clock. No custom A/V clock code.
6. **Seek**: interrupt reader → `av_seek_frame(BACKWARD)` to the keyframe ≤ target → flush queues and
   renderers → enqueue from the keyframe, marking video samples before the target `DoNotDisplay` and dropping
   audio before the target → `setRate(r, time: target)`.
7. **Timeline**: all timestamps are normalised to the media timeline (`pts − stream.start_time`, plus the
   server-provided start offset for transcoded streams) so positions match the server's ticks.
8. **Errors**: per-packet decode/enqueue failures are logged and skipped (corrupt-data scenario); reader I/O
   failure after the reconnect policy → `failed(position)`; renderer `.failed` status → `failed(position)`.

*Alternatives:* libmpv (plays everything on day one, but renders outside Apple's pipeline: no Dolby Vision, no
Atmos passthrough, no native PiP, Metal support experimental in MPVKit); VLCKit (similar trade-offs, large and
ageing on macOS); AVPlayer + server
remux (most files converted by the server; no DTS/TrueHD); decoding video ourselves with VideoToolbox
sessions (more code for no gain over the display layer).

### D4. All I/O through URLSession via custom AVIO
A `URLSessionIO` provides FFmpeg's `AVIOContext` read/seek callbacks backed by HTTP Range requests (with a
small read-ahead buffer), and the format context's `io_open`/`io_close2` callbacks route nested opens
(HLS playlists and segments) through the same layer. Benefits: system TLS, proxies and certificate handling;
the `Authorization` header is added per request so tokens never appear in URLs; cancellation integrates with
Swift tasks; reconnect/backoff (3 tries, 1/2/4 s) lives in one place.

*Alternative:* FFmpeg's own HTTP/TLS stack (needs a TLS library in the FFmpeg build, token in URLs or
`headers` option plumbing, separate proxy/cert behaviour from the rest of the app).

### D5. Thin hand-written API client over URLSession async/await
`JellyfinClient` with `async throws` methods and `Codable` models (PascalCase keys). Every request carries
`Authorization: MediaBrowser Client="Tiny Jellyfin", Device="<Mac name>", DeviceId="<uuid>", Version="<app version>", Token="<token>"`.
HTTP 401 maps to `JellyfinError.unauthorized`, which the session model observes to force re-login.

| Purpose | Endpoint |
|---|---|
| Validate server | `GET /System/Info/Public` |
| Sign in / out | `POST /Users/AuthenticateByName`, `POST /Sessions/Logout` |
| Libraries | `GET /UserViews?userId=` (filter `CollectionType` ∈ {movies, tvshows}) |
| Continue watching | `GET /UserItems/Resume?userId=&mediaTypes=Video` |
| Library items | `GET /Items?parentId=&sortBy=SortName&startIndex=&limit=&fields=…` |
| Series | `GET /Shows/{id}/Seasons`, `GET /Shows/{id}/Episodes?seasonId=` |
| Item details | `GET /Items/{id}?userId=` (incl. `MediaSources`, `MediaStreams`, `UserData`) |
| Images | `GET /Items/{id}/Images/Primary?maxHeight=` |
| Playback decision | `POST /Items/{id}/PlaybackInfo` |
| Static stream | `GET /Videos/{id}/stream?static=true&mediaSourceId=` |
| External subtitles | `GET /Videos/{id}/{mediaSourceId}/Subtitles/{index}/0/Stream.srt` |
| Reporting | `POST /Sessions/Playing`, `/Sessions/Playing/Progress`, `/Sessions/Playing/Stopped` |
| Transcode cleanup | `DELETE /Videos/ActiveEncodings?deviceId=&playSessionId=` |

*Alternatives:* generated OpenAPI client (huge surface); `jellyfin-sdk-swift` (extra dependency).

### D6. DeviceProfile mirrors engine capabilities; quality = profile + bitrate cap
`DeviceProfileBuilder` (JellyfinKit) takes an `EngineCapabilities` value (from PlayerCore at runtime, e.g. AV1
only when `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)`) and a `QualityPreset { id, label, maxBitrate,
maxHeight }` (Original has neither cap) and produces:
- DirectPlayProfiles: containers `mkv,webm,mp4,m4v,mov,ts`; video `h264,hevc[,av1]`; audio
  `aac,mp3,ac3,eac3,flac,alac,opus,vorbis,dts,truehd,pcm_*`.
- TranscodingProfile: HLS, `Container: mp4` (fMP4 segments), video `hevc,h264`, audio `aac,ac3,eac3`,
  `Context: Streaming` — listing h264/hevc lets the server copy compatible video (Direct Stream).
- CodecProfiles: HEVC/H.264 level and bit-depth limits from capabilities; for presets, `Height ≤ maxHeight`
  and `Width ≤ maxHeight·16/9` so the server downscales instead of only cutting bitrate.
- SubtitleProfiles: `srt,subrip,ass,ssa,vtt,webvtt,mov_text` → `Embed` and `External`; `pgssub,dvdsub,dvbsub`
  → `Encode` (burn-in).
- `MaxStreamingBitrate` = preset bitrate (Original: 200 Mbps), `StartTimeTicks` = position (1 tick = 100 ns),
  `SubtitleStreamIndex` = selected track.

Resulting play method: `SupportsDirectPlay` → static stream URL (Direct Play); otherwise the server's
`TranscodingUrl` — Direct Stream when its `TranscodeReasons` list no video reason, else Transcode. Both URLs
are opened by the same engine. Preset visibility is a pure function of source height; the remembered
preference falls back to Original without being overwritten. All of this is pure JellyfinKit logic with tests.

### D7. Seamless quality switch: prepare-then-splice
`PlaybackController` (`@MainActor @Observable`) owns the engine and `PlaybackSession { itemId,
mediaSourceId, playSessionId, playMethod, preset, subtitleIndex }`. A switch (also used for image-subtitle
burn-in on/off):

1. No-op if preset and burn-in state are unchanged; cancel any in-flight switch.
2. Request PlaybackInfo with the new preset and `StartTimeTicks` = current time + 2 s lookahead.
3. The engine opens a **second pipeline** (own reader, queues and format descriptions) and buffers ≥ 3 s,
   while the first keeps playing. Timeout 20 s.
4. Splice point K = first keyframe of the new pipeline at or after the current time. The old pipeline stops
   enqueueing samples with PTS ≥ K; the new pipeline's samples from K are enqueued into the **same renderers**
   (format description changes between samples are allowed), so video continues without a flush.
5. If K is already behind the clock when ready, fall back to a flush-and-seek swap (short gap, still < 1 s).
6. Tear down the old pipeline; report `Stopped` for the old session, `DELETE /Videos/ActiveEncodings` for its
   `playSessionId`, report `Playing` for the new one; persist the preset for this server.
7. Any failure in 2–4: discard the new pipeline, keep the old session, surface "Couldn't switch quality".

Subtitle selection for text tracks never reloads: embedded tracks come from the running demuxer, external
tracks are downloaded and parsed once.

### D8. Subtitles
Text subtitle packets are decoded with libavcodec (SRT/ASS/WebVTT/mov_text → `AVSubtitle` ASS text), ASS
override tags and drawing commands are stripped, and cues `{start, end, text}` go to a `SubtitleTrack`. A SwiftUI
overlay reads cues from the synchronizer's periodic time observer (every 100 ms) and renders them with a scaled
font, shadow, and bottom safe-area inset. External files use the same parser on downloaded data.

### D9. Reporting and system integration
- Progress: synchronizer periodic observer (10 s) plus state changes (pause/resume/seek) → `/Sessions/Playing/
  Progress` with `PositionTicks`, `IsPaused`, `PlayMethod`, `PlaySessionId`, `MediaSourceId`. Failures are
  logged, never interrupt playback. Window close and `ended` both route to a single `stop()`.
- PiP: `AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer:playbackDelegate:))`, with the
  delegate mapping play/pause/skip to the engine.
- Now Playing: `MPNowPlayingInfoCenter` (title, series, artwork, duration, elapsed, rate) and
  `MPRemoteCommandCenter` (play, pause, toggle, skip ±, change position).

### D10. UI structure
- Main window: `NavigationSplitView` — sidebar (Home, libraries) and detail stack (grid → series → season →
  item details), images via `AsyncImage` with title placeholders.
- Player window (one playback at a time): a layer-backed `NSView` hosting the display layer via
  `NSViewRepresentable`, with a SwiftUI overlay for controls (play/pause, scrubber, ±skip, volume, quality menu
  with "<quality> · <play method>", subtitle menu, PiP, full screen), auto-hide after 3 s, buffering spinner,
  error banner. Keyboard shortcuts via `.onKeyPress`; quality and subtitles also in a **Playback** menu-bar menu.

## Risks / Trade-offs

- [Engine complexity: sync, seeking and splicing are where custom players break] → Apple's synchronizer owns the
  clock; narrow v1 codec set; integration tests on generated fixtures (H.264/AAC MP4, HEVC10/E-AC-3 MKV,
  DTS/TrueHD MKV, SRT/ASS) run headless on the macOS CI runner.
- [Atmos passthrough via `AVSampleBufferAudioRenderer` on macOS not behaving like AVPlayer] → Verify early (task
  6.3) on AirPods Pro / built-in speakers; fallback is decoding E-AC-3 to multichannel PCM (loses Atmos objects
  only).
- [Dolby Vision signalling details (codec type, atoms) differ per profile and OS version] → Verify with
  reference P5/P8 clips on a DV-capable Mac; fall back to HDR10 base layer when the renderer rejects DV.
- [Splice glitches: audio renderer may not accept a format change mid-queue; transcoded stream offsets] → Flush
  only the audio renderer at K if needed (sub-100 ms audio blip); normalise timelines (D3.7); fallback swap (D7.5).
- [Server ignores the Height condition for some versions] → Profile JSON tests; verify on 10.9/10.10; append
  `maxHeight` to the transcoding URL if needed.
- [FFmpeg upgrades and security fixes are our responsibility] → Pinned version in the build script, CI builds
  the xcframework reproducibly; bump on FFmpeg security releases.
- [Plain-HTTP servers need an App Transport Security exception] → `NSAllowsArbitraryLoads` with a comment;
  self-hosted LAN servers are commonly HTTP.
- [Engine code can't be built in the Linux container] → JellyfinKit stays portable; PlayerCore and the app are
  built and tested on a GitHub Actions macOS runner.

## Migration Plan

Not applicable — first release, no existing users or data.

## Open Questions

- App icon and bundle identifier (`app.tinyjellyfin.TinyJellyfin` used as a placeholder).
- Which FFmpeg release to pin; pick the latest stable at implementation time.
