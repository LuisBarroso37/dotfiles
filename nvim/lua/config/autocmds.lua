-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- ---------------------------------------------------------------------------
-- ESLint --fix for JSON on save
--
-- Formatting is prettier's job (conform, see plugins/formatting.lua) and linting
-- is the eslint LSP's job (see plugins/eslint.lua). But the eslint LSP's filetypes
-- (upstream lspconfig) do NOT include `json`/`jsonc`, so it never attaches to JSON
-- buffers and LazyVim's fixAll-on-save never runs for them. This autocmd is the
-- only thing that applies eslint's auto-fixable JSON rules on save — notably
-- `jsonc/sort-keys` on **/{nl,fr}.json. Non-fixable violations (e.g. an invalid
-- schema property) are left untouched here and surfaced by :lint.
--
-- It composes with conform's prettier pass regardless of order: prettier only
-- touches whitespace and sort-keys only reorders keys, so the two are orthogonal
-- and idempotent — the saved result is the same whichever runs first.
--
-- We feed the buffer to ESLint over stdin with --stdin-filename set to the real
-- path, because ESLint 9 flat config matches rules by file path (e.g. sort-keys
-- only applies to **/{nl,fr}.json), so a temp file elsewhere would match nothing.
-- --fix-dry-run + --format json returns the fixed source in the `output` field.
-- ESLint 9 needs its CWD to be the directory containing eslint.config.*.
-- Self-gates on a local eslint install + config, so it's a no-op elsewhere.
-- ---------------------------------------------------------------------------

local format_group = vim.api.nvim_create_augroup("user_format_on_save", { clear = true })

vim.api.nvim_create_autocmd("BufWritePre", {
  group = format_group,
  pattern = { "*.json", "*.jsonc" },
  callback = function(args)
    local fname = vim.api.nvim_buf_get_name(args.buf)
    if fname == "" then
      return
    end

    local eslint_root = vim.fs.root(fname, { "node_modules" })
    if not eslint_root then
      return
    end
    local eslint = eslint_root .. "/node_modules/.bin/eslint"
    if vim.fn.executable(eslint) ~= 1 then
      return
    end

    local config_dir = vim.fs.root(fname, { "eslint.config.mjs", "eslint.config.js", "eslint.config.cjs" })
    if not config_dir then
      return
    end

    local input = table.concat(vim.api.nvim_buf_get_lines(args.buf, 0, -1, false), "\n")
    local result = vim
      .system(
        { eslint, "--stdin", "--stdin-filename", fname, "--fix-dry-run", "--format", "json" },
        { cwd = config_dir, stdin = input }
      )
      :wait()

    if not result.stdout or result.stdout == "" then
      return
    end
    local ok, parsed = pcall(vim.json.decode, result.stdout)
    if not ok or type(parsed) ~= "table" or not parsed[1] or type(parsed[1].output) ~= "string" then
      return -- parse failed or no autofixable changes
    end

    local fixed = vim.split(parsed[1].output, "\n")
    if fixed[#fixed] == "" then
      table.remove(fixed) -- drop trailing empty element from the final newline
    end
    vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, fixed)
  end,
})
