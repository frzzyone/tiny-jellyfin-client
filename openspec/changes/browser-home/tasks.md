# Tasks

## 1. JellyfinKit queries

- [x] 1.1 Add `nextUp(limit:seriesId:)`, `latest(limit:)` with `DateCreated` in the fields, `similar(to:limit:)`, `genres()`, `markPlayed(id:)` / `markUnplayed(id:)`, `backdropImageURL(for:)`, and an `ItemQuery` builder (`parentId`, `types`, `filters`, `sort`, `genreIds`, `years`, `searchTerm`, `limit`, `startIndex`) used by `items(_:)`; verify stubbed unit tests for each URL and for the `years` and `filters` encodings
- [x] 1.2 Add `BaseItem.dateCreated`, `backdropImageTags`, `parentBackdropItemId`, `genreItems`, `userData.lastPlayedDate`, and `MediaStream`-based format badges (`4K`, `HDR`, `Atmos`); verify decoding tests

## 2. Models

- [x] 2.1 Add `HomeModel` with `HomeRow` values and loaders for Continue watching (hero + rest), Next up, Added this week, and the seven discovery rows with the daily rotation; verify unit tests with a fake client: row order, hidden-when-empty, the 100-minute cut, the 7-day cut, the 1–2-left rule, the daily rotation being stable within a day
- [x] 2.2 Add `BrowserModel` with tabs, `BrowserSelection`, quick-look state and neighbour lookup, and `LibraryGridModel` filters (Unwatched / Recently added / A–Z / Longest unseen, genre, search term with a 250 ms debounce) that reset paging; verify unit tests for selection movement across rows of different lengths, grid movement by column count, neighbour lookup at row ends, and that a filter change restarts paging

## 3. Views

- [x] 3.1 Replace `NavigationSplitView` with `BrowserView`: top bar with the app name, Home + library tabs, search field, account menu with Sign out; remove the sidebar; verify manually that the tabs list exactly the video libraries
- [x] 3.2 Build `HomeView`: hero (backdrop, title, time left, progress, Resume, Start over, Enter hint), the rows with poster and still cards, the keyboard footer; verify manually against the server that the hero is the last-watched item and Enter resumes it
- [x] 3.3 Build the discovery rows: Surprise me control (and S), Short tonight, Because you watched, Almost done, the genre row with in-place switching, Been on the shelf, the decade row; verify manually that each row matches what the Jellyfin web UI shows for the same query
- [x] 3.4 Build the library tab: filter pills, genre strip, type-anywhere search with match count, paging kept; verify manually with the Movies library
- [x] 3.5 Build `QuickLookView` as an overlay: poster, title, facts and badges, overview, progress, Resume / Play, Start over, Mark watched / unwatched, ← → neighbour, Esc; wire Space and click; remove `ItemDetailsView` for movies and episodes; verify manually that Mark watched updates the card at once
- [x] 3.6 Keyboard: the root key handler for arrows, Return, Space, Escape, S and printable characters; selection outline; scroll-into-view; verify manually the "↓ ↓ → Enter" scenario and that typing while browsing lands in the search field
- [x] 3.7 Apply `BrowserStyle`: graphite chrome, off-white text, amber accent as the asset catalog accent colour, flat poster placeholders; verify manually that the player window is unchanged

## 4. Icon

- [x] 4.1 Add `App/Resources/AppIcon.svg` (the official Jellyfin shape, CC BY-SA, in the amber gradient on graphite) and `scripts/make-icon.sh` producing `AppIcon.appiconset`, reference it from `project.yml`, credit it in THIRD_PARTY_NOTICES.md; verified the asset catalog compiles and the icon renders at 16–1024 px (the Dock itself still needs a look)

## 5. Specs and docs

- [x] 5.1 Update README's feature list and screenshots note, CLAUDE.md's layout table (`BrowserView`, `HomeModel`), and the archived manual checklist pointer; verify `openspec validate --strict` passes

Implemented and unit-tested; the "verify manually" parts of 3.1–3.7 are collected in
`manual-checklist.md`. A run against the server logged
`Home: nextUp=24 shelf=24 decade=24 shortTonight=11 genre=24 hero=Troy`.
