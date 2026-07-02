if vim.g.loaded_claude_tour then
  return
end
vim.g.loaded_claude_tour = true

local ok, ct = pcall(require, "claude-tour")
if not ok then
  return
end

-- Default highlight groups (overridable in a colorscheme / config).
local function set_hl()
  vim.api.nvim_set_hl(0, "ClaudeTourTitle", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "ClaudeTourLocation", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "ClaudeTourNote", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "ClaudeTourCurrent", { link = "Visual", default = true })
  vim.api.nvim_set_hl(0, "ClaudeTourTarget", { link = "Visual", default = true })
end
set_hl()

-- Register this instance's RPC socket so the `claude-tour` CLI can find it.
ct._register()

local grp = vim.api.nvim_create_augroup("ClaudeTour", { clear = true })
vim.api.nvim_create_autocmd("DirChanged", {
  group = grp,
  callback = function()
    ct._register()
  end,
})
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = grp,
  callback = function()
    ct._unregister()
  end,
})
vim.api.nvim_create_autocmd("ColorScheme", {
  group = grp,
  callback = set_hl,
})

vim.api.nvim_create_user_command("ClaudeTourLoad", function(o)
  ct.load(vim.fn.fnamemodify(o.args, ":p"))
end, { nargs = 1, complete = "file", desc = "Load a tour JSON file" })

vim.api.nvim_create_user_command("ClaudeTour", function()
  ct.open()
end, { desc = "Open/focus the Claude tour sidebar" })

vim.api.nvim_create_user_command("ClaudeTourNext", function()
  ct.next()
end, { desc = "Jump to the next tour location" })

vim.api.nvim_create_user_command("ClaudeTourPrev", function()
  ct.prev()
end, { desc = "Jump to the previous tour location" })

vim.api.nvim_create_user_command("ClaudeTourClose", function()
  ct.close()
end, { desc = "Close the Claude tour sidebar" })
