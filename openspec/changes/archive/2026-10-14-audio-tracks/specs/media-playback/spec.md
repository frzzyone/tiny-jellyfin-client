## ADDED Requirements

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
