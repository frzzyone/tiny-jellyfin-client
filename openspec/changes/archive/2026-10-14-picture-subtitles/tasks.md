## 1. Engine

- [x] 1.1 PGS/DVD/DVB decoders in the FFmpeg build; slices rebuild when flags change
- [x] 1.2 Decode picture events, open-ended until the next event or clear (`testPGSBitmaps`), keep the latest 80 (`testBitmapStoreKeepsTheLatestEventsOnly`)
- [x] 1.3 Decode only the selected track; re-read from the clock on selection (`testPictureSubtitlesFollowTheSelection`)

## 2. App

- [x] 2.1 Drawn during Direct Play, burnt in when transcoding, moving between the two with quality (`testPictureSubtitleDuringDirectPlayIsDrawnByTheApp`, `testPictureSubtitleIsBurnedInWhenTranscodingAndRemovedAgain`, `testPictureSubtitleMovesFromBurnInToDrawnWhenTheFilePlaysAsItIs`)
- [x] 2.2 Placed on the frame, scaled with the picture (`testPictureSubtitleIsPlacedOnTheFrame`)
- [x] 2.3 Profile: picture subtitles can be embedded

## 3. Against the server

- [x] 3.1 Avatar (4K AV1, TrueHD, default English PGS) plays as Direct Play with its subtitles drawn (screenshot, 2026-10-14)
- [ ] 3.2 iPhone fill mode and Apple TV: subtitles follow the picture (needs a person looking)
