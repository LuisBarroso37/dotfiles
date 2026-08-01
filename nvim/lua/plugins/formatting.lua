-- Prettier config markers. Prettier only runs when one of these is resolvable
-- from the file upward, so a .json/.yaml/.md/… file in a non-JS project (Rust,
-- Go, …) is NOT reformatted by an unrelated prettier. This gate applies to every
-- filetype below and mirrors the root check the old pass-1 format autocmd had.
--
-- Deliberately NOT using lazyvim.plugins.extras.formatting.prettier: its
-- `vim.g.lazyvim_prettier_needs_config` gate shells out to `prettier
-- --find-config-path`, and prettier is not installed globally here (it comes
-- from each project's node_modules/.bin). That check would fail with "command
-- not found", report "no config", and silently disable prettier everywhere.
-- A filesystem lookup needs no binary and spawns no process.
local PRETTIER_CONFIGS = {
  ".prettierrc",
  ".prettierrc.json",
  ".prettierrc.json5",
  ".prettierrc.js",
  ".prettierrc.cjs",
  ".prettierrc.mjs",
  ".prettierrc.yaml",
  ".prettierrc.yml",
  ".prettierrc.toml",
  ".prettierrc.ts",
  ".prettierrc.mts",
  ".prettierrc.cts",
  "prettier.config.js",
  "prettier.config.cjs",
  "prettier.config.mjs",
  "prettier.config.ts",
  "prettier.config.mts",
  "prettier.config.cts",
}

return {
  {
    "stevearc/conform.nvim",
    opts = {
      -- Prettier handles ALL formatting; conform runs it on save via LazyVim's
      -- format-on-save. It resolves the workspace's own prettier binary (via
      -- node_modules/.bin) and its config from the file upward, so it works in
      -- monorepos. Linting/auto-fixing is the eslint LSP's job (plugins/eslint.lua).
      formatters_by_ft = {
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        json = { "prettier" },
        jsonc = { "prettier" },
        html = { "prettier" },
        htmlangular = { "prettier" }, -- Angular templates get their own filetype in LazyVim
        css = { "prettier" },
        scss = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        -- NOTE: prettier formats json whitespace here, but eslint's jsonc/sort-keys
        -- autofix for **/{nl,fr}.json is applied separately in config/autocmds.lua —
        -- the eslint LSP doesn't attach to json filetypes, so nothing else applies it.
      },
      formatters = {
        prettier = {
          -- Project-scope the (global) filetype mappings above: only format when a
          -- prettier config is resolvable, so these rules don't leak prettier into
          -- non-JS projects that merely happen to contain a .json/.yaml/.md file.
          condition = function(_, ctx)
            return ctx.filename ~= nil and ctx.filename ~= "" and vim.fs.root(ctx.filename, PRETTIER_CONFIGS) ~= nil
          end,
        },
      },
    },
  },
}
