# my-copilot-cli

Terminal tab title with a status icon + an LLM-generated session label, for the
[GitHub Copilot CLI](https://docs.github.com/copilot/how-tos/use-copilot-agents/use-copilot-cli).

By analogy with [`my-claude-code`](https://github.com/tim-mukhin/my-claude-code)
and [`my-oh-my-pi`](https://github.com/tim-mukhin/my-oh-my-pi) (opencode / omp / pi) —
same idea, another host.

```
⋯ 🪝 настройка вебхуков GitHub   <- agent is working
⏸ 🪝 настройка вебхуков GitHub   <- paused, waiting for you (permission / question)
✳ 🪝 настройка вебхуков GitHub   <- idle, ready for input
⋯ work-brain                     <- right after start, before the label is generated
```

Status icons:

- `⋯` working
- `⏸` paused, waiting for the user (permission prompt / `ask_user`)
- `✳` idle, ready for input

The label (emoji + 1-4 words) is generated **once per session** by a background,
one-shot `copilot -p` call using a small model. Language follows your first
message (Russian message → Russian label). Cached on disk per session, so it
doesn't regenerate when you switch tabs.

## How it works

Copilot CLI loads user-level hooks from `~/.copilot/hooks/*.json`
(`{ "version": 1, "hooks": { … } }`). We wire five events:

| Event                 | What we do                                                        |
| --------------------- | ----------------------------------------------------------------- |
| `sessionStart`        | Paint `✳` + cached label (or cwd basename).                       |
| `userPromptSubmitted` | Paint `⋯`. On the first prompt, spawn the background label-gen.    |
| `postToolUse`         | Paint `⋯` (still working; also recovers from `⏸` after approval). |
| `notification`        | `permission_prompt` / `elicitation_dialog` → paint `⏸`.           |
| `agentStop`           | Paint `✳` (turn ended).                                           |

The title is written directly as an `OSC 2` escape to `/dev/tty`, so it targets
the right tab automatically (one tty per terminal tab).

`sessionStart` and `agentStop` payloads carry no `sessionId`, so
`userPromptSubmitted` records a `tty → sessionId` pointer that those events use
to resolve the cached label.

### The disabled-host-title story

Copilot CLI writes its own terminal title (`Copilot: <intent>` / `GitHub
Copilot`) via `updateTerminalTitle`. Left on, it overwrites ours. The installer
sets `"updateTerminalTitle": false` in `~/.copilot/settings.json` (equivalent to
exporting `COPILOT_DISABLE_TERMINAL_TITLE=1`).

### Label generation, isolated and fast

The background generator runs `copilot -p` with `COPILOT_HOME` pointed at a
throwaway dir containing an empty `mcp-config.json`. That:

- skips MCP server startup (≈45s → ≈11s),
- loads **no hooks** there, so the inner `copilot` can't re-enter our
  `userPromptSubmitted` hook (no recursion — belt-and-suspenders with the
  `COPILOT_TAB_TITLE_SKIP=1` guard),
- loads no custom instructions.

Auth lives in the macOS keychain, so the one-shot stays logged in even with an
isolated home.

## Install

```bash
git clone <this-repo> ~/src/my-copilot-cli
cd ~/src/my-copilot-cli
./install.sh
```

This copies the scripts to `~/.copilot/tab-title/`, the hook config to
`~/.copilot/hooks/tab-title.json`, and sets `updateTerminalTitle: false`.
Open a fresh Copilot CLI session to pick up the hooks.

## Files

| File                  | Purpose                                                              |
| --------------------- | ------------------------------------------------------------------- |
| `hooks/tab-title.json`| Hook config (→ `~/.copilot/hooks/`).                                |
| `hooks/paint.sh`      | Resolve the cached label + paint `<icon> <label>` to `/dev/tty`.    |
| `hooks/on-prompt.sh`  | `userPromptSubmitted`: paint `⋯`, write tty pointer, spawn label-gen.|
| `hooks/label-gen.sh`  | Background one-shot `copilot -p` → label → cache → repaint.         |
| `install.sh`          | Copy scripts + config, disable the host title.                      |

## Customize

- **Icons** — `ICON`/`STATE` cases in `paint.sh` (and the repaint case in `label-gen.sh`).
- **Label prompt / language** — `SYS` in `label-gen.sh`.
- **Label model** — defaults to `claude-sonnet-4.5`. Override with
  `export TAB_TITLE_MODEL=claude-opus-4.5`. (Smaller models can 400 when MCP tool
  definitions leak into the label-gen request; the isolated home avoids that, but
  sonnet is the safe default.)

## Logs / cache

- Log: `~/.copilot/tab-title/tab-title.log`
- Per-session labels: `~/.copilot/tab-title/cache/labels/<sessionId>.txt`
- Per-tty pointers/state: `~/.copilot/tab-title/cache/tty/`

## Uninstall

```bash
rm -f ~/.copilot/hooks/tab-title.json
rm -rf ~/.copilot/tab-title
# remove "updateTerminalTitle": false from ~/.copilot/settings.json (or set it to true)
```

## Compared to my-claude-code, my-oh-my-pi

| Host        | Title API                     | Disable host title via       | Label-gen      | Status source        |
| ----------- | ----------------------------- | ---------------------------- | -------------- | -------------------- |
| Claude Code | shell hook writes OSC 2       | `CLAUDE_CODE_DISABLE_TERMINAL_TITLE` | `claude --print` | hook events  |
| Copilot CLI | shell hook writes OSC 2       | `updateTerminalTitle:false`  | `copilot -p`   | hook events          |
| opencode    | plugin                        | unset shell title trick      | `opencode run` | plugin events        |
| omp / pi    | extension `ctx.ui.setTitle()` | `PI_NO_TITLE=1` / watchdog    | `omp`/`pi -p`  | extension events     |

Deps: `bash`, `jq`, `shasum`, `copilot` CLI.
