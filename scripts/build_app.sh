#!/usr/bin/env bash
#
# Assembles "Hash D Island.app" from the release build so it can run as a proper
# agent app and register for "open at login". Works with the Command Line
# Tools alone — no full Xcode required.
#
#   ./scripts/build_app.sh          # build into "./build/Hash D Island.app" (ad-hoc signed)
#
# For a distributable build, set CODESIGN_IDENTITY to a "Developer ID
# Application: …" certificate; the app is then signed with the hardened
# runtime and a secure timestamp, ready for notarization:
#
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_app.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Hash D Island.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "Building release binary…"
swift build -c release --package-path "$ROOT" --product HashDIsland
BIN_DIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"

echo "Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HashDIsland" "$APP/Contents/MacOS/HashDIsland"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

# App icon. Regenerate the .icns from the master PNG if it is missing or
# older than the master (sips + iconutil, both always present); otherwise use
# the committed .icns as-is.
ICONSET="$ROOT/Packaging/AppIcon.iconset"
MASTER="$ROOT/Packaging/AppIcon-master.png"
ICNS="$ROOT/Packaging/AppIcon.icns"
if [ -f "$MASTER" ] && { [ ! -f "$ICNS" ] || [ "$MASTER" -nt "$ICNS" ]; }; then
  echo "Regenerating app icon…"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$MASTER" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICNS"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

# Signing the bundle covers its single main executable; --deep is unnecessary
# (and deprecated) because there is no nested code.
if [ "$IDENTITY" = "-" ]; then
  echo "Signing (ad-hoc)…"
  codesign --force --sign - "$APP"
else
  echo "Signing with: $IDENTITY (hardened runtime)…"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

# Checked with `if`, not `codesign --verify … && echo`. `set -e` deliberately
# does NOT stop on a command that is the left side of an &&, so the && form let
# a bundle whose signature does not verify print no complaint at all, fall
# through to "Built:", and exit 0 — the one failure that must never be reported
# as success, because macOS then refuses to launch the result.
if ! codesign --verify --strict "$APP"; then
  echo "Signature verification FAILED — this bundle must not be shipped." >&2
  exit 1
fi
echo "Signature verified."

echo "Built: $APP"
echo "Run it with: open \"$APP\""
