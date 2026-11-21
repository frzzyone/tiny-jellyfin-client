# Spec Delta

## ADDED Requirements

### Requirement: Screen stays awake during playback
On iPhone and Apple TV, the device SHALL NOT lock or start its screensaver while a film is loading,
buffering or playing. Once playback is paused, ends, fails or the player closes, the device's usual
sleep timer SHALL apply again.

#### Scenario: Slow start on the phone
- **WHEN** a film takes longer to start than the phone's auto-lock delay
- **THEN** the screen stays on until the picture comes and playback begins

#### Scenario: Paused film
- **WHEN** the user pauses a film and leaves the phone
- **THEN** the phone locks after its usual auto-lock delay

### Requirement: Playback memory stays bounded
Playing a file, local or streamed, SHALL keep no more memory than the player's buffers: memory SHALL NOT
grow with how much of the file has been read, however long it plays.

#### Scenario: A downloaded film played through
- **WHEN** a downloaded film plays from start to end on an iPhone
- **THEN** the app's memory at the end is about what it was a few minutes in
