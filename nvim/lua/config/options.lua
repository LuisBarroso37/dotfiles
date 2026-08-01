-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.smoothscroll = false -- LazyVim enables this but it breaks <C-d>zz / <C-u>zz centering
-- NOTE: snacks.scroll (LazyVim default) breaks the same centering via its scroll
-- animation -- disabled in lua/plugins/snacks.lua.

-- netrw is left alone, and `nvim .` is left to the snacks explorer's directory
-- hijack (the LazyVim default). The previous netrw disable + UIEnter dashboard
-- reconstruction existed only because snacks' hijack had been switched off; with
-- the explorer enabled in lua/plugins/snacks.lua, both are unnecessary.
--   nvim    -> dashboard
--   nvim .  -> snacks explorer tree

-- Load a project's own `.nvim.lua` / `.nvimrc` / `.exrc` from the cwd. This is
-- what keeps repo-specific editor config (LSP heap sizes, lint rules that only
-- one codebase has, format timeouts) inside that repo instead of in these
-- dotfiles, which follow every machine. Neovim requires each file to be trusted
-- once before it is sourced (`:trust`), so an untrusted repo cannot run code.
vim.o.exrc = true
