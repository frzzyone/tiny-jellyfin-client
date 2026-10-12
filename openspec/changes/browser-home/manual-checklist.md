# Manual checklist

What is left to verify by using the app. Tick the matching task in `tasks.md` when it passes, or
tell Claude. Everything here is implemented and unit-tested; what is missing is a person looking.

- [ ] **3.1** The top bar lists Home plus exactly the video libraries; the account menu signs out.
- [ ] **3.2** The hero is what you watched last; Enter with nothing selected resumes it; Start over
      starts from zero. With nothing in progress the hero is the next episode or the newest title.
- [ ] **3.3** Each discovery row matches what the Jellyfin web UI shows for the same query (Next up,
      latest, a genre, random unwatched). Surprise me (button or S) opens a quick look on a random
      unwatched film; pressing again picks another. The genre row switches in place.
- [ ] **3.4** Movies tab: Unwatched / Recently added / A–Z / Longest unseen and the genre pills each
      take one click; typing anywhere opens the search results and shows the match count; scrolling
      keeps loading.
- [ ] **3.5** Space or a click opens the quick look with poster, facts, badges, overview, progress;
      Resume / Play / Start over / Mark watched work and the card updates at once; ← → move to the
      neighbouring title; Esc closes. Series open to seasons and episodes; an episode row opens the
      quick look.
- [ ] **3.6** ↓ ↓ → Enter plays the third title of the second row; the outline follows the keys and
      the row scrolls to keep it in view; ⌘F focuses the search field.
- [ ] **3.7** Graphite chrome, off-white text, amber progress and Play; the player window is unchanged.
