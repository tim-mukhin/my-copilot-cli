# tab-title (Copilot CLI)

Terminal tab title with a status icon + an LLM-generated session label, for the
[GitHub Copilot CLI](https://docs.github.com/copilot/how-tos/use-copilot-agents/use-copilot-cli).

By analogy with [`my-claude-code`](https://github.com/tim-mukhin/my-claude-code)
and [`my-opencode`](https://github.com/tim-mukhin/my-opencode) — same idea,
another host.

```
⋯ 🪝 GitHub webhooks setup   <- agent is working
⏸ 🪝 GitHub webhooks setup   <- paused, waiting for you (permission / question)
✳ 🪝 GitHub webhooks setup   <- idle, ready for input
⋯ my-project                 <- right after start, before the label is generated
```

Status icons:

- `⋯` working
- `⏸` paused, waiting for the user (permission prompt / `ask_user`)
- `✳` idle, ready for input

The label (emoji + 1-4 words) is generated **once per session** by a background,
one-shot `copilot -p` call using a small model. Language follows your first
message (Russian message → Russian label).

The label is stored as the session's **own name** in
`~/.copilot/session-state/<id>/workspace.yaml` (`name` + `user_named: true`) —
not in an ad-hoc cache. So it survives tab reloads and computer restarts (it's
re-read on resume), and it also shows up in Copilot's own `/session` list.

## How it works

Copilot CLI loads user-level hooks from `~/.copilot/hooks/*.json`
(`{ "version": 1, "hooks": { … } }`). We wire five events:

| Event                 | What we do                                                        |
| --------------------- | ----------------------------------------------------------------- |
| `sessionStart`        | Paint `✳` + the session's saved label (or cwd basename).          |
| `userPromptSubmitted` | Paint `⋯`. If the session isn't named yet, spawn the label-gen.   |
| `postToolUse`         | Paint `⋯` (still working; also recovers from `⏸` after approval). |
| `notification`        | `permission_prompt` / `elicitation_dialog` → paint `⏸`.           |
| `agentStop`           | Paint `✳` (turn ended).                                           |

The title is written directly as an `OSC 2` escape to `/dev/tty`, so it targets
the right tab automatically (one tty per terminal tab).

`sessionStart` / `agentStop` payloads carry no `sessionId`, so every hook reads
`$COPILOT_AGENT_SESSION_ID` — the env var the CLI exports to all subprocesses —
and falls back to the payload's `sessionId`. That id locates the session's
`workspace.yaml`, both to read the label (incl. right after a resume) and to
write it.

### Why writing the session name is safe

The CLI keeps the workspace in memory but its mutators load-modify-save the
file: `update_context` (on start/resume) preserves a non-empty `name`, and the
auto-namer (`update_summary`) is a no-op once `user_named: true`. There is no
periodic naked save of the live in-memory copy, so an external write of
`name` + `user_named: true` sticks. We only generate when the session isn't
already named, so a manual `/rename` is respected.

### The disabled-host-title story

Copilot CLI writes its own terminal title (`Copilot: <intent>` / `GitHub
Copilot`) via `updateTerminalTitle`. Left on, it overwrites ours. The installer
sets `"updateTerminalTitle": false` in `~/.copilot/settings.json` (equivalent to
exporting `COPILOT_DISABLE_TERMINAL_TITLE=1`).

### Label generation, isolated and fast

The background generator runs `copilot -p` with `COPILOT_HOME` pointed at a
throwaway dir (unique per invocation) containing an empty `mcp-config.json`. That:

- skips MCP server startup (≈45s → ≈10s),
- loads **no hooks** there, so the inner `copilot` can't re-enter our
  `userPromptSubmitted` hook (no recursion — belt-and-suspenders with the
  `COPILOT_TAB_TITLE_SKIP=1` guard),
- loads no custom instructions,
- is unique per run, so two first-prompts in two terminals can't cross-talk.

Auth lives in the macOS keychain, so the one-shot stays logged in even with an
isolated home. The throwaway home is removed on exit.

## Install

```bash
git clone <this-repo> ~/src/my-copilot-cli
cd ~/src/my-copilot-cli
./tab-title/install.sh
```

This copies the scripts to `~/.copilot/tab-title/`, the hook config to
`~/.copilot/hooks/tab-title.json`, and sets `updateTerminalTitle: false`.
Open a fresh Copilot CLI session to pick up the hooks.

## Files

| File                        | Purpose                                                            |
| --------------------------- | ----------------------------------------------------------------- |
| `hooks/tab-title.json`      | Hook config (→ `~/.copilot/hooks/`).                              |
| `hooks/paint.sh`            | Resolve the session label + paint `<icon> <label>` to `/dev/tty`. |
| `hooks/on-prompt.sh`        | `userPromptSubmitted`: paint `⋯`, spawn label-gen if not named.   |
| `hooks/label-gen.sh`        | Background one-shot `copilot -p` → label → workspace.yaml → repaint. |
| `hooks/set-session-name.py` | Safe `--get` / `--set` of `name`/`user_named` in `workspace.yaml`. |
| `install.sh`                | Copy scripts + config, disable the host title.                    |

## Customize

- **Icons** — `ICON`/`STATE` cases in `paint.sh` (and the repaint case in `label-gen.sh`).
- **Label prompt / language** — `SYS` in `label-gen.sh`.
- **Label model** — defaults to `claude-sonnet-4.5`. Override with
  `export TAB_TITLE_MODEL=claude-opus-4.5`. (Smaller models can 400 when MCP tool
  definitions leak into the label-gen request; the isolated home avoids that, but
  sonnet is the safe default.)

## Where things live

- The label itself: `~/.copilot/session-state/<sessionId>/workspace.yaml` (`name`).
- Log: `~/.copilot/tab-title/tab-title.log`
- Per-session status icon (operational, for repaint): `~/.copilot/tab-title/state/`

## Uninstall

```bash
rm -f ~/.copilot/hooks/tab-title.json
rm -rf ~/.copilot/tab-title
# remove "updateTerminalTitle": false from ~/.copilot/settings.json (or set it to true)
```

Already-generated labels stay as the sessions' names (they're real session
names now) and show up in `/session`; that's harmless.

## Compared to my-claude-code, my-oh-my-pi

| Host        | Title API                     | Disable host title via       | Label-gen      | Status source        |
| ----------- | ----------------------------- | ---------------------------- | -------------- | -------------------- |
| Claude Code | shell hook writes OSC 2       | `CLAUDE_CODE_DISABLE_TERMINAL_TITLE` | `claude --print` | hook events  |
| Copilot CLI | shell hook writes OSC 2       | `updateTerminalTitle:false`  | `copilot -p`   | hook events          |
| opencode    | plugin                        | unset shell title trick      | `opencode run` | plugin events        |
| omp / pi    | extension `ctx.ui.setTitle()` | `PI_NO_TITLE=1` / watchdog    | `omp`/`pi -p`  | extension events     |

Deps: `bash`, `jq`, `shasum`, `copilot` CLI.
