# Tasks

## 1. Platform groundwork

- [x] 1.1 `build-ffmpeg.sh --ios`: device and simulator slices plus the macOS slice in `FFmpeg.xcframework`, same LGPL configure flags; verify `xcodebuild -create-xcframework` output lists three platforms and the script still refuses GPL options
- [x] 1.2 PlayerCore `CFFmpeg` as a `binaryTarget` on the XCFramework; packages declare `.iOS(.v17)`; verify the Mac app and all package tests are unchanged and green
- [x] 1.3 Run JellyfinKit and PlayerCore tests on the iOS simulator (fixtures served by the existing HTTP test server); verify green and add both to CI

## 2. Engine on iOS

- [x] 2.1 Audio session setup and the audio capability check: Dolby to the system decoder where accepted, the rest decoded to Float32 PCM with channel layout; `EngineCapabilities` reports it; verify unit tests for the mode choice and an engine test that decodes the AC-3, E-AC-3, DTS and TrueHD fixtures on the simulator
- [x] 2.2 Halve queue limits on iOS; verify the queue-limit tests per platform

## 3. Shared app code

- [x] 3.1 Split `App/` into `Shared/`, `macOS/`, `iOS/`; `SubtitleFont` on `CTFont`; `NowPlaying` artwork behind a typealias; verify the Mac app builds and its tests pass unchanged
- [x] 3.2 `TinyJellyfin-iOS` target in `project.yml` (bundle id, iOS 17, background audio, ATS exception, icon from the same SVG); verify it builds for the simulator

## 4. iPhone UI

- [x] 4.1 Sign-in screens on the shared `SessionModel`; verify on the simulator against the server
- [x] 4.2 Tabs and Home: hero, rows, discovery rows, pull to refresh; verify by screenshot on the simulator
- [x] 4.3 Detail sheet (Resume/Play, Start over, Mark watched), series → seasons → episodes; verify by screenshot
- [x] 4.4 Movies/Shows tabs with filter pills and genre strip, Search tab; verify by screenshot
- [ ] 4.5 Touch player: full-screen landscape, tap/double-tap/scrub, quality and subtitle menus, subtitles inside the picture; verify on a device
- [ ] 4.6 PiP, Now Playing, pause on headphones unplugged, progress reporting; verify on a device

## 5. Docs

- [ ] 5.1 README (building for iPhone, the personal-distribution assumption), CLAUDE.md layout table, `openspec/config.yaml` context, THIRD_PARTY_NOTICES (FFmpeg on iOS); verify `openspec validate --strict`

Simulator checks on 2026-10-13 (iPhone 18 Pro, iOS 27, against the server): sign-in, Home with the
hero and rows, detail sheet with badges and actions, Movies grid with filters and genres, the
landscape player playing For All Mankind with subtitles inside the picture and the controls over
video. The simulator has no hardware HEVC, so the server transcodes to H.264 and starts take
17–24 s there; on a phone the same file plays directly. 4.5 and 4.6 need a real iPhone.
