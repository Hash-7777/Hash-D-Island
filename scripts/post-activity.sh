#!/usr/bin/env bash
#
# Post a live activity to HashNotch. Any app, script, or Apple Shortcut can do
# the same by writing ~/.hashnotch/activities.json (an array of activities).
#
# Usage:
#   ./scripts/post-activity.sh "Food delivery" "Rider on the way" bicycle 12
#      title ------------------^  subtitle -----^          icon ---^  ^-- minutes left
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

# Escape a value for use inside a JSON string literal, so titles containing
# quotes, backslashes, or newlines produce a valid feed instead of breaking it.
json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/ }
  s=${s//$'\t'/ }
  printf '%s' "$s"
}

TITLE="$(json_escape "${1:-Activity}")"
SUBTITLE="$(json_escape "${2:-}")"
ICON="$(json_escape "${3:-app.badge}")"
MINUTES="${4:-15}"

if ! [[ "$MINUTES" =~ ^[0-9]+$ ]]; then
  echo "minutes must be a whole number (got: $MINUTES)" >&2
  exit 1
fi

ENDS_AT="$(date -u -v +"${MINUTES}"M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
           date -u -d "+${MINUTES} minutes" +"%Y-%m-%dT%H:%M:%SZ")"

cat > "$FEED" <<JSON
[
  {
    "id": "cli-1",
    "icon": "${ICON}",
    "title": "${TITLE}",
    "subtitle": "${SUBTITLE}",
    "endsAt": "${ENDS_AT}"
  }
]
JSON

echo "Posted activity to $FEED (ends in ${MINUTES} min)"
