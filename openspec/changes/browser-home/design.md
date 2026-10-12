# Design

## Context

`LibraryRootView` is a `NavigationSplitView` with a sidebar listing Home and the libraries; the
detail side is a `NavigationStack` with `HomeView` (one Continue Watching row), `LibraryGridView`
(a paged poster grid), `SeriesView`, `SeasonView` and `ItemDetailsView`. Loading is through
`Loader` and `LibraryGridModel`. JellyfinKit has `libraries()`, `resumeItems()`, `items(parentId:)`,
`seasons`, `episodes`, `item(id:)`, `primaryImageURL`. The accepted mockups are the visual contract.

## Goals / Non-Goals

- Everything the mockups show, with the server doing the finding: each row is one Jellyfin query.
- Keyboard-first without a custom focus engine: one selection value and one key handler.
- Non-goals: the Jellyfin home-section settings, playlists, collections browsing, people/studios,
  a "trailers" row, more than one user, offline caching.

## Decisions

### D1. Tabs in the top bar, one `NavigationStack`
`NavigationSplitView` goes. The window is a `NavigationStack` whose root is `BrowserView`: a thin
top bar (app name, tabs, search, account) over the selected tab's content. Tabs: Home plus one per
library, from `libraries()`. Window title bar stays standard; the bar is our own view so the tabs,
search and account fit the mockup. The account button holds Sign out.

### D2. Home rows are `Row` values, each with its own loader
`HomeModel` holds `[HomeRow]`: `{ id, title, subtitle, shape (.poster | .still), items, loader }`.
Rows load independently and hide when empty or failed (an error shows inline in that row with
Retry, as today). The row set, in order: Continue watching, Next up, Added this week, then four
discovery rows chosen per day from the seven (seeded by the date, so the set is stable within a
day: Surprise me and the genre row are always there, two more rotate).

### D3. Queries (JellyfinKit)
- Continue watching: existing `resumeItems`. Hero = first item; the row = the rest.
- Next up: `GET /Shows/NextUp?userId&fields&enableUserData&limit=24`.
- Added this week: `GET /Items/Latest?userId&includeItemTypes=Movie,Series,Episode&limit=24`, kept
  when `DateCreated` is within 7 days (field requested).
- Surprise me: `GET /Items?userId&includeItemTypes=Movie&recursive&filters=IsUnplayed&sortBy=Random&limit=1`.
- Short tonight: same query with `limit=60`, filtered client-side to runtime < 100 min (the API has
  no runtime filter), first 24 shown.
- Because you watched: last finished film = `GET /Items?userId&includeItemTypes=Movie&recursive&filters=IsPlayed&sortBy=DatePlayed&sortOrder=Descending&limit=1`,
  then `GET /Items/{id}/Similar?userId&limit=24`.
- Almost done: `GET /Items?userId&includeItemTypes=Series&recursive&enableUserData&fields=…`,
  filtered client-side to `unplayedItemCount` in 1...2 and `playedPercentage > 0 || played`; then
  Next up for those series supplies the episode shown (`seriesId` filter on NextUp).
- Genre row: `GET /Genres?userId&includeItemTypes=Movie,Series` once; then
  `GET /Items?…&genreIds=<id>&filters=IsUnplayed&sortBy=Random&limit=24`.
- Shelf: `GET /Items?…&filters=IsUnplayed&sortBy=DateCreated&sortOrder=Ascending&limit=24`.
- Decade: `GET /Items?…&years=1990,…,1999&sortBy=Random&limit=24`; the decade is picked from the
  library's year span by the day of the year.
- Library grid: `items(parentId:)` gains `sort` (`SortName`, `DateCreated desc`, `DateCreated asc`
  for Longest unseen combined with `IsUnplayed`), `filters`, `genreIds`, `searchTerm`.
- Mark watched: `POST /UserPlayedItems/{id}?userId`, `DELETE` to unmark; the item's `userData`
  is refreshed from the response.
- Backdrop: `GET /Items/{id}/Images/Backdrop?tag=<BackdropImageTags[0]>&maxWidth=1600`; episodes
  fall back to `ParentBackdropItemId`.
All new query builders are pure functions on `JellyfinClient` with Linux unit tests on the URL.

### D4. One selection, one key handler
`BrowserSelection` = `(rowID, index)` or `.hero` or `.none`, in `BrowserModel`. The root view has
`.onKeyPress` for arrows, Return, Space, Escape and "s"; everything else that is a printable
character goes to the search field (`.searchable` plus a `@FocusState` that is set on the first
printable key, with the key appended). Rows scroll their selected cell into view with
`ScrollViewReader`. The selected cell draws a 2 pt outline. In the grid, ↑ ↓ move by the column
count, which the grid reports from its `GeometryReader`.

### D5. Quick look is an overlay, not a destination
`QuickLookView` sits in the root `ZStack` over the content, driven by `BrowserModel.quickLook:
BaseItem?`. It loads full details with `item(id:)` (overview, media streams for the format
badges). ← → ask the model for the neighbour of the quick-looked item in its row. Play and
Resume call `AppModel.play` and open the player window as the details view does today. Series in
the quick look show "Open series" instead of Play; episodes and movies play. `SeriesView` and
`SeasonView` stay as navigation destinations.

### D6. Look
Dark chrome following the mockup: window background graphite, text off-white, one accent for
progress and Play (`Color("Accent")` = #F5C451, set as the asset catalog's accent colour so the
system tint follows), poster placeholders as flat dark blocks with the title. System font. These
are a handful of constants in `BrowserStyle`; nothing else in the app changes colour.

### D7. Icon
The official Jellyfin icon shape (jellyfin-ux, CC BY-SA 4.0, credited in THIRD_PARTY_NOTICES.md)
recoloured: an orange-to-pale-amber gradient in the official gradient's direction, on the app's
graphite squircle. `App/Resources/AppIcon.svg` is rendered to the 16–1024 px PNGs of
`AppIcon.appiconset` by `scripts/make-icon.sh` through AppKit's SVG support (no third-party
tools). The asset catalog is checked in; the script is for regenerating after editing the SVG.

## Risks / Trade-offs

- Seven discovery queries on every Home load is a dozen requests; they run concurrently and the
  server is local, but the rotation keeps it to four rows plus the three fixed ones.
- `sortBy=Random` is random per request: Surprise me is cheap; the random rows reshuffle on every
  Home load, which is the point.
- Type-anywhere search steals printable keys from everything else in the browser; the player
  window has its own handler and is unaffected.
- The look is custom chrome in a Mac app; the window title bar and traffic lights stay standard so
  it still behaves like a Mac window.
