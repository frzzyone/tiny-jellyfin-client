#!/usr/bin/env bash
# Builds the Mac app for download: archive, Developer ID export, notarise, staple, DMG.
# Output: build/release/Tinyfin-<version>.dmg (notarised and stapled, so it opens without warnings).
#
# One-time setup, with an app-specific password from appleid.apple.com:
#   xcrun notarytool store-credentials tinyfin --apple-id <your Apple ID> --team-id <team id>
# The team id comes from App/Signing.local.xcconfig. Xcode signs with your account's cloud-managed
# Developer ID certificate, so none needs to be installed. Bump CURRENT_PROJECT_VERSION in project.yml first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROFILE="${NOTARY_PROFILE:-tinyfin}"
TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$ROOT/App/Signing.local.xcconfig")"
[[ -n "$TEAM" ]] || { echo "No DEVELOPMENT_TEAM in App/Signing.local.xcconfig" >&2; exit 1; }
OUT="$ROOT/build/release"
# Everything but the DMG goes in WORK: Spotlight skips folders named *.noindex, so the app copies
# in the archive, the export and the staging folder stay out of its results.
WORK="$OUT/work.noindex"
rm -rf "$OUT" && mkdir -p "$WORK"

cd "$ROOT"
xcodegen generate -q
xcodebuild archive -project TinyJellyfin.xcodeproj -scheme TinyJellyfin -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$WORK/Tinyfin.xcarchive" \
  -derivedDataPath "$WORK/DerivedData" -allowProvisioningUpdates -quiet

cat > "$WORK/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$WORK/Tinyfin.xcarchive" -exportOptionsPlist "$WORK/export.plist" \
  -exportPath "$WORK/export" -allowProvisioningUpdates -quiet
APP="$WORK/export/Tinyfin.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# The app is notarised first so it can be stapled before it goes into the disk image; the image is
# then notarised and stapled too, so it opens offline.
ditto -c -k --keepParent "$APP" "$WORK/Tinyfin.zip"
xcrun notarytool submit "$WORK/Tinyfin.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

STAGE="$WORK/dmg"
mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Tinyfin-$VERSION.dmg"
hdiutil create -volname Tinyfin -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

# The image itself is unsigned (the Developer ID certificate is cloud-managed and only Xcode signs
# with it); Gatekeeper judges the app inside, which is signed, notarised and stapled.
xcrun stapler validate "$DMG"
spctl -a -vv "$APP"
shasum -a 256 "$DMG"
echo "$DMG"
