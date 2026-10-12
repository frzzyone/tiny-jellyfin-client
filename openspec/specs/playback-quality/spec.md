# playback-quality Specification

## Purpose
Lets the user control the streaming quality of a video, choosing between the original file and lower
bitrate/resolution presets, and switch between them during playback without losing their place.

## Requirements

### Requirement: Quality options
The app SHALL offer "Original" plus these presets: 4K 40 Mbps, 1080p 20 Mbps, 1080p 10 Mbps, 720p 4 Mbps,
480p 1.5 Mbps, 360p 720 kbps. Each preset caps both bitrate and vertical resolution. Presets whose resolution
exceeds the source video's SHALL be hidden.

#### Scenario: 1080p source
- **WHEN** the user opens the quality menu while playing a 1080p video
- **THEN** the menu lists Original, 1080p 20 Mbps, 1080p 10 Mbps, 720p 4 Mbps, 480p 1.5 Mbps and 360p 720 kbps, but not 4K 40 Mbps

#### Scenario: Unknown source resolution
- **WHEN** the server does not report the source video's resolution
- **THEN** the menu lists Original and every preset

### Requirement: Original quality
When "Original" is selected the app SHALL play the source file as-is if it can play its formats locally (see
playback-formats); otherwise it SHALL have the server convert only what it cannot play, without reducing
resolution.

#### Scenario: Supported file
- **WHEN** Original is selected for an MKV with HEVC video and E-AC-3 audio
- **THEN** the app plays the file as-is without server conversion

#### Scenario: Unsupported video codec
- **WHEN** Original is selected for a file with MPEG-2 video
- **THEN** the server converts the video at the source resolution and the stream plays

### Requirement: Preset quality
When a preset is selected the app SHALL request a stream whose bitrate and resolution do not exceed the
preset; if the source already fits within the preset and is playable, the server MAY deliver it unchanged.

#### Scenario: Lower quality requested
- **WHEN** the user selects 720p 4 Mbps for a 1080p 25 Mbps source
- **THEN** the stream delivered is at most 720 pixels tall and at most about 4 Mbps

#### Scenario: Source already below preset
- **WHEN** the user selects 1080p 20 Mbps for a 720p 3 Mbps H.264 source
- **THEN** the source plays without transcoding

### Requirement: Switch quality during playback
The app SHALL let the user change quality from the player at any time. Playback SHALL continue from the
position at the moment of switching (within 2 seconds) and keep its play/pause state.

#### Scenario: Downgrade mid-movie
- **WHEN** the user switches from Original to 480p 1.5 Mbps at 1:02:30 while playing
- **THEN** playback continues at 480p near 1:02:30 without returning to the details screen

#### Scenario: Switch while paused
- **WHEN** the user switches quality while playback is paused at 20:00
- **THEN** the video is shown at 20:00 in the new quality and stays paused

#### Scenario: Selecting the current quality
- **WHEN** the user selects the quality that is already active
- **THEN** nothing is reloaded and playback is not interrupted

### Requirement: Uninterrupted switching
While a new quality loads, the current stream SHALL keep playing. Once the new stream is ready the app SHALL
replace the old one without a pause or black frame longer than 1 second, and end any server transcoding job the
old stream used.

#### Scenario: Old stream keeps playing while new one loads
- **WHEN** the user switches quality and the new stream takes several seconds to start
- **THEN** the old stream keeps playing until the new one is ready, then playback continues in the new quality

#### Scenario: Old transcode cleaned up
- **WHEN** a switch away from a transcoded stream completes
- **THEN** the server's transcoding job for the old stream ends

### Requirement: Failed quality switch
If the new quality cannot be loaded, the app SHALL keep playing the previous stream, keep the previous quality
selected, and tell the user the switch failed.

#### Scenario: Server rejects the new stream
- **WHEN** the server fails to provide a stream for the selected quality
- **THEN** playback continues in the previous quality and the app shows a "couldn't switch quality" message

### Requirement: Active quality indicator
The player SHALL show the selected quality and how the stream is delivered: Direct Play (file as-is), Direct
Stream (video unchanged, other streams converted by the server), or Transcode (video re-encoded).

#### Scenario: Transcoded preset
- **WHEN** the user plays at 720p 4 Mbps and the server transcodes the video
- **THEN** the player shows "720p 4 Mbps · Transcode"

#### Scenario: Direct play
- **WHEN** an MKV/HEVC file plays at Original quality
- **THEN** the player shows "Original · Direct Play"

### Requirement: Remembered default quality
The app SHALL use the quality the user last selected as the starting quality for later playback on the same
server, including after relaunch. Before any selection, the default SHALL be Original.

#### Scenario: Default on first use
- **WHEN** the user plays a video for the first time after signing in
- **THEN** playback starts at Original quality

#### Scenario: Preference carries over
- **WHEN** the user switches to 720p 4 Mbps, closes the player, and later plays a different video
- **THEN** the new video starts at 720p 4 Mbps

#### Scenario: Remembered preset hidden for source
- **WHEN** the remembered quality is 4K 40 Mbps and the user plays a 1080p video
- **THEN** playback starts at Original, and the remembered preference stays 4K 40 Mbps
