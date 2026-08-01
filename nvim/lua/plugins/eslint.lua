return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      eslint = {
        -- Same memory headroom vtsls gets. A flat config that pulls in
        -- @typescript-eslint's type-aware rules makes the eslint server build a
        -- full TS program for the project; on a large Angular app that GC-thrashes
        -- (and eventually times out) at node's default heap size.
        cmd_env = {
          NODE_OPTIONS = "--max-old-space-size=8192",
        },
        -- General fix for monorepos: the default root_dir stops at the nearest
        -- eslint.config.js, but in a workspace dependencies are hoisted, so that
        -- per-package folder has no local eslint install. The server then emits
        -- `eslint/noLibrary` and silently never lints.
        --
        -- Instead, anchor the root at the nearest ancestor that actually has
        -- `node_modules/eslint` — the place the LSP can resolve the library from.
        -- This is project-agnostic: it lands on the project root for a plain repo
        -- and on the workspace root for any hoisted monorepo (npm/yarn/pnpm/Nx).
        -- `workingDirectories = { mode = "auto" }` (set by the LazyVim eslint
        -- extra) still picks up each package's own eslint.config.js per file.
        --
        -- Uses the nvim 0.11+ async root_dir signature: (bufnr, on_dir).
        root_dir = function(bufnr, on_dir)
          local fname = vim.api.nvim_buf_get_name(bufnr)
          local dir = fname ~= "" and vim.fs.dirname(fname) or vim.uv.cwd()

          while dir do
            if vim.uv.fs_stat(dir .. "/node_modules/eslint") then
              return on_dir(dir)
            end
            local parent = vim.fs.dirname(dir)
            if parent == dir then
              break
            end
            dir = parent
          end

          -- No eslint install found upward; fall back to conventional roots.
          on_dir(vim.fs.root(fname ~= "" and fname or vim.uv.cwd(), {
            "eslint.config.js",
            "eslint.config.mjs",
            "eslint.config.cjs",
            "eslint.config.ts",
            ".eslintrc.js",
            ".eslintrc.json",
            ".eslintrc",
            "package.json",
            ".git",
          }))
        end,
      },
    },
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
            name = "eslint", -- restrict LSP formatting to the eslint client
            -- The first fixAll after the server starts pays for the whole flat-config
            -- resolution plus the initial TS program build, which blows well past a
            -- few seconds on a large project — that's the "eslint LSP timeout" on the
            -- first save in a session. Steady-state saves land in well under a second,
            -- so the higher ceiling costs nothing after warm-up.
            timeout_ms = 10000,
          })
        end
        LazyVim.format.register(formatter)
      end,
    },
  },
}
