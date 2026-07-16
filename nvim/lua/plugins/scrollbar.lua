return {
  "petertriho/nvim-scrollbar",
  event = "BufReadPost",
  -- catppuccin is a dependency because config() reads its palette; this guarantees
  -- it's loaded first (it already is in practice via priority 1000, but be explicit).
  dependencies = { "lewis6991/gitsigns.nvim", "catppuccin/nvim" },
  config = function()
    -- Pull the handle color from the catppuccin palette so it tracks the flavor
    -- instead of being a hardcoded hex. overlay0 is close to VS Code's scrollbar handle.
    local mocha = require("catppuccin.palettes").get_palette("mocha")
    require("scrollbar").setup({
      handle = {
        color = mocha.overlay0,
        blend = 0,
      },
      handlers = {
        cursor = true,
        diagnostic = true, -- errors/warnings from the LSP
        gitsigns = true, -- added/changed/removed lines
        search = false, -- needs nvim-hlslens; off to avoid the extra dep
      },
    })
    require("scrollbar.handlers.gitsigns").setup()
  end,
}
