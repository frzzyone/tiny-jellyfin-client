## Why

Blu-ray remuxes carry their subtitles as pictures (PGS). The server could only show them by
burning them into the video, which re-encodes the whole film: on the test server, Avatar (4K AV1
HDR10, TrueHD Atmos, 43 PGS tracks and no text ones) became a 4K HEVC SDR transcode with
re-encoded audio, because its default English track is PGS. The app plays everything else in
that file as it is.

## What Changes

- FFmpeg's PGS, DVD and DVB subtitle decoders join our build (LGPL, as before).
- During Direct Play the engine decodes the selected picture track (only that one; selecting
  another re-reads from the clock) into a bounded store, and the player draws the images on the
  video frame where the disc placed them, scaled with the picture (and with the iPhone's fill).
- The device profile tells the server picture subtitles can be embedded, so it sends such files
  as they are. Transcodes still burn them in: Jellyfin never embeds subtitles in HLS.
- Every new stream asks for the selected picture subtitle; whether it comes embedded or burnt in
  is read from the stream (`burnedInSubtitle`).
- The FFmpeg build script rebuilds a platform when its configure flags change.

## Impact

`scripts/build-ffmpeg.sh` (and a rebuilt `Vendor/FFmpeg`), PlayerCore subtitles, pipeline and
engine API (`subtitleBitmap(at:)`), `PlaybackController`, `SubtitleOverlay`, the device profile,
a hand-written PGS fixture in `make-fixtures.sh`.
