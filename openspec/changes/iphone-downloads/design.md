# Design

## Context

The engine already plays local files (`ByteSource` opens `file://` URLs, and FFmpeg is built with
the `file` protocol), including MPEG-TS. `PlaybackController` reaches the server only through
`PlaybackService` (item, stream, subtitles, images, reports), so a second implementation that
answers from disk lets the same player run with no connection. `SessionModel.restore()` works
offline: it reads the server address, user and Keychain token without a request, so an offline
launch already reaches `PhoneTabsView`, where Home and the libraries then fail.

`playbackInfo` sends a DeviceProfile whose only transcoding profile is HLS MPEG-TS. Jellyfin
decides Direct Play against `MaxStreamingBitrate` and the profile's limits, and `resolveStream`
already handles progressive (non-HLS) transcodes with a timeline starting at 0.

Scope: iPhone only. Everything new lives under `App/iOS`, or in `App/Shared` behind
`#if os(iOS)` where the player needs it.

## Goals / Non-Goals

**Goals:**
- One download path for every title. The server decides between the original and a copy, with
  the same PlaybackInfo call the player uses.
- The player plays a download with no download-specific code beyond hiding Quality.
- Progress written offline reaches the server, without overwriting newer progress.

**Non-Goals:**
- Downloads on the Mac or the TV; a season or series download button; expiry; storage quotas.
- Choosing the audio track or the quality of a download, or what Downloads for you picks.
- Resuming an interrupted server copy part-way (it restarts; see Risks).

## Decisions

### D1. Ask the server once: original or copy
A download calls `playbackInfo` with a download quality (1080p, 8 Mbps, not shown in the menu) and
a DeviceProfile whose transcoding profile is **progressive MPEG-TS over HTTP** (`protocol: "http"`,
`context: "Streaming"`, `container: "ts"`, H.264/HEVC video, AAC/AC-3/E-AC-3 audio up to 6 channels), with subtitle `-1`
so nothing is burnt in.
- **Direct Play:** download `/Videos/{id}/stream?static=true` (the original). It has a
  Content-Length and can resume.
- **Otherwise:** download the transcoding URL, a single `stream.ts` the server encodes while
  sending.

Alternatives considered:
- *HLS segments, fetched one by one and joined.* Each segment could be retried on its own, but a
  2-hour film is about 1,200 requests, which iOS throttles in a background session (it delays
  each task started while the app is suspended). Rejected.
- *`/Items/{id}/Download`.* Original only, and it depends on the user's download permission on
  the server. The static stream URL does the same job with the permission the player already uses.
- *fMP4 progressive.* MPEG-TS already plays and seeks in the engine without an index; fragmented
  MP4 has to scan its fragments.

The playSessionId is ended (`endEncoding`) when a server copy finishes, is cancelled or fails, as
the player does for streams it doesn't adopt.

### D2. Background URLSession, Wi-Fi only
`DownloadManager` (`App/iOS`) owns one background `URLSession`
(`app.tinyjellyfin.Tinyfin.downloads`) with `allowsCellularAccess = false`, `isDiscretionary = false`
and `sessionSendsLaunchEvents = true`, and uses download tasks with the `Authorization` header.
`PhoneAppDelegate` passes `handleEventsForBackgroundURLSession` to it.
- **Progress:** `countOfBytesReceived` against the expected size. That is the Content-Length for
  an original; for a copy it is an estimate (bitrate × runtime), capped at 99% until done.
- **Waiting for Wi-Fi:** an `NWPathMonitor` that sees no Wi-Fi turns a queued download's label
  into Waiting for Wi-Fi. The session itself waits; nothing is retried by hand.
- **Interruptions:** an original resumes from the error's resume data. A copy restarts from zero,
  up to 3 times, then fails with the reason. Not enough space (`NSURLErrorCannotWriteToFile` or a
  free-space check before starting) is its own message.

Alternative considered: a foreground session with `beginBackgroundTask`. It gets about 30 s of
background time, far short of a film.

### D3. On disk
Each download is a folder under `Application Support/Downloads/<itemId>/`, excluded from backup:
- `media.ts` or `media.<container>` — the video.
- `record.json` — one file holding two things:
  - the `BaseItem` with its `MediaSourceInfo` *as downloaded* (`DownloadedSource`). A copy keeps
    one audio stream and the subtitle tracks that came with it, marked external. An original keeps
    its own streams plus any downloaded external tracks.
  - the transfer: queued, downloading, done or failed, the bytes expected and received, the
    playSessionId, `timelineOffset`, and whose it is (`user` or `forYou`, D8).
- `poster.jpg` and `backdrop.jpg`.
- `sub-<index>.srt` and `sub-<index>.sup`.

The store also keeps `dismissed.json`: item ids of Downloads for you that the user deleted.

`DownloadStore` (portable, `App/Shared`) reads and writes these folders and is what the tests cover.
A folder per item rather than one manifest means a crash can damage at most one download.

