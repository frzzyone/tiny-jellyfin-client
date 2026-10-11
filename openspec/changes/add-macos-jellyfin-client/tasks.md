# Tasks

## 1. Project scaffolding

- [ ] 1.1 Create `Packages/JellyfinKit` Swift package (library + test target, Foundation only) and verify `swift build` and `swift test` succeed with a placeholder test
- [ ] 1.2 Add `project.yml` (XcodeGen) for the `TinyJellyfin` macOS 14+ app target depending on JellyfinKit, with Info.plist (ATS exception for HTTP servers, bundle id placeholder), git-ignore the generated `.xcodeproj`, and verify `xcodegen generate && xcodebuild build` succeeds on macOS with an empty SwiftUI window
- [ ] 1.3 Add a GitHub Actions workflow on a macOS runner that runs `swift test` for JellyfinKit and `xcodegen generate && xcodebuild test` for the app, and verify it passes on the branch
- [ ] 1.4 Write `README.md` with prerequisites (Xcode 15+, XcodeGen) and build/run/test commands, and verify the commands run as written on macOS

## 2. JellyfinKit API core

- [ ] 2.1 Implement the `MediaBrowser` authorization header builder (client, device, device ID, version, optional token) and verify unit tests cover with/without token and value escaping
- [ ] 2.2 Implement `JellyfinClient` request plumbing (base URL joining, JSON coding with PascalCase keys, `JellyfinError` with `.unauthorized` on 401, `.server`, `.network`, `.decoding`) and verify unit tests using a stub `URLProtocol`
- [ ] 2.3 Implement server-address normalization (default `https://`, keep explicit `http://`, strip trailing slashes, keep port/path) and verify unit tests for each case in the server-connection spec

## 3. Server connection

- [ ] 3.1 Add JellyfinKit endpoints `publicSystemInfo()`, `authenticate(username:password:)`, `logout()` with Codable models and verify stubbed-response unit tests including wrong-credentials (401)
- [ ] 3.2 Implement `KeychainStore` (protocol + Keychain implementation + in-memory fake) storing only the token, and a persistent device ID in UserDefaults; verify unit tests with the fake and a manual check that the password is absent from Keychain and preferences
- [ ] 3.3 Implement the `SessionModel` (signed-out → server step → sign-in step → signed-in; restore on launch; 401 anywhere → sign-in step with server pre-filled; sign out clears token even if offline) and verify view-model unit tests for each server-connection scenario
- [ ] 3.4 Build the server-address and sign-in SwiftUI screens with error states and verify manually against a real server: valid/invalid address, wrong password clears field, relaunch restores session, sign out

## 4. Library browsing

- [ ] 4.1 Add JellyfinKit endpoints and models for user views, resume items, paged items, seasons, episodes, item details, and image URLs; verify stubbed unit tests including filtering views to movies/tvshows
- [ ] 4.2 Build the `NavigationSplitView` shell with Home (Continue Watching row, hidden when empty) and a sidebar of libraries; verify manually that music libraries are hidden and progress bars appear for partly watched items
- [ ] 4.3 Build the library poster grid with paging on scroll and title placeholders for missing artwork; verify manually with a library larger than one page
- [ ] 4.4 Build series → seasons → episodes navigation with episode numbers and watched indicators; verify manually against a TV library
- [ ] 4.5 Build the item details view with Play / Resume from <time> / Play from beginning, and inline load errors with Retry that do not sign the user out; verify view-model tests for resume-time formatting and error state

## 5. Playback

- [ ] 5.1 Implement `QualityPreset` (Original + six presets) and the DeviceProfile / PlaybackInfo request builder per design D3; verify unit tests snapshot the JSON for Original and for 720p 4 Mbps (bitrate cap + Height ≤ 720 condition)
- [ ] 5.2 Add `playbackInfo(...)` and play-URL resolution (Direct Play static URL vs. server `TranscodingUrl`) plus the play-method classifier (Direct Play / Direct Stream / Transcode); verify unit tests with recorded PlaybackInfo responses for MP4/H.264, MKV/H.264 remux, and transcoded cases, and the "no playable stream" error
- [ ] 5.3 Add session reporting endpoints (`Playing`, `Progress`, `Stopped`) and `DELETE /Videos/ActiveEncodings`; verify stubbed unit tests for tick conversion and payload fields
- [ ] 5.4 Implement `PlaybackController` with AVPlayer: start at position, periodic (10 s) and event-driven progress reports, single `stop()` on window close or end-of-item with encode cleanup, error state with Retry from last position; verify controller unit tests with a fake reporter and manual playback against a real server
- [ ] 5.5 Build the player window hosting `AVPlayerView` (native controls, full screen) opened from item details; verify manually: play, resume within 2 s of saved position, progress visible on Jellyfin web after closing, watched state after finishing

## 6. Quality switching

- [ ] 6.1 Implement preset visibility by source height and default-quality resolution (remembered per server, fallback to Original without overwriting the preference); verify unit tests for the 1080p, unknown-resolution, and hidden-remembered-preset scenarios
- [ ] 6.2 Implement prepare-then-swap switching in `PlaybackController` per design D4 (no-op on same quality, keep old item playing, seek new item, restore rate, cancel in-flight switch, stop old session + delete encode, persist preference); verify controller unit tests with fake player/item readiness including the failure path keeping the old session
- [ ] 6.3 Add the quality menu overlay, the "<quality> · <play method>" indicator, switching spinner, failure banner, and the Playback ▸ Quality menu-bar menu; verify manually that switching works from both the overlay and the menu bar
- [ ] 6.4 Document quality presets and play methods in README.md and verify the documented presets match `QualityPreset`

## 7. Integration checks

- [ ] 7.1 Run the end-to-end checklist against a real Jellyfin 10.9+ server: Original on MP4 → Direct Play, Original on MKV/H.264 → Direct Stream at source resolution, 1080p → 480p mid-movie continues within 2 s, switch while paused stays paused, server dashboard shows no leftover transcodes after switches and after closing the player, preference persists after relaunch
- [ ] 7.2 Run `openspec validate add-macos-jellyfin-client --strict` and confirm CI is green on the final commit

## Workflow follow-up

- Archive the change with `openspec archive add-macos-jellyfin-client` after review and the integration checklist pass.
- Verify the archived specs appear under `openspec/specs/` with their Purpose sections.
