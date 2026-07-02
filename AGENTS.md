# claude-tour — instructions for coding agents

This file tells a coding agent (Claude Code, Codex, OpenCode, …) how to install
and use `claude-tour`. The tool lets you push an **annotated, navigable list of
code locations** into the user's running Neovim, so after a deep dive you can
hand them a guided walkthrough instead of a wall of text.

## When to use it

Reach for `claude-tour` whenever you've explored a codebase and the user would
benefit from *seeing* the relevant spots in their editor, in order:

- explaining how a feature/flow works across multiple files
- pointing out where a bug lives and the call sites that lead to it
- onboarding: "here are the 8 places that matter in this service"

It complements your text answer — send the tour, then summarize.

## Prerequisites

- Neovim ≥ 0.9
- Python 3 (standard library only)

## Installation

The user must have the Neovim plugin loaded **and** the `claude-tour` CLI on
your `PATH`. Check first — if `claude-tour --list` runs, it's already installed;
skip to Usage.

### 1. Install the Neovim plugin

Add it with the user's plugin manager. It must load at startup (`lazy = false`)
so it registers its RPC socket before any tour is sent.

lazy.nvim (`~/.config/nvim/lua/plugins/claude-tour.lua`):

```lua
return {
  {
    "yilenpan/claude-tour",
    lazy = false,
    config = function()
      require("claude-tour").setup()
    end,
  },
}
```

Then install headlessly:

```sh
nvim --headless "+Lazy! install" +qa
```

### 2. Put the CLI on PATH

The CLI ships in the plugin's `bin/` directory. Symlink it somewhere on PATH:

```sh
# lazy.nvim install location:
ln -sf ~/.local/share/nvim/lazy/claude-tour/bin/claude-tour ~/.local/bin/claude-tour
# (packer: ~/.local/share/nvim/site/pack/packer/start/claude-tour/bin/claude-tour)
```

Make sure `~/.local/bin` is on PATH. Verify:

```sh
claude-tour --list        # lists connected nvim instances (or "0 connected")
```

## Usage

The user keeps Neovim open in the project. From a terminal **in the same
project root**, write a tour JSON and send it:

```sh
claude-tour tour.json
# or pipe it:
echo '{"title":"...","items":[...]}' | claude-tour
```

The sidebar opens in their editor and jumps to the first location. They walk it
with `n`/`p`/`<CR>`.

### Tour JSON schema

```json
{
  "title": "How login works",
  "items": [
    { "file": "src/auth.py", "line": 42, "end_line": 48, "col": 5,
      "note": "Entry point. Validates the user then mints a token here." },
    { "file": "src/store.py", "line": 88,
      "note": "Token is persisted in Redis with a 24h TTL." }
  ]
}
```

- `file` (**required**) — relative paths resolve against the directory you run
  `claude-tour` from. Prefer paths relative to the project root.
- `line` (**required**), `col` (optional, 1-based).
- `end_line` (optional) — highlights the whole block `line`–`end_line` in the
  code window on jump. Use it to spotlight a function or a multi-line statement.
- `note` (optional) — the annotation. One or two sentences; it's word-wrapped in
  the sidebar. `annotation` / `comment` are accepted aliases.
- `title` (optional) — shown at the top of the sidebar.

### Authoring good tours

- **Order items in reading order** — the user presses `n` to walk them top to bottom.
- **Number the story in the notes** ("STEP 1 — …") when it's a sequential flow.
- **Use `end_line`** to highlight the whole relevant block, not just one line.
- **Keep notes tight** — the sidebar is narrow (~44 cols). One idea per item.
- **Keep tours focused** — 5–15 locations. Split a huge investigation into
  several themed tours rather than one 50-item dump.

## Output contract (for parsing results)

The CLI follows the AXI convention: all output — including errors — goes to
**stdout**; stderr stays empty. Exit codes: `0` success, `1` runtime error
(e.g. no nvim connected), `2` usage error (bad JSON, unknown flag).

```
$ claude-tour tour.json
sent: 3 location(s)
tour: How login works
help[2]:
  In nvim: n/p to walk locations, <CR> to jump, q to close
  Run `claude-tour` to see the current tour state
```

On failure, read the `error:` and `help:` lines and act on them:

```
$ claude-tour tour.json
error: no nvim connected for /path/to/project
help: Open nvim (with claude-tour.nvim loaded) in this directory, then retry
help: Run `claude-tour --list` to see every connected nvim
```

`claude-tour` (no args) prints the connected nvim and the currently loaded tour
— useful to confirm state before sending.

## Gotchas

- **Same project root** — the CLI finds the user's nvim by matching your current
  directory (exact, then nearest ancestor, then the sole running instance). Run
  it from inside the project.
- **`no nvim connected`** — the user has no nvim open there, or the plugin didn't
  load at startup. Ask them to open nvim in the project (and confirm `lazy = false`).
- **Multiple nvims** — set `CLAUDE_TOUR_SOCKET` to target a specific one; get its
  socket from `claude-tour --list`.
