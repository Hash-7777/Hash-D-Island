#!/usr/bin/env bash
#
# Assembles HashNotch.app from the release build so it can run as a proper
# agent app and register for "open at login". Works with the Command Line
# Tools alone — no full Xcode required.
#
#   ./scripts/build_app.sh          # build into ./build/HashNotch.app
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/HashNotch.app"

echo "Building release binary…"
swift build -c release --package-path "$ROOT" --product HashNotch
BIN_DIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"

echo "Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HashNotch" "$APP/Contents/MacOS/HashNotch"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

echo "Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "  (ad-hoc signing skipped; app will still run)"

echo "Built: $APP"
echo "Run it with: open \"$APP\""
