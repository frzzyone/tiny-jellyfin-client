# Design

## Context

Greenfield repository: nothing exists besides OpenSpec scaffolding. See proposal.md for motivation and specs/
for required behavior. Constraints that shape the design:

- Native macOS 14+ app in Swift/SwiftUI with AVFoundation/AVKit, no third-party runtime dependencies.
- AVFoundation can play MP4/MOV/M4V files and HLS, but **not** Matroska (MKV), WebM or AVI containers, and has
  no support for codecs such as VP9, AV1 (pre-M3 hardware), DTS or TrueHD. Most Jellyfin libraries are MKV-heavy,
  so "Original" frequently means a server-side remux rather than true direct play.
- Jellyfin decides how to deliver a stream from a client-supplied **DeviceProfile** and a
  **MaxStreamingBitrate**, via `POST /Items/{id}/PlaybackInfo`. The server's HLS output (`master.m3u8`) has a
  single variant, so quality cannot be switched by the player's adaptive bitrate logic.
- Development here happens partly in a Linux container; macOS-only code (SwiftUI, AVKit, Keychain) can only be
  built and tested on a Mac or a macOS CI runner.

## Goals / Non-Goals

**Goals:**
- Keep networking, models and quality logic in a platform-agnostic Swift package that is unit-testable without
  a server, a UI, or AVFoundation.
- Make a quality switch a single, well-defined operation: new PlaybackInfo request → prepare new item →
  swap → clean up old session.
- Keep the app small: one window for browsing, one window per playback, no custom video rendering.

**Non-Goals:**
- Adaptive (automatic) bitrate switching, subtitle/audio track pickers, offline downloads.
- Supporting Jellyfin servers older than 10.9.
- A custom player UI that replaces AVKit's transport controls.

## Decisions

### D1. Project layout: Swift package + XcodeGen app target
- `Packages/JellyfinKit` (Swift package, library): API client, Codable models, auth header, DeviceProfile
  builder, quality presets and selection logic, playback-session reporting. Depends only on Foundation.
- `App/` (macOS app target): SwiftUI views, view models, Keychain store, AVKit player, and the
  playback controller that wires AVPlayer to JellyfinKit.
- `project.yml` (XcodeGen) generates `TinyJellyfin.xcodeproj`; the generated project is git-ignored.

*Alternatives:* a committed `.xcodeproj` (unreadable diffs, merge conflicts, hard to author without Xcode); a
pure SwiftPM executable (no proper app bundle, Info.plist, entitlements or icon). XcodeGen is a build-time
tool only, not a runtime dependency.

### D2. Thin hand-written API client over URLSession async/await
A `JellyfinClient` with `async throws` methods for the handful of endpoints needed, using `Codable` models with
PascalCase key mapping. Every request carries
`Authorization: MediaBrowser Client="Tiny Jellyfin", Device="<Mac name>", DeviceId="<uuid>", Version="<app version>", Token="<token>"`.
HTTP 401 maps to a dedicated `JellyfinError.unauthorized` that the app's session model observes to force
re-login (server-connection: Expired or revoked session).

Endpoints used:

| Purpose | Endpoint |
|---|---|
| Validate server | `GET /System/Info/Public` |
| Sign in / out | `POST /Users/AuthenticateByName`, `POST /Sessions/Logout` |
| Libraries | `GET /UserViews?userId=` (filter `CollectionType` ∈ {movies, tvshows}) |
| Continue watching | `GET /UserItems/Resume?userId=&mediaTypes=Video` |
| Library items | `GET /Items?parentId=&sortBy=SortName&startIndex=&limit=&fields=…` |
| Series | `GET /Shows/{id}/Seasons`, `GET /Shows/{id}/Episodes?seasonId=` |
| Item details | `GET /Items/{id}?userId=` (incl. `MediaSources`, `UserData.PlaybackPositionTicks`) |
| Images | `GET /Items/{id}/Images/Primary?maxHeight=` |
| Playback decision | `POST /Items/{id}/PlaybackInfo` |
| Reporting | `POST /Sessions/Playing`, `/Sessions/Playing/Progress`, `/Sessions/Playing/Stopped` |
| Transcode cleanup | `DELETE /Videos/ActiveEncodings?deviceId=&playSessionId=` |

*Alternatives:* generated client from Jellyfin's OpenAPI spec (huge surface, codegen tooling to maintain);
the community `jellyfin-sdk-swift` (third-party dependency, broader than needed). Revisit if the endpoint set grows.

### D3. Quality is expressed to the server as DeviceProfile + MaxStreamingBitrate
A `QualityPreset` is `{ id, label, maxBitrate, maxHeight }`; `Original` has neither cap. For each playback or
switch, JellyfinKit builds a request with:
- `MaxStreamingBitrate` = preset bitrate (Original: 120 Mbps, effectively uncapped).
- A **DeviceProfile** describing what AVFoundation plays:
  - DirectPlayProfiles: containers `mp4,m4v,mov`; video `h264,hevc`; audio `aac,mp3,ac3,eac3,alac,flac`.
  - TranscodingProfiles: HLS, `Container: mp4` (fMP4 segments), `Protocol: hls`, video `hevc,h264`, audio
    `aac,ac3,eac3`, `Context: Streaming`. Listing h264/hevc lets the server *copy* compatible video
    (Direct Stream / remux) rather than re-encode.
  - For presets, a CodecProfile condition `Height LessThanEqual maxHeight` (and `Width ≤ maxHeight·16/9`) so
    the server must downscale; without it the server only enforces bitrate and may keep 1080p at 1.5 Mbps.
