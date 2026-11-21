## ADDED Requirements

### Requirement: Seeking during a quality switch
A seek while a quality switch is under way SHALL give the switch up and continue from the seek
position, then restart at the new quality from there; the server SHALL be told the abandoned stream
is unused.

#### Scenario: Scrub right after picking a quality
- **WHEN** the user picks 720p and scrubs before the new stream is spliced in
- **THEN** the picture continues from the scrubbed position, and the 720p stream starts again from there

### Requirement: Closing while opening
Closing the player while a stream is still opening SHALL stop the open at once and end any
transcode the server started for it.

#### Scenario: Close during "Opening video…"
- **WHEN** the user closes the player before a transcode has started playing
- **THEN** the player closes without an error and the server stops encoding
