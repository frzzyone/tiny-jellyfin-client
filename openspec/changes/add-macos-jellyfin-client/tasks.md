# Tasks

## 1. Project scaffolding

- [x] 1.1 Create `Packages/JellyfinKit` Swift package (library + test target, Foundation only) and verify `swift build` and `swift test` succeed on Linux and macOS with a placeholder test
- [x] 1.2 Write `scripts/build-ffmpeg.sh` per design D2 (pinned release, LGPL-only, demux + audio/subtitle decoders, `http`/`tcp` protocols only, arm64 + x86_64 universal `libffmpeg.dylib` with headers in `Vendor/FFmpeg`) and verify the script builds on macOS and refuses GPL configurations
- [ ] 1.3 Create `Packages/PlayerCore` (macOS 14) with a `CFFmpeg` shim target linking `Vendor/FFmpeg` on macOS and the system FFmpeg on Linux, cache `Vendor/FFmpeg` in CI, and verify `swift test` passes on macOS and Linux
- [ ] 1.4 Add `project.yml` (XcodeGen) for the `TinyJellyfin` app target depending on both packages, with Info.plist (ATS exception, bundle id placeholder) and an FFmpeg LGPL notice in the About panel; git-ignore the generated project and verify `xcodegen generate && xcodebuild build` succeeds with an empty SwiftUI window
- [ ] 1.5 Add a GitHub Actions workflow: JellyfinKit `swift test` on Linux and macOS, PlayerCore tests and `xcodebuild test` on macOS, with test-fixture generation via the `ffmpeg` CLI; verify it passes on the branch
- [ ] 1.6 Write `README.md` with prerequisites (Xcode 15+, XcodeGen), FFmpeg build/licence notes, and build/run/test commands; verify the commands run as written on macOS

## 2. JellyfinKit API core

- [x] 2.1 Implement the `MediaBrowser` authorization header builder (client, device, device ID, version, optional token) and verify unit tests cover with/without token and value escaping
- [x] 2.2 Implement `JellyfinClient` request plumbing (base URL joining, JSON coding with PascalCase keys, `JellyfinError` with `.unauthorized` on 401, `.server`, `.network`, `.decoding`) and verify unit tests using a stub `URLProtocol`
- [x] 2.3 Implement server-address normalization (default `https://`, keep explicit `http://`, strip trailing slashes, keep port/path) and verify unit tests for each case in the server-connection spec

## 3. Server connection

- [x] 3.1 Add endpoints `publicSystemInfo()`, `authenticate(username:password:)`, `logout()` with Codable models and verify stubbed-response unit tests including wrong-credentials (401)
- [ ] 3.2 Implement `KeychainStore` (protocol + Keychain implementation + in-memory fake) storing only the token, and a persistent device ID in UserDefaults; verify unit tests with the fake and a manual check that the password is absent from Keychain and preferences
- [x] 3.3 Implement `SessionModel` (server step → sign-in step → signed-in; restore on launch; 401 anywhere → sign-in with server pre-filled; sign out clears token even offline) and verify view-model unit tests for each server-connection scenario
- [ ] 3.4 Build the server-address and sign-in SwiftUI screens with error states and verify manually against a real server: valid/invalid address, wrong password clears field, relaunch restores session, sign out

## 4. Library browsing

- [x] 4.1 Add endpoints and models for user views, resume items, paged items, seasons, episodes, item details (incl. `MediaStreams`), and image URLs; verify stubbed unit tests including filtering views to movies/tvshows
- [ ] 4.2 Build the `NavigationSplitView` shell with Home (Continue Watching, hidden when empty) and a library sidebar; verify manually that music libraries are hidden and progress bars appear for partly watched items
- [ ] 4.3 Build the library poster grid with paging on scroll and title placeholders for missing artwork; verify manually with a library larger than one page
- [ ] 4.4 Build series → seasons → episodes navigation with episode numbers and watched indicators; verify manually against a TV library
- [ ] 4.5 Build the item details view with Play / Resume from <time> / Play from beginning, and inline load errors with Retry that keep the user signed in; verify view-model tests for resume-time formatting and error state

