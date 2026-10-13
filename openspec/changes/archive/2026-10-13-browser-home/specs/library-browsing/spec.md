# Spec Delta

## MODIFIED Requirements

### Requirement: Library list
The app SHALL show the video libraries (movies and TV shows) the signed-in user can access as tabs in the
window's top bar after a Home tab, in the order the server returns them. Libraries of unsupported types
(music, books, live TV) SHALL NOT be shown. There SHALL be no sidebar.

#### Scenario: User with movie and TV libraries
- **WHEN** the user opens the app and has access to a Movies and a Shows library
- **THEN** the top bar shows Home, Movies and Shows, with Home selected

#### Scenario: Music library is hidden
- **WHEN** the user also has access to a Music library
- **THEN** no Music tab is shown

### Requirement: Continue watching
The app SHALL show the user's partly watched videos on Home, most recently watched first: the most recent
one as a hero with its backdrop, title, time left, progress, Resume and Start over; the rest in a
"Continue watching" row with progress bars. Pressing Enter on Home with nothing selected SHALL resume
the hero item.

#### Scenario: Partly watched movie
- **WHEN** the user has stopped a movie halfway through on any Jellyfin client
- **THEN** that movie is the hero with a progress indicator near 50% and a Resume action

#### Scenario: Enter resumes
- **WHEN** Home is showing and the user presses Enter without having selected a title
- **THEN** the hero item resumes in the player

#### Scenario: Nothing in progress
- **WHEN** the user has no partly watched items
- **THEN** the hero shows the newest Next up episode or the newest added title instead, and the Continue watching row is hidden

### Requirement: Library contents
The app SHALL show a library's items as a grid of posters with titles, with one-click filters Unwatched,
Recently added, A–Z and Longest unseen, a strip of the library's genres, and a search that starts when the
user types anywhere in the grid. Further items SHALL load as the user scrolls.

#### Scenario: Open a movie library
- **WHEN** the user selects the Movies tab
- **THEN** the app shows movie posters with titles, Unwatched selected by default, with the genre strip above

#### Scenario: Type to filter
- **WHEN** the user types "he" with the grid showing
- **THEN** the grid narrows to titles matching "he" and shows the match count, without the user clicking a search field first

#### Scenario: Large library
- **WHEN** a library contains more items than one page
- **THEN** additional items are loaded as the user scrolls near the end of the grid

#### Scenario: Item without artwork
- **WHEN** an item has no poster image on the server
- **THEN** the app shows a placeholder with the item's title instead of a broken image

### Requirement: Item details
The app SHALL show a quick look overlay for a playable item, opened by Space or a click, with its poster,
title, year or air date, runtime, format badges, overview, progress and time left when partly watched,
and the actions Resume or Play, Start over when partly watched, and Mark watched or Mark unwatched.
← and → SHALL move the quick look to the neighbouring title and Esc SHALL close it.

#### Scenario: Partly watched item
- **WHEN** the user opens the quick look of a movie they stopped at 42:10
- **THEN** it shows the time left and offers Resume and Start over

#### Scenario: Unwatched item
- **WHEN** the user opens the quick look of a movie they have never played
- **THEN** it offers a single Play action and Mark watched

#### Scenario: Move along the row
- **WHEN** the quick look is open and the user presses →
- **THEN** the quick look shows the next title in the same row or grid without closing

## ADDED Requirements

### Requirement: Next up
Home SHALL show a "Next up" row with the next unwatched episode of every series the user has started,
most recently watched series first, each with series name, season and episode number, episode title
and runtime.

#### Scenario: Series in progress
- **WHEN** the user has watched episodes 1–3 of a series on any client
- **THEN** Next up shows episode 4 of that series

#### Scenario: Season finished
- **WHEN** the user has finished season 1 of a series that has a season 2
- **THEN** Next up shows season 2 episode 1

### Requirement: Recently added
Home SHALL show an "Added this week" row with titles added to the libraries in the last seven days,
newest first, hidden when empty.

#### Scenario: New film
- **WHEN** a film was added to the server two days ago
- **THEN** it appears in Added this week

### Requirement: Discovery rows
Home SHALL offer rows that find something without typing: Surprise me, Short tonight, Because you
watched, Almost done, Tonight a genre, Been on the shelf a while, and a decade row. Each row is defined
by its scenario below. Rows with nothing to show SHALL be hidden.

#### Scenario: Surprise me
- **WHEN** the user presses Surprise me (or S) on Home
- **THEN** the quick look opens on a random film the user has not watched, ready to play

#### Scenario: Short tonight
- **WHEN** the user has unwatched films shorter than 100 minutes
- **THEN** Short tonight lists them with their runtimes

#### Scenario: Because you watched
- **WHEN** the last film the user finished was Heat
- **THEN** a row titled "Because you watched Heat" shows the server's similar titles

#### Scenario: Almost done
- **WHEN** the user has watched some of a series and one or two episodes remain unwatched
- **THEN** Almost done shows that series with its next episode and how many are left

#### Scenario: Switch the genre in place
- **WHEN** the user chooses Comedy in the genre row
- **THEN** the row's titles change to unwatched comedies without leaving Home

#### Scenario: On the shelf
- **WHEN** the user has unplayed titles that were added long ago
- **THEN** Been on the shelf a while lists the oldest of them with when they were added

#### Scenario: Decade of the day
- **WHEN** the user opens Home on two different days
- **THEN** the decade row shows a different decade, chosen from the years in the library

### Requirement: Keyboard browsing
The browser SHALL be fully usable from the keyboard: ↑ ↓ move between rows, ← → between titles, Enter
plays the selected title, Space opens its quick look, Esc closes it, and typing starts a search. The
selected title SHALL be visibly outlined.

#### Scenario: Play without the mouse
- **WHEN** the user presses ↓ twice and → once on Home, then Enter
- **THEN** the third title of the second row below the hero plays

#### Scenario: Type anywhere
- **WHEN** the user types a letter while browsing
- **THEN** the search field takes the keystroke and the view filters as they type
