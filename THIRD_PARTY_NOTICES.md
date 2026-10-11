# Third-party notices

## FFmpeg

Tiny Jellyfin uses libraries from the FFmpeg project (libavformat, libavcodec, libavutil,
libswresample) under the GNU Lesser General Public License version 2.1 or later.

- FFmpeg is built without GPL or non-free components by `scripts/build-ffmpeg.sh` in this
  repository, which records the exact version and configure flags.
- The libraries are dynamically linked (`Contents/Frameworks/libffmpeg.dylib`) and can be
  replaced with a compatible build.
- Source code: https://ffmpeg.org/download.html (version pinned in the build script).
- Licence text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
