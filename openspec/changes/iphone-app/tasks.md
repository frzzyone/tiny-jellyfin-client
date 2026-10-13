# Tasks

## 1. Platform groundwork

- [ ] 1.1 `build-ffmpeg.sh --ios`: device and simulator slices plus the macOS slice in `FFmpeg.xcframework`, same LGPL configure flags; verify `xcodebuild -create-xcframework` output lists three platforms and the script still refuses GPL options
- [ ] 1.2 PlayerCore `CFFmpeg` as a `binaryTarget` on the XCFramework; packages declare `.iOS(.v17)`; verify the Mac app and all package tests are unchanged and green
- [ ] 1.3 Run JellyfinKit and PlayerCore tests on the iOS simulator (fixtures served by the existing HTTP test server); verify green and add both to CI

## 2. Engine on iOS

- [ ] 2.1 Audio session setup and the audio capability check: Dolby to the system decoder where accepted, the rest decoded to Float32 PCM with channel layout; `EngineCapabilities` reports it; verify unit tests for the mode choice and an engine test that decodes the AC-3, E-AC-3, DTS and TrueHD fixtures on the simulator
- [ ] 2.2 Halve queue limits on iOS; verify the queue-limit tests per platform

## 3. Shared app code

- [ ] 3.1 Split `App/` into `Shared/`, `macOS/`, `iOS/`; `SubtitleFont` on `CTFont`; `NowPlaying` artwork behind a typealias; verify the Mac app builds and its tests pass unchanged
- [ ] 3.2 `TinyJellyfin-iOS` target in `project.yml` (bundle id, iOS 17, background audio, ATS exception, icon from the same SVG); verify it builds for the simulator

## 4. iPhone UI

- [ ] 4.1 Sign-in screens on the shared `SessionModel`; verify on the simulator against the server
- [ ] 4.2 Tabs and Home: hero, rows, discovery rows, pull to refresh; verify by screenshot on the simulator
- [ ] 4.3 Detail sheet (Resume/Play, Start over, Mark watched), series → seasons → episodes; verify by screenshot
- [ ] 4.4 Movies/Shows tabs with filter pills and genre strip, Search tab; verify by screenshot
- [ ] 4.5 Touch player: full-screen landscape, tap/double-tap/scrub, quality and subtitle menus, subtitles inside the picture; verify on a device
- [ ] 4.6 PiP, Now Playing, pause on headphones unplugged, progress reporting; verify on a device

## 5. Docs

- [ ] 5.1 README (building for iPhone, the personal-distribution assumption), CLAUDE.md layout table, `openspec/config.yaml` context, THIRD_PARTY_NOTICES (FFmpeg on iOS); verify `openspec validate --strict`
