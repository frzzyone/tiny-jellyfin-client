## MODIFIED Requirements

### Requirement: Default subtitle track
When playback starts, the app SHALL select the subtitle track the server recommends for the user's
preferences, or "Off" when the server recommends none. A recommended picture track that the server already
burns into the stream SHALL NOT start a second stream.

#### Scenario: Forced subtitles
- **WHEN** the user's server preferences select forced subtitles only and the file has a forced English track
- **THEN** the forced English track is selected when playback starts

#### Scenario: Default picture subtitle
- **WHEN** a film's default subtitle is a PGS track
- **THEN** playback starts with it burned in from a single server stream

### Requirement: Image-based subtitles
When the user selects an image-based subtitle track (PGS, VobSub, DVB), the app SHALL have the server burn it
into the video, keeping the playback position. Turning it off SHALL ask the server for no subtitle.

#### Scenario: Select a PGS track
- **WHEN** the user selects a PGS subtitle track during Direct Play at 20:00
- **THEN** playback continues near 20:00 with the subtitles burned into the video, and the play method shows Transcode

#### Scenario: Turn image subtitles off again
- **WHEN** the user then selects "Off" or a text subtitle track
- **THEN** playback returns to the delivery the selected quality allows without burn-in, keeping the position
