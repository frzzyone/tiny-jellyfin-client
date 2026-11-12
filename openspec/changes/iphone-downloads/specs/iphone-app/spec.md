# Spec Delta

## MODIFIED Requirements

### Requirement: Browsing on iPhone
The app SHALL offer Home, one tab per video library (named after it), Search and Downloads, with Home showing the resume hero and the
same rows as the Mac app, each row scrolling sideways. Tapping a title SHALL open a detail sheet with
its facts, overview, progress, Resume or Play, Start over, Mark watched and Download; series open to seasons and
episodes.

#### Scenario: Resume from Home
- **WHEN** the user opens the app with a film half watched
- **THEN** the hero shows that film with its time left, and tapping Resume starts it where it stopped

#### Scenario: Detail sheet
- **WHEN** the user taps a poster in a row
- **THEN** a sheet rises with the title's details and actions, and swiping it down returns to the row

### Requirement: Touch player
The player SHALL fill the screen in landscape, show its controls on a tap and hide them after 3 s of
playback, skip back 10 s or forward 30 s on a double-tap on the left or right third, scrub with the
progress bar, and offer quality and subtitle menus with the same behaviour as the Mac player. An
open menu SHALL stay open, and the controls with it, until the user picks an option or closes it.
A downloaded copy SHALL offer no quality menu.

#### Scenario: Skip with a double-tap
- **WHEN** the user double-taps the right third of the picture
- **THEN** playback jumps 30 s forward and a brief "+30" mark appears there

#### Scenario: Quality switch on the phone
- **WHEN** the user switches from Original to 720p 4 Mbps on cellular
- **THEN** playback continues near the same position at the new quality, as on the Mac

#### Scenario: A menu waits for the user
- **WHEN** the user opens Subtitles during playback and doesn't touch the screen for a minute
- **THEN** the menu and the controls are still showing

#### Scenario: Playing a download
- **WHEN** the user plays a downloaded film
- **THEN** the controls show Subtitles but no Quality menu, and the delivery reads Downloaded
