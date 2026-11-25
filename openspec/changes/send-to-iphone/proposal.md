# Proposal

## Why

Browsing is comfortable on the Mac, but downloading has to be started on the phone. A film picked
on the Mac in the evening should be on the iPhone by the time the user leaves, without opening the
phone to find it again.

## What Changes

- The Mac's quick look gets **Download to iPhone** on a film or an episode. Pressing it again
  (**Queued for iPhone**) takes it back off the queue.
- The queue lives on the user's own Jellyfin server, in a per-user store Jellyfin keeps for
  clients (display preferences under Tinyfin's own client name). It does not appear in Jellyfin's
  library, other clients, or any service of ours; there is none.
- The iPhone reads the queue whenever its downloads sync (opening the app, coming back to it, the
  network returning, a background refresh), downloads each title as if the user had tapped
  Download on the phone (same copy rules, Wi-Fi only, shown in Downloads), and takes it off the
  queue.
- The Mac shows the action only once an iPhone signed in to the same user has synced at least
  once, so Mac-only users never see it.
- Out of scope: sending a whole series or season, choosing which of several iPhones gets it (the
  first to sync takes it), the Mac showing what the phone already holds, sending from the Apple TV,
  and a push to wake the phone (iOS decides when background refresh runs).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `iphone-downloads`: adds downloads queued from the Mac, and the Mac action that queues them.

## Impact

- JellyfinKit: get and set `/DisplayPreferences/{id}` for Tinyfin's client (tested with the stub
  protocol like the other endpoints).
- App/Shared/Downloads: a small queue type both apps use; `Downloads.sync()` picks the queue up.
- App/macOS/Views/QuickLookView.swift: the action.
- No new dependency, no settings, nothing stored outside the user's server and devices.
