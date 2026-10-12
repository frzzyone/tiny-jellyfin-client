#!/usr/bin/env bash
# Generates small media fixtures for PlayerCore tests with the ffmpeg CLI.
# Usage: scripts/make-fixtures.sh [output-dir]
set -euo pipefail

OUT="${1:-$(cd "$(dirname "$0")/.." && pwd)/Packages/PlayerCore/Tests/PlayerCoreTests/Fixtures}"
mkdir -p "$OUT/hls"
cd "$OUT"
FF=(ffmpeg -hide_banner -loglevel error -y)
DUR=6
VIDEO=(-f lavfi -i "testsrc2=size=320x180:rate=24:duration=$DUR")
STEREO=(-f lavfi -i "sine=frequency=440:sample_rate=48000:duration=$DUR")
SURROUND=(-f lavfi -i "sine=frequency=440:sample_rate=48000:duration=$DUR" -filter_complex "[1:a]pan=5.1|c0=c0|c1=c0|c2=c0|c3=c0|c4=c0|c5=c0[a]")
H264=(-c:v libx264 -preset ultrafast -g 24 -pix_fmt yuv420p)

echo "Writing fixtures to $OUT"

# H.264 + AAC in MP4 (keyframe every second).
"${FF[@]}" "${VIDEO[@]}" "${STEREO[@]}" "${H264[@]}" -c:a aac -b:a 96k -shortest h264_aac.mp4

# A lower bitrate of the same content, for splice tests.
"${FF[@]}" "${VIDEO[@]}" "${STEREO[@]}" "${H264[@]}" -b:v 150k -c:a aac -b:a 64k -shortest h264_aac_low.mp4

# HEVC Main 10 + E-AC-3 5.1 in MKV.
"${FF[@]}" "${VIDEO[@]}" "${SURROUND[@]}" -map 0:v -map "[a]" -c:v libx265 -preset ultrafast \
  -x265-params "keyint=24:log-level=error" -pix_fmt yuv420p10le -c:a eac3 -b:a 384k -shortest hevc10_eac3.mkv

# HDR10 HEVC with mastering display and content light level metadata.
"${FF[@]}" "${VIDEO[@]}" -c:v libx265 -preset ultrafast -pix_fmt yuv420p10le \
  -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
  -x265-params "keyint=24:log-level=error:hdr10=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400" \
  hdr10.mkv

# Audio codecs that take the decode path (video is H.264 so only the audio differs).
"${FF[@]}" "${VIDEO[@]}" "${SURROUND[@]}" -map 0:v -map "[a]" "${H264[@]}" -c:a dca -strict -2 -b:a 768k -shortest h264_dts.mkv
"${FF[@]}" "${VIDEO[@]}" "${SURROUND[@]}" -map 0:v -map "[a]" "${H264[@]}" -c:a truehd -strict -2 -shortest h264_truehd.mkv
has_encoder() { ffmpeg -hide_banner -encoders 2>/dev/null | grep -q " $1 "; }
for codec in flac:flac:flac opus:libopus:opus vorbis:libvorbis:vorbis mp3:libmp3lame:libshine pcm:pcm_s16le:pcm_s16le ac3:ac3:ac3 aac:aac:aac; do
  IFS=: read -r name enc fallback <<< "$codec"
  if ! has_encoder "$enc"; then enc="$fallback"; fi
  # FFmpeg's native opus/vorbis encoders are experimental and want stereo.
  "${FF[@]}" "${STEREO[@]}" -c:a "$enc" -strict -2 -ac 2 "audio_$name.mkv"
done

# Subtitles: SRT and ASS, embedded and external.
cat > subs.srt <<'SRT'
1
00:00:01,000 --> 00:00:02,500
Hello there.

2
00:00:02,000 --> 00:00:04,000
<i>Overlapping</i> line
second row

3
00:00:04,500 --> 00:00:05,500
Last one.
SRT
cat > subs.ass <<'ASS'
[Script Info]
ScriptType: v4.00+
PlayResX: 384
PlayResY: 288

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\an8\pos(10,10)}{\b1}Styled{\b0} text\Nsecond line
Dialogue: 0,0:00:03.50,0:00:05.00,Default,,0,0,0,,{\p1}m 0 0 l 100 0 100 100{\p0}Drawing gone
ASS
"${FF[@]}" "${VIDEO[@]}" "${STEREO[@]}" -i subs.srt -i subs.ass -map 0:v -map 1:a -map 2:s -map 3:s \
  "${H264[@]}" -c:a aac -c:s:0 srt -c:s:1 ass \
  -metadata:s:s:0 language=eng -metadata:s:s:1 language=spa -metadata:s:s:1 title="Signs" \
  -disposition:s:0 default -t "$DUR" subs.mkv

# Annex B H.264 in MPEG-TS.
"${FF[@]}" "${VIDEO[@]}" "${STEREO[@]}" "${H264[@]}" -c:a aac -shortest annexb.ts

# HLS with MPEG-TS segments (what our transcoding profile asks Jellyfin for; FFmpeg 7.1 cannot
# seek HLS with fMP4 segments). -max_delay 0 keeps the packet timestamps equal to item time.
"${FF[@]}" -i h264_aac.mp4 -c copy -f hls -max_delay 0 -hls_time 2 -hls_playlist_type vod \
  -hls_segment_filename "hls/seg%d.ts" hls/main.m3u8

# The same stream written the way Jellyfin writes it (DynamicHlsController): -max_delay 5000000
# makes the MPEG-TS muxer stamp every packet 10 s late, while the playlist still runs from 0.
mkdir -p hls-jellyfin
"${FF[@]}" -i h264_aac.mp4 -c copy -copyts -avoid_negative_ts disabled -f hls -max_delay 5000000 \
  -hls_time 2 -hls_playlist_type vod -hls_segment_filename "hls-jellyfin/seg%d.ts" hls-jellyfin/main.m3u8

# Damaged files: garbage in the middle, and a truncated copy.
cp hevc10_eac3.mkv corrupt.mkv
size=$(wc -c < corrupt.mkv)
dd if=/dev/urandom of=corrupt.mkv bs=1 count=4096 seek=$((size / 2)) conv=notrunc status=none
head -c $((size / 2)) hevc10_eac3.mkv > truncated.mkv

echo "Done."
