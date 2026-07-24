return {
  "nvim-mini/mini.files",
  dependencies = { "nvim-mini/mini.icons" },
  opts = {
    options = {
      use_as_default_explorer = false,
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
  },
}
