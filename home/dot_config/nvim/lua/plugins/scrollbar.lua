return {
  "petertriho/nvim-scrollbar",
  event = "BufReadPost",
  -- catppuccin is a dependency because config() reads its palette. LazyVim declares
  -- catppuccin `lazy = true`, so nothing else guarantees it is loaded by BufReadPost —
  -- this dependency is what actually forces it to load first.
  dependencies = { "lewis6991/gitsigns.nvim", "catppuccin/nvim" },
  config = function()
    -- Pull the handle color from the catppuccin palette so it tracks the flavor
    -- instead of being a hardcoded hex. overlay0 is close to VS Code's scrollbar handle.
    local mocha = require("catppuccin.palettes").get_palette("mocha")
    require("scrollbar").setup({
      scrollbar = {
        thumb = {
          highlight = { bg = mocha.overlay0 },
          blend = 0,
        },
      },
      providers = {
        gitsigns = true,
        search = false,
        marks = false,
      },
    })
  end,
}
