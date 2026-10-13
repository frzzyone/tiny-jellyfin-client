## Why

On the iPhone the Quality and Subtitles menus closed by themselves when the controls faded 3 s into
playback, often before the user had chosen. A menu should close only when the user closes it.

## What Changes

- The two menus become popovers the player knows are open; while one is open the controls stay up.
- Choosing an option or tapping outside closes it, as before.

## Impact

`App/iOS/PhonePlayerView.swift`, the shared menu items in `App/Shared/Player/PlayerPieces.swift`.
