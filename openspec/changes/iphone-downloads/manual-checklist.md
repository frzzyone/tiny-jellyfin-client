# Manual checklist: iPhone downloads

Verified on the simulator against the demo server (2026-11-12):
- an original downloaded in the background session and survived a relaunch;
- two Downloads for you picks started on their own;
- a downloaded film played from the phone (opened in 0.1 s);
- its stop reached the server with the time it was watched;
- the tab and the sheet match the mockups, also at the largest text size.

Verified with `curl` against jellyfin.dcm.wtf (12.4.0):
- the download profile gets an original or a `stream.ts` copy;
- copies start at 1.44 s and the server encodes them at about 13× real time;
- `POST /UserItems/{id}/UserData` works.

These need a real iPhone:

- [ ] **Server copy, locked phone (5.1, 7.1):** download a 4K remux on Wi-Fi and lock the phone.
  It finishes, Downloads shows it, and it plays from the start with no 1.4 s jump. Seek, then
  resume after closing the app.
- [ ] **Wi-Fi only (5.2):** turn Wi-Fi off with cellular on and tap Download. It reads Waiting for
  Wi-Fi, and starts once Wi-Fi is back.
- [ ] **Interrupted copy:** while a copy downloads, switch Wi-Fi off for a minute, then on. It
  starts over (up to 3 times), and the server's dashboard shows no leftover encode.
- [ ] **Flight mode (6.3):**
  - Open the app: it lands on Downloads.
  - Home shows You're offline with Go to Downloads.
  - A title that isn't downloaded has no Play button; a downloaded one plays with subtitles.
- [ ] **Back online (6.4):**
  - Finish a downloaded episode in flight mode, then turn flight mode off.
  - The server marks the episode watched, the phone deletes it, and the next episode downloads.
- [ ] **Downloads for you (5.3, 7.1):**
  - Leave the phone on Wi-Fi overnight after watching an episode at home. By morning the next
    episode is there, marked Downloaded for you.
  - In the Downloads footer, the total stays within 15 GB.
  - To force the refresh task, pause in the debugger and run:
    `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"app.tinyjellyfin.Tinyfin.refresh"]`
- [ ] **Delete a pick:** swipe a Downloaded for you title and delete it. It doesn't come back while
  it is still in Next up or Continue watching.
- [ ] **Sign out:** with downloads on the phone, sign out. The Downloads folder empties, and
  Settings › General › iPhone Storage shows the space back.
