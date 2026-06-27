#!/bin/bash
# Paint the terminal tab title: <status-icon> <session-label>.
#
# Usage: paint.sh work|wait|idle
# Stdin: the hook JSON payload (may contain sessionId, cwd).
#
# Shared by the sessionStart / postToolUse / notification / agentStop hooks.
# The label itself is generated once per session by on-prompt.sh; here we only
# resolve the cached label and repaint with the right status icon.

STATE="${1:-work}"

case "$STATE" in
  work) ICON='⋯' ;;   # agent is working
  wait) ICON='⏸' ;;   # paused, waiting for the user (permission / question)
  idle) ICON='✳' ;;   # idle, ready for input
  *)    ICON='⋯' ;;
esac

ROOT="$HOME/.copilot/tab-title"
CACHE="$ROOT/cache"
mkdir -p "$CACHE/labels" "$CACHE/tty" 2>/dev/null

INPUT=$(cat 2>/dev/null)

# Resolve the controlling terminal. No tty -> nothing to paint.
TTYDEV=$(tty </dev/tty 2>/dev/null)
[ -z "$TTYDEV" ] || [ "$TTYDEV" = "not a tty" ] && exit 0
TTYHASH=$(printf '%s' "$TTYDEV" | shasum 2>/dev/null | cut -d' ' -f1)
[ -z "$TTYHASH" ] && exit 0

# Remember the current status for this tab so a late-arriving label repaint
# (from the background label generator) can reuse the right icon.
printf '%s' "$STATE" > "$CACHE/tty/$TTYHASH.state" 2>/dev/null

# Session id: prefer the payload, fall back to the per-tty pointer that
# on-prompt.sh writes (sessionStart / agentStop payloads carry no sessionId).
SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // empty' 2>/dev/null)
[ -z "$SID" ] && SID=$(cat "$CACHE/tty/$TTYHASH.sid" 2>/dev/null)

LABEL=""
[ -n "$SID" ] && [ -f "$CACHE/labels/$SID.txt" ] && LABEL=$(cat "$CACHE/labels/$SID.txt" 2>/dev/null)

# Fallback before a label exists: the working directory basename.
if [ -z "$LABEL" ]; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  [ -z "$CWD" ] && CWD=$(pwd)
  LABEL=$(basename "$CWD")
fi

printf '\033]2;%s %s\007' "$ICON" "$LABEL" > /dev/tty 2>/dev/null
exit 0
