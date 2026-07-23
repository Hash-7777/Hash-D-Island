#!/usr/bin/env bash
#
# Sets each README screenshot to display at HALF its pixel width.
#
# Why half: macOS captures a Retina screen at 2x, so a 300-point panel arrives
# as a 600-pixel image. Displaying that at 300 gives one image pixel per screen
# pixel — crisp. Displaying it at 600 (or displaying a 1x capture at 300)
# stretches it, which is exactly how the first screenshots ended up soft.
#
# Run this after dropping new captures into docs/media/:
#
#   ./scripts/fit-media.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT/README.md"
changed=0

for image in "$ROOT"/docs/media/*.png; do
  [ -f "$image" ] || continue
  name="$(basename "$image")"
  pixels="$(sips -g pixelWidth "$image" | awk '/pixelWidth/ {print $2}')"
  [ -n "$pixels" ] || continue

  half=$((pixels / 2))
  if [ "$half" -lt 1 ]; then half=1; fi

  # The width is pulled out with a capture rather than a trailing-digits match:
  # a pattern like [0-9]*$ also matches the empty string at end of line, and
  # silently reports every image as unreferenced.
  current="$(/usr/bin/sed -n "s|.*src=\"docs/media/$name\" width=\"\([0-9][0-9]*\)\".*|\1|p" "$README" | head -1)"
  if [ -z "$current" ]; then
    echo "  $name — not referenced in README, skipped"
    continue
  fi

  if [ "$current" = "$half" ]; then
    echo "  $name — ${pixels}px, already shown at $half"
  else
    /usr/bin/sed -i '' \
      "s|src=\"docs/media/$name\" width=\"$current\"|src=\"docs/media/$name\" width=\"$half\"|" \
      "$README"
    echo "  $name — ${pixels}px, now shown at $half (was $current)"
    changed=1
  fi

  if [ "$pixels" -lt 400 ]; then
    echo "      note: only ${pixels}px wide, so this looks like a 1x capture."
    echo "            Recapture it on the Retina display for a sharper image."
  fi
done

if [ "$changed" = "1" ]; then
  echo "README.md updated."
else
  echo "Nothing to change."
fi
