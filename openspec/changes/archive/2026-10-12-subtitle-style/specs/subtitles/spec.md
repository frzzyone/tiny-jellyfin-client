# Spec Delta

## MODIFIED Requirements

### Requirement: Text subtitle display
The app SHALL display text subtitles (SRT, WebVTT, MP4 timed text, and SSA/ASS shown as plain text without
styling or positioning) over the bottom of the video picture, inside the image rather than in any letterbox
or pillarbox bars, whether the bars come from the window's shape or are encoded into the frames, in time
with playback, scaled with the picture size.

#### Scenario: Embedded SRT track
- **WHEN** the user plays an MKV with an embedded SRT subtitle track selected
- **THEN** each subtitle line appears over the video at its start time and disappears at its end time

#### Scenario: Styled ASS track
- **WHEN** the selected track is ASS with styling tags and positioning
- **THEN** the dialogue text is shown at the bottom without raw style tags visible

#### Scenario: Full screen
- **WHEN** the user enters full screen with subtitles visible
- **THEN** the subtitle text scales up with the video

#### Scenario: Letterboxed picture
- **WHEN** a 2.39:1 film is shown full screen on a 16:9 display, leaving black bars above and below the picture
- **THEN** the subtitle text is drawn near the bottom edge of the picture, not in the bar below it, and its size follows the picture height rather than the screen height

#### Scenario: Pillarboxed picture
- **WHEN** a 4:3 video is shown in a window wider than its picture, leaving bars at the sides
- **THEN** the subtitle text is centred on the picture and wraps within its width

#### Scenario: Bars encoded into the frames
- **WHEN** a 2.39:1 film is stored as 16:9 frames with black bars above and below the image
- **THEN** within a few seconds of playback the subtitle text moves up to sit inside the image, and it stays there through dark scenes and fades to black
