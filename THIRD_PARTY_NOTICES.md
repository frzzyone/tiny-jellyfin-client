# Third-party notices

## FFmpeg

Tiny Jellyfin uses libraries from the FFmpeg project (libavformat, libavcodec, libavutil,
libswresample) under the GNU Lesser General Public License version 2.1 or later.

- FFmpeg is built without GPL or non-free components by `scripts/build-ffmpeg.sh` in this
  repository, which records the exact version and configure flags.
- The libraries are dynamically linked as `FFmpeg.framework` (in `Contents/Frameworks` on macOS,
  `Frameworks` on iOS) and can be
  replaced with a compatible build.
- Source code: https://ffmpeg.org/download.html (version pinned in the build script).
- Licence text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html

## App icon

The app icon is the Jellyfin icon shape from the Jellyfin project's `jellyfin-ux` repository
(`branding/SVG/icon-transparent.svg`), recoloured. The shape is unchanged.

- Copyright the Jellyfin contributors, licensed under the Creative Commons
  Attribution-ShareAlike 4.0 International License: https://creativecommons.org/licenses/by-sa/4.0/
- This recolouring (`App/Resources/AppIcon.svg` and the rendered `AppIcon.appiconset`) is shared
  under the same licence.
- Tiny Jellyfin is an independent client and not an official Jellyfin product.
