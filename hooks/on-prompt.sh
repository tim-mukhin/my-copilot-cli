#!/bin/bash
# userPromptSubmitted hook:
#   1. paint the working icon immediately
#   2. record the tty -> sessionId pointer (so no-sessionId events resolve the label)
#   3. fire-and-forget a background label generation on the first prompt of a session
#
# Stdout is kept empty so the CLI parses no hook output (no prompt modification).

# Recursion guard: the background generator runs `copilot -p`, which would
# otherwise re-enter this hook. We also isolate COPILOT_HOME for the generator
# (no hooks there), so this is belt-and-suspenders.
[ -n "$COPILOT_TAB_TITLE_SKIP" ] && exit 0

ROOT="$HOME/.copilot/tab-title"
CACHE="$ROOT/cache"
mkdir -p "$CACHE/labels" "$CACHE/tty" 2>/dev/null

INPUT=$(cat 2>/dev/null)

TTYDEV=$(tty </dev/tty 2>/dev/null)
[ -z "$TTYDEV" ] || [ "$TTYDEV" = "not a tty" ] && TTYDEV=""
TTYHASH=""
[ -n "$TTYDEV" ] && TTYHASH=$(printf '%s' "$TTYDEV" | shasum 2>/dev/null | cut -d' ' -f1)

SID=$(printf '%s' "$INPUT" | jq -r '.sessionId // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD=$(pwd)

# Bridge for sessionStart / agentStop (no sessionId in their payloads).
[ -n "$TTYHASH" ] && [ -n "$SID" ] && printf '%s' "$SID" > "$CACHE/tty/$TTYHASH.sid" 2>/dev/null

# Paint working now (reuse paint.sh with the same payload).
printf '%s' "$INPUT" | "$ROOT/paint.sh" work >/dev/null 2>&1

# Generate the label once per session. Fully detach stdio from the inherited
# hook pipe (so the CLI's hook executor sees EOF and this hook returns at once)
# while the generator keeps running in the background. `setsid` is unavailable
# on macOS, so we rely on the redirection + `disown` instead.
if [ -n "$SID" ] && [ ! -f "$CACHE/labels/$SID.txt" ] && [ "${#PROMPT}" -ge 3 ]; then
  "$ROOT/label-gen.sh" "$SID" "$TTYDEV" "$CWD" "$PROMPT" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

exit 0
