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

HERE="$(cd "$(dirname "$0")" && pwd)"
# The hook always sits beside this script — in the repo's scripts/ folder, or in
# Contents/Resources/scripts inside the app bundle for anyone who downloaded the
# app rather than the source.
HOOK_SRC="$HERE/claude-code-hook.sh"
HOOK_DST="$HOME/.hashdisland/claude-code-hook.sh"
SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$HOOK_SRC" ]; then
  echo "Cannot find claude-code-hook.sh next to this script ($HERE)." >&2
  exit 1
fi

mkdir -p "$HOME/.hashdisland" "$HOME/.claude"

# Explain the logo slot, because an empty folder explains nothing.
#
# The hook points the activity at ~/.hashdisland/logos/claude.png and the app
# quietly draws its checkmark symbol when no such file exists — which is correct
# behaviour and completely invisible, so "why is there no logo?" has had no
# answer anywhere. No mark is shipped: Claude's logo belongs to Anthropic, not
# to this app, and an app that ships someone else's brand has helped itself to
# it. Put one there yourself and the notch wears it.
LOGO_DIR="$HOME/.hashdisland/logos"
mkdir -p "$LOGO_DIR"
if [ ! -f "$LOGO_DIR/README.txt" ]; then
  cat > "$LOGO_DIR/README.txt" <<'NOTE'
Logos shown on the notch instead of a symbol.

Drop a square PNG here named after the tool and the island will use it in place
of the built-in symbol for that tool's alerts:

    claude.png      shown for the Claude Code alerts

Anything readable works — PNG, JPEG, TIFF, HEIC, PDF — up to 4 MB. Small is
fine; it is drawn about 21 points wide. Remove the file and the symbol comes
back. Nothing here is downloaded or shipped with the app: these marks belong to
the tools they represent, so you supply the ones you want to see.
NOTE
fi

# Say out loud when an older hook is being replaced.
#
# The hook is COPIED here, so it does not follow app updates: an install done
# months ago keeps posting in the format that was current that day. That is how
# an alert already fixed in the app went on looking broken at the notch, with
# nothing anywhere saying why. Version in, version out, every time.
version_of() { [ -f "$1" ] && sed -n 's/^HOOK_VERSION=\([0-9][0-9]*\).*/\1/p' "$1" | head -1; }
OLD_VERSION="$(version_of "$HOOK_DST" || true)"
NEW_VERSION="$(version_of "$HOOK_SRC" || true)"

cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"

if [ -z "${OLD_VERSION:-}" ]; then
  echo "Installed the notch hook (v${NEW_VERSION:-?})."
elif [ "$OLD_VERSION" != "${NEW_VERSION:-}" ]; then
  echo "Updated the notch hook: v$OLD_VERSION to v${NEW_VERSION:-?}."
else
  echo "The notch hook was already current (v${NEW_VERSION:-?})."
fi

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.hashdisland-backup-$(date +%s)"
  # Keep the three most recent and delete the rest of OUR OWN backups. This is
  # safe to re-run at any time, and re-running it is exactly what the README now
  # tells people to do after every update — without a limit, being helpful once
  # a version turns into a drawer full of near-identical files in a folder this
  # app does not own. Only the .hashdisland-backup-* names are ever touched.
  ls -t "$SETTINGS".hashdisland-backup-* 2>/dev/null \
    | tail -n +4 \
    | while IFS= read -r stale; do rm -f "$stale"; done
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
