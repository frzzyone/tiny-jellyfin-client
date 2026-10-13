## MODIFIED Requirements

### Requirement: Image-based subtitles
When the file plays as it is, the app SHALL draw image-based subtitle tracks (PGS, VobSub, DVB) itself, placed
where the disc puts them on the frame and scaled with the picture. When the server transcodes, the app SHALL
have the server burn the selected track into the video, keeping the playback position. Turning it off SHALL
ask the server for no subtitle.

#### Scenario: PGS during Direct Play
- **WHEN** a 4K Blu-ray remux whose default subtitle is English PGS starts at Original quality
- **THEN** it plays as Direct Play and the app draws the English subtitles, with no server transcode

#### Scenario: Select a PGS track
- **WHEN** the user selects a PGS subtitle track while playing at 720p 4 Mbps at 20:00
- **THEN** playback continues near 20:00 with the subtitles burned into the video

#### Scenario: Turn image subtitles off again
- **WHEN** the user then selects "Off" or a text subtitle track
- **THEN** playback returns to the delivery the selected quality allows without burn-in, keeping the position