## 5. Playback engine core (PlayerCore)

- [ ] 5.1 Define the public `PlaybackEngine` protocol, `EngineState`, `EngineEvent`, `EngineCapabilities` and track types (no FFmpeg types exposed) and verify the package builds and a fake engine conforms
- [x] 5.2 Implement `URLSessionIO` (AVIOContext read/seek via HTTP Range with read-ahead, `io_open`/`io_close2` for nested HLS opens, per-request `Authorization` header, interrupt on cancel, 3-try 1/2/4 s reconnect) and verify tests against a local HTTP fixture server including range seeks, an HLS playlist, and a dropped connection
- [ ] 5.3 Implement the demux thread and duration/byte-bounded packet queues with interrupt-based cancellation and verify tests that open MP4 and MKV fixtures, list streams/tracks, and stop promptly on close
- [x] 5.4 Implement video sample conversion (H.264 `avcC`, HEVC `hvcC`, AV1 `av1C` format descriptions, timing, sync attachments) feeding the display layer's renderer, and verify a headless test renders 5 s of each fixture with no renderer errors and advancing time
- [x] 5.5 Implement audio passthrough (AAC, AC-3, E-AC-3 with magic cookies) and decode path (DTS, TrueHD, FLAC, Opus, Vorbis, MP3, PCM → Float32 via libswresample keeping channel layout) feeding the audio renderer, and verify headless tests per codec fixture produce audio samples with the expected channel count
- [ ] 5.6 Wire both renderers to `AVSampleBufferRenderSynchronizer` with play/pause/rate and timeline normalisation, and verify a test that audio and video presentation times stay within 40 ms over 30 s
- [ ] 5.7 Implement seeking (interrupt, keyframe seek, flush, `DoNotDisplay` pre-roll, audio trim) and verify tests that seeks to 10 random positions land within 100 ms of target on MKV and HLS fixtures
- [x] 5.8 Implement buffering/ended/failed states and corrupt-packet skipping, and verify tests with a truncated file and an injected corrupt section (playback continues past it, state reports `failed` only on I/O loss)

## 6. HDR, Dolby Vision and Atmos

- [ ] 6.1 Attach colour primaries/transfer/matrix, mastering display and content light level extensions to video format descriptions, and verify unit tests for HDR10 and HLG fixtures plus a manual check on an XDR display and an SDR display
- [ ] 6.2 Implement Dolby Vision handling per design D3.3 (P5/P8 `dvh1` + `dvcC`/`dvvC`; P7 base layer only; HDR10 fallback when rejected) and verify unit tests on the generated format descriptions plus a manual check with P5, P8.1 and P7 reference clips on a DV-capable Mac
- [ ] 6.3 Verify E-AC-3 JOC Atmos passthrough on AirPods Pro and built-in speakers; if the renderer does not present Atmos, switch E-AC-3 to the decode path and record the outcome in design.md
- [ ] 6.4 Report `EngineCapabilities` (AV1 via `VTIsHardwareDecodeSupported`, HEVC 10-bit, DV support) and verify a unit test on the capability mapping

## 7. Jellyfin playback integration

