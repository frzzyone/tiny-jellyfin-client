## Why

The engine played the container's best audio track and the players only listed the others (the
Apple TV said "Audio tracks can't be switched yet"). A film with a commentary, another language,
or a lossless and a lossy mix offered no choice, and the server's pick for the user's language
was ignored during Direct Play.

## What Changes

- Playback starts on the server's audio pick for the user (`DefaultAudioStreamIndex`).
- An Audio menu (Mac player and menu bar, iPhone chip, Apple TV panel) switches tracks: in place
  during Direct Play, since every track is in the file being read (the reader takes the new
  track while it re-reads from the clock: a short pause, one download); through the server
  otherwise, switched like a quality change. Quality switches and restarts keep the track.
- Tried first and dropped: a seamless switch reopening the same file with the other track. On a
  34 Mbps 4K remux over the internet the second download never caught up.

## Impact

`MediaSource.audioTrack`, `Pipeline` (audio stream chosen or changed with a seek),
`FFmpegEngine.selectAudioTrack`, `PlaybackService.resolveStream(audioStreamIndex:)`,
`PlaybackController` (audio options, selection, carryover), the three players, a debug hook
`TJ_AUTOPLAY_AUDIO`, a two-audio-track fixture.
