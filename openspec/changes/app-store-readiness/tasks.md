## 1. Submission

- [x] 1.1 Privacy manifests for the apps and the Top Shelf; `ITSAppUsesNonExemptEncryption`; local-network text everywhere; `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`
- [ ] 1.2 Validate an archive per platform in Xcode's Organizer (needs the signing team)
- [ ] 1.3 App Store Connect: reserve "Kinema", privacy policy URL, "Data Not Collected", review notes with the demo server (https://demo.jellyfin.org/stable, demo / empty password; "Use a password instead" on Apple TV) and the plain-HTTP justification

## 2. Sign-in

- [x] 2.1 No scheme: https then http (`testAddressWithoutSchemeFallsBackToHTTP`); explicit https not downgraded, certificate message (`testExplicitHTTPSIsNotDowngraded`)
- [x] 2.2 Error pages aren't messages (`testServerErrorPagesAreNotShownAsMessages`)

## 3. Security

- [x] 3.1 Stream errors without the URL (`testFailedRequestErrorsDontCarryTheURL`, checked to fail without the fix)

## 4. Engine and controller

- [x] 4.1 Seek during a switch (`testSeekDuringSwitchAbandonsIt`)
- [x] 4.2 Overlapping seeks (`testOverlappingSeeksLandOnTheNewest`)
- [x] 4.3 Cancelled open stops at once (`testCancelledOpenStopsAtOnce`); abandoned start ends its transcode (`testClosingWhileOpeningEndsTheTranscode`)
- [x] 4.4 HLS seek reopens at the target (covered by the HLS seek tests)
- [x] 4.5 Backgrounding: pause unless Picture in Picture takes over, redraw on return (`testBackgroundPausesAndReturnRedraws`, `testPictureInPictureKeepsPlayingInTheBackground`); an interrupted display layer isn't a failure
- [ ] 4.5a Lock the phone and come back; swipe home with PiP; leave the Apple TV app mid-film (needs devices)
- [x] 4.6 Shared engine state behind its locks; Thread Sanitizer finds no races in the engine tests (it also found the packet queues' end-of-stream flag)

## 5. User experience

- [x] 5.1 Sign-in fields: URL keyboard, no capitals or autocorrect on iPhone; username/password AutoFill on iPhone and Mac
- [x] 5.2 One switch-error capsule on Mac, iPhone and Apple TV (`SwitchErrorCapsule`)
- [x] 5.3 Apple TV: the track panel scrolls past nine rows; "Watched" with Play Again / Close at the end
- [x] 5.4 Apple TV: the Top Shelf reloads when the session ends (sign-out or an expired token)
- [x] 5.5 iPhone: controls don't hide under VoiceOver; Magic Tap plays and pauses
- [ ] 5.6 Check on devices: sign-in keyboard and AutoFill (iPhone); a 40-track subtitle panel and the end card (Apple TV); Top Shelf after signing out; VoiceOver in the iPhone player
- [ ] 5.7 Dynamic Type in the iPhone browser (fonts are fixed sizes today)
