# Spec Delta

## Purpose

Lets the iPhone app take films and episodes along: download them in the background, play them with
no connection, send what was watched back to the server, and keep the next episode coming.

## ADDED Requirements

### Requirement: Download a film or an episode
The iPhone app SHALL offer Download for every film and episode, on its detail sheet and on its row
in a season, showing the expected size before the download, its progress during, and a downloaded
mark after. Tapping a download in progress SHALL offer to cancel it; tapping a downloaded one SHALL
offer to delete it.

#### Scenario: Download from the detail sheet
- **WHEN** the user opens a film's sheet and taps Download · 6.1 GB
- **THEN** the button shows the download's progress, and once complete it shows Downloaded

#### Scenario: Cancel a download
- **WHEN** the user taps a download that is halfway and confirms Cancel
- **THEN** the transfer stops, the partial file is removed and the button offers Download again

### Requirement: Phone-sized copies
A download SHALL be a copy of at most 1080p and about 8 Mbps video, with one audio track (the one
the server picks for the user) and no subtitle burnt in, made by the server. A file the server says
plays as it is within that size SHALL be downloaded unchanged instead.

#### Scenario: A large remux
- **WHEN** the user downloads a 4K remux of 60 Mbps
- **THEN** the phone receives a 1080p copy of about 8 Mbps with the user's audio track

#### Scenario: A small file
- **WHEN** the user downloads a 1080p file of 5 Mbps that the phone plays directly
- **THEN** the original file is downloaded, with all its audio and subtitle tracks

### Requirement: Background, Wi-Fi only
Downloads SHALL run in the background and continue while the app is closed or the phone is locked,
SHALL use Wi-Fi only and show Waiting for Wi-Fi otherwise, and SHALL be kept out of iCloud backups.
An interrupted original SHALL resume where it stopped; an interrupted server copy SHALL start again.
A download that fails for good SHALL say why and offer to try again.

#### Scenario: Leave the app while downloading
- **WHEN** the user starts a download and leaves the app for an hour on Wi-Fi
- **THEN** the download finishes, and the Downloads tab shows it ready when the app is opened

#### Scenario: On cellular
- **WHEN** the user taps Download with no Wi-Fi
- **THEN** the download shows Waiting for Wi-Fi and starts once the phone joins a Wi-Fi network

#### Scenario: Phone full
- **WHEN** the phone runs out of space during a download
- **THEN** the download stops with "Not enough space" and Try again

### Requirement: Downloads tab
The iPhone app SHALL have a Downloads tab listing downloaded and downloading films and series, with
their posters, sizes and progress, readable with no connection. A series SHALL open to its downloaded
episodes. Swiping a row SHALL delete it. Titles the app picked SHALL be marked Downloaded for you.
With nothing downloaded, the tab SHALL say how to download.

#### Scenario: A series with three episodes
- **WHEN** the user has downloaded three episodes of one series and opens Downloads
- **THEN** the series appears once with "3 episodes" and its total size, and opens to the three episodes

#### Scenario: Delete with a swipe
- **WHEN** the user swipes a downloaded film and taps Delete
- **THEN** the film leaves the list and its space is freed

### Requirement: Play a download
A downloaded title SHALL play from the phone, connected or not, in the same player, starting at the
last position known to the phone or server, with its downloaded subtitles. With no connection, a
title that is not downloaded SHALL not offer to play.

#### Scenario: On a plane
- **WHEN** the user, with no connection, taps a downloaded episode they stopped halfway
- **THEN** it plays from where they stopped, with subtitles, and skipping and scrubbing work

#### Scenario: Downloaded and online
- **WHEN** the user plays a downloaded film at home on Wi-Fi
- **THEN** it plays the downloaded copy, not a stream from the server

### Requirement: Progress back to the server
Where the user stops in a download, and whether they finished it, SHALL be kept on the phone and
sent to the server as soon as it can be reached. Progress the server got from another device after
the phone's playback SHALL be kept.

#### Scenario: Back from a trip
- **WHEN** the user watches two episodes offline and opens the app at home
- **THEN** the server marks both watched, and Next up on every device shows the episode after them

#### Scenario: Watched elsewhere since
- **WHEN** the user stops a film offline at 20 minutes, then watches it to 1:10 on the TV before the phone reconnects
- **THEN** the server keeps 1:10

### Requirement: Smart Downloads
Finishing a downloaded episode SHALL delete it and download the next unwatched episode of the
series, once the server knows the episode was watched and the phone is on Wi-Fi, unless that episode
is already downloaded. The new episode SHALL be the user's own download if the finished one was,
and Downloaded for you otherwise. There is no setting.

#### Scenario: Binge on the train
- **WHEN** the user finishes downloaded episode 3 offline and later reaches Wi-Fi
- **THEN** episode 3 is deleted and episode 4 downloads

#### Scenario: End of the series
- **WHEN** the user finishes the last downloaded episode and no unwatched episode follows
- **THEN** it is deleted and nothing new is downloaded

### Requirement: Downloads for you
The app SHALL keep downloaded, with no setting, the next unwatched episode of each of the first 3
shows in Next up and the film at the top of Continue watching, in that order. It SHALL download only
on Wi-Fi, keep at least 5 GB of the phone free, and hold at most 15 GB of these titles; titles that
don't fit SHALL wait. A title already downloaded by the user SHALL count as ready.

#### Scenario: Something ready by morning
- **WHEN** the user watches episode 2 of a show at home in the evening and leaves the phone on Wi-Fi overnight
- **THEN** episode 3 is on the phone the next morning, marked Downloaded for you, without the app being opened

#### Scenario: Over the budget
- **WHEN** the next episodes of three shows and the top film together would need 22 GB
- **THEN** titles are downloaded in that order until the next one would pass 15 GB, and the rest wait

#### Scenario: Phone nearly full
- **WHEN** the phone has 6 GB free and the next pick is 3 GB
- **THEN** it is not downloaded

### Requirement: Downloads for you leave on their own
A title downloaded for you SHALL be deleted once it is watched, or once it is no longer among the
picks. A pick the user deletes SHALL not be picked again. Playing a pick SHALL not change whose it is;
the user's own downloads SHALL never be deleted by the app except by Smart Downloads and signing out.

#### Scenario: Show finished elsewhere
- **WHEN** a downloaded-for-you episode is watched on the TV
- **THEN** the phone deletes it the next time it reaches the server and downloads the episode after it

#### Scenario: Not interested
- **WHEN** the user deletes a downloaded-for-you film
- **THEN** that film is not downloaded for them again, while it stays at the top of Continue watching

### Requirement: Open without a connection
Opened with no network, the iPhone app SHALL go to the Downloads tab. Home and the libraries, when
they cannot load, SHALL offer Go to Downloads.

#### Scenario: Flight mode
- **WHEN** the user opens the app in flight mode with downloads on the phone
- **THEN** it opens on Downloads, ready to play

### Requirement: Signing out removes downloads
Signing out SHALL delete every download and the progress waiting to be sent, after sending what can
be sent.

#### Scenario: Sign out
- **WHEN** the user signs out with four downloads on the phone
- **THEN** the downloads are deleted and their space is freed
