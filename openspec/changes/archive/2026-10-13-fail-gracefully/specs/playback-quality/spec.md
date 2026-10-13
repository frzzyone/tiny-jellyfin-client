## MODIFIED Requirements

### Requirement: Failed quality switch
If the new quality cannot be loaded, the app SHALL keep playing the previous stream, keep the previous quality
selected, tell the user the switch failed, and end the server transcode it asked for. If the new stream was
only too slow to catch up, the app SHALL instead stop the old stream and start the new quality at the same
position, keeping the subtitle and pause.

#### Scenario: Server rejects the new stream
- **WHEN** the server fails to provide a stream for the selected quality
- **THEN** playback continues in the previous quality and the app shows a "couldn't switch quality" message

#### Scenario: New stream too slow to catch up
- **WHEN** the user switches to 1080p 10 Mbps at 1:02:00 on a server that encodes at about real time
- **THEN** after a short wait playback continues near 1:02:00 at 1080p 10 Mbps, and the server encodes only that stream
