-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.smoothscroll = false -- LazyVim enables this but it breaks <C-d>zz / <C-u>zz centering
-- NOTE: snacks.scroll (LazyVim default) breaks the same centering via its scroll
-- animation -- disabled in lua/plugins/snacks.lua.
