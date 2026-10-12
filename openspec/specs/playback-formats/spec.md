# playback-formats Specification

## Purpose
Defines which media files the app plays as-is on the Mac, how it falls back to server conversion for the rest,
and how HDR, Dolby Vision and Dolby Atmos content is presented.

## Requirements

### Requirement: Local playback of supported formats
The app SHALL play files without server conversion when the container is MKV, MP4, MOV, M4V, MPEG-TS or WebM,
the video is H.264 or HEVC (8- or 10-bit), or AV1 on Macs with an AV1 hardware decoder, and the audio is any of
AAC, MP3, AC-3, E-AC-3, FLAC, ALAC, Opus, Vorbis, DTS, DTS-HD, TrueHD or PCM.

#### Scenario: MKV with HEVC 10-bit and DTS
- **WHEN** the user plays an MKV file with HEVC Main 10 video and DTS audio at Original quality
- **THEN** the file plays as-is with no conversion on the server

#### Scenario: AV1 on a Mac with hardware decoding
- **WHEN** the user plays an AV1 file on a Mac whose hardware can decode AV1
- **THEN** the file plays as-is with no conversion on the server

### Requirement: Server conversion for unsupported formats
When a file contains a video codec the app cannot play locally (for example VC-1, MPEG-2, MPEG-4 Part 2, VP9,
or AV1 without a hardware decoder), the app SHALL have the server convert only the streams it cannot play,
keeping the others unchanged.

#### Scenario: VC-1 video
- **WHEN** the user plays a file with VC-1 video and AC-3 audio at Original quality
- **THEN** the server converts the video, the AC-3 audio is passed through unchanged, and the source resolution is kept

#### Scenario: AV1 on a Mac without hardware decoding
- **WHEN** the user plays an AV1 file on a Mac without an AV1 hardware decoder
- **THEN** the server converts the video to a format the Mac decodes in hardware, and the video plays

### Requirement: HDR output
The app SHALL present HDR10 and HLG video in HDR on displays that support extended dynamic range, and SHALL
show it with correct tone mapping on SDR displays.

#### Scenario: HDR10 on an XDR display
- **WHEN** the user plays an HDR10 movie on a MacBook Pro with a Liquid Retina XDR display
- **THEN** the video is shown in HDR with highlights brighter than the SDR interface around it

#### Scenario: HDR10 on an SDR display
- **WHEN** the user plays the same movie on an SDR external display
- **THEN** the video is shown tone-mapped, without washed-out or overly dark colours

### Requirement: Dolby Vision
The app SHALL present Dolby Vision Profile 5 and Profile 8 video as Dolby Vision where the Mac and display
support it. For Profile 7 it SHALL play the HDR10 base layer.

#### Scenario: Profile 8.1 file
- **WHEN** the user plays an MKV with Dolby Vision Profile 8.1 on a Dolby Vision-capable Mac display
- **THEN** the video is presented in Dolby Vision without server conversion

#### Scenario: Profile 7 file
- **WHEN** the user plays a Dolby Vision Profile 7 file
- **THEN** the HDR10 base layer plays in HDR, without server conversion

### Requirement: Dolby Atmos and multichannel audio
The app SHALL pass E-AC-3 audio, including Dolby Atmos (E-AC-3 JOC), to macOS unchanged so Atmos-capable outputs
render it. Other multichannel audio SHALL play with all channels, downmixed by macOS to the available speakers.

#### Scenario: Atmos with AirPods Pro
- **WHEN** the user plays a movie with an E-AC-3 Atmos track using AirPods Pro
- **THEN** macOS presents the audio as Dolby Atmos (spatial audio)

#### Scenario: 5.1 TrueHD on stereo speakers
- **WHEN** the user plays a TrueHD 5.1 track on a Mac with stereo speakers
- **THEN** all channels are heard, including centre-channel dialogue
