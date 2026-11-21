# Proposal

## Why

Builds 18–22 (iPhone and Apple TV 1.3.0, now in App Review) and Mac 1.3.1 shipped a run of fixes as
plain commits, each with its test but without a change. Two of them change what a user sees (a tap
in the iPhone player, the screen staying on while a film loads) and one changes what the specs should
promise (memory while playing a downloaded film), so the specs no longer describe the app exactly.
This change writes them up after the fact; everything in it is already implemented.

## What Changes

- **iPhone player taps work again.** Since hold-to-2× landed, a touch-down started the hold and the tap
  gesture lost to it, so a tap no longer showed or hid the controls. The hold now begins only after
  the finger has stayed still for half a second, and taps are recognised alongside it.
- **The screen stays on while a film loads.** The video layer keeps the display awake only while frames
  move, so a slow start or a stall let the iPhone lock and the Apple TV start its screensaver before the
  picture came. The idle timer is now held off while loading, buffering or playing.
- **Playing a downloaded film no longer keeps what it read.** The reader thread never drained its
  autorelease pool, so a local file kept every byte read until playback ended (about 1 GB every
  17 minutes at 8 Mbps). Streams over HTTP were not affected.
- **The Apple TV flight recorder is gone.** It was added for TestFlight to catch memory kills and sent a
  log to the user's own server after an unfinished playback; a shipping app shouldn't do that unannounced.
  `JellyfinClient.uploadClientLog` went with it.
- **Less work for the same result** (no behaviour change): artwork cache of 32 MB in memory and 256 MB on
  disk; hidden hover and focus shadows with radius 0; home rows and grids no longer ask for every file's
  track lists; picture subtitle files and download probes leave the main thread; the player reads
  subtitles from a snapshot instead of waiting on the engine queue; the engine polls the renderers only
  when more is needed; the letterbox detector waits its interval when it finds no bars.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `iphone-app`: the hold to 2× starts after half a second held still, and a tap still shows or hides the
  controls.
- `media-playback`: the screen stays awake while a film loads, buffers or plays on iPhone and Apple TV;
  playing a file keeps no more memory than its buffers, however long it plays.

## Impact

- `App/iOS/PhonePlayerView.swift` (gestures, keep-awake), `App/tvOS/TVPlayerView.swift` (keep-awake),
  `App/Shared/Player/PlayerPieces.swift` (`PlayerStatus.keepsScreenOn`, `View.keepsScreenOn`).
- `Packages/PlayerCore/.../Apple/Pipeline.swift` (reader autorelease pools), `FFmpegEngine.swift`
  (subtitle snapshot, feeding cadence).
- `App/Shared/AppModel.swift` (URL cache), `Cards.swift` and `TVTabsView.swift` (shadows),
  `LetterboxDetector`, `Downloads.swift`, `PlaybackController.swift`, JellyfinKit `Endpoints.swift`
  (list fields, removed client log upload).
- Removed `App/Shared/Player/FlightRecorder.swift` and its BACKLOG entry.
- No new dependencies; no server or API changes beyond requesting fewer fields.
