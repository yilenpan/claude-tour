# claude-tour.nvim

A navigable, annotated list of code locations pushed into a running Neovim from
another process — built for the workflow of "Claude in one terminal, nvim in
another." When Claude does a deep dive on a codebase, it emits a list of
`file:line` locations with annotations; this plugin shows them in a sidebar you
can walk through, jumping the main window to each spot.

```
┌─ TOUR ───────────────────────┬─ src/auth.py ──────────────────────────┐
│  How login works             │                                        │
│ ──────────────────────────── │  2      if not user.is_active:         │
│ 1. src/auth.py:4             │  3          raise Disabled()           │
│    Entry point. Validates    │▸ 4      token = mint_token(user.id)     │
│    the user then mints a     │  5      store.put(token, user.id)       │
│    token here.               │  6      return token                   │
│                              │                                        │
│ 2. src/store.py:2           │                                        │
│    Token is persisted in     │                                        │
│    Redis with a 24h TTL.     │                                        │
└──────────────────────────────┴────────────────────────────────────────┘
```

## How it works

1. On startup the plugin records its RPC socket in
   `$XDG_STATE_HOME/claude-tour/servers.json` (default
   `~/.local/state/claude-tour/servers.json`), keyed by nvim's working directory.
2. The bundled `claude-tour` CLI reads a tour JSON, looks up the socket for the
   current directory, and pushes the tour into nvim over RPC.
3. The plugin renders the sidebar and jumps to the first location.

No polling, no file-watching, no copy-paste.

## Install

### lazy.nvim

```lua
{
  dir = "~/claude-tour.nvim",   -- or a git URL once you push it
  lazy = false,                 -- must load at startup so it registers its socket
  config = function()
    require("claude-tour").setup({
      side = "left",      -- "left" or "right"
      width = 44,
      auto_jump = true,   -- jump to the first location when a tour arrives
      auto_open = true,   -- open the sidebar when a tour arrives
    })
  end,
}
```

### Put the CLI on your PATH

```sh
ln -s ~/claude-tour.nvim/bin/claude-tour ~/.local/bin/claude-tour
# or add ~/claude-tour.nvim/bin to $PATH
```

## Usage

Open nvim in your project (that's what registers the socket). Then, from a
second terminal *in the same project*, send a tour:

```sh
claude-tour tour.json
# or
echo '{"title":"...","items":[...]}' | claude-tour
```

### Sidebar keys

| key       | action                              |
|-----------|-------------------------------------|
| `<CR>`    | jump to the location under the cursor |
| `n` / `p` | next / previous location (auto-jumps) |
| `q`       | close the sidebar                   |

### Commands

- `:ClaudeTour` — open/focus the sidebar
- `:ClaudeTourLoad <file.json>` — load a tour manually
- `:ClaudeTourNext` / `:ClaudeTourPrev` — navigate
- `:ClaudeTourClose` — close the sidebar

## Tour JSON schema

```json
{
  "title": "How login works",
  "items": [
    { "file": "src/auth.py", "line": 4, "col": 5,
      "note": "Entry point. Validates the user then mints a token here." },
    { "file": "src/store.py", "line": 2,
      "note": "Token is persisted in Redis with a 24h TTL." }
  ]
}
```

- `file` (required): relative paths resolve against the directory where
  `claude-tour` was invoked.
- `line` (required), `col` (optional, 1-based).
- `note` / `annotation` / `comment` (optional): free-form, multi-line, word-wrapped.
- `title` (optional): shown at the top of the sidebar.

## Telling Claude how to use it

Add something like this to your project's `CLAUDE.md`:

> When you finish exploring the codebase and want to walk me through it, write a
> tour file and run `claude-tour <file>`. The tour is JSON:
> `{"title": "...", "items": [{"file": "relative/path", "line": N, "note": "what happens here"}]}`.
> Order items in reading order. Keep notes to a sentence or two.

## Troubleshooting

- **`no matching nvim found`** — make sure nvim is open in the same project and
  the plugin loaded at startup (`lazy = false`). Check `claude-tour --list`.
- **Multiple nvim instances** — the socket is matched by exact cwd, then nearest
  ancestor directory, then (if only one server is running) that one. Override
  with the `CLAUDE_TOUR_SOCKET` environment variable.
