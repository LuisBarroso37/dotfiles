-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.smoothscroll = false -- LazyVim enables this but it breaks <C-d>zz / <C-u>zz centering
-- NOTE: snacks.scroll (LazyVim default) breaks the same centering via its scroll
-- animation -- disabled in lua/plugins/snacks.lua.

-- Disable netrw. Nothing auto-replaces it (snacks explorer is disabled; mini.files
-- is opened manually). Without this, `nvim .` would open the netrw directory listing.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- When `nvim .` (or any single directory arg) is invoked, cd to the directory and
-- show the dashboard instead. Must live here (not autocmds.lua) because autocmds.lua
-- is loaded on VeryLazy — after VimEnter has already fired.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    if vim.fn.argc(-1) ~= 1 then return end
    local arg = vim.fn.argv(0) --[[@as string]]
    if arg == "" or vim.fn.isdirectory(arg) ~= 1 then return end
    vim.cmd("cd " .. vim.fn.fnameescape(arg))
    vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(false, true))
    vim.schedule(function()
      require("snacks").dashboard()
    end)
  end,
})
