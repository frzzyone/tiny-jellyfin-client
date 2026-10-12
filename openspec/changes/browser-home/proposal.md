# Proposal

## Why

The browser is the least finished part of the app: a sidebar for two libraries, a bare poster grid,
and a details page per item. Finding something to watch takes several clicks and some typing, and
the things people actually want first (what they were watching, the next episode, what's new) are
either one row or missing. The mockups at https://claude.ai/artifact/N34ygeBdXoi63aVu2vADfB were
reviewed and accepted on 2026-10-12.

## What Changes

- **No sidebar.** Home, Movies and Shows are tabs in the window's top bar. (Users with more video
  libraries get one tab per library; the tabs scroll if they must.)
- **Home is built around resuming.** A hero shows where the user left off with Resume as the one
  prominent action; Enter resumes it. Below: Continue watching, Next up (the next episode of every
  series in progress), Added this week.
- **Discovery rows that need no typing**, each one server query: Surprise me (a random unwatched
  film, straight into the quick look), Short tonight (unwatched, under 100 minutes), Because you
  watched X (the server's similar items for the last finished film), Almost done (series with one
  or two episodes left), Tonight, a genre (one genre at a time, unwatched only), Been on the shelf a
  while (oldest unplayed), From the 1990s (a decade that changes daily). Home shows four of them;
  the rest live under the library tabs.
- **Library tab with one-click filters**: Unwatched, Recently added, A–Z, Longest unseen, and a
  genre strip; typing anywhere filters the grid.
- **Quick look replaces the details page**: Space (or click) on any title opens an overlay with
  poster, year, runtime, format badges, overview, progress, Resume / Play, Start over and Mark
  watched; ← → move it to the neighbouring title; Esc closes. Series still open to seasons and
  episodes.
- **Keyboard-first**: ↑ ↓ move between rows, ← → between titles, Enter plays, Space quick-looks,
  typing searches. The footer of Home states this.
- **App icon**: a play triangle that is also a jellyfish bell, amber on graphite (our own mark).

Assumptions:
- Styling follows the mockups: graphite and off-white chrome, posters as the only colour, one amber
  accent on progress and Play, system font in the native build (Instrument Sans was for the mockup).
- "Short" means under 100 minutes; "Added this week" is the last 7 days; "Almost done" is 1–2
  unplayed episodes in a series with at least one played. Constants, easy to change.
- Music, books and live TV stay hidden as before.

## Capabilities

### New Capabilities
<!-- None: all of this is library browsing. -->

### Modified Capabilities
- `library-browsing`: library list becomes tabs; Continue watching gains the hero; new requirements
  for Next up, Recently added, discovery rows, the library filters, the quick look and keyboard
  navigation; Item details becomes the quick look.

## Impact

- JellyfinKit: new endpoints (next up, latest, similar, genres, filtered/random/sorted item queries,
  mark played/unplayed, backdrop image URL); unit-tested on Linux.
- App: `LibraryRootView` loses the split view; new Home, discovery, library filter, quick look and
  keyboard-selection code; details view removed for movies and episodes.
- Spec `library-browsing` rewritten in large part. No engine change.
