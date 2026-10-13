#!/usr/bin/env bash
# Builds the FFmpeg subset PlayerCore needs as one dynamic framework per Apple platform, bundled as
# Vendor/FFmpeg/FFmpeg.xcframework (macOS 14+ arm64/x86_64, iOS 17+ arm64, iOS Simulator arm64),
# with the headers in Vendor/FFmpeg/include.
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
IOS_MIN="17.0"
# platform:arch:sdk:clang target. macOS builds keep their old directory names (build-<arch>).
SLICES=(
  "macos:arm64:macosx:arm64-apple-macos$MACOS_MIN"
  "macos:x86_64:macosx:x86_64-apple-macos$MACOS_MIN"
  "ios:arm64:iphoneos:arm64-apple-ios$IOS_MIN"
  "iossim:arm64:iphonesimulator:arm64-apple-ios$IOS_MIN-simulator"
)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Vendor/FFmpeg"
WORK="$ROOT/Vendor/.ffmpeg-build"
STAMP="$OUT/BUILD-INFO"
SCRIPT_HASH="$(shasum -a 256 "$0" | cut -d' ' -f1)"

if [[ -f "$STAMP" ]] && grep -q "$SCRIPT_HASH" "$STAMP"; then
  echo "FFmpeg $FFMPEG_VERSION already built in $OUT"
  exit 0
fi

[[ "$(uname)" == "Darwin" ]] || { echo "This script builds for Apple platforms and must run on macOS." >&2; exit 1; }

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

builddir() { [[ "$1" == macos ]] && echo "$WORK/build-$2" || echo "$WORK/build-$1-$2"; }

for slice in "${SLICES[@]}"; do
  IFS=: read -r platform arch sdk target <<< "$slice"
  build="$(builddir "$platform" "$arch")"
  if [[ -f "$build/install/lib/libavformat.a" ]]; then continue; fi
  mkdir -p "$build"
  (
    cd "$build"
    sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
    extra=()
    if [[ "$platform" != macos || "$arch" != "$(uname -m)" ]]; then extra+=(--enable-cross-compile); fi
    if [[ "$arch" == "x86_64" ]]; then extra+=(--disable-x86asm); fi
    "$SRC/configure" --prefix="$build/install" --arch="$arch" --target-os=darwin \
      --cc="$(xcrun --sdk "$sdk" -f clang) -target $target -isysroot $sysroot" \
      --extra-ldflags="-target $target -isysroot $sysroot" \
      ${extra[@]+"${extra[@]}"} "${CONFIGURE_FLAGS[@]}"
    make -j"$(sysctl -n hw.ncpu)"
    make install
  )
done

# One dynamic library per slice with all four FFmpeg libraries, wrapped as FFmpeg.framework per
# platform (versioned bundle on macOS, shallow on iOS), then one XCFramework.
LIBS=(libavformat libavcodec libswresample libavutil)
rm -rf "$WORK/frameworks" "$OUT/FFmpeg.xcframework" "$OUT/lib"
xcargs=()
for platform in macos ios iossim; do
  dylibs=()
  for slice in "${SLICES[@]}"; do
    IFS=: read -r p arch sdk target <<< "$slice"
    [[ "$p" == "$platform" ]] || continue
    build="$(builddir "$p" "$arch")"
    inputs=()
    for lib in "${LIBS[@]}"; do inputs+=("$build/install/lib/$lib.a"); done
    if [[ "$platform" == macos ]]; then install=@rpath/FFmpeg.framework/Versions/A/FFmpeg; else install=@rpath/FFmpeg.framework/FFmpeg; fi
    xcrun --sdk "$sdk" clang -target "$target" -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" -dynamiclib \
      -install_name "$install" -compatibility_version 1 -current_version 1 \
      -Wl,-all_load "${inputs[@]}" -lz -lbz2 -o "$WORK/ffmpeg-$platform-$arch.dylib"
    dylibs+=("$WORK/ffmpeg-$platform-$arch.dylib")
  done
  fw="$WORK/frameworks/$platform/FFmpeg.framework"
  if [[ "$platform" == macos ]]; then
    mkdir -p "$fw/Versions/A/Resources"
    lipo -create "${dylibs[@]}" -output "$fw/Versions/A/FFmpeg"
    plist="$fw/Versions/A/Resources/Info.plist"
    ln -s A "$fw/Versions/Current"; ln -s Versions/Current/FFmpeg "$fw/FFmpeg"; ln -s Versions/Current/Resources "$fw/Resources"
    minkey=LSMinimumSystemVersion; minver=$MACOS_MIN
  else
    mkdir -p "$fw"
    lipo -create "${dylibs[@]}" -output "$fw/FFmpeg"
    plist="$fw/Info.plist"
    minkey=MinimumOSVersion; minver=$IOS_MIN
  fi
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>FFmpeg</string>
  <key>CFBundleIdentifier</key><string>org.ffmpeg.FFmpeg</string>
  <key>CFBundleName</key><string>FFmpeg</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$FFMPEG_VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>$minkey</key><string>$minver</string>
</dict></plist>
PLIST
  xcargs+=(-framework "$fw")
done
xcodebuild -create-xcframework "${xcargs[@]}" -output "$OUT/FFmpeg.xcframework"

# Headers are architecture-independent for these little-endian targets.
rm -rf "$OUT/include"
cp -R "$WORK/build-arm64/install/include" "$OUT/include"
cp "$SRC/COPYING.LGPLv2.1" "$OUT/COPYING.LGPLv2.1"

for platform in macos ios iossim; do
  # Not grep -q: it stops reading early and nm then fails on a broken pipe under pipefail.
  if [[ "$(nm -gU "$WORK/frameworks/$platform/FFmpeg.framework/FFmpeg" | grep -c " _avformat_open_input$")" == 0 ]]; then
    echo "FFmpeg.framework ($platform) does not export avformat_open_input" >&2
    exit 1
  fi
done
echo "Exports OK"
for slice in "${SLICES[@]}"; do
  IFS=: read -r platform arch _ _ <<< "$slice"
  if grep -q "enable-gpl" "$(builddir "$platform" "$arch")/ffbuild/config.mak"; then
    echo "GPL components enabled ($platform $arch) — refusing." >&2
    exit 1
  fi
done

{
  echo "FFmpeg $FFMPEG_VERSION: macOS $MACOS_MIN+ (arm64 x86_64), iOS $IOS_MIN+ (arm64), iOS Simulator (arm64)"
  echo "script-sha256: $SCRIPT_HASH"
  echo "license: $(grep '#define FFMPEG_LICENSE' "$WORK/build-arm64/config.h" | cut -d'"' -f2)"
  echo "configure: ${CONFIGURE_FLAGS[*]}"
} > "$STAMP"
cat "$STAMP"
