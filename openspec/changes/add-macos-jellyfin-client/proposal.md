# Proposal

## Why

There is no lightweight, native macOS Jellyfin client: the options are the web UI in a browser tab or heavy
cross-platform apps. A small SwiftUI/AVKit app gives a Mac-native experience, and the one feature that matters
most on mixed networks (laptop on Wi-Fi, travel, remote server) is letting the user pick the streaming quality
on the fly instead of being stuck with whatever the server picks.

## What Changes

- New native macOS app (SwiftUI, macOS 14+) that connects to a self-hosted Jellyfin server.
- Sign in with server URL + username/password; the session is kept securely and restored on relaunch; sign out.
- Browse the user's libraries: movies, TV shows (series → seasons → episodes), and a "Continue Watching" row.
- Play videos with AVKit, resume from the last watched position, and report playback progress to the server so
  watch state stays in sync with other Jellyfin clients.
- **Quality switching**: during playback the user can choose "Original" (direct play when the Mac can play the
  file as-is) or a fixed bitrate/resolution preset (e.g. 1080p 10 Mbps, 720p 4 Mbps, 480p 1.5 Mbps). Switching
  keeps the playback position, shows the active quality and play method, and the last choice becomes the
  default for future playback.

Assumptions (recorded because they were not stated explicitly):
- Quality switching is manual (user-selected presets + Original). An automatic, bandwidth-driven mode is out of
  scope for this change and can be proposed later.
- Out of scope: music, live TV, downloads/offline, subtitles and audio-track selection beyond server defaults,
  Quick Connect, multiple saved servers, and iOS/tvOS targets.

## Capabilities

### New Capabilities
- `server-connection`: connecting to a Jellyfin server, signing in, persisting/restoring the session, signing out.
- `library-browsing`: listing libraries and navigating their items (movies, series, seasons, episodes, continue watching).
- `media-playback`: starting, resuming, and stopping video playback, and reporting playback state to the server.
- `playback-quality`: the set of quality options, the default quality, and switching quality during playback.

### Modified Capabilities
<!-- None: this is the first change in the project; no specs exist yet. -->

## Impact

- New code: a Swift package for the Jellyfin API client and quality logic, plus a macOS SwiftUI app target.
- External API: Jellyfin server REST API (authentication, user views, items, PlaybackInfo, video streaming/HLS,
  session reporting, active-encoding cleanup).
- System frameworks: SwiftUI, AVFoundation/AVKit, Security (Keychain). No third-party runtime dependencies.
- Tooling: XcodeGen to generate the Xcode project; GitHub Actions macOS runner for build and tests.
