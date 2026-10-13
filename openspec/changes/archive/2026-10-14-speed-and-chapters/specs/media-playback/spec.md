## ADDED Requirements

### Requirement: Playback speed
The player SHALL offer 0.75×, 1×, 1.25×, 1.5× and 2×, keeping the audio's pitch, and start each new item at 1×.

#### Scenario: Faster through a talk
- **WHEN** the user picks 1.5× during playback
- **THEN** the film plays half as fast again with voices at their normal pitch, and the next film starts at 1×

### Requirement: Chapters
When the server lists two or more chapters for an item, the player SHALL list them with their start times and
jump to a chosen one.

#### Scenario: Jump to a chapter
- **WHEN** the user picks "The Heist" (05:00) from the chapter list
- **THEN** playback continues from 05:00
