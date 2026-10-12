# Design

## Context

`SubtitleOverlay` (App, `PlayerWindowView.swift`) lays the text out in a `GeometryReader` over the
whole player view: bottom-aligned with 7% of the view height below it and a font of 4.5% of the view
height. The window normally takes the video's shape, so this only goes wrong where it cannot: full
screen, Picture in Picture, and while resizing. There is no style model; the font is hard-coded.

## Goals / Non-Goals

- Text inside the aspect-fitted picture, sized by the picture. Pure geometry, unit-tested.
- A font choice that costs as little code as possible and feels native: the macOS Font panel.
- Persist the choice in `AppPreferences` (UserDefaults; it is not a secret).
- Non-goals: colour/outline/background options, per-item styles, ASS styling, a custom font browser.

## Decisions

### D1. `SubtitleLayout.pictureRect(video:in:)`
A pure function returning the aspect-fitted rectangle of the video inside the overlay's bounds (the
whole bounds when the video size is unknown). `SubtitleOverlay` positions a frame of that size at
that origin and keeps today's proportions relative to it: 7% of the picture height below the text,
8% of the picture width as side margins. The controller already publishes `videoSize`.

### D2. `SubtitleStyle` = font name + reference size
`struct SubtitleStyle { fontName: String?; size: Double }`. `fontName` is a PostScript name, nil for
the system font (semibold, as today). `size` is the point size on a 1080-line picture; the drawn size
is `size × pictureHeight / 1080`, never below 12. The default is 48, which is what 4.5% of 1080
rounds to, so existing users see no change. A font name that no longer exists on the Mac falls back
to the system font rather than failing.

### D3. The Font panel, driven by `SubtitleFontPanel`
`NSFontManager.shared.orderFrontFontPanel` with the manager's `target` set to a small `NSObject` that
implements `changeFont(_:)` and converts the current font through the manager. The panel is opened
with the style's font at its reference size, so the size the user sees is "points at 1080p". Colour,
underline and strikethrough changes (`changeAttributes:`) are ignored. One shared instance; the
system has one Font panel anyway.

### D4. Where the state lives
`PlaybackController.subtitleStyle` (observable, persisted through `AppPreferences` on change), so
the overlay and both menus share one source. Menus: a "Font…" item that names the current font, and
"Default Font" when a font is set, in `SubtitleMenu` and `PlaybackCommands`.

## Risks / Trade-offs

- `NSFontManager.target` is global; we set it whenever we open the panel, and nothing else in the
  app uses the Font panel, so it does not conflict.
- `AppPreferences` lives in JellyfinKit (Foundation only); two plain keys are fine there and keep
  all non-secret settings in one place.
