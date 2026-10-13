## MODIFIED Requirements

### Requirement: Touch player
The player SHALL fill the screen in landscape, show its controls on a tap and hide them after 3 s of
playback, skip back 10 s or forward 30 s on a double-tap on the left or right third, scrub with the
progress bar, and offer quality and subtitle menus with the same behaviour as the Mac player. An
open menu SHALL stay open, and the controls with it, until the user picks an option or closes it.

#### Scenario: Skip with a double-tap
- **WHEN** the user double-taps the right third of the picture
- **THEN** playback jumps 30 s forward and a brief "+30" mark appears there

#### Scenario: Quality switch on the phone
- **WHEN** the user switches from Original to 720p 4 Mbps on cellular
- **THEN** playback continues near the same position at the new quality, as on the Mac

#### Scenario: A menu waits for the user
- **WHEN** the user opens Subtitles during playback and doesn't touch the screen for a minute
- **THEN** the menu and the controls are still showing
