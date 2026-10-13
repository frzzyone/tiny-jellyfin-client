# Proposal

## Why

The Mac app is the only way to use Tiny Jellyfin, and the phone is where most casual watching
happens. Most of the code is already portable: JellyfinKit is Foundation only, PlayerCore's engine
uses no AppKit, and the Apple renderers it feeds (`AVSampleBufferDisplayLayer`, the audio
renderer, the synchronizer, VideoToolbox) exist on iOS with the same API.

## What Changes

- A new iPhone app target (iOS 17+, matching the Mac's macOS 14 floor) in the same project,
  sharing JellyfinKit, PlayerCore, and the app-level models (`SessionModel`, `PlaybackController`,
  `HomeModel`, `BrowserModel`, `LibraryGridModel`).
- FFmpeg built for iOS as an XCFramework (device arm64 + simulator arm64), LGPL-only as on the Mac,
  by the same script.
- Audio that the phone can play: Dolby formats are handed to the system decoder where iOS has one,
  everything else is decoded to PCM by FFmpeg; no passthrough on the phone.
- An iPhone UI: sign-in, a Home tab with the same rows as the Mac (resume hero, Continue watching,
  Next up, Added this week, discovery rows), Movies and Shows tabs, search, a detail sheet in place
  of the Mac's quick look, and a full-screen landscape player with touch controls (tap to show,
  double-tap sides to skip, drag to scrub), quality and subtitle menus, PiP and Now Playing.
- The Mac app does not change.

Assumptions:
- **Distribution is personal: Xcode or TestFlight, not the App Store.** FFmpeg is LGPL; on iOS the
  library cannot be swapped by the user, and whether that is acceptable on the App Store is
  unresolved. Revisit before any public release.
- iPhone only. iPad runs the iPhone layout scaled; an iPad layout is a later change.
- One server and one user, as on the Mac. No downloads or offline play.

## Capabilities

### New Capabilities
- `iphone-app`: the app on iPhone: what it runs on, its navigation, the touch player, audio on the
  phone, and background behaviour.

### Modified Capabilities
<!-- None: the existing specs describe behaviour, and the iPhone app meets them as written
     except where `iphone-app` says otherwise (touch instead of keyboard, sheet instead of quick
     look). -->

## Impact

- `scripts/build-ffmpeg.sh` gains an iOS mode producing `Vendor/FFmpeg/FFmpeg.xcframework`.
- `Packages/*/Package.swift` add `.iOS(.v17)`; PlayerCore links the XCFramework on iOS.
- `App/` splits into `Shared/`, `macOS/` and `iOS/`; `project.yml` gains `TinyJellyfin-iOS`.
- CI gains an iOS simulator build and PlayerCore tests on the simulator.
- `openspec/config.yaml` context ("Native macOS app") is updated to "macOS and iPhone".
