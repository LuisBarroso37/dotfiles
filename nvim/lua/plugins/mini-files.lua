return {
  "nvim-mini/mini.files",
  dependencies = { "nvim-mini/mini.icons" },
  -- No `use_as_default_explorer` override: LazyVim's mini-files extra already
  -- sets it false, and directory buffers are the snacks explorer's job. mini.files
  -- is deliberately manual-only, on <leader>fm / <leader>fM.
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
