## 1. Switching

- [x] 1.1 A switch that times out restarts at the new quality from the same position, keeping subtitle and pause (`testSlowSwitchRestartsAtTheNewQuality`)
- [x] 1.2 A switch that fails for another reason keeps playing (`testSwitchErrorKeepsPlaying`) and stops its server transcode (`testFailedSwitchStopsItsTranscode`)

## 2. Server errors

- [x] 2.1 HTTP 500 is not retried; 502–504, 408 and 429 are (`testServerErrorsAreNotRetriedButGatewayErrorsAre`)
- [x] 2.2 A definitive failure stops FFmpeg at once and is reported as the server's answer (`testFailingSegmentsFailTheOpenFast`)
- [x] 2.3 Opening gives up after 60 s (`testOpenGivesUpAfterTheDeadline`)

## 3. Subtitles

- [x] 3.1 The burned-in subtitle is read from the transcoding URL (`testReportsTheSubtitleTheServerBurnsIn`); a default picture subtitle starts one stream (`testDefaultPictureSubtitleStartsOneStream`)
- [x] 3.2 Off asks the server for no subtitle (`testImageSubtitleIsBurnedInAndRemovedAgain`)

## 4. Against the server

- [ ] 4.1 A switch on a server that can't keep up restarts at the new quality (needs a slow server again)
- [x] 4.2 Avatar with its default PGS subtitle opens one stream
