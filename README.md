# my-copilot-cli

Personal GitHub Copilot CLI tweaks. Each folder is a self-contained feature —
run its installer or copy what you want into `~/.copilot/`. Built to be cloned
by an agent ("set me up like this repo"), not installed wholesale.

## Features

- **[tab-title/](tab-title/)** — terminal tab title with a status icon (`⋯`
  working, `⏸` waiting for you, `✳` idle) plus an LLM-generated session label.
  The label is stored as the session's own name in `workspace.yaml`, so it
  survives restarts and shows up in Copilot's `/session` list. Install with
  `./tab-title/install.sh`.

See each folder's README for details and install steps.

## Related

- [`my-claude-code`](../my-claude-code/) — same idea for Claude Code.
- [`my-opencode`](../my-opencode/) — same idea for OpenCode.
