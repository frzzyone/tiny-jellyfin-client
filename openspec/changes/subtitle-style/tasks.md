# Tasks

## 1. Layout

- [x] 1.1 Add `SubtitleLayout.pictureRect(video:in:)` and verify unit tests for letterbox, pillarbox, exact fit and unknown size
- [ ] 1.2 Make `SubtitleOverlay` position and size the text against the picture rect, and verify manually with a 2.39:1 film in full screen (text inside the picture) and a 16:9 window (unchanged)

## 2. Style model

- [x] 2.1 Add `SubtitleStyle` (font name + reference size, scaled font, fallback to the system font) with persistence keys in `AppPreferences`, and verify unit tests for scaling, fallback and the preferences round trip
- [x] 2.2 Publish `subtitleStyle` from `PlaybackController`, loaded from preferences and saved on change, and verify a controller test that a change is persisted

## 3. Picker

- [ ] 3.1 Add `SubtitleFontPanel` (Font panel via `NSFontManager`, `changeFont:` target) and the "Font…" / "Default Font" items in the subtitle menu and the Playback menu, and verify manually that choosing Helvetica Bold 60 changes the subtitles live, that it survives a relaunch, and that "Default Font" restores the original look
