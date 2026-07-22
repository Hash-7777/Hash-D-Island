#!/usr/bin/env bash
#
# Post a live activity to HashNotch. Any app, script, or Apple Shortcut can do
# the same by writing ~/.hashnotch/activities.json (an array of activities).
# Activities MERGE by id — posting replaces your previous activity with the
# same id and leaves other posters' activities alone.
#
# Usage:
#   ./scripts/post-activity.sh "Food delivery" "Rider on the way" bicycle 12
#      title ------------------^  subtitle -----^          icon ---^  ^-- minutes left
#   ./scripts/post-activity.sh --id build "Building app" "release" hammer 10
#
# Clear all activities:
#   ./scripts/post-activity.sh --clear
#
set -euo pipefail

FEED="$HOME/.hashnotch/activities.json"
mkdir -p "$(dirname "$FEED")"

if [ "${1:-}" = "--clear" ]; then
  echo "[]" > "$FEED"
  echo "Cleared $FEED"
  exit 0
fi

ID="cli-1"
if [ "${1:-}" = "--id" ]; then
  ID="${2:?--id needs a value}"
  shift 2
fi

TITLE="${1:-Activity}"
SUBTITLE="${2:-}"
ICON="${3:-app.badge}"
MINUTES="${4:-15}"

if ! [[ "$MINUTES" =~ ^[0-9]+$ ]]; then
  echo "minutes must be a whole number (got: $MINUTES)" >&2
  exit 1
fi

# All JSON handling in JavaScript-for-Automation (always present on macOS).
# Values pass as argv, so quotes/backslashes/newlines in titles are safe.
osascript -l JavaScript - "$FEED" "$ID" "$ICON" "$TITLE" "$SUBTITLE" "$MINUTES" >/dev/null <<'JXA'
function run(argv) {
  ObjC.import('Foundation');
  const feedPath = argv[0];

  let items = [];
  const existing = $.NSString.stringWithContentsOfFileEncodingError(
    feedPath, $.NSUTF8StringEncoding, null);
  if (existing && !existing.isNil()) {
    try { items = JSON.parse(ObjC.unwrap(existing)); } catch (e) { items = []; }
  }
  if (!Array.isArray(items)) items = [];
  const now = Date.now();
  items = items.filter(function (a) {
    return a && a.id && a.id !== argv[1]
      && (!a.endsAt || Date.parse(a.endsAt) > now - 2000);
  });

  const activity = {
    id: argv[1],
    icon: argv[2],
    title: argv[3],
    endsAt: new Date(now + parseInt(argv[5], 10) * 60000).toISOString().replace(/\.\d+Z$/, 'Z'),
  };
  if (argv[4]) activity.subtitle = argv[4];
  items.push(activity);

  $.NSString.alloc.initWithUTF8String(JSON.stringify(items, null, 2))
    .writeToFileAtomicallyEncodingError(feedPath, true, $.NSUTF8StringEncoding, null);
}
JXA

echo "Posted activity '$ID' to $FEED (ends in $MINUTES min)"
