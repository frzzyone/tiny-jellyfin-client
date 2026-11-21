## ADDED Requirements

### Requirement: Plain HTTP when no scheme was typed
When the address names no scheme and `https://` fails, the app SHALL try the same address over
`http://` before reporting an error. An explicit scheme SHALL be used as given.

#### Scenario: Home server without a certificate
- **WHEN** the user enters `media.lan:8096` and the server only speaks plain HTTP
- **THEN** the app connects to `http://media.lan:8096` and moves to the sign-in step

#### Scenario: Self-signed certificate
- **WHEN** the user enters an `https://` address whose certificate isn't trusted
- **THEN** the app stays on the server step and says the certificate isn't trusted, without retrying over HTTP

### Requirement: Credentials stay out of logs and messages
Errors that reach the log or the screen SHALL NOT contain the access token, including the
`api_key` the server puts in transcode URLs.

#### Scenario: A transcode request fails
- **WHEN** a segment request fails for good
- **THEN** the logged and displayed error names the failure without the request's URL
