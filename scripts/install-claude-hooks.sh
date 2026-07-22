#!/usr/bin/env bash
#
# Wires Claude Code to your notch: after this, HashNotch shows a live activity
# the moment Claude finishes a reply or is waiting for your permission.
#
# What it does — nothing more:
#   1. Copies claude-code-hook.sh to ~/.hashnotch/ (the hook writes only the
#      local activities feed).
#   2. Registers it as a Stop + Notification hook in ~/.claude/settings.json,
#      backing the file up first. Safe to re-run; already-installed is a no-op.
#
# Uninstall: delete the two entries mentioning claude-code-hook.sh from
# ~/.claude/settings.json and remove ~/.hashnotch/claude-code-hook.sh.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_SRC="$ROOT/scripts/claude-code-hook.sh"
HOOK_DST="$HOME/.hashnotch/claude-code-hook.sh"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOME/.hashnotch" "$HOME/.claude"
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.hashnotch-backup-$(date +%s)"
fi

RESULT="$(osascript -l JavaScript - "$SETTINGS" "$HOOK_DST" <<'JXA'
function run(argv) {
  ObjC.import('Foundation');
  const path = argv[0];
  const hook = argv[1];

  let settings = {};
  const existing = $.NSString.stringWithContentsOfFileEncodingError(
    path, $.NSUTF8StringEncoding, null);
  if (existing && !existing.isNil()) {
    try {
      settings = JSON.parse(ObjC.unwrap(existing));
    } catch (e) {
      return 'ERROR: ' + path + ' is not valid JSON - fix it first; nothing was changed.';
    }
  }
  if (typeof settings !== 'object' || settings === null || Array.isArray(settings)) {
    settings = {};
  }

  settings.hooks = settings.hooks || {};
  let added = 0;
  const pairs = [['Stop', 'stop'], ['Notification', 'notification']];
  for (let i = 0; i < pairs.length; i++) {
    const name = pairs[i][0];
    const command = hook + ' ' + pairs[i][1];
    settings.hooks[name] = settings.hooks[name] || [];
    if (JSON.stringify(settings.hooks[name]).indexOf(hook) === -1) {
      settings.hooks[name].push({ hooks: [{ type: 'command', command: command }] });
      added++;
    }
  }

  if (added > 0) {
    $.NSString.alloc.initWithUTF8String(JSON.stringify(settings, null, 2))
      .writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
  }
  return added > 0
    ? 'Installed ' + added + ' hook(s).'
    : 'Already installed - nothing to do.';
}
JXA
)"

echo "$RESULT"
case "$RESULT" in
  ERROR*) exit 1 ;;
esac
echo "Claude Code will now post to your notch when it finishes or needs permission."
echo "(Restart any running Claude Code session so it picks up the new hooks.)"
