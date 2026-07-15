return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      eslint = {
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
  },
}
