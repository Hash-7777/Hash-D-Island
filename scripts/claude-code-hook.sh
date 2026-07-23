#!/usr/bin/env bash
#
# Posts a HashDIsland live activity when Claude Code finishes a reply or is
# waiting for your permission. Wired into ~/.claude/settings.json as a Stop +
# Notification hook by scripts/install-claude-hooks.sh. Reads the hook payload
# Claude Code sends on stdin (JSON) and writes ONLY the local activities feed
# (~/.hashdisland/activities.json) — nothing else, nowhere else.
#
#   claude-code-hook.sh stop           # "Claude finished"
#   claude-code-hook.sh notification   # "Claude needs you" (+ the reason)
#
set -euo pipefail

EVENT="${1:-stop}"
# A logo to show instead of the symbol, if one has been placed here. Claude's
# own mark is not shipped with this app — drop a PNG at this path and the notch
# uses it; without it the checkmark symbol is shown exactly as before.
LOGO="$HOME/.hashdisland/logos/claude.png"
PAYLOAD="$(cat 2>/dev/null || true)"
FEED="$HOME/.hashdisland/activities.json"
mkdir -p "$(dirname "$FEED")"

# All JSON handling in JavaScript-for-Automation (always present on macOS —
# no jq or python needed). Arguments pass as argv, so payload quoting is safe.
osascript -l JavaScript - "$FEED" "$EVENT" "$PAYLOAD" "$LOGO" >/dev/null <<'JXA'
function run(argv) {
  ObjC.import('Foundation');
  const feedPath = argv[0];
  const event = argv[1];
  const logoPath = argv[3] || '';
  let payload = {};
  try { payload = JSON.parse(argv[2] || '{}'); } catch (e) {}

  // "Finished" has already happened, so it is a notice: it shows for a moment
  // and leaves, with no timer counting down beside it. "Needs you" is a
  // standing request — it waits, because dismissing it after a few seconds
  // would hide the very thing it is asking you to deal with.
  let icon, title, subtitle, dismissAfter = null, waitSeconds = null;
  if (event === 'notification') {
    icon = 'hand.raised.fill';
    title = 'Claude needs you';
    subtitle = String(payload.message || '').slice(0, 120) || null;
    waitSeconds = 180;
  } else {
    icon = 'checkmark.circle.fill';
    title = 'Claude finished';
    const cwd = String(payload.cwd || '');
    subtitle = cwd ? cwd.split('/').filter(Boolean).pop() : null;
    dismissAfter = 3;
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

  const activity = { id: 'claude-code', icon: icon, title: title };
  // The app ignores an image it cannot read, so pointing at a missing file is
  // harmless — it simply falls back to the symbol.
  if (logoPath) activity.image = logoPath;
  if (dismissAfter !== null) {
    // dismissAfter says "no timer, and leave after this long". endsAt is
    // written alongside it purely so the entry expires from the file on its
    // own — without it a finished notice would linger in the feed and pop up
    // again the next time the app started.
    activity.dismissAfter = dismissAfter;
    activity.endsAt = stamp(now + dismissAfter * 1000);
  } else {
    activity.endsAt = stamp(now + waitSeconds * 1000);
  }
  if (subtitle) activity.subtitle = subtitle;
  items.push(activity);

  function stamp(ms) {
    return new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z');
  }

  $.NSString.alloc.initWithUTF8String(JSON.stringify(items, null, 2))
    .writeToFileAtomicallyEncodingError(feedPath, true, $.NSUTF8StringEncoding, null);
}
JXA
