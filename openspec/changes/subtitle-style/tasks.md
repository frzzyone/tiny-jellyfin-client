# Tasks

## 1. Layout

- [x] 1.1 Add `SubtitleLayout.pictureRect(video:in:bars:)` and verify unit tests for letterbox, pillarbox, exact fit, unknown size and bars in the frame
- [x] 1.2 Make `SubtitleOverlay` position and size the text against the picture rect in Helvetica Neue 48, and verify with an offscreen render that the text rows lie inside the picture (`SubtitleRenderTests`)
- [ ] 1.3 Verify manually with a 2.39:1 film in full screen (text inside the picture) and a 16:9 window (unchanged)

## 2. Bars in the frames

- [x] 2.1 Add `LetterboxDetector` over a decoded frame's luma plane and verify unit tests on 8-bit and 10-bit frames: bars found, dim picture still counts, stray pixels ignored, mostly black frames rejected
- [x] 2.2 Expose the displayed frame from the engine and have `PlaybackController` sample it every 2 s while playing, narrowing the estimate, publishing after two looks and stopping once ten looks leave it unchanged; verify controller tests that bars narrow but never widen, reset on stop, and are no longer measured once settled
- [ ] 2.3 Verify manually with a file whose bars are encoded in the frames: the log shows `Picture bars: …` within a few seconds and the subtitles sit above the bar, and stay there through a fade to black. (Checked against the server with a 16:9 documentary: `Picture bars: 3.1% top, 0.0% bottom` 2 s after playback started, then narrowing; a letterboxed file and the screen still need a person.)

## 3. Transcodes

- [x] 3.1 Report the picture size for transcoded streams once the first keyframe resolves the format (`Pipeline.presentationSize`, engine tick, controller refresh), so the window takes the video's shape and the overlay uses the picture rect; verify a controller test that the size arrives after open
- [ ] 3.2 Verify manually on a transcoded start: the log shows `Video size known after open: …` and then `Window …: resizing …`, and the window takes the video's shape
