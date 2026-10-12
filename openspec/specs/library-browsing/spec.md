# library-browsing Specification

## Purpose
Lets a signed-in user find something to watch by listing their Jellyfin libraries and navigating movies,
TV series, seasons, and episodes, including picking up items they have partly watched.

## Requirements

### Requirement: Library list
The app SHALL show the video libraries (movies and TV shows) the signed-in user can access, in the order the
server returns them. Libraries of unsupported types (music, books, live TV) SHALL NOT be shown.

#### Scenario: User with movie and TV libraries
- **WHEN** the user opens the home screen and has access to a Movies and a Shows library
- **THEN** both libraries are listed with their names

#### Scenario: Music library is hidden
- **WHEN** the user also has access to a Music library
- **THEN** the Music library is not listed

### Requirement: Continue watching
The app SHALL show a "Continue Watching" section on the home screen with the user's partly watched videos,
most recently watched first, each showing its progress.

#### Scenario: Partly watched movie
- **WHEN** the user has stopped a movie halfway through on any Jellyfin client
- **THEN** that movie appears in Continue Watching with a progress indicator near 50%

#### Scenario: Nothing in progress
- **WHEN** the user has no partly watched items
- **THEN** the Continue Watching section is hidden

### Requirement: Library contents
The app SHALL show a library's top-level items as a grid of poster images with titles, sorted by name, and
SHALL load further items as the user scrolls rather than all at once.

#### Scenario: Open a movie library
- **WHEN** the user selects a Movies library
- **THEN** the app shows movie posters with titles sorted alphabetically

#### Scenario: Large library
- **WHEN** a library contains more items than one page
- **THEN** additional items are loaded as the user scrolls near the end of the grid

#### Scenario: Item without artwork
- **WHEN** an item has no poster image on the server
- **THEN** the app shows a placeholder with the item's title instead of a broken image

### Requirement: Series navigation
The app SHALL let the user open a TV series to see its seasons, and open a season to see its episodes in
episode order with episode number, title, and watched state.

#### Scenario: Browse to an episode
- **WHEN** the user opens a series and then one of its seasons
- **THEN** the app lists that season's episodes in order with their numbers, titles, and watched indicators

### Requirement: Item details
The app SHALL show a details view for a playable item with its title, year or air date, runtime, overview,
and a Play action; when the item is partly watched it SHALL also offer Resume and show the resume time.

#### Scenario: Partly watched item
- **WHEN** the user opens a movie they stopped at 42:10
- **THEN** the details view offers "Resume from 42:10" and "Play from beginning"

#### Scenario: Unwatched item
- **WHEN** the user opens a movie they have never played
- **THEN** the details view offers a single Play action

### Requirement: Browsing errors
The app SHALL show an inline error with a Retry action when library content fails to load, without signing
the user out unless the failure is an authentication rejection.

#### Scenario: Network drop while browsing
- **WHEN** loading a library fails because the network is unavailable
- **THEN** the app shows an error message and a Retry button, and the user stays signed in
