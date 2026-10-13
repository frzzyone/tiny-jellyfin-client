# Tasks

## 1. Platform groundwork

- [x] 1.1 `build-ffmpeg.sh`: tvOS device and simulator slices in `FFmpeg.xcframework`, same LGPL flags; verify six slices and the GPL refusal
- [x] 1.2 Packages declare `.tvOS(.v17)`; "not the Mac" `#if`s cover tvOS; verify both packages build and test on the Apple TV simulator (`scripts/test-ios.sh` with a TV destination) and the Mac and iPhone are unchanged

## 2. Engine on tvOS

- [ ] 2.1 Engine exposes the stream frame rate and the current video format description; verify with fixture tests (24/25/29.97/60 fps, HDR10, Dolby Vision)
- [ ] 2.2 Audio session for HDMI: maximum output channels; verify the audio tests on the TV simulator

## 3. Sign-in

- [ ] 3.1 JellyfinKit Quick Connect calls and `SessionModel` Quick Connect sign-in with polling and cancel; verify against the fake server (approved, pending, disabled, cancelled)
- [ ] 3.2 TV sign-in screens: address, code, password fallback; verify on the simulator against the server

## 4. TV app

- [ ] 4.1 `TinyJellyfinTV` target (tvOS 17, team from Signing.xcconfig, layered icon and Top Shelf image); verify it builds for the simulator
- [ ] 4.2 Tabs and Home shelves with the hero; verify by screenshot
- [ ] 4.3 Title pages: film and series (season strip, episode shelf), Mark watched; verify by screenshot
- [ ] 4.4 Library tabs with pills and genres, Search; verify by screenshot
- [ ] 4.5 Remote player: transport bar, click/skip, touch scrub, panel (Subtitles, Quality, Audio), Back; verify on the simulator with the remote, then on an Apple TV
- [ ] 4.6 Display criteria with the wait for the mode switch; Now Playing; verify on an Apple TV
- [ ] 4.7 Dolby to the receiver, PCM 5.1/7.1 for the rest; verify on an Apple TV with a receiver

## 5. Top Shelf

- [ ] 5.1 App Group and shared Keychain group; `KeychainTokenStore` access group; verify the app still restores its session on all three platforms
- [ ] 5.2 `TinyJellyfinTopShelf` extension (Continue watching, Next up, progress, deep links) and `onOpenURL` in the app; refresh on playback stop; verify on the simulator

## 6. Docs and CI

- [ ] 6.1 README (Apple TV section), CLAUDE.md layout row, `openspec/config.yaml`, BACKLOG; CI builds the TV app; verify `openspec validate --strict`
