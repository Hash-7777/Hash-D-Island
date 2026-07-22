#!/usr/bin/env bash
#
# Posts a HashNotch live activity when Claude Code finishes a reply or is
# waiting for your permission. Wired into ~/.claude/settings.json as a Stop +
# Notification hook by scripts/install-claude-hooks.sh. Reads the hook payload
# Claude Code sends on stdin (JSON) and writes ONLY the local activities feed
# (~/.hashnotch/activities.json) — nothing else, nowhere else.
#
#   claude-code-hook.sh stop           # "Claude finished"
#   claude-code-hook.sh notification   # "Claude needs you" (+ the reason)
#
set -euo pipefail

EVENT="${1:-stop}"
PAYLOAD="$(cat 2>/dev/null || true)"
FEED="$HOME/.hashnotch/activities.json"
mkdir -p "$(dirname "$FEED")"

# All JSON handling in JavaScript-for-Automation (always present on macOS —
# no jq or python needed). Arguments pass as argv, so payload quoting is safe.
osascript -l JavaScript - "$FEED" "$EVENT" "$PAYLOAD" >/dev/null <<'JXA'
function run(argv) {
  ObjC.import('Foundation');
  const feedPath = argv[0];
  const event = argv[1];
  let payload = {};
  try { payload = JSON.parse(argv[2] || '{}'); } catch (e) {}

  let icon, title, subtitle, seconds;
  if (event === 'notification') {
    icon = 'hand.raised.fill';
    title = 'Claude needs you';
    subtitle = String(payload.message || '').slice(0, 120) || null;
    seconds = 180;
  } else {
    icon = 'checkmark.circle.fill';
    title = 'Claude finished';
    const cwd = String(payload.cwd || '');
    subtitle = cwd ? cwd.split('/').filter(Boolean).pop() : null;
    seconds = 45;
  }

  // Merge by id: keep other posters' activities, drop our previous one and
  // anything already expired.
  let items = [];
  const existing = $.NSString.stringWithContentsOfFileEncodingError(
    feedPath, $.NSUTF8StringEncoding, null);
  if (existing && !existing.isNil()) {
    try { items = JSON.parse(ObjC.unwrap(existing)); } catch (e) { items = []; }
  }
  if (!Array.isArray(items)) items = [];
  const now = Date.now();
  items = items.filter(function (a) {
    return a && a.id && a.id !== 'claude-code'
      && (!a.endsAt || Date.parse(a.endsAt) > now - 2000);
  });

  const activity = {
    id: 'claude-code',
    icon: icon,
    title: title,
    endsAt: new Date(now + seconds * 1000).toISOString().replace(/\.\d+Z$/, 'Z'),
  };
  if (subtitle) activity.subtitle = subtitle;
  items.push(activity);

  $.NSString.alloc.initWithUTF8String(JSON.stringify(items, null, 2))
    .writeToFileAtomicallyEncodingError(feedPath, true, $.NSUTF8StringEncoding, null);
}
JXA
