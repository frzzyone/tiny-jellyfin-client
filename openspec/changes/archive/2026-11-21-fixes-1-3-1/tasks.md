# Tasks

All implemented before this change was written; each box names its commit.

## 1. Memory

- [x] 1.1 Reader thread: an autorelease pool around each `readPacket()` and `route(packet)`; `testReadingAFileKeepsNothingOfWhatItRead` (6b0bccf; the test comment corrected to "local files only" in f54c24e)

## 2. iPhone and Apple TV player

- [x] 2.1 Hold to 2×: a 0.5 s long press sequenced before a drag, driving `@GestureState`; the tap and double-tap composition made simultaneous; checked by a UI test in the simulator (cc207d5)
- [x] 2.2 Keep-awake: `PlayerStatus.keepsScreenOn` and `keepsScreenOn(while:)` on the iPhone and Apple TV players; `testTheScreenStaysOnUntilThePictureComes` (cc207d5)
- [x] 2.3 Remove the Apple TV flight recorder, `uploadClientLog` and its test, and the BACKLOG entry (6db6e0d)

## 3. Less work, same behaviour

- [x] 3.1 Artwork cache of 32 MB in memory and 256 MB on disk, `testArtworkCacheHoldsMoreThanARow`; hidden hover and focus shadows with radius 0 (6b0bccf)
- [x] 3.2 Home rows, grids, similar items and season lists no longer ask for `MediaSources`/`MediaStreams`; PGS files and download probes leave the main actor; download posters come first and are retried on every sync (e163eec)
- [x] 3.3 Subtitle reads from a snapshot under `snapshotLock`; feeding looks again only when more is needed (at most 0.5 s on); Thread Sanitizer clean on `EngineTests` (ab9966e)
- [x] 3.4 Letterbox looks wait their interval when they find no bars (2e7e75c)

## 4. On devices

- [x] 4.1 On a real iPhone: taps show and hide the controls, a double-tap skips, a half-second hold plays at 2×, and the phone doesn't lock during a slow start but does once paused (confirmed by the user on their devices, 2026-11-21)
- [x] 4.2 On a real Apple TV: the screensaver doesn't start while a film loads (confirmed by the user on their devices, 2026-11-21)

## Workflow follow-up

- Archive with `/opsx:archive fixes-1-3-1` once 4.1 and 4.2 are checked, so the deltas fold into `openspec/specs/iphone-app` and `openspec/specs/media-playback`.
