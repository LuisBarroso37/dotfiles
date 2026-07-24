return {
  "nvim-mini/mini.files",
  opts = {
    options = {
      use_as_default_explorer = true,
    },
  },
  keys = {
    {
      "<leader>fm",
      function()
        local mf = require("mini.files")
        if not mf.close() then
          mf.open(vim.api.nvim_buf_get_name(0), true)
        end
      end,
      desc = "Toggle mini.files (Current File)",
    },
    {
      "<leader>fM",
      function()
        local mf = require("mini.files")
        if not mf.close() then
          mf.open(vim.uv.cwd(), true)
        end
      end,
      desc = "Toggle mini.files (cwd)",
    },
    {
      "<leader>e",
      function()
        local mf = require("mini.files")
        if not mf.close() then
          mf.open(vim.api.nvim_buf_get_name(0), true)
        end
      end,
      desc = "Toggle mini.files (Current File)",
    },
    {
      "<leader>E",
      function()
        local mf = require("mini.files")
        if not mf.close() then
          mf.open(vim.uv.cwd(), true)
        end
      end,
      desc = "Toggle mini.files (cwd)",
    },
  },
}
