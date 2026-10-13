# Backlog

Things we know about and have chosen not to do yet. Each should become its own OpenSpec change
(`/opsx:new`) when picked up.

## Player UI (from the 2026-10-12 UX review)

- **Library polish.** Standard grid and list, no poster hover state, no year/rating overlay, a
  left-aligned details block. Functional, but the least finished-looking part of the app.

## Subtitles (from the 2026-10-12 subtitle-style change)

- **Picture subtitles in the bars.** The app now draws PGS/DVD/DVB itself during Direct Play, where
  the disc placed them, which on a scope film can be inside the black bar of a 16:9 frame. Moving
  them above detected bars (as text subtitles do) is possible now that we hold the bitmaps.
  Transcodes still burn them in, on purpose: drawing them during a transcode would need the
  server to extract the track as a `.sup` file first, which reads the whole file (a minute or
  more for a 4K remux). Decided 2026-10-14: a wait like that is not acceptable.
- **The first bar reading can step.** Bars encoded in the frames are applied after two looks (4 s);
  a dark opening shot can place the text high for 2 s before a brighter frame narrows the bars.
  Waiting for more agreeing looks, or easing the move, would hide it. Decide after seeing it.
- **Verification owed:** `openspec/changes/archive/2026-10-12-subtitle-style/manual-checklist.md` and `openspec/changes/archive/2026-10-13-browser-home/manual-checklist.md`.

## iPhone

- **From the production review (2026-10-13), not yet decided:** Dynamic Type for the
  browser text, PiP restore-to-app.
- **iPad** would want a layout closer to the Mac's; the phone layout only stretches today.
- **App Store** distribution: LGPL FFmpeg under code signing is unresolved; the app is for your own
  devices.

## Apple TV

- **Scrub previews** (trickplay thumbnails while swiping) and holding left/right to scrub.
- **Siri and system search** ("play Troy"), user profiles, server discovery: left out of the first version.

## Playback engine

- **Trim the HLS playlist before handing it to FFmpeg.** On a transcoded start FFmpeg fetches
  segment 0 to detect the format, which the server has to encode for nothing (~3 s of the ~5.5 s
  start). Rewriting the playlist to begin at the resume point would remove that, at the cost of
  owning playlist parsing. Declined for now; revisit if transcoded starts feel slow. Seen on
  2026-10-13 against a slow server: a quality switch spent 8 of its 17 s opening on segment 0.
- **AV1 transcodes, HEVC as the fallback.** Jellyfin only sends AV1 in fMP4 HLS segments, and
  our FFmpeg 7.1 neither seeks HLS with fMP4 segments nor reads AV1 from MPEG-TS. Needs FFmpeg 8.x
  (or an engine workaround for fMP4 seeks), fMP4 segments requested with `av1,hevc,h264`, and the
  MPEG-TS invariants (the 10 s offset, open and seek paths) rechecked with new fixtures. Gain:
  ~20–30% less bitrate for the same picture, mostly on the low presets.
- **Atmos fallback.** If E-AC-3 passthrough ever fails on some output, decode to multichannel PCM
  instead. One-line change, not needed until someone sees it fail.

## Tests

- **`testClocksStayInSync` fails on a Bluetooth output device.** It measures the audio renderer's
  clock against real time; Bluetooth adds ~0.2 s of latency and the clock lags accordingly. Either
  skip it when the default output is Bluetooth, or route the test engine to a null device.

## Verification still owed

The first change was archived with 15 of its 48 tasks unverified by a person (they need a screen,
speakers, or specific files). The list is in
`openspec/changes/archive/2026-10-12-add-macos-jellyfin-client/manual-checklist.md`. Anything that
fails there is a bug, not backlog.
