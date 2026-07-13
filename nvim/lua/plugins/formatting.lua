return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        javascript = { "eslint_d", "prettier" },
        typescript = { "eslint_d", "prettier" },
        javascriptreact = { "eslint_d", "prettier" },
        typescriptreact = { "eslint_d", "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        scss = { "prettier" },
        json = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
      },
      format_on_save = false,
      format_after_save = {
        lsp_format = "fallback",
      },
      formatters = {
        eslint_d = {
          -- Per-lib eslint.config.mjs files — eslint_d must run from the lib root, not the workspace root
          cwd = require("conform.util").root_file({
            "eslint.config.mjs",
            "eslint.config.js",
            ".eslintrc.js",
            ".eslintrc.json",
          }),
        },
      },
    },
  },
}
