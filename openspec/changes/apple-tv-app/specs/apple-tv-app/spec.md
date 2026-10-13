# Spec Delta

## Purpose

Tiny Jellyfin on Apple TV: the same server connection, browsing and playback engine as the Mac and
iPhone apps, driven by the Siri Remote, with the TV matching each film and the Top Shelf showing
what to watch next.

## ADDED Requirements

### Requirement: Runs on Apple TV
The app SHALL install and run on Apple TV with tvOS 17 or later, keep the token in the Keychain,
and restore the session on launch.

#### Scenario: Second launch
- **WHEN** the user opens the app after signing in once
- **THEN** they land on Home without signing in again

### Requirement: Sign in with Quick Connect
After the server address is entered, the app SHALL show a Quick Connect code and sign in as soon as
the user approves it from another Jellyfin client, offering username and password as an
alternative. When the server has Quick Connect off, the app SHALL go straight to the password form.

#### Scenario: Approve from the phone
- **WHEN** the user enters their server address and approves the shown code in Jellyfin on their phone
- **THEN** the TV signs in within a few seconds without anything typed on the TV but the address

#### Scenario: Quick Connect disabled
- **WHEN** the server reports Quick Connect as disabled
- **THEN** the app shows the username and password form

### Requirement: Browsing with the remote
The app SHALL offer a tab bar with Home (titled Tiny Jellyfin), one tab per video library and
Search. Home SHALL show the resume hero and the same rows as the other apps as shelves. Selecting a
title SHALL open its page with facts, overview, progress, Resume or Play, Start over and Mark
watched; a series page SHALL show its seasons and that season's episodes.

#### Scenario: Resume from Home
- **WHEN** the user opens the app with a film half watched
- **THEN** focus is on Resume in the hero, and one click resumes the film where it stopped

#### Scenario: Pick an episode
- **WHEN** the user opens a series, moves to Season 2 and selects episode 3
- **THEN** that episode's page opens with Play

### Requirement: Remote player
The player SHALL toggle play and pause on a centre click or the Play/Pause button, skip back 10 s
and forward 30 s on left and right clicks, scrub with a swipe on the touch surface, open a panel
with Subtitles, Quality and Audio on a swipe down, and on Back close the panel or else leave the
player, reporting progress.

#### Scenario: Skip with a click
- **WHEN** the user clicks the right edge of the touch surface during playback
- **THEN** playback jumps 30 s forward and the transport bar shows the new position

#### Scenario: Change subtitles
- **WHEN** the user swipes down and selects English in Subtitles
- **THEN** English subtitles appear inside the picture and the panel can be closed with Back

### Requirement: Match the display
When the user has Match Content enabled on the Apple TV, the app SHALL request the film's frame
rate and dynamic range from the display before playback starts, and release the request when the
player closes.

#### Scenario: 24 fps Dolby Vision film
- **WHEN** the user plays a 23.976 fps Dolby Vision film on a TV that supports it, with Match Content on
- **THEN** the TV switches to 24 Hz Dolby Vision before the film starts, and back when the player closes

### Requirement: Audio on Apple TV
The app SHALL hand Dolby Digital and Dolby Digital Plus to the system unchanged, so Atmos reaches a
receiver that supports it, and SHALL decode other formats to PCM keeping all their channels.

#### Scenario: Atmos to a receiver
- **WHEN** the user plays a film with an E-AC-3 Atmos track through an Atmos receiver
- **THEN** the receiver shows Dolby Atmos and the server does not transcode the audio

#### Scenario: TrueHD 7.1
- **WHEN** the film's audio is TrueHD 7.1
- **THEN** the receiver gets 7.1 PCM

### Requirement: Top Shelf
With the app in the top row of the Apple TV home screen, the Top Shelf SHALL show the user's
Continue watching and Next up items with their progress. Selecting an item SHALL open its page in
the app; its play action SHALL start playback.

#### Scenario: Resume from the home screen
- **WHEN** the user moves to Tiny Jellyfin on the home screen and selects a film in Continue watching
- **THEN** the app opens on that film's page with Resume focused

#### Scenario: Shelf follows playback
- **WHEN** the user stops a film halfway and returns to the home screen
- **THEN** that film leads Continue watching with its new progress
