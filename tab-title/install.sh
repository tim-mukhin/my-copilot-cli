#!/bin/bash
# Install the tab-title hooks for GitHub Copilot CLI.
#
#   - scripts  -> ~/.copilot/tab-title/
#   - hook cfg -> ~/.copilot/hooks/tab-title.json
#   - disables Copilot's own terminal title so ours doesn't flicker
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/hooks"
DEST="$HOME/.copilot/tab-title"
HOOKS="$HOME/.copilot/hooks"
SETTINGS="$HOME/.copilot/settings.json"

mkdir -p "$DEST" "$HOOKS"

cp "$SRC/paint.sh" "$SRC/on-prompt.sh" "$SRC/label-gen.sh" "$SRC/set-session-name.py" "$DEST/"
chmod +x "$DEST/paint.sh" "$DEST/on-prompt.sh" "$DEST/label-gen.sh" "$DEST/set-session-name.py"
cp "$SRC/tab-title.json" "$HOOKS/tab-title.json"

# Turn off Copilot's built-in terminal title writer (otherwise it overwrites ours).
if command -v jq >/dev/null 2>&1; then
  if [ -f "$SETTINGS" ]; then
    tmp=$(mktemp)
    jq '.updateTerminalTitle = false' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  else
    printf '%s\n' '{ "updateTerminalTitle": false }' > "$SETTINGS"
  fi
  echo "set updateTerminalTitle=false in $SETTINGS"
else
  echo "jq not found: manually add \"updateTerminalTitle\": false to $SETTINGS"
  echo "(or export COPILOT_DISABLE_TERMINAL_TITLE=1 in your shell rc)"
fi

echo "installed tab-title hooks -> $HOOKS/tab-title.json"
echo "scripts -> $DEST/"
echo "Open a fresh Copilot CLI session to pick up the hooks."
