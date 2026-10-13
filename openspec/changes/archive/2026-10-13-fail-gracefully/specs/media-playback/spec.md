## MODIFIED Requirements

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
