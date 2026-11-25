# Design

## Context

The Mac and the iPhone never talk to each other: each talks only to the user's Jellyfin server,
and there is no Tinyfin service. So the queue has to live on that server, in something per user
that a normal (non-admin) user may write.

The iPhone already has everything after the queue: `Downloads.download(_:kind:)` makes a user
download (copy or original, Wi-Fi only, in the Downloads tab), and `Downloads.sync()` runs when the
app opens, comes back, the network returns, after playback stops and in a background refresh
(`BGAppRefreshTaskRequest`, earliest 6 h, iOS decides).

## Goals / Non-Goals

**Goals:** a queue the Mac adds to and the phone empties, with one request each way and no new
state on either device.

**Non-Goals:** waking the phone when something is queued; telling the Mac what the phone holds.

## Decisions

### The queue is a Display Preferences record of Tinyfin's own

Jellyfin keeps `DisplayPreferences` per user, per id and per client, with a free `CustomPrefs`
string dictionary that web clients use for their own settings (`GET/POST
/DisplayPreferences/{id}?client=…`, any user may write their own). Tinyfin uses id
`tinyfin-send-to-iphone` and client `Tinyfin`, so it shares no record with any other client
or with Tinyfin's own views. Keys:

- `item.<itemId>`: queued, value the ISO date it was queued (oldest first when the phone takes them).
- `phone`: an iPhone of this user has synced; value the date of its first sync. The Mac shows the
  action only when it is present.

Read from Jellyfin's source (`DisplayPreferencesController`, `DisplayPreferencesManager`): a
non-GUID id is hashed to one, keys and values have no length limit (only the client name, 32), and
a POST replaces the record's whole custom set.

Alternatives: a Jellyfin playlist (atomic add and remove, but it shows up as a playlist in every
client and in the web UI); a tag or favourite on the item (changes the user's library data, and
tags need edit rights); iCloud (a second account and entitlement, tied to the Apple ID instead of
the Jellyfin user, and the Mac app ships outside the App Store).

### Read, change own keys, write

Because a POST replaces the set, each side GETs the record, changes only the keys it means to
(the Mac one `item.` key, the phone the `item.` keys it took plus `phone`), and POSTs it straight
back. The body is the DTO the GET returned with the new `CustomPrefs`; Jellyfin also rewrites the
record's other fields from the body, which are this record's own and unused.

### The phone takes the queue early in the sync

Right after the progress flush and before Smart Downloads and Downloads for you, so a sent title
counts as the user's in the Downloads for you budget. For each key, oldest first: fetch the item
(`/Items/{id}`); a 404 drops it, any other failure stops taking (stays queued, next sync); an item
already in `records` is dropped; otherwise `download(item, kind: .user)`. Then one write removes
the keys taken and adds `phone` if missing. A queue that can't be read is skipped silently: the
sync goes on as before.

### The Mac reads the queue with the quick look

`QuickLookView` already loads the item when it opens; it reads the record alongside and shows the
button from it. Pressing it does the read-change-write and shows the result. No cache in
`AppModel`: one small GET per quick look.

### Where the code lives

JellyfinKit: `displayPreferences(id:)` and `setDisplayPreferences(_:id:)` for client
`JellyfinKitInfo.clientName`, with a `DisplayPreferences` model that keeps `CustomPrefs` and the
rest as Jellyfin sent it. App/Shared/Downloads: a small `SendToPhone` enum with the id, the key
format and the pure "what to take / what to write" logic, tested without a server.

## Risks / Trade-offs

- [A Mac add and a phone take in the same moment: the later write drops the other's change] → each
  write follows its read within one round trip; a dropped add shows as Download to iPhone on the
  Mac again, a dropped take only means the phone sees the title once more and drops it as already
  downloaded. Noted with a `ponytail:` comment; a playlist is the upgrade if it ever matters.
- [The phone may not sync for hours if it isn't opened] → stated in the spec's scenarios (taken
  "when the phone opens" or next sync); no push.
- [Two iPhones on one user] → the first to sync takes it; the other never sees it. Out of scope.
- [A Jellyfin version where the record behaves differently] → verified against a real server
  (local container) before shipping; the read fails soft, so the worst case is no action on the
  Mac and nothing taken on the phone.
