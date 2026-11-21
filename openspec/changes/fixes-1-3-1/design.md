# Design

## Context

Written after the fact: every decision below is already in the code. See proposal.md for why each fix
was needed.

## Goals / Non-Goals

**Goals:** record why each fix took the shape it did, so a later change doesn't undo it.

**Non-Goals:** smoother Apple TV focus animation and any change to the incoming stream's buffer cap.
Both were considered alongside these fixes and left out (see Decisions).

## Decisions

**Autorelease pool per read on the reader thread.** `Pipeline`'s reader is a Foundation `Thread` with no
run loop, so its autorelease pool drains only when the thread exits. Every `Data` a `FileHandle` read
returned (local files: iPhone downloads, test fixtures) lived until playback ended. `readPacket()` and
`route(packet)` (which decodes audio and subtitles) now each run inside `autoreleasepool`. HTTP sources
never leaked, because URLSession hands over memory that isn't autoreleased on that thread.
`testReadingAFileKeepsNothingOfWhatItRead` reads a fixture 300 times over, seeking back each time, and
fails on growth over 50 MB. Alternative considered: halving the incoming stream's buffer cap. Rejected,
because the HTTP path was already bounded and the cap is what absorbs a slow server.

**Keep-awake from the player's status, not the video layer.** `preventsDisplaySleepDuringVideoPlayback`
only works while frames are being presented, so it doesn't cover loading or a stall.
`PlayerStatus.keepsScreenOn` is true for loading, buffering and playing, and a `keepsScreenOn(while:)`
view modifier mirrors it into `UIApplication.isIdleTimerDisabled`, then clears it on disappear. iPhone
and Apple TV share it. The Mac is out of scope: it has no idle timer, and its display sleep wasn't reported as a
problem. `testTheScreenStaysOnUntilThePictureComes` covers the status mapping.

**Hold as a sequenced gesture; taps simultaneous.** In SwiftUI, a `.gesture` attached outside a stack of
`.simultaneousGesture`s loses to them. The hold's drag began at touch-down, so the tap and double-tap
composition never fired. The hold is now `LongPressGesture(minimumDuration: 0.5, maximumDistance: 10)`
sequenced before a zero-distance drag, which drives a `@GestureState` that resets on lift, and the
tap composition is a `.simultaneousGesture` too. Making only the hold sequenced did not fix taps; the
precedence did. A UI test in the simulator checked taps in the centre, left and right, hold to 2×, the
"1×" button and a double-tap skip. That test isn't committed, because it needs the demo server.

**Remove the flight recorder outright** rather than gating it behind a flag. The app has no settings,
and a TestFlight-only code path would ship in the App Store binary anyway.

**Work avoided, not features changed.**
- Artwork: Jellyfin sends tagged images as immutable for a year, so a bigger `URLCache.shared`
  (32 MB memory, 256 MB disk) is all the caching needed.
- Shadows: a hidden shadow still blurs at its full radius, so hidden shadows use radius 0.
- List requests drop `MediaSources` and `MediaStreams`; only the download planner asks for them.
- PGS files and download probes are read off the main actor.
- Subtitles are read from a snapshot under `snapshotLock` instead of `queue.sync`.
- Feeding schedules its next look for when more is needed (at most 0.5 s on) instead of polling every
  20 ms.
- A letterbox look that finds no bars still waits its interval.

## Risks / Trade-offs

- A 256 MB disk cache counts against the app's storage on small phones → iOS purges caches under
  pressure.
- Disabling the idle timer while buffering could keep a stuck player's screen on → it clears when the
  player fails, pauses or closes.
- A hold now needs half a second before 2× starts → the UI test confirmed the hold still engages.
