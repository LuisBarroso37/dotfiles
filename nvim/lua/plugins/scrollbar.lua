return {
  "petertriho/nvim-scrollbar",
  event = "BufReadPost",
  dependencies = { "lewis6991/gitsigns.nvim" },
  config = function()
    require("scrollbar").setup({
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
