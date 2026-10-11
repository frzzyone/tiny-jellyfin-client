# Spec Delta

## Purpose

Lets the user watch a movie or episode from their Jellyfin server in a native macOS player, resume where they
left off, and keep watch progress in sync with the server and other Jellyfin clients.

## ADDED Requirements

### Requirement: Start playback
The app SHALL play a selected movie or episode in a player window with standard macOS playback controls
(play/pause, seek bar, volume, full screen) and SHALL ask the server how to deliver the stream for this Mac.

#### Scenario: Play an unwatched movie
- **WHEN** the user chooses Play on a movie
- **THEN** a player window opens and the movie starts playing from the beginning

#### Scenario: Server cannot provide a playable stream
- **WHEN** the server reports that no stream can be produced for the item
- **THEN** the app shows an error explaining playback is not possible and does not open an empty player

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
the user retry from that position.

#### Scenario: Stream fails mid-playback
- **WHEN** the stream stops loading due to a network failure at 15:30
- **THEN** the player shows an error with a Retry action, and Retry resumes playback near 15:30

