#!/usr/bin/env bash
#
# Wires Claude Code to your notch: after this, HashDIsland shows a live activity
# the moment Claude finishes a reply or is waiting for your permission.
#
# What it does — nothing more:
#   1. Copies claude-code-hook.sh to ~/.hashdisland/ (the hook writes only the
#      local activities feed).
#   2. Registers it as a Stop + Notification hook in ~/.claude/settings.json,
#      backing the file up first. Safe to re-run; already-installed is a no-op.
#
# Uninstall: delete the two entries mentioning claude-code-hook.sh from
# ~/.claude/settings.json and remove ~/.hashdisland/claude-code-hook.sh.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_SRC="$ROOT/scripts/claude-code-hook.sh"
HOOK_DST="$HOME/.hashdisland/claude-code-hook.sh"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOME/.hashdisland" "$HOME/.claude"
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.hashdisland-backup-$(date +%s)"
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
  let removed = 0;
  const pairs = [['Stop', 'stop'], ['Notification', 'notification']];

  // True for any entry that runs THIS hook script, wherever it currently lives
  // or used to live. Matching on the script's file name rather than its full
  // path is what makes re-running this safe after the folder has moved: the
  // stale entry is dropped instead of left behind firing into nowhere.
  function isOurs(entry) {
    return JSON.stringify(entry || {}).indexOf('claude-code-hook.sh') !== -1;
  }

  for (let i = 0; i < pairs.length; i++) {
    const name = pairs[i][0];
    // The hook path is quoted: it contains the user's home directory, and a
    // home folder with a space in it would otherwise be split into two words
    // by the shell that runs this command.
    const command = '"' + hook + '" ' + pairs[i][1];
    const existing = settings.hooks[name] || [];
    const kept = existing.filter(function (entry) { return !isOurs(entry); });
    removed += existing.length - kept.length;

    kept.push({ hooks: [{ type: 'command', command: command }] });
    added++;
    settings.hooks[name] = kept;
  }

  $.NSString.alloc.initWithUTF8String(JSON.stringify(settings, null, 2))
    .writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);

  return removed > 0
    ? 'Installed ' + added + ' hook(s), replacing ' + removed + ' older one(s).'
    : 'Installed ' + added + ' hook(s).';
}
JXA
)"

echo "$RESULT"
case "$RESULT" in
  ERROR*) exit 1 ;;
esac
echo "Claude Code will now post to your notch when it finishes or needs permission."
echo "(Restart any running Claude Code session so it picks up the new hooks.)"
