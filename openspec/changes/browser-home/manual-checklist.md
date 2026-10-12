# Manual checklist

What is left to verify by using the app. Tick the matching task in `tasks.md` when it passes, or
tell Claude. Everything here is implemented and unit-tested; what is missing is a person looking.

- [x] **3.1** The top bar lists Home plus exactly the video libraries (seen: Home, Movies, Shows); the
      account menu signs out (menu not yet exercised).
- [ ] **3.2** The hero is what you watched last; Enter with nothing selected resumes it; Start over
      starts from zero. With nothing in progress the hero is the next episode or the newest title.
- [ ] **3.3** Each discovery row matches what the Jellyfin web UI shows for the same query (Next up,
      latest, a genre, random unwatched). Surprise me (button or S) opens a quick look on a random
      unwatched film; pressing again picks another. The genre row switches in place.
- [ ] **3.4** Movies tab: Unwatched / Recently added / A–Z / Longest unseen and the genre pills each
      take one click; typing anywhere opens the search results and shows the match count; scrolling
      keeps loading. (Typing "hel" from Home with posted keys gave "hel" and 8 results; ↓ → then "p"
      gave "help" and 2 results. Pills and paging still need a click.)
- [ ] **3.5** Space or a click opens the quick look with poster, facts, badges, overview, progress;
      Resume / Play / Start over / Mark watched work and the card updates at once; ← → move to the
      neighbouring title; Esc closes. Series open to seasons and episodes; an episode row opens the
      quick look.
- [ ] **3.6** ↓ ↓ → Enter plays the third title of the second row; the outline follows the keys and
      the row scrolls to keep it in view; ⌘F focuses the search field. (Posted ↓ ↓ → then Space to
      the app with CGEvent on 2026-10-12: the outline moved hero → Next up → second title, and Space
      opened its quick look. Enter and ⌘F still need a hand.)
- [x] **3.7** Graphite chrome, off-white text, amber progress and Play (seen in screenshots of Home, the
      Movies tab, search results and the quick look); the player window is unchanged.

Screenshots taken on 2026-10-12 with `screencapture -l <window>` against the server: the hero
(Troy, time left, Resume / Start over), Next up stills, the shelf row, the Movies tab at 8
columns with "60 of 735", search results for "he" ("60 of 180"), and the quick look on Troy with
badges, overview, progress and the three buttons. What is left is the interaction: keys, Enter,
Mark watched updating the card, and the Shows tab.

Keyboard and tabs (2026-10-12, posted keys): ↓ ↑ → went hero → tabs → Movies and switched the
page; ⌘1/⌘2/⌘3 jump to a tab. A card under the real cursor showed the hover outline.
