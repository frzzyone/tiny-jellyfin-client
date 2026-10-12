# Backlog

Things we know about and have chosen not to do yet. Each should become its own OpenSpec change
(`/opsx:new`) when picked up.

## Player UI (from the 2026-10-12 UX review)

1. **Controls hide while the pointer rests on them.** The 3 s auto-hide timer resets only on mouse
   movement, so a cursor parked on the play button loses the controls underneath it. Keep them
   visible while the pointer is over the control bar.
2. **Player window title.** `.hiddenTitleBar` leaves the title empty, so the Window menu and Mission
   Control show "Player". Set the item's name as the window title anyway.
3. **Single click on the video toggles play/pause.** Infuse and IINA do this; we deliberately don't,
   because a click that focuses the window would also pause. Decide, then do it or document why not.
4. **An "ended" state.** When a film finishes the last frame stays up with a play button that restarts
   from zero. Show something like "Watched · Play again", or close the window.
5. **Library polish.** Standard grid and list, no poster hover state, no year/rating overlay, a
   left-aligned details block. Functional, but the least finished-looking part of the app.

## Playback engine

- **Trim the HLS playlist before handing it to FFmpeg.** On a transcoded start FFmpeg fetches
  segment 0 to detect the format, which the server has to encode for nothing (~3 s of the ~5.5 s
  start). Rewriting the playlist to begin at the resume point would remove that, at the cost of
  owning playlist parsing. Declined for now; revisit if transcoded starts feel slow.
- **Atmos fallback.** If E-AC-3 passthrough ever fails on some output, decode to multichannel PCM
  instead. One-line change, not needed until someone sees it fail.

## Verification still owed

The first change was archived with 15 of its 48 tasks unverified by a person (they need a screen,
speakers, or specific files). The list is in
`openspec/changes/archive/2026-10-12-add-macos-jellyfin-client/manual-checklist.md`. Anything that
fails there is a bug, not backlog.