- [x] 7.1 Implement `QualityPreset` (Original + six presets) and `DeviceProfileBuilder` per design D6 from `EngineCapabilities`, and verify JSON snapshot tests for Original, 720p 4 Mbps (bitrate + Height ≤ 720), and a Mac without AV1
- [x] 7.2 Add `playbackInfo(...)`, play-URL resolution (static stream vs. `TranscodingUrl`), and the play-method classifier; verify unit tests with recorded PlaybackInfo responses for MKV/HEVC Direct Play, VC-1 transcode, audio-only conversion (Direct Stream), and the "no playable stream" error
- [x] 7.3 Add session reporting endpoints and `DELETE /Videos/ActiveEncodings`; verify stubbed unit tests for tick conversion and payload fields
- [ ] 7.4 Implement `PlaybackController` (start at position, 10 s + event-driven progress reports, single `stop()` on close/end with encode cleanup, error state with Retry from last position) and verify controller unit tests with a fake engine and fake reporter
- [ ] 7.5 Build the player window: display layer host view, SwiftUI control overlay (play/pause, scrubber, skip −10/+30, volume/mute, full screen, auto-hide after 3 s, buffering spinner, error banner) and keyboard shortcuts; verify manually each media-playback controls/shortcuts scenario
- [ ] 7.6 Add Picture in Picture and Now Playing / remote commands per design D9 and verify manually: PiP enter/leave keeps position, media key pauses, Control Center shows title and progress
- [ ] 7.7 Verify end-to-end against a real server: Play and Resume (within 2 s), progress visible on Jellyfin web after closing, watched state after finishing, MKV/HEVC/DTS file plays as Direct Play with no server transcode

## 8. Subtitles

- [x] 8.1 Implement text subtitle decoding (SRT, ASS/SSA tag stripping, WebVTT, mov_text) into timed cues, and verify unit tests including ASS override tags and overlapping cues
- [ ] 8.2 Add external subtitle download and parsing, plus the default-track choice from PlaybackInfo, and verify stubbed tests for a sidecar SRT and a forced-track default
- [ ] 8.3 Build the subtitle overlay (time-synced, scaled with video, shadowed) and the subtitle menu (language/title + Off) in the player and the Playback menu; verify manually embedded SRT, ASS, external SRT and switching tracks without a position jump
- [ ] 8.4 Route image-subtitle selection (PGS/VobSub/DVB) through the switch path with `SubtitleStreamIndex` and burn-in, and back on Off; verify manually that position is kept and the indicator shows Transcode

## 9. Quality switching

- [x] 9.1 Implement preset visibility by source height and default-quality resolution (remembered per server, fallback to Original without overwriting); verify unit tests for the 1080p, unknown-resolution and hidden-remembered-preset scenarios
- [x] 9.2 Implement the second-pipeline prepare and splice-at-keyframe in the engine per design D7 (incl. flush-and-seek fallback and audio-only flush if needed), and verify a headless test that splices between two fixtures of different bitrates with no video gap > 100 ms and position continuity within 1 s
- [ ] 9.3 Implement the switch flow in `PlaybackController` (no-op on same quality, cancel in-flight, 20 s timeout, failure keeps old session, old session stopped + encode deleted, preference persisted, subtitle selection preserved) and verify controller tests with a fake engine including the failure path
- [ ] 9.4 Add the quality menu, "<quality> · <play method>" indicator, switching spinner and failure banner in the overlay and the Playback menu; verify manually switching from both places while playing and while paused
- [x] 9.5 Document quality presets, play methods and supported formats in README.md and verify the documented presets and codecs match `QualityPreset` and `DeviceProfileBuilder`

## 10. Integration checks

- [ ] 10.1 Run the end-to-end checklist against a real Jellyfin 10.9+ server: MKV/HEVC Original → Direct Play; VC-1 → video transcoded at source resolution; 1080p → 480p mid-movie with no gap > 1 s; switch while paused stays paused; HDR10 and DV P8 clips present in HDR/DV; Atmos track presents as Atmos (or recorded fallback); subtitles stay in sync across a switch; no leftover transcodes on the server dashboard after switches and after closing; preference persists after relaunch
- [ ] 10.2 Run `openspec validate add-macos-jellyfin-client --strict` and confirm CI is green on the final commit

## Workflow follow-up

- Archive the change with `openspec archive add-macos-jellyfin-client` after review and the integration checklist pass.
- Verify the archived specs appear under `openspec/specs/` with their Purpose sections.