- `StartTimeTicks` = position (1 tick = 100 ns), `EnableDirectPlay/DirectStream/Transcoding = true`.

The response's chosen `MediaSource` decides the play method:
`SupportsDirectPlay` → `/Videos/{id}/stream?static=true&mediaSourceId=&api_key=` (Direct Play);
otherwise `TranscodingUrl` (server-relative, prefixed with the server URL). That stream is labelled Direct
Stream when the `TranscodeReasons` query parameter lists only container/audio reasons (video is copied), and
Transcode when it lists any video reason (`Video*NotSupported`, `ContainerBitrateExceedsLimit`, …). The label
logic is a pure function in JellyfinKit with unit tests.

Preset visibility (playback-quality: Quality options) is a pure function of the source video stream's height;
the remembered preference is resolved against visible presets, falling back to Original without overwriting
the stored preference.

*Alternative considered:* AVPlayer `preferredPeakBitRate` / `preferredMaximumResolution` — rejected because
Jellyfin's master playlist has one variant, so there is nothing for AVPlayer to choose between.

### D4. Quality switch = prepare-then-swap with a fresh play session
`PlaybackController` (app target, `@Observable`, `@MainActor`) owns one `AVPlayer` and the current
`PlaybackSession { itemId, mediaSourceId, playSessionId, playMethod, preset }`. Switching:

1. Ignore if the selected preset equals the current one.
2. Capture `currentTime` and `rate`; mark `isSwitching` (UI shows a small spinner on the quality menu).
3. Call PlaybackInfo with the new preset and `StartTimeTicks` = captured position; build a new `AVPlayerItem`.
4. Wait for `status == .readyToPlay` (timeout 20 s) and `seek(to: position)` on the new item before it is
   attached — the old item keeps playing meanwhile (playback-quality: Uninterrupted switching).
5. Re-read the old player's current time, seek the new item to it if the drift is > 2 s, then
   `replaceCurrentItem(with:)` and restore `rate` (0 keeps it paused).
6. Report `Stopped` for the old session, `DELETE /Videos/ActiveEncodings` for its `playSessionId`, then report
   `Playing` for the new session. Persist the preset as the default for this server.
7. On any failure in 3–4: discard the new item, keep the old session untouched, surface an error banner.

Concurrent switches: a new selection cancels an in-flight switch task (Swift `Task` cancellation) before
starting.

*Alternative:* tear down and recreate the player (simpler, but causes a black gap and loses state when the
new stream fails — violates the Failed quality switch requirement).

### D5. Progress reporting driven by AVPlayer observers
A periodic time observer (every 10 s) plus KVO on `timeControlStatus` and seek completion send
`/Sessions/Playing/Progress` with `PositionTicks`, `IsPaused`, `PlayMethod`, `PlaySessionId`,
`MediaSourceId`. Reporting failures are logged and never interrupt playback. Window close and
`AVPlayerItemDidPlayToEndTime` both route to a single `stop()` that reports `Stopped` and cleans up the encode.

### D6. Session storage
Keychain (`kSecClassGenericPassword`, service `app.tinyjellyfin.token`, account = `<serverURL>|<userId>`)
holds the token. `UserDefaults` holds server URL, user ID, user name, device ID, and per-server preferred
quality ID. A `KeychainStore` protocol lets view models be tested with an in-memory fake.

### D7. UI structure
- `WindowGroup` main window: `NavigationSplitView` with sidebar (Home, each library) and detail stack
  (grid → series → season → item details). Images via `AsyncImage` with a title placeholder.
- Player opens in its own `Window` (one at a time, replacing any current playback) hosting `AVPlayerView`
  through `NSViewRepresentable` for native macOS controls and full screen. The quality `Menu` and the
  "720p 4 Mbps · Transcode" indicator sit in an overlay at the top-right that hides with the controls, and
  are also exposed as a **Playback ▸ Quality** menu-bar menu for keyboard access.

## Risks / Trade-offs

- [Server ignores the Height condition for some codecs/versions] → Unit-test the generated profile; verify
  against a real 10.9/10.10 server during the integration task; fall back to appending `maxHeight` to the
  transcoding URL if needed.
- [HLS seek accuracy: transcoded segments start on keyframes, so resume/switch can land a few seconds off] →
  Specs allow 2 s tolerance; seek with zero tolerance after the item is ready.
- [Direct Play URLs carry the token as `api_key` in the query string] → Required by AVPlayer (no custom
  headers on plain `AVURLAsset` without private options); URLs are never logged or persisted.
- [Plain-HTTP servers require an App Transport Security exception] → Set `NSAllowsArbitraryLoads` with a
  comment; self-hosted LAN servers are commonly HTTP. Accepted trade-off for a personal media client.
- [macOS code can't be built in the Linux dev container] → Keep logic in JellyfinKit (builds with `swift test`
  on Linux), and run the full Xcode build/test on a GitHub Actions macOS runner.
- [Server hardware may be too slow to transcode 4K] → Out of our control; the Failed quality switch path keeps
  the old stream playing and reports the error.

## Migration Plan

Not applicable — first release, no existing users or data.

## Open Questions

- App icon and bundle identifier (`app.tinyjellyfin.TinyJellyfin` used as a placeholder) — cosmetic, can be
  decided before the first release build.
