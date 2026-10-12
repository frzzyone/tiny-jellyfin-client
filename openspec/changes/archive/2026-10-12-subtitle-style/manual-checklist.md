# Manual checklist

What is left to verify by using the app. Each line names the task in `tasks.md` it closes; tick the
task there when it passes, or tell Claude. Everything here is implemented and unit-tested; what is
missing is a person looking at the screen.

Watch the logs while you go: `log stream --predicate 'subsystem == "app.tinyjellyfin"' --style compact`.

- [ ] **1.3** A 2.39:1 film with a *text* subtitle track (SRT/ASS, not PGS) in full screen: the text
      sits inside the picture, in Helvetica Neue. In a 16:9 window nothing moved.
- [ ] **2.3** A file whose bars are encoded into the frames, again with a text track: within ~4 s
      the log shows `Picture bars: …` and the text moves up above the bar; it stays put through a
      fade to black; after ~20 s the log shows `Picture bars settled …`. The only visible movement
      is at most one or two steps downward in the first seconds.
- [ ] **3.2** A transcoded start (a quality preset, or a burn-in): the log shows
      `Video size known after open: …` then `Window …: resizing …`, and the window takes the video's
      shape instead of the size it had last time.

Not a bug: a PGS/VobSub track is burned in by the server, so its text is wherever the disc put it,
usually in the bar. See BACKLOG.md.
