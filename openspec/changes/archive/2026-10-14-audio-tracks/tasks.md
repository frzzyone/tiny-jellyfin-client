## 1. Engine

- [x] 1.1 Start on a given audio track (`testStartsOnTheAskedAudioTrack`)
- [x] 1.2 Change track in place with a re-read from the clock (`testAudioTrackChangesInPlace`); seamless switch to a stream with another track still works (`testAudioTrackSwitchIsSeamless`)

## 2. App

- [x] 2.1 Server's pick at start (`testDirectPlayStartsOnTheServersAudioPick`); in place during Direct Play, kept through quality switches (`testAudioTrackSwitchesWithoutAPause`); through the server when transcoding (`testTranscodedAudioSwitchAsksTheServer`); a failure keeps the track (`testFailedAudioSwitchKeepsTheTrack`)
- [x] 2.2 Audio menu on the Mac (player and menu bar), iPhone and Apple TV

## 3. Against the server

- [x] 3.1 Avatar, TrueHD to AC-3 during Direct Play: 3 s pause, one stream
- [ ] 3.2 Heard on a receiver / Apple TV (needs a person listening)
