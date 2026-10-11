# Spec Delta

## Purpose

Lets the user connect the app to their self-hosted Jellyfin server, sign in, stay signed in across launches,
and sign out, while keeping credentials secure.

## ADDED Requirements

### Requirement: Server address validation
The app SHALL accept a server address entered by the user, normalize it (add `https://` when no scheme is
given, strip trailing slashes), and confirm it points to a reachable Jellyfin server before asking for
credentials.

#### Scenario: Valid Jellyfin server
- **WHEN** the user enters `media.example.com:8096` and continues
- **THEN** the app contacts the normalized address, shows the server's name, and moves to the sign-in step

#### Scenario: Unreachable or non-Jellyfin address
- **WHEN** the address cannot be reached or does not respond like a Jellyfin server
- **THEN** the app stays on the server step and shows an error explaining the server could not be reached

#### Scenario: Plain HTTP server
- **WHEN** the user enters an address with an explicit `http://` scheme
- **THEN** the app connects over HTTP as given and does not silently upgrade or reject it

### Requirement: Username and password sign-in
The app SHALL sign the user in with a username and password against the validated server and obtain an
access token for all later requests.

#### Scenario: Correct credentials
- **WHEN** the user submits a valid username and password
- **THEN** the app signs in and shows the user's library home screen

#### Scenario: Wrong credentials
- **WHEN** the server rejects the username or password
- **THEN** the app stays on the sign-in step, clears the password field, and shows an "incorrect username or password" error

### Requirement: Secure session persistence
The app SHALL store the access token only in the macOS Keychain and SHALL NOT store the user's password.
Non-secret session details (server address, user ID, user name) MAY be stored in app preferences.

#### Scenario: Relaunch while signed in
- **WHEN** the user quits and relaunches the app after signing in
- **THEN** the app restores the session and opens the library home screen without asking for credentials

#### Scenario: Password is never persisted
- **WHEN** the user has signed in
- **THEN** the password does not exist in the Keychain, preferences, or any file written by the app

### Requirement: Expired or revoked session
The app SHALL treat an authentication rejection from the server on any request as a lost session, clear the
stored token, and return the user to the sign-in step for the same server.

#### Scenario: Token revoked on the server
- **WHEN** an administrator revokes the app's device or token and the app makes its next request
- **THEN** the app removes the stored token and shows the sign-in step with the server address pre-filled

### Requirement: Sign out
The app SHALL let the user sign out, which ends the session on the server when reachable and removes the
stored token from the Keychain.

#### Scenario: Sign out
- **WHEN** the user chooses Sign Out
- **THEN** the app notifies the server, deletes the stored token, and returns to the server step

#### Scenario: Sign out while server is unreachable
- **WHEN** the user signs out and the server cannot be reached
- **THEN** the app still deletes the stored token locally and returns to the server step

### Requirement: Stable device identity
The app SHALL identify itself to the server with a fixed client name, its version, the Mac's name, and a
device identifier that is generated once and stays the same across launches.

#### Scenario: Same device across launches
- **WHEN** the user signs in, quits, and relaunches the app
- **THEN** the server's device list shows a single entry for this Mac rather than a new device per launch
