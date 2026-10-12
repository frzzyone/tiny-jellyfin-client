# Proposal

## Why

Subtitles are drawn against the whole player window, so on a wide film in full screen they land in
the black bar under the picture instead of over it. Many files also carry their letterbox bars
inside the frames (a 2.39:1 film encoded as 16:9), and the text then sits in that bar too, hugging
the edge of the image. Both came up in the first viewing sessions after the initial release.

## What Changes

- Subtitle text is positioned and sized against the image: the aspect-fitted video minus any black
  bars found in the frames themselves. In full screen, Picture in Picture and while resizing the
  text sits inside the picture like every other player; when the window has the video's shape and
  the frames have no bars, nothing moves.
- Bars encoded into the frames are measured from the picture on screen a few seconds into
  playback, and only ever narrow as brighter frames come by, so a fade to black cannot push the
  subtitles up.
- The subtitle font becomes Helvetica Neue, 48 pt on a 1080-line picture, scaled with the picture
  as the previous fixed size already was. No font picker (considered and dropped).

Assumptions:
- Colour, outline and background styling stay as they are (white, shadowed). Styled ASS rendering
  stays out of scope.
- Pillarbox bars at the sides are not measured: the text is centred anyway.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities
- `subtitles`: the "Text subtitle display" requirement moves the text into the picture, including
  when the bars are part of the frames.

## Impact

- App: the subtitle overlay and its layout, the playback controller samples the displayed frame.
- PlayerCore (Apple): a letterbox detector over a decoded frame's luma plane, and the engine hands
  out the displayed frame (`AVSampleBufferVideoRenderer.displayedPixelBuffer`, macOS 14.4+; on
  14.0–14.3 bars in the frames are not detected and the text stays at the frame's bottom).
- No server-API change, no new dependency.
