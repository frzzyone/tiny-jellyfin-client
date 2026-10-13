# Spec Delta

## MODIFIED Requirements

### Requirement: Player controls
The player SHALL provide play/pause, a scrubber showing elapsed and remaining time, skip back 10 s and forward
30 s, volume and mute, and full screen. Controls SHALL hide after 3 seconds without mouse movement while playing,
and stay up while the pointer rests on them.

#### Scenario: Scrub to a position
- **WHEN** the user drags the scrubber to 1:10:00 and releases it
- **THEN** playback continues from within 1 second of 1:10:00

#### Scenario: Controls auto-hide
- **WHEN** the video is playing and the mouse has not moved for 3 seconds
- **THEN** the controls and the mouse pointer are hidden until the mouse moves again

#### Scenario: Controls stay while paused
- **WHEN** playback is paused
- **THEN** the controls remain visible

#### Scenario: Pointer on the controls
- **WHEN** the pointer rests on the play button for 5 seconds during playback
- **THEN** the controls stay visible

### Requirement: Keyboard shortcuts
The player SHALL support Space (play/pause), Left/Right arrows (skip back 10 s / forward 30 s), Up/Down arrows
(volume), F (toggle full screen), M (mute), Escape (exit full screen), S (next text subtitle, then off) and
0–9 (jump to that tenth of the film).

#### Scenario: Pause with the keyboard
- **WHEN** the player window is focused and the user presses Space during playback
- **THEN** playback pauses, and pressing Space again resumes it

#### Scenario: Jump by tenths
- **WHEN** the user presses 5 during a two-hour film
- **THEN** playback continues from one hour in

## ADDED Requirements

### Requirement: Mouse, trackpad and the end of a film
On the Mac, a single click on the picture SHALL toggle play and pause (except the click that brings the
window forward), a sideways two-finger trackpad swipe SHALL scrub and seek when the fingers lift, the
window SHALL carry the film's title, and a finished film SHALL show Watched with Play Again and Close.

#### Scenario: Click to pause
- **WHEN** the user clicks once on the playing picture
- **THEN** playback pauses, and a double-click still toggles full screen

#### Scenario: End of a film
- **WHEN** a film plays to its end
- **THEN** the player shows Watched with Play Again and Close
