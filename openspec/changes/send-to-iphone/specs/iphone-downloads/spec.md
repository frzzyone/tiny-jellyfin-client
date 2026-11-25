# Spec Delta

## ADDED Requirements

### Requirement: Download to iPhone from the Mac
The Mac app SHALL offer Download to iPhone in a film's or episode's quick look once an iPhone signed
in to the same user on the same server has synced its downloads. Pressing it SHALL queue the title
and show Queued for iPhone; pressing that SHALL take it off the queue. The queue SHALL be kept only
on the user's Jellyfin server, per user, and SHALL NOT appear in the server's library or in other
clients.

#### Scenario: Queue a film on the Mac
- **WHEN** the user opens a film's quick look on the Mac and presses Download to iPhone
- **THEN** the button reads Queued for iPhone, and still does when the quick look is opened again

#### Scenario: Change of mind
- **WHEN** the user presses Queued for iPhone
- **THEN** the title leaves the queue and the button offers Download to iPhone again

#### Scenario: No iPhone
- **WHEN** a user who has never signed in to Tinyfin on an iPhone opens a quick look on the Mac
- **THEN** there is no Download to iPhone

#### Scenario: Not a film or an episode
- **WHEN** the user opens a series' quick look
- **THEN** there is no Download to iPhone

### Requirement: The iPhone takes what the Mac sent
Whenever its downloads sync, the iPhone app SHALL download each queued title as if the user had
tapped Download on the phone, with the same copies, Wi-Fi rule and Downloads tab entry, and SHALL
take it off the queue. A title already on the phone, or no longer on the server, SHALL leave the
queue without a download. A title SHALL stay queued while the phone cannot reach the server.

#### Scenario: Picked up when the phone opens
- **WHEN** the user queues a film on the Mac and later opens Tinyfin on the iPhone on Wi-Fi
- **THEN** the film appears in Downloads as downloading, and the Mac's quick look offers Download to iPhone again

#### Scenario: Phone on cellular
- **WHEN** the phone syncs on cellular with a film queued
- **THEN** the film appears in Downloads as Waiting for Wi-Fi and downloads once the phone joins Wi-Fi

#### Scenario: Already downloaded
- **WHEN** the Mac queues an episode the phone already holds
- **THEN** the phone takes it off the queue and keeps its one copy

#### Scenario: Server out of reach
- **WHEN** the phone syncs with no connection to the server
- **THEN** the queue is unchanged, and the title is taken at the next sync that reaches the server
