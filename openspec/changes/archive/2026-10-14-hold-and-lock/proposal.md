## Why

Review item 17: two common touch-player habits the iPhone player lacked — holding the picture
to fast-forward through a dull stretch, and locking the screen so a pocket, a child or a
blanket can't pause or scrub.

## What Changes

- Holding a finger still on the picture for half a second plays at 2× (with a "2×" badge) until
  it lifts, then returns to the speed before. Moving the finger makes it a swipe as before; the
  lift after a hold is not a tap.
- A lock button in the top bar hides the controls and ignores gestures; a tap shows "Unlock" for
  3 s.

## Impact

`PhonePlayerView` (gestures, lock), `SpeedHold` in PlayerPieces.
