# Proposal

## Why

There is no lightweight, native macOS Jellyfin client: the options are the web UI in a browser tab or heavy
cross-platform apps. The goal is an Infuse-like experience for Jellyfin: play files as-is, with native HDR,
Dolby Vision and Atmos, in a small Mac-native app. The one feature that matters most on mixed networks (laptop
on Wi-Fi, travel, remote server) is letting the user pick the streaming quality on the fly instead of being
stuck with whatever the server picks.

## What Changes

- New native macOS app (SwiftUI, macOS 14+) that connects to a self-hosted Jellyfin server.
- Sign in with server URL + username/password; the session is kept securely and restored on relaunch; sign out.
- Browse the user's libraries: movies, TV shows (series → seasons → episodes), and a "Continue Watching" row.
- An Infuse-style playback engine: FFmpeg reads the file (MKV, MP4, MOV, TS, WebM…) and hands compressed
  video to macOS's hardware decoder and display layer, and audio to the system audio renderer. Most files play
  as-is, with no server conversion. Anything the engine cannot handle yet is converted by the server.
- Native-quality output: HDR10/HLG on EDR displays, Dolby Vision (Profiles 5 and 8), and Dolby Atmos (E-AC-3)
  passed through to the system.
- A custom SwiftUI player (play/pause, scrubber, skip, volume, full screen, keyboard shortcuts) with native
  Picture in Picture, Now Playing and media-key support.
- Text subtitles (embedded and external) with track selection; image-based subtitles are burned in by the server.
- Resume from the last watched position, and playback progress reported to the server so watch state stays in
  sync with other Jellyfin clients.
- **Quality switching**: during playback the user can choose "Original" (the file as-is whenever the engine
  supports it) or a fixed bitrate/resolution preset (e.g. 1080p 10 Mbps, 720p 4 Mbps, 480p 1.5 Mbps).
  Switching keeps the position, the old stream keeps playing until the new one is ready, the player shows the
  active quality and play method, and the last choice becomes the default for future playback.

Assumptions (recorded because they were not stated explicitly):
- Quality switching is manual (user-selected presets + Original). An automatic, bandwidth-driven mode is out of
  scope for this change and can be proposed later.
- Out of scope for v1: software video decoding (VC-1, MPEG-2, VP9, AV1 on Macs without an AV1 hardware decoder
  are converted by the server), local rendering of image subtitles, styled ASS rendering (shown as plain text),
  Dolby Vision Profile 7 enhancement layers (the HDR10 base layer plays), audio-track selection (server default
  track is used), music, live TV, downloads/offline, Quick Connect, multiple saved servers, iOS/tvOS targets.

## Capabilities

### New Capabilities
- `server-connection`: connecting to a Jellyfin server, signing in, persisting/restoring the session, signing out.
- `library-browsing`: listing libraries and navigating their items (movies, series, seasons, episodes, continue watching).
- `media-playback`: starting, controlling, resuming, and stopping playback, system integration (PiP, Now Playing,
  media keys), and reporting playback state to the server.
- `playback-formats`: which containers and codecs play locally, server fallback for the rest, and HDR, Dolby
  Vision and Atmos output.
- `subtitles`: showing text subtitles, choosing subtitle tracks, and server burn-in for image subtitles.
- `playback-quality`: the set of quality options, the default quality, and switching quality during playback.

### Modified Capabilities
<!-- None: this is the first change in the project; no specs exist yet. -->

## Impact

- New code: a Swift package for the Jellyfin API client and quality logic, a macOS-only playback-engine package,
  and a macOS SwiftUI app target.
- External API: Jellyfin server REST API (authentication, user views, items, PlaybackInfo, static and HLS
  streams, subtitle delivery, session reporting, active-encoding cleanup).
- System frameworks: SwiftUI, AVFoundation (AVSampleBufferDisplayLayer/AudioRenderer/RenderSynchronizer, PiP),
  CoreMedia, VideoToolbox, MediaPlayer (Now Playing), Security (Keychain).
- New dependency: FFmpeg (libavformat, libavcodec, libavutil, libswresample), LGPL-only build distributed as an
  xcframework, with licence notice and build script in the repository.
- Tooling: XcodeGen to generate the Xcode project; FFmpeg build script; GitHub Actions macOS runner for build and tests.
