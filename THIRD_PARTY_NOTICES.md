# Third-party notices

Kinema is an independent Jellyfin client, not an official Jellyfin product. Its source, including
everything below, is at https://github.com/frzzyone/tiny-jellyfin-client.

## FFmpeg

Kinema uses libraries from the FFmpeg project (libavformat, libavcodec, libavutil,
libswresample) under the GNU Lesser General Public License version 2.1 or later.

- FFmpeg 7.1.1 is used unmodified, built without GPL or non-free components by
  `scripts/build-ffmpeg.sh` in the repository above. Each app carries `BUILD-INFO`, the exact
  version and configure flags it was built with.
- The libraries are dynamically linked as `FFmpeg.framework` (in `Contents/Frameworks` on macOS,
  `Frameworks` on iPhone and Apple TV). On the Mac the framework can be replaced with a compatible
  build; on iPhone and Apple TV, where a signed app cannot be changed, build the app from the
  repository above against your own FFmpeg build.
- FFmpeg source code: https://ffmpeg.org/download.html (version pinned in the build script).
- Licence text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
