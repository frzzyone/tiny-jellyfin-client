# Spec Delta

## ADDED Requirements

### Requirement: Swipe to scrub and pinch
In the player, a sideways swipe SHALL scrub, showing the target time and the offset, and seek when the
finger lifts; a swipe across the screen moves a tenth of the film (at least a minute, at most ten). A
pinch out SHALL fill the screen and a pinch in fit the picture, like the fill button.

#### Scenario: Scrub with a swipe
- **WHEN** the user swipes halfway across the screen to the right during a two-hour film
- **THEN** the readout shows +5:00 while swiping and playback continues five minutes later on release

#### Scenario: Pinch to fill
- **WHEN** the user pinches out on a 2.39:1 film
- **THEN** the picture fills the screen, as the fill button would
