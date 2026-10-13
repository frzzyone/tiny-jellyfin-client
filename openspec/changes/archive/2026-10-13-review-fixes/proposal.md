# Review fixes (items 13–33 of the 2026-10-13 production review)

## Why

The production review left items the owner chose to fix after the first twelve: gestures and keys an
Infuse user expects, Mac player rough edges from the backlog, discovery rows the design promised for
the library tabs, and small correctness and hygiene items.

## What Changes

- iPhone player: a sideways swipe scrubs; a pinch fills or fits the screen.
- Mac player: a single click pauses; a sideways two-finger trackpad swipe scrubs; S cycles text
  subtitles and 0–9 jump by tenths; controls stay up under the pointer; the window is titled with the
  film; a finished film says so and offers Play Again and Close.
- Library tabs (Mac, iPhone, Apple TV) show two of the day's discovery rows for that library, the
  ones Home isn't showing first.
- Home says so when there is nothing to show; Mac Surprise me errors are shown; a failed sign-in
  always clears the password; the accent colour is in the asset catalog.
- Engine: a cancelled quality switch backs out even after choosing its splice point; the audio
  decoder's flush and decode are serialised.
- Hygiene: no titles in the log, dead code removed, the two Swift 6 warnings fixed.

## Impact

`App/Shared` (HomeModel, PlaybackController, cards, sign-in), `App/macOS`, `App/iOS`, `App/tvOS`,
`PlayerCore` (FFmpegEngine, AudioDecoder), `JellyfinKit` (dead code, `BaseItem: Hashable`).
