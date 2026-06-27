#!/bin/bash
# Background label generator (fire-and-forget, spawned by on-prompt.sh).
#
# Args: <sessionId> <ttyDevice> <cwd> <prompt>
#
# Runs a one-shot `copilot -p` with the configured small model to turn the
# user's first message into a short "emoji + 2-4 words" label, caches it, then
# repaints the tab keeping whatever status icon the tab currently shows.

SID="$1"
TTYDEV="$2"
CWD="$3"
PROMPT="$4"

ROOT="$HOME/.copilot/tab-title"
CACHE="$ROOT/cache"
LOG="$ROOT/tab-title.log"
mkdir -p "$CACHE/labels" "$CACHE/tty" 2>/dev/null

log() { printf '%s [%s] %s\n' "$(date +%H:%M:%S)" "${SID:0:8}" "$1" >> "$LOG" 2>/dev/null; }

[ -z "$SID" ] && exit 0
[ -f "$CACHE/labels/$SID.txt" ] && exit 0   # already generated

MODEL="${TAB_TITLE_MODEL:-claude-sonnet-4.5}"

# Isolated copilot home: no MCP servers, no hooks (no recursion), no custom
# instructions -> fast, cheap, and side-effect free. Auth lives in the OS
# keychain on macOS, so the one-shot stays logged in.
GENHOME="$ROOT/gen-home"
mkdir -p "$GENHOME" 2>/dev/null
printf '%s' '{"mcpServers":{}}' > "$GENHOME/mcp-config.json" 2>/dev/null

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
# Trim overly long labels (emoji-safe-ish byte cap).
[ "${#LABEL}" -gt 48 ] && LABEL="${LABEL:0:48}"

printf '%s' "$LABEL" > "$CACHE/labels/$SID.txt" 2>/dev/null
log "label: $LABEL"

# Repaint, reusing the tab's current status icon if we know it.
[ -z "$TTYDEV" ] || [ "$TTYDEV" = "not a tty" ] && exit 0
TTYHASH=$(printf '%s' "$TTYDEV" | shasum 2>/dev/null | cut -d' ' -f1)
STATE=$(cat "$CACHE/tty/$TTYHASH.state" 2>/dev/null)
case "$STATE" in
  wait) ICON='⏸' ;;
  idle) ICON='✳' ;;
  *)    ICON='⋯' ;;
esac
printf '\033]2;%s %s\007' "$ICON" "$LABEL" > "$TTYDEV" 2>/dev/null
exit 0
