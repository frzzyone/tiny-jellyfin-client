# Spec Delta

## MODIFIED Requirements

### Requirement: Text subtitle display
The app SHALL display text subtitles (SRT, WebVTT, MP4 timed text, and SSA/ASS shown as plain text without
styling or positioning) over the bottom of the video picture, inside the image rather than in any letterbox
or pillarbox bars, in time with playback, scaled with the picture size.

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

## ADDED Requirements

### Requirement: Subtitle font
The user SHALL be able to choose the subtitle font (family, face and point size) with the system Font
panel from the player's subtitle menu and the Playback menu, restore the default font, and have the
choice remembered across launches and applied to every item. The chosen size is the size on a
1080-line picture and scales with the picture.

#### Scenario: Choose a font
- **WHEN** the user opens the font picker while a film with subtitles is playing and selects Helvetica Bold 60
- **THEN** the subtitles on screen change to Helvetica Bold at 60 points for a 1080-line picture, without playback stopping

#### Scenario: Font is remembered
- **WHEN** the user has chosen a font, quits the app and plays another item with subtitles
- **THEN** the subtitles use the chosen font

#### Scenario: Default font
- **WHEN** the user chooses "Default Font"
- **THEN** subtitles return to the app's default font and size, and the menu shows the default as current

#### Scenario: Size scales with the picture
- **WHEN** the chosen size is 48 and the picture is 540 lines tall
- **THEN** the text is drawn at 24 points
