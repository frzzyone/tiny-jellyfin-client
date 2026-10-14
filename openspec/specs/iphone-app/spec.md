# iphone-app Specification

## Purpose
Tinyfin on iPhone: the same server connection, browsing and playback engine as the Mac app,
with a touch interface and the audio and background behaviour a phone needs.

## Requirements

### Requirement: Runs on iPhone
The app SHALL install and run on iPhones with iOS 17 or later, connect and sign in to a Jellyfin
server as the Mac app does, keep the token in the iOS Keychain, and restore the session on launch.

#### Scenario: First launch
- **WHEN** the user opens the app for the first time and enters their server address and credentials
- **THEN** they land on Home, and on the next launch they land on Home without signing in

### Requirement: Browsing on iPhone
The app SHALL offer Home, one tab per video library (named after it) and Search, with Home showing the resume hero and the
same rows as the Mac app, each row scrolling sideways. Tapping a title SHALL open a detail sheet with
its facts, overview, progress, Resume or Play, Start over and Mark watched; series open to seasons and
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

#### Scenario: Skip with a double-tap
- **WHEN** the user double-taps the right third of the picture
- **THEN** playback jumps 30 s forward and a brief "+30" mark appears there

#### Scenario: Quality switch on the phone
- **WHEN** the user switches from Original to 720p 4 Mbps on cellular
- **THEN** playback continues near the same position at the new quality, as on the Mac

#### Scenario: A menu waits for the user
- **WHEN** the user opens Subtitles during playback and doesn't touch the screen for a minute
- **THEN** the menu and the controls are still showing

### Requirement: Brightness, volume and fill
In the player, a vertical swipe SHALL set the screen brightness on the left half and the device
volume on the right half, whether or not the controls are showing. A button SHALL switch between
fitting the picture and filling the screen, remembered between films.

#### Scenario: Volume with a swipe
- **WHEN** the user swipes up on the right half of the picture with the controls hidden
- **THEN** the device volume rises, the same level the volume buttons set, and a level bar shows it

#### Scenario: Fill the screen
- **WHEN** the user switches a 2.39:1 film to fill on a 19.5:9 phone
- **THEN** the picture covers the screen, cropping its sides, and the next film opens filled too

### Requirement: Audio on iPhone
The app SHALL play every audio format the Mac app plays. Formats iOS decodes itself are handed to the
system; others SHALL be decoded to PCM by the app, keeping their channel layout for the system to
render (spatial audio on supported headphones).

#### Scenario: E-AC-3 track on AirPods
- **WHEN** the user plays a file with an E-AC-3 5.1 track
- **THEN** sound plays through the phone's output with no server transcode

#### Scenario: DTS or TrueHD track
- **WHEN** the file's audio is DTS or TrueHD
- **THEN** the app decodes it to PCM and it plays with no server transcode

### Requirement: Background and Picture in Picture
Playback SHALL continue in Picture in Picture when the user leaves the app during playback, appear
in the Lock Screen and Control Center Now Playing controls, pause when headphones are unplugged, and
report progress to the server so another client resumes at the same point.

#### Scenario: Leave the app while watching
- **WHEN** the user swipes home during playback
- **THEN** the video continues in a Picture in Picture window and the lock screen shows its controls

#### Scenario: Phone call during a film
- **WHEN** a call comes in during playback and the user declines it
- **THEN** playback pauses for the call and carries on afterwards

#### Scenario: Headphones unplugged
- **WHEN** wired or Bluetooth headphones disconnect during playback
- **THEN** playback pauses

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

### Requirement: Hold to fast-forward and touch lock
In the player, holding a finger still on the picture SHALL play at 2× until it lifts, then return to the
previous speed. A lock button SHALL hide the controls and ignore gestures until the user unlocks, offered by
a tap.

#### Scenario: Hold through a slow scene
- **WHEN** the user holds a finger on the picture during playback at 1×
- **THEN** playback runs at 2× with a "2×" badge while the finger is down, and at 1× again once it lifts

#### Scenario: Locked in a pocket
- **WHEN** the user locks the screen and the phone is then touched and swiped
- **THEN** playback is unaffected, and a tap only shows the Unlock button
