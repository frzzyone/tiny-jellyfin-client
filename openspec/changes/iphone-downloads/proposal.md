# Proposal

## Why

A phone is where films are watched away from the server: on a plane, on the underground, abroad
on a data cap. Today the iPhone app does nothing without a connection. Netflix taught people the
answer: tap Download, and the title is there later with no signal, and the next episode is waiting
when you finish one.

## What Changes

- **Download** on the iPhone for films and episodes, from the detail sheet and from each episode
  in a season. The copy is phone-sized: the server makes a 1080p copy of about 8 Mbps with the
  user's audio track (about 3.5 GB an hour). A file that is already that small and plays as it is
  is downloaded as the original instead: an exact copy that also resumes after an interruption.
- Downloads run in the background, on Wi-Fi only, and survive the app being closed. The button
  shows the expected size before, the progress during, and a tick after.
- A **Downloads** tab: films and series (series open to their downloaded episodes), each with
  its size and progress; swipe to delete. Signing out deletes every download.
- **Offline playback** with the same player: the downloaded copy plays whether or not the server
  is reachable. The quality menu is hidden for a download. Text subtitle tracks and the default
  picture subtitle come with it.
- **Progress comes back**: where you stopped, and what you finished, is saved on the phone and
  sent to the server once it can be reached, unless another device has watched it since.
- **Smart Downloads**, always on: finishing a downloaded episode deletes it and downloads the next
  unwatched episode of the series, next time the phone is on Wi-Fi.
- **Downloads for you**, always on, so there is always something ready to watch. The app keeps
  these downloaded:
  - the next unwatched episode of each of the first 3 shows in Next up;
  - the film at the top of Continue watching.

  It downloads only on Wi-Fi, only while the phone has room, and up to about 15 GB in all. These
  titles are marked "Downloaded for you" and leave once watched or no longer in those rows. A
  title deleted by hand is not picked again. The user's own downloads are never touched.
- Opened with no connection, the app goes straight to Downloads.
- No settings: the quality, Wi-Fi only, Smart Downloads and Downloads for you are fixed defaults.
- The Mac and Apple TV apps do not change.

Assumptions:
- Downloads count on the server's transcoder for most titles: the download goes as fast as the
  server encodes, and an interrupted server copy starts over.
- One audio track per server copy. The original keeps every track.
- No expiry, no download limits, no "download whole season" button (episodes are downloaded one by
  one, and Smart Downloads keeps the next one coming).

## Capabilities

### New Capabilities
- `iphone-downloads`: downloading films and episodes to the iPhone, the Downloads tab, playing
  them offline, sending progress back, Smart Downloads, Downloads for you, and opening without a
  connection.

### Modified Capabilities
- `iphone-app`: the tabs gain Downloads (Browsing on iPhone), and the player hides Quality for a
  downloaded copy (Touch player).

## Impact

- `App/iOS`: Downloads tab, download buttons on the detail sheet and episode rows, the app delegate
  hands background-session events to the downloader, offline launch.
- `App/Shared` (iOS-only parts behind `#if os(iOS)`): the download store and manager (background
  `URLSession`), a `PlaybackService` that serves the local copy, the progress queue.
- `JellyfinKit`: a download DeviceProfile (progressive MPEG-TS, not HLS), the user-data update
  call, and Next up for one series (already there).
- `PlaybackController`: no quality options when the service says so; otherwise unchanged.
- `App/iOS` also registers a background refresh task, so Downloads for you can top up without the
  app being opened. iOS decides when that runs.
- Server load: each download of a large file is one full transcode on the server. Downloads for
  you adds up to four of them whenever Next up moves on, one at a time.
- Storage: the app's Application Support folder, excluded from iCloud backup.
