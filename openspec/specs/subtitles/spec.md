# subtitles Specification

## Purpose
Lets the user read subtitles while watching: text subtitles from the file or the server are shown by the app,
subtitle tracks can be chosen during playback, and image-based subtitles are handled by the server.

## Requirements

### Requirement: Text subtitle display
The app SHALL display text subtitles (SRT, WebVTT, MP4 timed text, and SSA/ASS shown as plain text without
styling or positioning) over the bottom of the video, in time with playback, scaled with the video size.

#### Scenario: Embedded SRT track
- **WHEN** the user plays an MKV with an embedded SRT subtitle track selected
- **THEN** each subtitle line appears over the video at its start time and disappears at its end time

#### Scenario: Styled ASS track
- **WHEN** the selected track is ASS with styling tags and positioning
- **THEN** the dialogue text is shown at the bottom without raw style tags visible

#### Scenario: Full screen
- **WHEN** the user enters full screen with subtitles visible
- **THEN** the subtitle text scales up with the video

### Requirement: External subtitle files
The app SHALL offer external text subtitle files known to the server for the item alongside embedded tracks,
and display them the same way.

#### Scenario: Sidecar SRT file
- **WHEN** the movie folder on the server contains `Movie.en.srt` next to the video
- **THEN** an English external track appears in the subtitle menu and is displayed when selected

### Requirement: Subtitle track selection
The player SHALL list all subtitle tracks with their language and title plus "Off", and SHALL let the user
change the track during playback without changing the playback position.

#### Scenario: Switch track mid-playback
- **WHEN** the user switches from English to Spanish subtitles at 45:00
- **THEN** Spanish subtitles appear from 45:00 onward and playback does not jump

#### Scenario: Turn subtitles off
- **WHEN** the user selects "Off"
- **THEN** no subtitles are shown

### Requirement: Default subtitle track
When playback starts, the app SHALL select the subtitle track the server recommends for the user's
preferences, or "Off" when the server recommends none.

#### Scenario: Forced subtitles
- **WHEN** the user's server preferences select forced subtitles only and the file has a forced English track
- **THEN** the forced English track is selected when playback starts

### Requirement: Image-based subtitles
When the user selects an image-based subtitle track (PGS, VobSub, DVB), the app SHALL have the server burn it
into the video, keeping the playback position.

#### Scenario: Select a PGS track
- **WHEN** the user selects a PGS subtitle track during Direct Play at 20:00
- **THEN** playback continues near 20:00 with the subtitles burned into the video, and the play method shows Transcode

#### Scenario: Turn image subtitles off again
- **WHEN** the user then selects "Off" or a text subtitle track
- **THEN** playback returns to the delivery the selected quality allows without burn-in, keeping the position

### Requirement: Subtitles survive quality switches
The selected subtitle track SHALL stay selected and in sync after a quality switch.

#### Scenario: Quality switch with subtitles
- **WHEN** the user switches quality while English text subtitles are shown
- **THEN** English subtitles continue in sync in the new quality
