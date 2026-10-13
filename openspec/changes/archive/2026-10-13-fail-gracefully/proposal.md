## Why

Testing against a real server whose transcodes ran at about real time (and then, misconfigured,
failed outright) showed four ways the player failed badly:

- A quality switch whose new stream couldn't catch up just gave up after 20 s, and left the
  server encoding that stream for nobody.
- When the server answered a segment with HTTP 500, the player kept retrying and skipping
  segments behind the spinner for minutes instead of saying so.
- A film whose default subtitle is a picture track started two identical burned-in streams: the
  server burns its default in, and the app, not knowing, asked for it again.
- "Off" after a burned-in subtitle asked for no particular subtitle, which lets the server burn
  in its default again.

## What Changes

- A switch that times out falls back to stopping the old stream and starting the new quality at
  the same position (a short wait, like a seek), keeping the subtitle and pause. A switch that
  fails for another reason keeps playing as before, and its stream is stopped on the server.
- HTTP 500 and other definitive statuses fail the stream at once with the server's answer; only
  408, 429 and 502–504 are retried. Opening a stream gives up after 60 s.
- The app reads which subtitle the server burns into a stream, and asks for none (`-1`) when
  subtitles are turned off.

## Impact

PlayerCore (`HTTPByteSource`, `MediaIO`, `Demuxer`, `FFmpegEngine`), JellyfinKit
(`ResolvedStream.burnedInSubtitle`), `PlaybackController`, the test server (`?segstatus=`).
