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
- [ ] 4.5 Backgrounding on iPhone and Apple TV
- [ ] 4.6 Shared engine state behind its locks

## 5. User experience

- [ ] 5.1 iPhone sign-in fields: no autocapitalisation or autocorrect, AutoFill
- [ ] 5.2 Switch errors shown on iPhone and Apple TV
- [ ] 5.3 Apple TV: track panel scrolls; an end state after the film
- [ ] 5.4 Top Shelf cleared on sign-out
- [ ] 5.5 VoiceOver can bring the iPhone controls back
