#!/bin/bash
# Paint the terminal tab title: <status-icon> <session-label>.
#
# Usage: paint.sh work|wait|idle
# Stdin: the hook JSON payload (may contain sessionId, cwd).
#
# The label is the session's own name in workspace.yaml (set by label-gen.sh),
# so it survives tab reloads / restarts. Here we only resolve it and repaint
# with the right status icon.

STATE="${1:-work}"
case "$STATE" in
  work) ICON='⋯' ;;   # agent is working
  wait) ICON='⏸' ;;   # paused, waiting for the user (permission / question)
  idle) ICON='✳' ;;   # idle, ready for input
  *)    ICON='⋯' ;;
esac

ROOT="$HOME/.copilot/tab-title"
STATEDIR="$ROOT/state"
SESSIONS="$HOME/.copilot/session-state"
mkdir -p "$STATEDIR" 2>/dev/null

INPUT=$(cat 2>/dev/null)

# Session id: payload first, then the env var the CLI exports to every
# subprocess (the only source for sessionStart / agentStop payloads).
SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // empty' 2>/dev/null)
[ -z "$SID" ] && SID="$COPILOT_AGENT_SESSION_ID"

# Remember the current status so a late label repaint reuses the right icon.
[ -n "$SID" ] && printf '%s' "$STATE" > "$STATEDIR/$SID.icon" 2>/dev/null

# Label = the session name (only when user_named, i.e. ours or a manual rename).
LABEL=""
WS="$SESSIONS/$SID/workspace.yaml"
if [ -n "$SID" ] && [ -f "$WS" ]; then
  LABEL=$(python3 "$ROOT/set-session-name.py" --get "$WS" 2>/dev/null)
fi

# Fallback before a label exists: the working directory basename.
if [ -z "$LABEL" ]; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  [ -z "$CWD" ] && CWD=$(pwd)
  LABEL=$(basename "$CWD")
fi

printf '\033]2;%s %s\007' "$ICON" "$LABEL" > /dev/tty 2>/dev/null
exit 0
