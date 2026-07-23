return {
  -- In-buffer markdown rendering (tables, headings, code blocks).
  -- Renders in normal/command/terminal mode; raw syntax in insert mode.
  -- Toggle with <leader>um.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
    ft = { "markdown" },
    opts = {
      render_modes = { "n", "c", "t" },
    },
    config = function(_, opts)
      require("render-markdown").setup(opts)
      Snacks.toggle({
        name = "Render Markdown",
        get = require("render-markdown").get,
        set = require("render-markdown").set,
      }):map("<leader>um")
    end,
  },

  -- Markdown LSP: cross-document link navigation and dead link detection.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        marksman = {},
      },
    },
  },
}
