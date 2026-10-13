#!/usr/bin/env bash
# Runs JellyfinKit and PlayerCore tests on an iPhone simulator. The simulator cannot launch the
# fixture HTTP server itself, so it runs here on the host and its port is passed to the tests.
# Usage: scripts/test-ios.sh ["iPhone 17"]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-$(xcrun simctl list devices available | grep -m1 -oE 'iPhone [^(]+' | sed 's/ *$//')}"
[[ -n "$DEVICE" ]] || { echo "No iPhone simulator; install one: xcodebuild -downloadPlatform iOS" >&2; exit 1; }
DEST="platform=iOS Simulator,name=$DEVICE"

exec 3< <(python3 "$ROOT/scripts/test-http-server.py" "$ROOT/Packages/PlayerCore/Tests/PlayerCoreTests/Fixtures")
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
read -r PORT <&3
echo "fixture server on port $PORT, testing on $DEVICE"

for pkg in JellyfinKit PlayerCore; do
  (cd "$ROOT/Packages/$pkg" && TEST_RUNNER_TEST_HTTP_PORT="$PORT" \
    xcodebuild test -scheme "$pkg" -destination "$DEST" -quiet)
done
