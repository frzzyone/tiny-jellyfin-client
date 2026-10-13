# media-playback Specification

## Purpose
Lets the user watch a movie or episode from their Jellyfin server in a native macOS player, control it with the
mouse, keyboard and system media controls, resume where they left off, and keep watch progress in sync with the
server and other Jellyfin clients.

## Requirements

### Requirement: Start playback
The app SHALL play a selected movie or episode in a player window and SHALL ask the server how to deliver the
stream for this app's playback capabilities.

#### Scenario: Play an unwatched movie
- **WHEN** the user chooses Play on a movie
- **THEN** a player window opens and the movie starts playing from the beginning

#### Scenario: Server cannot provide a playable stream
- **WHEN** the server reports that no stream can be produced for the item
- **THEN** the app shows an error explaining playback is not possible and does not open an empty player

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

### Requirement: Buffering indicator
The player SHALL show a loading indicator whenever playback is waiting for data, and hide it as soon as playback
continues.

#### Scenario: Slow network
- **WHEN** the stream cannot be downloaded fast enough and playback stalls
- **THEN** a loading indicator appears over the video until playback resumes

### Requirement: Picture in Picture
The player SHALL offer system Picture in Picture, keeping playback position and play/pause state when entering
and leaving it.

#### Scenario: Enter and leave PiP
- **WHEN** the user enters Picture in Picture at 30:00 and later returns to the player window
- **THEN** the video keeps playing in a floating window and returns to the player window at its current position

### Requirement: System media controls
While a video is playing the app SHALL publish its title and position to macOS Now Playing and respond to
system media controls (media keys, Control Center, headphones): play, pause, toggle, skip, and seek.

#### Scenario: Media key
- **WHEN** a video is playing and the user presses the keyboard's play/pause media key
- **THEN** playback pauses

#### Scenario: Now Playing shows the item
- **WHEN** the user opens Control Center during playback of an episode
- **THEN** Now Playing shows the episode and series title, elapsed time and duration

### Requirement: Resume playback
The app SHALL start playback at the server-stored position when the user chooses Resume, and at the
beginning when the user chooses Play from beginning.

#### Scenario: Resume
- **WHEN** the user chooses "Resume from 42:10"
- **THEN** playback starts within 2 seconds of 42:10

### Requirement: Playback state reporting
The app SHALL report to the server when playback starts, the current position and paused state at least
every 10 seconds and on every pause, resume and seek, and when playback stops.

#### Scenario: Progress visible on another client
- **WHEN** the user watches for one minute and then closes the player
- **THEN** another Jellyfin client shows the item as partly watched at approximately that position

#### Scenario: Watched to the end
- **WHEN** playback reaches the end of the video
- **THEN** the app reports the stop at the final position and the server marks the item as watched

### Requirement: Stop playback cleanly
The app SHALL stop playback when the player window closes, report the stop to the server, and ask the server
to end any transcoding job started for this playback session.

#### Scenario: Close player during transcoded playback
- **WHEN** the user closes the player while the server is transcoding the stream
- **THEN** the app reports playback stopped and the server's transcoding job for that session ends

### Requirement: Playback errors
The app SHALL show a playback error in the player window, report the stop at the last known position, and let
the user retry from that position. A server error that won't go away by retrying SHALL be shown at once with
the server's answer, and a stream that doesn't open within 60 s SHALL fail.

#### Scenario: Stream fails mid-playback
- **WHEN** the stream stops loading due to a network failure at 15:30
- **THEN** the player shows an error with a Retry action, and Retry resumes playback near 15:30

#### Scenario: Corrupt data in the file
- **WHEN** the file contains a damaged section that cannot be decoded
- **THEN** playback skips past the damaged section and continues, rather than freezing or crashing the app

#### Scenario: Server can't encode the stream
- **WHEN** the server answers the first segment with HTTP 500
- **THEN** within seconds the player shows "The server answered HTTP 500." with Retry, instead of spinning

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

### Requirement: Audio tracks
Playback SHALL start on the audio track the server picks for the user. The player SHALL list the item's audio
tracks and switch to the chosen one at the current position: in place during Direct Play, through the server
when transcoding. The choice SHALL survive quality switches.

#### Scenario: Switch to the other language
- **WHEN** the user picks the Spanish track at 42:00 of a file played as it is
- **THEN** after a short pause playback continues near 42:00 in Spanish, without a second download

#### Scenario: Quality switch keeps the track
- **WHEN** the user then switches to 720p 4 Mbps
- **THEN** the transcode carries the Spanish track

### Requirement: Playback speed
The player SHALL offer 0.75×, 1×, 1.25×, 1.5× and 2×, keeping the audio's pitch, and start each new item at 1×.

#### Scenario: Faster through a talk
- **WHEN** the user picks 1.5× during playback
- **THEN** the film plays half as fast again with voices at their normal pitch, and the next film starts at 1×

### Requirement: Chapters
When the server lists two or more chapters for an item, the player SHALL list them with their start times and
jump to a chosen one.

#### Scenario: Jump to a chapter
- **WHEN** the user picks "The Heist" (05:00) from the chapter list
- **THEN** playback continues from 05:00
