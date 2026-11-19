return {
  "neovim/nvim-lspconfig",
  opts = {
    setup = {
      -- Fix LazyVim's ESLint formatter so it actually runs the ESLint LSP on save.
      --
      -- LazyVim's eslint extra registers an "eslint: lsp" formatter whose format fn
      -- calls conform WITHOUT setting `lsp_format`, so it inherits the default
      -- "fallback" — which only uses the LSP when NO CLI formatter exists. Because
      -- prettier is configured for TS (plugins/formatting.lua), conform always runs
      -- prettier and never the ESLint LSP, so eslint --fix (sort-imports, import/order)
      -- never applies. The registered formatter is silently just a second prettier pass.
      --
      -- We re-register the same formatter but force an ESLint-LSP-only conform pass:
      -- no CLI formatters, prefer the LSP, restricted to the eslint client. This runs
      -- eslint --fix as part of LazyVim's format-on-save — respecting the <leader>uf
      -- toggle and needing no manual BufWritePre autocmd.
      --
      -- This is the one deliberate deviation from stock in this file: it is a general
      -- LazyVim gap, not a project quirk, and without it eslint autofix never runs.
      -- Everything project-shaped (heap sizes, timeouts, per-repo lint rules) lives in
      -- that project's own `.nvim.lua` instead — see `vim.o.exrc` in config/options.lua.
      eslint = function()
        if vim.g.lazyvim_eslint_auto_format == false then
          return
        end
        local formatter = LazyVim.lsp.formatter({
          name = "eslint: lsp",
          primary = false,
          priority = 200,
          filter = "eslint",
        })
        formatter.format = function(buf)
          require("conform").format({
            bufnr = buf,
            formatters = {}, -- no CLI formatters; eslint LSP only
            lsp_format = "prefer", -- run the LSP even though prettier exists
            name = "eslint", -- only the eslint client; without it vtsls also formats
            -- Projects whose first fixAll has to build a whole TS program can raise
            -- this from their own .nvim.lua; conform's default is fine elsewhere.
            timeout_ms = vim.g.eslint_format_timeout_ms,
          })
        end
        LazyVim.format.register(formatter)
      end,
    },
  },
}
