## Why

Five reviews (App Store rules, release builds, the engine, security, user experience) asked whether
Tinyfin could go to the App Store. The code was sound, but the submission scaffolding was missing,
and they found a token that could reach the system log, sign-in that failed on the most common home
setup, and engine races reachable by ordinary use.

## What Changes

- Submission: privacy manifests (UserDefaults, the TV's App Group, FFmpeg's file stats), export
  compliance, the local-network prompt text on every target, one version for every target.
- Sign-in: an address typed without a scheme tries `https://`, then `http://`; an untrusted
  certificate says so instead of "not a Jellyfin server"; a proxy's HTML error page or a stack
  trace is no longer shown as the message.
- Security: a failed stream request's error keeps only its code, never the URL (transcode URLs
  carry the access token).
- Engine: a seek during a quality switch gives the switch up (the controller restarts at the new
  position); overlapping seeks end on the newest; a cancelled open stops at once; an HLS seek
  reopens at the target rather than probing from the start; the position shows the seek target
  while the reader repositions.
- Controller: a transcode asked for but never playing (the player closed while opening, or the
  start failed) is ended on the server.
- The Mac app ships as Developer ID, outside the store (no sandbox needed); the name and icon are
  Tinyfin's own: no "Jellyfin" or its logo shape (Jellyfin's branding guide; it also discourages
  "…fin" names, a request Tinyfin knowingly sets aside).

## Impact

project.yml, `App/Resources/**/PrivacyInfo.xcprivacy`, JellyfinKit (`ServerAddress`, `SessionModel`,
`JellyfinClient`, `JellyfinError`), PlayerCore (`HTTPByteSource`, `FFmpegEngine`, `Pipeline`),
`PlaybackController`.
