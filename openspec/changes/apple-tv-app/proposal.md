# Proposal

## Why

The Mac and the iPhone cover the desk and the couch-with-a-phone, but films are watched on the TV.
Infuse's strongest platform is Apple TV, and our engine is built from the same Apple renderers
that exist there: `AVSampleBufferDisplayLayer`, the audio renderer, the synchronizer and
VideoToolbox all run on tvOS with the API the iPhone app already uses.

## What Changes

- A new Apple TV app target (tvOS 17+) in the same project, sharing JellyfinKit, PlayerCore and
  `App/Shared` with the Mac and iPhone apps.
- FFmpeg gains tvOS device and simulator slices in the same XCFramework, LGPL-only, same script.
- Sign-in suited to a remote: type the server address once, then approve a code from Jellyfin on
  a phone or the web (**Quick Connect**); a password stays as the fallback. No server discovery:
  the user's server is not on the home network.
- A focus-driven UI: a top tab bar (Tiny Jellyfin, one tab per library, Search), Home as shelves
  with a resume hero, full title pages (series show seasons and an episode shelf), library grids
  with filter pills, the tvOS search screen.
- A Siri Remote player in the Infuse manner: click to pause, click left/right to skip, swipe on
  the touch surface to scrub, swipe down for a Subtitles / Quality / Audio panel.
- The TV follows the film: frame rate and dynamic range are requested from the display when the
  user has Match Content on. Dolby audio goes to the system (Atmos reaches the receiver),
  everything else is decoded to multichannel PCM.
- **Top Shelf**: Continue watching and Next up on the Apple TV home screen, opening the title or
  playing it directly.
- The Mac and iPhone apps do not change in behaviour.

Assumptions:
- Distribution is personal (Xcode or TestFlight), as for the iPhone; the LGPL/App Store question
  stays open.
- One server and one user, as elsewhere. No profiles picker, downloads or server discovery.

## Capabilities

### New Capabilities
- `apple-tv-app`: the app on Apple TV: sign-in with Quick Connect, browsing with the remote, the
  remote player, matching the display, audio over HDMI, and Top Shelf.

### Modified Capabilities
<!-- None. The shared specs (browser, playback, subtitles) hold on the TV as written, except where
     `apple-tv-app` says otherwise (remote instead of keys or touch, a page instead of a sheet). -->

## Impact

- `scripts/build-ffmpeg.sh` gains `tvos` and `tvsim` slices.
- `Packages/*/Package.swift` add `.tvOS(.v17)`.
- JellyfinKit gains the Quick Connect calls and `SessionModel` a Quick Connect sign-in.
- `App/tvOS` (the app) and `App/TopShelf` (the extension); `project.yml` gains both targets, an
  App Group and a shared Keychain access group for the extension.
- `scripts/test-ios.sh` learns to run the package tests on an Apple TV simulator; CI builds the TV
  app for the simulator.
