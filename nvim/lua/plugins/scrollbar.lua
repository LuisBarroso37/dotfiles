return {
  "petertriho/nvim-scrollbar",
  event = "BufReadPost",
  dependencies = { "lewis6991/gitsigns.nvim" },
  config = function()
    require("scrollbar").setup({
      handle = {
        color = "#6c7086", -- catppuccin mocha overlay0, similar to VS Code's scrollbar handle
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
