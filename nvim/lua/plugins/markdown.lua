return {
  -- In-buffer markdown rendering (tables, headings, code blocks). Stock plugin
  -- defaults throughout — it renders in normal/command/terminal mode and shows raw
  -- syntax in insert mode without being told to. The only reason for a `config`
  -- instead of bare `opts` is to hang the <leader>um toggle off the plugin's
  -- get/set pair.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" },
    ft = { "markdown" },
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
