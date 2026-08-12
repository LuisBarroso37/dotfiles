-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.smoothscroll = false -- LazyVim enables this but it breaks <C-d>zz / <C-u>zz centering
-- NOTE: snacks.scroll (LazyVim default) breaks the same centering via its scroll
-- animation -- disabled in lua/plugins/snacks.lua.

-- netrwPlugin is disabled in lazy.lua (snacks' replace_netrw=false no longer
-- does it). Without both disabled, `nvim .` would open netrw. With both off,
-- snacks dashboard's built-in argc skip (only when explorer.enabled) makes
-- the dashboard appear normally for a directory arg too.
--   nvim    -> dashboard
--   nvim .  -> dashboard (explorer still available via <leader>e)

-- Load a project's own `.nvim.lua` / `.nvimrc` / `.exrc` from the cwd. This is
-- what keeps repo-specific editor config (LSP heap sizes, lint rules that only
-- one codebase has, format timeouts) inside that repo instead of in these
-- dotfiles, which follow every machine. Neovim requires each file to be trusted
-- once before it is sourced (`:trust`), so an untrusted repo cannot run code.
vim.o.exrc = true
