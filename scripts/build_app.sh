#!/usr/bin/env bash
#
# Assembles HashNotch.app from the release build so it can run as a proper
# agent app and register for "open at login". Works with the Command Line
# Tools alone — no full Xcode required.
#
#   ./scripts/build_app.sh          # build into ./build/HashNotch.app (ad-hoc signed)
#
# For a distributable build, set CODESIGN_IDENTITY to a "Developer ID
# Application: …" certificate; the app is then signed with the hardened
# runtime and a secure timestamp, ready for notarization:
#
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_app.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/HashNotch.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "Building release binary…"
swift build -c release --package-path "$ROOT" --product HashNotch
BIN_DIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"

echo "Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HashNotch" "$APP/Contents/MacOS/HashNotch"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

# Signing the bundle covers its single main executable; --deep is unnecessary
# (and deprecated) because there is no nested code.
if [ "$IDENTITY" = "-" ]; then
  echo "Signing (ad-hoc)…"
  codesign --force --sign - "$APP"
else
  echo "Signing with: $IDENTITY (hardened runtime)…"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify "$APP" && echo "Signature verified."

echo "Built: $APP"
echo "Run it with: open \"$APP\""
