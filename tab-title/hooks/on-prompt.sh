#!/bin/bash
# userPromptSubmitted hook:
#   1. paint the working icon immediately
#   2. on the first prompt of a not-yet-named session, fire-and-forget the
#      background label generator
#
# Stdout is kept empty so the CLI parses no hook output (no prompt modification).

# Recursion guard: the background generator runs `copilot -p`, which would
# otherwise re-enter this hook. (It also uses an isolated COPILOT_HOME with no
# hooks, so this is belt-and-suspenders.)
[ -n "$COPILOT_TAB_TITLE_SKIP" ] && exit 0

ROOT="$HOME/.copilot/tab-title"
SESSIONS="$HOME/.copilot/session-state"

INPUT=$(cat 2>/dev/null)

SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // empty' 2>/dev/null)
[ -z "$SID" ] && SID="$COPILOT_AGENT_SESSION_ID"
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD=$(pwd)

TTYDEV=$(tty </dev/tty 2>/dev/null)
[ "$TTYDEV" = "not a tty" ] && TTYDEV=""

# Paint working now (reuse paint.sh with the same payload).
printf '%s' "$INPUT" | "$ROOT/paint.sh" work >/dev/null 2>&1

# Generate the label once per session: skip if the session is already named
# (by us on a previous prompt, or manually via /rename).
WS="$SESSIONS/$SID/workspace.yaml"
NAMED=""
[ -f "$WS" ] && NAMED=$(python3 "$ROOT/set-session-name.py" --get "$WS" 2>/dev/null)

if [ -n "$SID" ] && [ -z "$NAMED" ] && [ "${#PROMPT}" -ge 3 ]; then
  # Fully detach stdio from the inherited hook pipe so the CLI's hook executor
  # sees EOF and this hook returns at once, while the generator runs on.
  # (`setsid` is unavailable on macOS, so redirection + `disown` is used.)
  "$ROOT/label-gen.sh" "$SID" "$TTYDEV" "$CWD" "$PROMPT" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

exit 0
