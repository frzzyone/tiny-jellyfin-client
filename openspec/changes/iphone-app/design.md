# Design

## Context

What is portable today: JellyfinKit (Foundation only, Linux-tested), PlayerCore `Core/` (FFmpeg
demux, byte sources, audio/subtitle decode) and `Apple/` (sample buffers, renderers, splicing,
letterbox detection), none of which imports AppKit. App-level models (`SessionModel`,
`PlaybackController`, `HomeModel`, `BrowserModel`, `LibraryGridModel`, `ItemLabels`) are SwiftUI
and Foundation only. Mac-only: the FFmpeg dylib build, E-AC-3/AC-3 passthrough, and seven app
files (`BrowserView`, `KeyMonitor`, `PlayerWindowView`, `NowPlaying`, `SubtitleLayout`'s `NSFont`,
`DebugAutoplay`, the app scene).

## Goals / Non-Goals

- One codebase, two app targets; the Mac app unchanged in behaviour.
- The phone plays what the Mac plays, without the server transcoding audio.
- Non-goals: iPad layout, App Store distribution, downloads, CarPlay, tvOS, widgets.

## Decisions

### D1. FFmpeg as an XCFramework
`scripts/build-ffmpeg.sh --ios` cross-compiles the same LGPL configuration for `arm64-apple-ios17.0`
and `arm64-apple-ios17.0-simulator`, links each into a dynamic framework (`FFmpeg.framework`, so the
LGPL "replaceable library" form survives as far as iOS allows), and bundles them with the macOS
dylib into `Vendor/FFmpeg/FFmpeg.xcframework`. PlayerCore's `CFFmpeg` target switches from
`unsafeFlags` linking to a `binaryTarget` on the XCFramework (through a symlink, since SwiftPM wants
binary targets inside the package), which also cleans up the Mac build: Xcode now embeds and signs
`FFmpeg.framework` itself. Headers stay where they were (`Vendor/FFmpeg/include`, identical on
every Apple platform), still passed with `-I`.

### D2. Audio
On iOS the audio renderer has no passthrough, but it decodes AC-3 and E-AC-3 itself, so the engine's
existing `.passthrough` path (compressed Dolby sample buffers) works unchanged: the system decodes
them. TrueHD, DTS and the rest already go through FFmpeg to Float32 PCM with their channel layout.
Verified on the simulator: the engine's play tests for AAC, E-AC-3, DTS and TrueHD now also assert
the audio renderer did not fail, and all pass. The player sets AVAudioSession `.playback`/
`.moviePlayback` with `setSupportsMultichannelContent(true)` so 5.1 reaches spatial audio. The
DeviceProfile needs no change: every codec it declares plays on the phone. (The capability check
the plan foresaw turned out unnecessary.)

### D3. Folder split
`App/Shared` (models, `ItemLabels`, `BrowserStyle` colours, `SubtitleLayout` geometry, the service
protocols), `App/macOS` (today's views), `App/iOS` (new views). `SubtitleFont` uses `CTFont` instead
of `NSFont` so it is shared. `NowPlaying` already uses MediaPlayer; only its artwork type differs
(`NSImage`/`UIImage`) behind a typealias.

### D4. iPhone UI
Mockups: the "Tiny Jellyfin · iPhone" row of https://claude.ai/artifact/N34ygeBdXoi63aVu2vADfB
(Home, detail sheet, Movies tab, landscape player).
SwiftUI `TabView` (Home, Movies, Shows, Search). Home's large title is "Tiny Jellyfin" with the flat mark, not "Home"; the tab keeps the name Home. Home is a `ScrollView` of the same `HomeModel`
rows as horizontal `ScrollView`s with the Mac's card proportions scaled to the phone (posters
110 pt wide, stills 220 pt). The quick look becomes a `.sheet` with detents; Mark watched and the
neighbour logic are reused. Library tabs reuse `LibraryGridModel` with the filter pills in a
horizontal scroller. Keyboard navigation is not ported.

### D5. Player
A `UIViewRepresentable` hosting the engine's `displayLayer`, presented `.fullScreenCover`, forced
landscape while it is up. Controls are SwiftUI over the layer: tap toggles, double-tap thirds skip,
a scrubber with the existing seek path, quality and subtitle `Menu`s bound to the same
`PlaybackController`. PiP uses the same `AVPictureInPictureController(contentSource:)` with the
sample buffer layer as on the Mac; `UIBackgroundModes: audio` keeps playback alive.

### D6. Engine checks that must hold on device
- The HTTP-through-URLSession path, HLS seeks and the 10 s MPEG-TS offset are platform-neutral and
  covered by tests that will now also run on the iOS simulator.
- `displayedPixelBuffer()` exists on iOS 17.4+; the letterbox detector is the same.
- Memory: the demuxer queues are bounded by duration and bytes; their limits are halved on iOS.

## Risks / Trade-offs

- App Store distribution is out of scope until the LGPL question is answered (see proposal).
- Simulator video decode differs from device (no VideoToolbox HEVC 10-bit on some hosts); playback
  correctness is verified on a real phone, the simulator only builds and runs unit tests.
- Two UIs to keep in step; mitigated by sharing every model and label.
