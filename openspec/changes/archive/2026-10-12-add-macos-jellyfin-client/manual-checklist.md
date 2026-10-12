# Manual checklist

What is left to verify by using the app. Each line names the task in `tasks.md` it closes; tick the
task there (`- [ ]` → `- [x]`) when it passes, or tell Claude. Everything here is implemented and
unit-tested; what is missing is a person looking at the screen or listening.

Watch the logs while you go: `log stream --predicate 'subsystem == "app.tinyjellyfin"' --style compact`.

## Sign-in and library

- [ ] **3.4** Sign out, then sign in again. Wrong password shows "Incorrect username or password" and
      clears the field. Quit and relaunch: you land on the library without signing in.
- [ ] **4.2** Home shows Continue Watching with progress bars; the sidebar lists only movie and TV
      libraries (no music, books, live TV).
- [ ] **4.3** Open a library with more than 60 items: posters keep loading as you scroll. An item
      without artwork shows its title on a placeholder.
- [ ] **4.4** Series → seasons → episodes, in episode order, with watched ticks.

## Player

- [ ] **7.5** Space pauses, ←/→ skip 10 s / 30 s, ↑/↓ volume, F full screen, M mute, Esc leaves
      full screen. Controls hide after 3 s while playing and stay while paused. Scrubbing lands
      within a second.
- [ ] **7.6** Picture in Picture keeps position when entering and leaving. The keyboard play/pause
      key pauses. Control Center's Now Playing shows the title and progress.
- [ ] **7.7 (rest)** Play something to the very end: it shows as watched in Jellyfin web.
      If you have a DTS or TrueHD file, it should show "Original · Direct Play".
- [ ] **5.6** Lips match speech on dialogue 10 minutes into a file, and still do an hour later.

## Picture and sound (needs your display and speakers)

- [ ] **6.1** An HDR10 file on an XDR display looks HDR (highlights brighter than the UI); on an SDR
      display it is not washed out. Log line to confirm: `transfer=pq` in `Opened …`.
- [ ] **6.2** "He Built the Saturn V" (Dolby Vision P8): the log says `videoFormat=dolby-vision`
      and the picture is not green/purple or dim. If it ever logs a fallback, tell Claude.
- [ ] **6.3** An E-AC-3 Atmos track with AirPods Pro or Atmos speakers: Control Center shows
      Spatial Audio active. If not, say so — the fallback (decode to multichannel PCM) is a one-line
      change.

## Subtitles

- [ ] **8.3** Subtitle menu lists tracks by language; switching tracks mid-playback does not jump.
      Embedded SRT and ASS display as plain text, scaled up in full screen.
- [ ] **8.4** Pick a PGS/image track: position is kept, the badge changes to Transcode, subtitles
      are burned in. Pick Off: back to Direct Play, position kept.

## Quality switching

- [ ] **9.4** Switch from Original to 480p mid-movie: the picture continues from the same spot with
      no gap longer than a second, and the badge reads "480p 1.5 Mbps · Transcode". Switch while
      paused: stays paused at the same frame. Pick the current quality: nothing happens.
- [ ] **10.1 (rest)** After several switches and quitting, the Jellyfin dashboard shows no
      transcodes running. Subtitles stay in sync across a switch. If you have a VC-1 or MPEG-2
      file: "Original · Transcode" at the source resolution.

The change was archived on 2026-10-12 with these still open; see `BACKLOG.md` at the repo root.
