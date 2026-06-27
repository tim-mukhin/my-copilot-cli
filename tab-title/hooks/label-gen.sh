#!/bin/bash
# Background label generator (fire-and-forget, spawned by on-prompt.sh).
#
# Args: <sessionId> <ttyDevice> <cwd> <prompt>
#
# Runs a one-shot `copilot -p` with the configured small model to turn the
# user's first message into a short "emoji + 2-4 words" label, stores it as the
# session's own name in workspace.yaml (so it persists across reloads/restarts),
# then repaints the tab keeping whatever status icon the tab currently shows.

SID="$1"
TTYDEV="$2"
CWD="$3"
PROMPT="$4"

ROOT="$HOME/.copilot/tab-title"
STATEDIR="$ROOT/state"
LOG="$ROOT/tab-title.log"
WS="$HOME/.copilot/session-state/$SID/workspace.yaml"
mkdir -p "$STATEDIR" 2>/dev/null

log() { printf '%s [%s] %s\n' "$(date +%H:%M:%S)" "${SID:0:8}" "$1" >> "$LOG" 2>/dev/null; }

[ -z "$SID" ] && exit 0
# Already named (race with another prompt or a manual /rename) -> nothing to do.
[ -f "$WS" ] && [ -n "$(python3 "$ROOT/set-session-name.py" --get "$WS" 2>/dev/null)" ] && exit 0

# Model used to generate the tab label. Set this default to a model YOU have
# access to, or override per-shell with `export TAB_TITLE_MODEL=...`.
MODEL="${TAB_TITLE_MODEL:-claude-sonnet-4.5}"

# Isolated copilot home: no MCP servers, no hooks (no recursion), no custom
# instructions -> fast and side-effect free. Auth lives in the OS keychain.
# A unique home per invocation prevents crosstalk between concurrent label-gens
# (e.g. first prompts in two terminals within the same ~10s window).
GENHOME=$(mktemp -d "$ROOT/gen-home.XXXXXX" 2>/dev/null) || GENHOME="$ROOT/gen-home.$$"
mkdir -p "$GENHOME" 2>/dev/null
printf '%s' '{"mcpServers":{}}' > "$GENHOME/mcp-config.json" 2>/dev/null
trap 'rm -rf "$GENHOME" 2>/dev/null' EXIT

SYS='Extract a short label for this conversation. Output ONLY the label: an emoji + a 1-4 word description of the USER GOAL, in the language of the user message. No quotes, no markdown, no explanation. Max 30 chars. Describe what THEY want.'

RAW=$(cd "$CWD" 2>/dev/null; \
  COPILOT_TAB_TITLE_SKIP=1 COPILOT_HOME="$GENHOME" \
  copilot -p "$SYS"$'\n\nUser message:\n'"${PROMPT:0:500}" \
    -s --model "$MODEL" --no-color --allow-all-tools 2>>"$LOG")

# First non-empty line, stripped of surrounding quotes/whitespace.
LABEL=$(printf '%s' "$RAW" | grep -m1 -v '^[[:space:]]*$' | sed -e 's/^["'"'"' ]*//' -e 's/["'"'"' ]*$//')

if [ -z "$LABEL" ] || [ "${#LABEL}" -lt 2 ]; then
  log "empty label (model=$MODEL); raw=${RAW:0:120}"
  exit 1
fi
[ "${#LABEL}" -gt 48 ] && LABEL="${LABEL:0:48}"

# Persist as the session name (name + user_named:true) in the session store.
if [ -f "$WS" ]; then
  python3 "$ROOT/set-session-name.py" --set "$WS" "$LABEL" 2>>"$LOG" \
    && log "name set: $LABEL" || log "name set FAILED: $LABEL"
else
  log "workspace.yaml not found yet: $WS (label=$LABEL)"
fi

# Repaint, reusing the tab's current status icon if we know it.
[ -z "$TTYDEV" ] || [ "$TTYDEV" = "not a tty" ] && exit 0
STATE=$(cat "$STATEDIR/$SID.icon" 2>/dev/null)
case "$STATE" in
  wait) ICON='⏸' ;;
  idle) ICON='✳' ;;
  *)    ICON='⋯' ;;
esac
printf '\033]2;%s %s\007' "$ICON" "$LABEL" > "$TTYDEV" 2>/dev/null
exit 0
