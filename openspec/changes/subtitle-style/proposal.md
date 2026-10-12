# Proposal

## Why

Subtitles are drawn against the whole player window, so on a wide film in full screen they land in
the black bar under the picture instead of over it, and the font is fixed to the system font. Both
came up in the first viewing sessions after the initial release.

## What Changes

- Subtitle text is positioned and sized against the video picture (the aspect-fitted image), not the
  window. In the letterboxed cases (full screen, Picture in Picture, a window being resized) the text
  sits inside the image like every other player; when the window has the video's shape nothing moves.
- The user can choose the subtitle font (family, face and size) with the standard macOS Font panel,
  from the subtitle menu in the player and from the Playback menu. The choice persists across
  launches and applies to every item. "Default Font" restores the system font.
- The chosen size is relative to the picture: it is the point size on a 1080-line picture and scales
  with the window and full screen, as the current fixed size already does.

Assumptions:
- Colour, outline and background styling stay as they are (white, shadowed). The Font panel's colour
  and underline controls are ignored. Styled ASS rendering stays out of scope.
- One font setting for the whole app, not per server or per item.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities
- `subtitles`: the "Text subtitle display" requirement moves the text into the picture; a new
  "Subtitle font" requirement covers choosing and remembering the font.

## Impact

- App only: the subtitle overlay in the player window, the subtitle menus, a small style model with
  its persistence, and two new preference keys. No engine or server-API change.
- New AppKit use: `NSFontPanel`/`NSFontManager` for the picker (system framework, no dependency).