Subtitles fetched with a download:
- every text track, as SRT, through the same URL the player uses;
- the server's default picture track, as `.sup`, when the server already has it extracted
  (`pictureSubtitleData` with the player's short wait). Others are left out.

Small files are fetched in the foreground when the download starts. If the app is suspended before
they finish, they are fetched again at the next launch.

### D4. `LocalPlaybackService`
A second `PlaybackService` built from a `DownloadStore` record:

| Call | Answer |
|---|---|
| `item(id:)` | the stored item, with the newer of the stored and the queued position |
| `resolveStream` | a `file://` URL, the stored source, playSessionId nil, timelineOffset 0; `.directPlay` for an original, `.transcode` for a copy |
| `subtitleData`, `pictureSubtitleData` | the stored files |
| `primaryImageURL` | the stored poster |
| reports | the progress queue (D5) |

With `.transcode`, the controller already takes subtitles from `subtitleData` instead of the file,
and leaves the engine's audio choice to the single track. The protocol gains
`var isDownloaded: Bool` (false by default). Set, the controller:
- offers no quality options;
- labels the delivery Downloaded;
- treats a picture track it can't draw as unavailable: no switch is tried, so it can't fall back
  to burn-in.

`AppModel.play` picks `LocalPlaybackService` whenever the item is downloaded, online or not.

Alternative considered: playing downloads online through the server. That breaks the spec ("plays
the downloaded copy") and wastes the data.

### D5. Progress queue
- **Recording:** `ProgressQueue` (`App/Shared`, one JSON file) keeps the latest record per item:
  position, played, and the time it was watched. `reportProgress` and `reportStopped` from
  `LocalPlaybackService` update it. A stop at 90% or more, or at the end, counts as played, the
  same threshold as Jellyfin's.
- **Flushing:** at launch, on return to the foreground, when `NWPathMonitor` sees a network, and
  after each stop. A flush reads the item from the server first. If the server's
  `userData.lastPlayedDate` is newer than the record, the record is dropped (watched elsewhere
  since). Otherwise it calls `POST /UserItems/{id}/UserData` with `PlaybackPositionTicks`,
  `Played` and `LastPlayedDate`, a new JellyfinKit call `updateUserData`.
- **Failures:** a failed flush keeps the record; one that succeeds removes it.

Alternative considered: replaying `Sessions/Playing/Stopped`. It stamps the time of the request,
not of the viewing, so Continue Watching would order offline viewing wrongly, and there is no
session to stop.

### D6. Smart Downloads
After a flush marks a downloaded episode played on the server, `SmartDownloads`:
1. deletes the episode;
2. asks `nextUp(limit: 1, seriesId:)`;
3. starts a download of the result when it is neither downloaded nor downloading.

It runs only after the flush, so Next up already accounts for the episode. Being on Wi-Fi is left
to the session (D2), so a Smart Download can be created on cellular and wait. The decision is a
pure function over the record and the Next up answer, and is tested on its own.

### D8. Downloads for you
A pure function plans what to keep:

```
plan(shows, resume, records, dismissed, freeBytes) -> (download: [item], delete: [itemId])
```

**Wanted** is taken in rounds from the first 3 series in Next up and the first 3 films in Continue
watching: the Next up episode of each series, then the first film; then each series' episode after
that and the second film; then the third of each. So every show has its next episode before any has
its third. Up to 9 episodes and 3 films, about 30 GB at the download quality. Items in `dismissed` are left out, and an item the user already downloaded counts
as ready and costs nothing.

**download:** wanted items not yet on the phone, taken in order while two limits hold:
- the estimated sizes of all `forYou` records plus the new ones stay within 30 GB;
- free space after each one stays at least 5 GB.

The first item that doesn't fit stops the list. Nothing jumps ahead of it, so the order holds.

**delete:** `forYou` records that are no longer wanted, other than one being played or with
progress still waiting to be sent.

**When it runs:**
- after every flush (D5), which keeps the server's Next up current;
- when Home refreshes;
- from a `BGAppRefreshTask` (`app.tinyjellyfin.Tinyfin.refresh`, asked for every 6 hours at the
  earliest), which flushes, plans and starts the downloads in the background session.

Each run reads `nextUp(limit: 3)` and `resumeItems` (films only), the calls Home already makes, and
for each Next up episode `/Shows/{series}/Episodes?startItemId=…&limit=3&isMissing=false`: that
episode and the ones after it, across seasons, without those missing from the library. Watched ones
are left out.
Free space comes from `volumeAvailableCapacityForImportantUsage`.

Smart Downloads (D6) becomes the same planner for one series. Its new download takes the finished
record's kind. Deleting a `forYou` record by hand adds the item to `dismissed`. A dismissed id is
forgotten once the item leaves Next up and Continue watching (`stillDismissed`): watched, or the
show moved on. It can then be picked again, as a later episode would be.

Alternatives considered:
- *A budget in hours.* Bytes are what fill a phone, and the estimate is already there.
- *Downloads for you only while the app is open.* That misses "ready by morning". The refresh
  task is the system's way of doing this, and the background session does the transfer.

### D7. UI
- **Detail sheet:** for a film or an episode, a `DownloadButton` under Play/Start over with four
  states:
  - Download · size;
  - progress ring with percent (or Waiting for Wi-Fi), where a tap offers Cancel;
  - Downloaded, where a tap offers Delete;
  - Failed, with the reason and Try again.

  The size comes from PlaybackInfo, asked for when the sheet opens. The episode rows in
  `SeasonView` show the same states as an icon.
- **Downloads tab:** after Search (the order Netflix uses). `List` sections with films and series;
  a series opens a list of its episodes. Swipe to delete. Each row shows the poster from disk,
  title, size and progress, plus a "Downloaded for you" caption on picks the app made. A footer
  explains them in one line: "Tinyfin keeps your next episodes and films ready on Wi-Fi, up to
  30 GB". The empty state says "Tap Download on a film or an episode."
- **Offline launch:** when `NWPathMonitor` reports no route at launch, `tab = "downloads"`.
  Home's and the libraries' error views gain Go to Downloads. With no connection, the detail sheet
  of a title that isn't downloaded hides Play.
- **Sign out:** flush (best effort, 5 s), then delete every download, the queue and the background
  session's tasks.

Mockups go to the user before any UI code is written (tasks.md 1.1).

## Risks / Trade-offs

- [Jellyfin ends a progressive transcode when nothing reads it, and iOS can pause background
  transfers] → A copy that is cut off restarts (up to 3 tries) and then reports the failure. A
  retry is a full new encode on the server. Verify against the user's server with a 2-hour film
  and the phone locked.
- [A copy cut off by the server can still end like a normal response, leaving a truncated file
  that looks complete] → At completion, check the received length against the estimate. Below 90%
  of it, open the file with the engine's demuxer and compare its duration with the runtime; more
  than 1% short counts as failed, with no retry: the server's encode failed (on the user's server
  a full 8.4 GB transcode disk cut a 2¼-hour film off twice at 8.1 GB), and a retry is another
  full encode. Try again starts it by hand.
- [Progressive MPEG-TS from Jellyfin starts its timestamps late] → **Measured: 1.44 s**, the
  MPEG-TS muxer's default delay, not the 10 s of its HLS segments. The engine uses timestamps as
  they are plus `MediaSource.timelineOffset`, so at the end of every download the file's
  `Demuxer.startTime` is read and stored in `record.json` as `timelineOffset = -startTime`. That is
  0 for most originals.
- [`/UserItems/{id}/UserData` doesn't exist on some 10.9 builds] → **Verified on the user's
  12.4.0:** `POST /UserItems/{id}/UserData?userId=` with `PlaybackPositionTicks`, `Played` and
  `LastPlayedDate` returns 200 and keeps the date as sent. `LastPlayedDate` can't be cleared to
  null. No fallback: the call came with the same 10.9 API generation as `/UserPlayedItems`, which
  the app already needs.

Measured against the user's server (12.4.0) on 2026-11-12:
- **Copy offered:** an AV1/DTS 1080p episode at 10.4 Mbps came back as `stream.ts` (H.264, 6-channel
  AAC, `VideoBitrate=7360000`) only with `Context: "Streaming"`. `Context: "Static"` gives no
  transcoding URL, on the demo server too.
- **Encode speed:** the server encoded at about 13× real time, with real output near 5.7 Mbps
  (about 2.6 GB an hour). The size shown before downloading (Video + Audio bitrate × runtime) is
  therefore an upper bound, so the button shows it as "~".
- **Original offered:** a 6.2 Mbps HEVC episode was Direct Play under the cap. Its static stream
  answers ranged requests (206 with `Accept-Ranges: bytes`), so an original can resume.
- **Downloading permission:** the demo server's user has `EnableContentDownloading: false`, and the
  static stream still plays, as D1 assumed.
- [A long encode keeps the server busy] → One copy at a time: further downloads wait in the queue.
  Originals can run alongside, since they are plain file reads.
- [Storage] → The size is shown before downloading. Automatic downloads stop at 30 GB and never
  take the phone below 5 GB free.
- [Downloads for you starts large transcodes the user didn't ask for] → One copy at a time, and only
  when Next up or Continue watching changes, which happens about once an episode. A small original
  costs the server only the read.
- [iOS runs the refresh task rarely, or never, for an app the user seldom opens] → It is a top-up.
  Every launch, foreground return and Home refresh plans too, so "ready by morning" holds for
  someone who opened the app the evening before.
- [Sizes are estimates] → A copy's real size can differ from bitrate × runtime by about 20%. The
  budget uses the real size of finished downloads and the estimate for the rest. Passing 30 GB by
  a little is acceptable.

## Migration Plan

Additive and iPhone-only. Version bump; no data migration. Rollback is a build without the tab.
Existing folders would be orphaned and removed by the next build that has the feature (or by
deleting the app).
