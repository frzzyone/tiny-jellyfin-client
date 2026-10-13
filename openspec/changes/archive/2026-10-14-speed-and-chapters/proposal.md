## Why

The last open part of review item 18: no way to watch faster or slower, and no way to reach a
film's chapters, which Jellyfin already provides.

## What Changes

- Speed 0.75×, 1×, 1.25×, 1.5× and 2×, with the audio's pitch kept; back to 1× for each new item.
- Chapters from the server (single-item request), listed with their start times; picking one
  jumps there. Hidden when an item has fewer than two.
- Mac: a speed menu showing the current speed and a chapters menu in the control bar, and both in
  the menu bar's Playback menu. iPhone: "Chapters" and a speed chip. Apple TV: Chapters and Speed
  tabs in the panel.

## Impact

`FFmpegEngine.speed` (synchronizer rate, spectral time-pitch), `BaseItem.chapters`,
`PlaybackController` (`speed`, `chapters`, `currentChapter`, `jump(to:)`), shared menu items, the
three players.
