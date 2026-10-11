#!/usr/bin/env bash
# Builds the FFmpeg subset PlayerCore needs, for macOS 14+ (arm64 + x86_64), as one dynamic
# library: Vendor/FFmpeg/lib/libffmpeg.dylib with headers in Vendor/FFmpeg/include.
#
# - LGPL only: --disable-gpl --disable-nonfree, no external libraries besides zlib/bzip2.
# - Demuxing plus audio and text-subtitle decoding only. Video is decoded by VideoToolbox.
# - Networking: only the `http` protocol is compiled in, so FFmpeg's HLS demuxer recognises
#   URLs. Every actual request goes through PlayerCore's io_open callback and URLSession.
# - Dynamically linked, which keeps LGPL obligations simple (see THIRD_PARTY_NOTICES.md).
#
# Usage: scripts/build-ffmpeg.sh   (re-runs are no-ops while Vendor/FFmpeg matches this script)
set -euo pipefail

FFMPEG_VERSION="7.1.1"
MACOS_MIN="14.0"
ARCHS=(arm64 x86_64)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Vendor/FFmpeg"
WORK="$ROOT/Vendor/.ffmpeg-build"
STAMP="$OUT/BUILD-INFO"
SCRIPT_HASH="$(shasum -a 256 "$0" | cut -d' ' -f1)"

if [[ -f "$STAMP" ]] && grep -q "$SCRIPT_HASH" "$STAMP"; then
  echo "FFmpeg $FFMPEG_VERSION already built in $OUT"
  exit 0
fi

[[ "$(uname)" == "Darwin" ]] || { echo "This script builds for macOS and must run on macOS." >&2; exit 1; }

mkdir -p "$WORK"
cd "$WORK"
if [[ ! -d "FFmpeg-n$FFMPEG_VERSION" ]]; then
  curl -fsSL "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n$FFMPEG_VERSION.tar.gz" -o ffmpeg.tar.gz
  tar xzf ffmpeg.tar.gz
fi
SRC="$WORK/FFmpeg-n$FFMPEG_VERSION"

DECODERS="aac,aac_latm,ac3,eac3,dca,truehd,mlp,flac,alac,opus,vorbis,mp1,mp2,mp3,mp3float"
DECODERS+=",pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f32be,pcm_bluray,pcm_dvd"
DECODERS+=",srt,subrip,ass,ssa,webvtt,mov_text,text"
DEMUXERS="matroska,mov,mpegts,hls,srt,ass,webvtt,flac,wav,aac,ac3,eac3,mp3,dts,truehd"
PARSERS="h264,hevc,av1,aac,aac_latm,ac3,dca,mlp,flac,opus,vorbis,mpegaudio"

CONFIGURE_FLAGS=(
  --disable-autodetect --enable-zlib --enable-bzlib
  --disable-gpl --disable-nonfree --disable-programs --disable-doc
  --disable-avdevice --disable-avfilter --disable-swscale --disable-postproc
  --disable-encoders --disable-muxers --disable-hwaccels --disable-devices --disable-filters --disable-bsfs
  --disable-decoders --enable-decoder="$DECODERS"
  --disable-demuxers --enable-demuxer="$DEMUXERS"
  --disable-parsers --enable-parser="$PARSERS"
  --enable-network --disable-protocols --enable-protocol=file,http,tcp
  --enable-static --disable-shared --enable-pic
)

for arch in "${ARCHS[@]}"; do
  build="$WORK/build-$arch"
  if [[ -f "$build/install/lib/libavformat.a" ]]; then continue; fi
  mkdir -p "$build"
  (
    cd "$build"
    extra=()
    if [[ "$arch" != "$(uname -m)" ]]; then extra+=(--enable-cross-compile); fi
    if [[ "$arch" == "x86_64" ]]; then extra+=(--disable-x86asm); fi
    "$SRC/configure" --prefix="$build/install" --arch="$arch" --target-os=darwin \
      --cc="clang -arch $arch" \
      --extra-cflags="-mmacosx-version-min=$MACOS_MIN" --extra-ldflags="-mmacosx-version-min=$MACOS_MIN" \
      "${extra[@]}" "${CONFIGURE_FLAGS[@]}"
    make -j"$(sysctl -n hw.ncpu)"
    make install
  )
done

# One universal dynamic library containing all four FFmpeg libraries.
mkdir -p "$OUT/lib"
LIBS=(libavformat libavcodec libswresample libavutil)
for arch in "${ARCHS[@]}"; do
  inputs=()
  for lib in "${LIBS[@]}"; do inputs+=("$WORK/build-$arch/install/lib/$lib.a"); done
  clang -arch "$arch" -dynamiclib -mmacosx-version-min="$MACOS_MIN" \
    -install_name @rpath/libffmpeg.dylib -compatibility_version 1 -current_version 1 \
    -Wl,-all_load "${inputs[@]}" -lz -lbz2 -o "$WORK/libffmpeg-$arch.dylib"
done
lipo -create "$WORK"/libffmpeg-*.dylib -output "$OUT/lib/libffmpeg.dylib"

# Headers are architecture-independent for these little-endian targets.
rm -rf "$OUT/include"
cp -R "$WORK/build-${ARCHS[0]}/install/include" "$OUT/include"
cp "$SRC/COPYING.LGPLv2.1" "$OUT/COPYING.LGPLv2.1"

if nm -gU "$OUT/lib/libffmpeg.dylib" | grep -q " _avformat_open_input$"; then
  echo "Exports OK"
else
  echo "libffmpeg.dylib does not export avformat_open_input" >&2
  exit 1
fi
if grep -q "enable-gpl" "$WORK/build-${ARCHS[0]}/ffbuild/config.mak"; then
  echo "GPL components enabled — refusing." >&2
  exit 1
fi

{
  echo "FFmpeg $FFMPEG_VERSION for macOS $MACOS_MIN+ (${ARCHS[*]})"
  echo "script-sha256: $SCRIPT_HASH"
  echo "license: $(grep '#define FFMPEG_LICENSE' "$WORK/build-${ARCHS[0]}/config.h" | cut -d'"' -f2)"
  echo "configure: ${CONFIGURE_FLAGS[*]}"
} > "$STAMP"
cat "$STAMP"
