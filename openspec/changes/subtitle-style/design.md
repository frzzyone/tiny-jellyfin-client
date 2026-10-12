# Design

## Context

`SubtitleOverlay` (App, `PlayerWindowView.swift`) laid the text out in a `GeometryReader` over the
whole player view: bottom-aligned with 7% of the view height below it and a font of 4.5% of the view
height. The window normally takes the video's shape, so this only went wrong where it cannot: full
screen, Picture in Picture, and while resizing. It also goes wrong whenever the black bars are part
of the frames, which no window shape can fix: the player does not know where the image ends.

## Goals / Non-Goals

- Text inside the image, sized by the image, in both the letterbox-by-window and bars-in-the-frame
  cases. Pure geometry, unit-tested; the pixel scan unit-tested on synthetic frames.
- Nothing that can make subtitles jump around during a film.
- Non-goals: font choice, colour/outline options, side (pillarbox) bars, ASS styling.

## Decisions

### D1. `SubtitleLayout.pictureRect(video:in:bars:)`
A pure function: the aspect-fitted rectangle of the video inside the overlay's bounds (the whole
bounds when the video size is unknown), then inset at the top and bottom by the bar fractions.
`SubtitleOverlay` positions a frame of that size at that origin and keeps the old proportions
relative to it: 7% of the image height below the text, 8% of the image width as side margins. The
font is `SubtitleFont`: Helvetica Neue, 48 pt × image height / 1080, never under 12 pt.
`SubtitleRenderTests` renders the overlay offscreen with `ImageRenderer` and checks which rows hold
white pixels, so "the text is inside the picture" is asserted, not eyeballed.

### D2. Bars are measured from the displayed frame
`PlaybackEngine.copyDisplayedFrame()` returns the renderer's current pixel buffer
(`displayedPixelBuffer()`, macOS 14.4+; nil before). `LetterboxDetector.bars(in:)` locks the luma
plane and finds the first and last rows with picture in them: a row counts when at least 2% of its
sampled columns (every 8th) are above luma 32 on an 8-bit scale, at least two of them. 10-bit planes
keep their bits at the top of 16-bit samples, so `>> 8` puts them on the same scale. A frame whose
picture rows are under 30% of its height says nothing (a fade, a credits card).

### D3. Bars only narrow, and are used once two looks agree
`PlaybackController` looks at the frame every 2 s while playing. Each result is combined with the
running estimate by taking the smaller bar on each edge: a dark scene can only make bars look
bigger, never smaller, so the minimum converges on the true bars. The estimate is published after
the second look, so one dark frame at the start cannot place the subtitles halfway up the screen.
The cost is a stray bright pixel in a bar (a logo, a burned-in subtitle) shrinking that bar for the
rest of the item; accepted. The estimate is reset when playback stops and survives quality switches.

## Risks / Trade-offs

- `displayedPixelBuffer()` can return nil for protected or unavailable frames; detection then
  simply does not happen and the text sits at the frame's bottom, as before.
- Reading a frame every 2 s is one IOSurface lock and a scan of ~1/8 of one plane; negligible.
