# Tasks

## 1. Look and server facts first

- [x] 1.1 Mockups of the detail sheet's Download button (four states), an episode row's icon, the Downloads tab (films, series, series opened, Downloaded for you captions and footer, empty) and offline Home; verify the user approves them
- [x] 1.2 Against the user's server, by hand with `curl` or a scratch test: PlaybackInfo with the download profile returns DirectPlay for a small 1080p file and a `stream.ts` transcoding URL for a 4K remux; the `stream.ts` timestamps start where the engine expects (D4 risk); `POST /UserItems/{id}/UserData` updates the position and played flag; verify by writing the answers into design.md's Risks

## 2. JellyfinKit

- [x] 2.1 `QualityPreset.download` (1080p, 8 Mbps, not in the menu) and the download DeviceProfile (progressive MPEG-TS, 6 channels, subtitles not burnt in); verify with `DeviceProfileTests` (transcoding profile protocol `http`, container `ts`)
- [x] 2.2 `updateUserData(itemId:position:played:lastPlayed:)`; verify an `EndpointTests` case for its path, method and body (with the fallback from 1.2 if needed)

## 3. Store, queue and decisions (App/Shared, portable)

- [x] 3.1 `DownloadStore`: folder per item (`item.json`, `state.json`, media, images, subtitles), list, delete, delete all, excluded from backup; verify `DownloadStoreTests` (round trip, a damaged folder is skipped, delete frees the folder)
- [x] 3.2 The "as downloaded" `MediaSourceInfo`: a copy keeps one audio track and the downloaded subtitles marked external, an original keeps its own; verify tests for both
- [x] 3.3 `ProgressQueue` with flush (drop when the server's `lastPlayedDate` is newer, keep on failure, 90% counts as played); verify `ProgressQueueTests` with a fake service
- [x] 3.4 `SmartDownloads` decision (delete the played episode; next from Next up unless downloaded; the new one takes the finished one's kind); verify tests for next found, end of series, next already downloaded, a film (no action), user vs forYou kind
- [x] 3.5 Downloads for you planner (D8): wanted = 3 Next up shows then the top Continue watching film; 15 GB budget and 5 GB free floor, in order, stopping at the first that doesn't fit; user downloads count as ready; dismissed left out and cleared once watched; deletes for picks no longer wanted, except one playing or with unsent progress; verify `DownloadsForYouTests` for each of those

## 4. Playback of a download

- [x] 4.1 `PlaybackService.isDownloaded` and `LocalPlaybackService` (D4); controller: no quality options, "Downloaded" label, no burn-in fallback; verify `PlaybackControllerTests` with a fake engine (local URL opened, resume from the newer of stored and queued position, subtitles from disk, no quality menu)
- [x] 4.2 `AppModel.play` picks the local service for a downloaded item; verify a test and an engine test that plays a `.ts` fixture from a `file://` URL with external SRT

## 5. Downloader (App/iOS)

- [x] 5.1 `DownloadManager`: background session, start (PlaybackInfo with the download profile → original or copy), subtitles and images, progress, cancel, original resume, copy restart ×3, truncation check, not-enough-space, `endEncoding`, one copy at a time; `PhoneAppDelegate` forwards session events; verify the logic it can test with an injected transfer (states, retries, truncation) and a real download on the simulator against the demo server
- [ ] 5.2 Wi-Fi only with Waiting for Wi-Fi from `NWPathMonitor`; verify on a phone with Wi-Fi off (cellular only) that a download waits and starts when Wi-Fi returns
- [ ] 5.3 `BGAppRefreshTask` `app.tinyjellyfin.Tinyfin.refresh` (Info.plist permitted identifier, `fetch` background mode in project.yml): flush, plan, start downloads, reschedule for 6 h; verify with `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"app.tinyjellyfin.Tinyfin.refresh"]` in the debugger that a pick starts downloading

## 6. iPhone UI

- [x] 6.1 `DownloadButton` on the detail sheet and the episode-row icon, as approved in 1.1; verify by simulator screenshots of each state (`TJ_*` hooks as needed)
- [x] 6.2 Downloads tab: sections, series list, swipe to delete, empty state, posters from disk; verify by screenshots, including in flight mode
- [ ] 6.3 Offline launch to Downloads, Go to Downloads on Home and library errors, no Play for titles that aren't downloaded while offline; verify on the simulator with the network off (or a phone in flight mode)
- [ ] 6.4 Flush, Smart Downloads and Downloads for you triggers (launch, foreground, network back, after a stop, Home refresh); deleting a pick by hand dismisses it; sign out deletes everything after a best-effort flush; verify on a phone: finish a downloaded episode offline, reconnect, see it watched on the server and the next one downloading
- [x] 6.5 Dynamic Type for the new screens (the iPhone app follows it); verify a screenshot at accessibility-extra-extra-extra-large

## 7. Integration and docs

- [ ] 7.1 Real-world pass on the user's iPhone: a 2-hour 4K film downloaded with the phone locked, Downloads for you filling overnight on Wi-Fi within 15 GB, played in flight mode with subtitles, progress back on the server, an interrupted copy retried; verify and record anything still needing a person in `manual-checklist.md`
- [x] 7.2 README (iPhone section: Downloads), CLAUDE.md (download invariants found on the way), `openspec validate iphone-downloads --strict`; verify the validate passes and CI is green

## Workflow follow-up

- Archive the change once 7.1 is done.
