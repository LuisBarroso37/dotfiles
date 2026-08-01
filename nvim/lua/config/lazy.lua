local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins", opts = { colorscheme = "catppuccin-mocha" } },
    -- Explorer setup: snacks explorer is the tree (<leader>e), mini.files the
    -- manual picker (<leader>fm). Both extras are declared in lazyvim.json so
    -- :LazyExtras reflects reality — importing one here instead bypassed
    -- LazyVim's bookkeeping and showed mini-files as "not enabled".
    -- No neo-tree disable is needed: it is not in LazyVim's core spec, only in
    -- the (unenabled) lazyvim.plugins.extras.editor.neo-tree extra.
    -- disable LazyVim's default colorscheme
    { "folke/tokyonight.nvim", enabled = false },
    -- catppuccin colorscheme
    { "catppuccin/nvim", name = "catppuccin", priority = 1000, opts = { flavour = "mocha" } },
    -- import/override with your plugins
    { import = "plugins" },
  },
  install = { colorscheme = { "catppuccin", "habamax" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
