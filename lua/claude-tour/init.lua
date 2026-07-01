-- claude-tour.nvim
-- A navigable, annotated list of code locations pushed in from an external
-- process (e.g. Claude running in another terminal).

local M = {}

local config = {
  side = "left", -- "left" or "right"
  width = 44,
  auto_jump = true, -- jump to the first location when a tour loads
  auto_open = true, -- open/focus the sidebar when a tour loads
}

local state = {
  items = {},
  title = "",
  idx = 0,
  bufnr = nil,
  winid = nil,
  origin_win = nil,
  item_line = {}, -- item index -> 1-based buffer line of its header
  line_item = {}, -- 1-based buffer line -> item index
  ns = vim.api.nvim_create_namespace("claude_tour_current"),
  sns = vim.api.nvim_create_namespace("claude_tour_static"),
}

----------------------------------------------------------------------
-- server registry (shared with the `claude-tour` CLI)
----------------------------------------------------------------------

local function state_dir()
  local base = os.getenv("XDG_STATE_HOME")
  if not base or base == "" then
    base = vim.fn.expand("~/.local/state")
  end
  return base .. "/claude-tour"
end

local function registry_path()
  return state_dir() .. "/servers.json"
end

local function read_registry()
  local f = io.open(registry_path(), "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    return data
  end
  return {}
end

local function write_registry(reg)
  vim.fn.mkdir(state_dir(), "p")
  local f = io.open(registry_path(), "w")
  if not f then
    return
  end
  f:write(vim.json.encode(reg))
  f:close()
end

-- Prune registry entries whose socket no longer exists on disk.
local function prune(reg)
  local out = {}
  for dir, sock in pairs(reg) do
    if type(sock) == "string" and vim.fn.getftype(sock) ~= "" then
      out[dir] = sock
    end
  end
  return out
end

function M._register()
  local server = vim.v.servername
  if server == nil or server == "" then
    server = vim.fn.serverstart()
  end
  if not server or server == "" then
    return
  end
  local reg = prune(read_registry())
  reg[vim.fn.getcwd()] = server
  write_registry(reg)
end

function M._unregister()
  local reg = read_registry()
  reg[vim.fn.getcwd()] = nil
  write_registry(prune(reg))
end

----------------------------------------------------------------------
-- rendering
----------------------------------------------------------------------

local function wrap(text, width)
  local out = {}
  for _, para in ipairs(vim.split(text, "\n", { plain = true })) do
    local line = ""
    for word in para:gmatch("%S+") do
      if #line == 0 then
        line = word
      elseif #line + 1 + #word <= width then
        line = line .. " " .. word
      else
        out[#out + 1] = line
        line = word
      end
    end
    out[#out + 1] = line
  end
  return out
end

local function render()
  if not (state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)) then
    return
  end
  local lines = {}
  local statics = {} -- { line0, group }
  state.item_line = {}
  state.line_item = {}

  local function add(s)
    lines[#lines + 1] = s
    return #lines
  end

  add("  " .. (state.title ~= "" and state.title or "Claude Tour"))
  statics[#statics + 1] = { 0, "ClaudeTourTitle" }
  add(string.rep("─", config.width - 1))
  statics[#statics + 1] = { 1, "ClaudeTourNote" }

  for i, it in ipairs(state.items) do
    local header = string.format("%d. %s:%d", i, it.display_file, it.line)
    local hl = add(header)
    state.item_line[i] = hl
    state.line_item[hl] = i
    statics[#statics + 1] = { hl - 1, "ClaudeTourLocation" }
    if it.note and it.note ~= "" then
      for _, nl in ipairs(wrap(it.note, config.width - 5)) do
        local l = add("    " .. nl)
        state.line_item[l] = i
        statics[#statics + 1] = { l - 1, "ClaudeTourNote" }
      end
    end
    add("")
  end

  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.bufnr, state.sns, 0, -1)
  for _, s in ipairs(statics) do
    vim.api.nvim_buf_add_highlight(state.bufnr, state.sns, s[2], s[1], 0, -1)
  end
end

local function highlight_current()
  if not (state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)) then
    return
  end
  vim.api.nvim_buf_clear_namespace(state.bufnr, state.ns, 0, -1)
  local ln = state.item_line[state.idx]
  if ln then
    vim.api.nvim_buf_add_highlight(state.bufnr, state.ns, "ClaudeTourCurrent", ln - 1, 0, -1)
    if state.winid and vim.api.nvim_win_is_valid(state.winid) then
      pcall(vim.api.nvim_win_set_cursor, state.winid, { ln, 0 })
    end
  end
end

----------------------------------------------------------------------
-- sidebar window / buffer
----------------------------------------------------------------------

local function setup_keymaps(buf)
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local i = state.line_item[row]
    if i then
      M.goto_item(i, true)
    end
  end)
  map("n", function()
    M.next()
  end)
  map("p", function()
    M.prev()
  end)
  map("q", function()
    M.close()
  end)
end

local function ensure_buffer()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "claudetour"
  vim.api.nvim_buf_set_name(buf, "claude-tour://tour")
  setup_keymaps(buf)
  state.bufnr = buf
end

function M.open()
  ensure_buffer()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
    return
  end
  -- Remember where the user was so jumps land there.
  local cur = vim.api.nvim_get_current_win()
  if cur ~= state.winid then
    state.origin_win = cur
  end
  local pos = config.side == "right" and "botright" or "topleft"
  vim.cmd(pos .. " vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, state.bufnr)
  vim.api.nvim_win_set_width(win, config.width)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winfixwidth = true
  vim.wo[win].list = false
  state.winid = win
end

function M.close()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
  state.winid = nil
end

----------------------------------------------------------------------
-- navigation
----------------------------------------------------------------------

local function usable_target_win()
  local win = state.origin_win
  if win and vim.api.nvim_win_is_valid(win) and win ~= state.winid then
    return win
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= state.winid and vim.api.nvim_win_get_config(w).relative == "" then
      return w
    end
  end
  -- No non-sidebar window: make one next to the sidebar.
  local pos = config.side == "right" and "topleft" or "botright"
  vim.cmd(pos .. " vsplit")
  return vim.api.nvim_get_current_win()
end

function M.goto_item(i, keep_focus_sidebar)
  if i < 1 or i > #state.items then
    return
  end
  state.idx = i
  local it = state.items[i]
  local win = usable_target_win()
  state.origin_win = win
  vim.api.nvim_set_current_win(win)
  vim.cmd("edit " .. vim.fn.fnameescape(it.path))
  local lnum = math.max(it.line, 1)
  local col = math.max((it.col or 1) - 1, 0)
  pcall(vim.api.nvim_win_set_cursor, 0, { lnum, col })
  vim.cmd("normal! zz")
  highlight_current()
  if keep_focus_sidebar and state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
  end
end

function M.next()
  local i = state.idx < 1 and 1 or state.idx + 1
  if i > #state.items then
    i = #state.items
  end
  M.goto_item(i, true)
end

function M.prev()
  local i = state.idx <= 1 and 1 or state.idx - 1
  M.goto_item(i, true)
end

----------------------------------------------------------------------
-- loading a tour
----------------------------------------------------------------------

function M.set_tour(data)
  if type(data) ~= "table" then
    return
  end
  local base = data.cwd or vim.fn.getcwd()
  local items = {}
  for _, raw in ipairs(data.items or {}) do
    local line = tonumber(raw.line)
    if raw.file and line then
      local path = raw.file
      if not path:match("^/") then
        path = base .. "/" .. path
      end
      path = vim.fn.fnamemodify(path, ":p")
      items[#items + 1] = {
        path = path,
        display_file = vim.fn.fnamemodify(path, ":."),
        line = line,
        col = tonumber(raw.col),
        note = raw.note or raw.annotation or raw.comment or "",
      }
    end
  end

  state.items = items
  state.title = data.title or ""
  state.idx = 0

  if config.auto_open then
    M.open()
  end
  render()
  if #items > 0 and config.auto_jump then
    M.goto_item(1, true)
  end
  vim.notify(string.format("claude-tour: loaded %d location(s)", #items), vim.log.levels.INFO)
end

-- Entry point used by the CLI bridge via --remote-expr. Runs async so it is
-- safe to call from remote-expr context (which forbids window changes inline).
function M.load(path)
  vim.schedule(function()
    local f = io.open(path, "r")
    if not f then
      vim.notify("claude-tour: cannot read " .. tostring(path), vim.log.levels.ERROR)
      return
    end
    local content = f:read("*a")
    f:close()
    local ok, data = pcall(vim.json.decode, content)
    if not ok then
      vim.notify("claude-tour: invalid JSON in tour", vim.log.levels.ERROR)
      return
    end
    M.set_tour(data)
  end)
  return 1
end

-- Compact snapshot of the current tour, as a JSON string. Called by the
-- `claude-tour` CLI (via --remote-expr) to render its "content-first" home view.
function M.status()
  local items = {}
  for i, it in ipairs(state.items) do
    items[i] = { n = i, file = it.display_file, line = it.line, note = it.note }
  end
  return vim.json.encode({
    title = state.title,
    count = #state.items,
    current = state.idx,
    items = items,
  })
end

function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
end

function M._config()
  return config
end

return M
