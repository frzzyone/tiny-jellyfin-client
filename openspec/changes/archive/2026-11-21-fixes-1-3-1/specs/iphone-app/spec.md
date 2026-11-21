# Spec Delta

## MODIFIED Requirements

### Requirement: Hold to fast-forward and touch lock
In the player, holding a finger still on the picture for half a second SHALL play at 2× until it lifts,
then return to the previous speed; a shorter touch SHALL remain a tap, showing or hiding the controls as
before. A lock button SHALL hide the controls and ignore gestures until the user unlocks, offered by
a tap.

#### Scenario: Hold through a slow scene
- **WHEN** the user holds a finger on the picture during playback at 1×
- **THEN** playback runs at 2× with a "2×" badge while the finger is down, and at 1× again once it lifts

#### Scenario: A tap is not a hold
- **WHEN** the user taps the picture while the controls are hidden, then taps it again away from the buttons
- **THEN** the first tap shows the controls, the second hides them, and playback speed never changes

#### Scenario: Locked in a pocket
- **WHEN** the user locks the screen and the phone is then touched and swiped
- **THEN** playback is unaffected, and a tap only shows the Unlock button
