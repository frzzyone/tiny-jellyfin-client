# Tasks

## 1. Players

- [x] 1.1 iPhone: sideways swipe scrubs with a time readout, pinch fills/fits (review 13, 14); verify by build, gestures on a device
- [x] 1.2 Mac: single click pauses, trackpad scrub, S and 0–9, controls under the pointer, window title, ended state (review 19, 33); verify with controller tests (subtitle cycle, digit jumps)

## 2. Browsing

- [x] 2.1 Discovery rows in library tabs on Mac, iPhone and TV (review 20); verify with HomeModel tests and screenshots against the server
- [x] 2.2 Empty Home message, Mac Surprise errors, password cleared on every failure, AccentColor (review 21, 24, 26, 32)

## 3. Engine and hygiene

- [x] 3.1 Cancelled switch backs out after the splice is chosen; AudioDecoder lock (review 29); verify with `testCancelledSwitchBacksOutAfterChoosingTheSplice`
- [x] 3.2 Drop the hero-title log line, delete dead code, fix the two warnings (review 23, 27, 28)
