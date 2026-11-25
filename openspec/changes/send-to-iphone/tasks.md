# Tasks

## 1. The record on the server

- [ ] 1.1 JellyfinKit: `DisplayPreferences` model (keeps every field Jellyfin sends, `CustomPrefs` as a string dictionary) and `displayPreferences(id:)` / `setDisplayPreferences(_:id:)` for client `Tinyfin`; verify with EndpointTests through `StubURLProtocol` (path, `client` query, POST body round-trips unknown fields) and `swift test --package-path Packages/JellyfinKit`
- [ ] 1.2 Run a local Jellyfin in Docker (pinned image tag, a throwaway user, a fixture film from `scripts/make-fixtures.sh`) and check the round trip with the 1.1 calls: a new id reads as empty, a write then read returns the keys, a second write replaces the set, and the web UI shows no playlist or library change; record what was seen in design.md

## 2. The queue's rules

- [ ] 2.1 App/Shared/Downloads: `SendToPhone` with the record id, the `item.` and `phone` keys, queued ids oldest first, and the two edits (add/remove one id; remove taken ids and mark the phone) that leave every other key alone; verify with unit tests in App/Tests

## 3. The iPhone takes the queue

- [ ] 3.1 `DownloadServer` gets the record read and write; `Downloads.sync()` takes the queue after the progress flush (404 drops, other failures keep, already downloaded drops, else a user download) and writes once; verify with DownloadsTests: taken as a user download and removed, already-downloaded removed without a second record, 404 removed, server unreachable leaves the queue untouched, `phone` written on the first sync, other keys kept
- [ ] 3.2 Verify on the iPhone simulator against the local server: queue a film with the 1.1 call, launch with `TJ_SERVER`/`TJ_USER`, and see it in Downloads (screenshot), and the record emptied

## 4. The Mac's action

- [ ] 4.1 `QuickLookView`: Download to iPhone / Queued for iPhone for films and episodes when `phone` is present, read with the quick look, the press writing and showing the result or the error like Mark watched; verify with a test of the button state from a record (no `phone`, queued, not queued, a series) and a screenshot of the Mac quick look against the local server via `TJ_BROWSER_QUICKLOOK`
- [ ] 4.2 README: one line under the iPhone downloads description; verify it reads correctly in the rendered README

## 5. End to end

- [ ] 5.1 Against the local server: queue on the Mac debug build, then sync the iPhone simulator; the film downloads on the phone and the Mac's quick look offers Download to iPhone again. Then `openspec validate send-to-iphone --strict`
- [ ] 5.2 Manual on the user's devices (in `manual-checklist.md`): queue a film on the Mac in the evening, open the iPhone on Wi-Fi, the film is in Downloads
