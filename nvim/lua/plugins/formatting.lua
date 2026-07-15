return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        html = { "prettier" },
        htmlangular = { "prettier" }, -- Angular templates get their own filetype in LazyVim
        css = { "prettier" },
        scss = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        -- json is intentionally omitted: it's fixed via `eslint --fix` on save
        -- (jsonc/sort-keys + json-schema validation), see config/autocmds.lua
      },
    },
  },
}
