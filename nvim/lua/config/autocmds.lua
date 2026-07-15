-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- ---------------------------------------------------------------------------
-- Format on save
--
-- LazyVim's built-in format-on-save doesn't reliably drive conform for markup
-- filetypes in this setup, and Angular templates use the `htmlangular` filetype
-- which the default `html` mapping misses. These autocmds handle it explicitly.
--
-- Both self-gate on the relevant tool config existing, so they're no-ops in
-- projects that don't use prettier/eslint (e.g. non-JS projects). JS/TS are left
-- to the eslint LSP (config/../plugins/eslint.lua) and deliberately not touched
-- here, to avoid double-formatting.
--
-- JSON is handled by BOTH passes, in order: prettier (indentation/whitespace)
-- then eslint --fix (jsonc/sort-keys, schema). The two are orthogonal — prettier
-- never reorders keys and eslint never touches whitespace — so they compose.
-- Ordering is guaranteed because same-group BufWritePre autocmds run in the order
-- they are registered, and the prettier autocmd below is registered first.
-- ---------------------------------------------------------------------------

local format_group = vim.api.nvim_create_augroup("user_format_on_save", { clear = true })

local PRETTIER_CONFIGS = {
  ".prettierrc",
  ".prettierrc.json",
  ".prettierrc.js",
  ".prettierrc.cjs",
  ".prettierrc.mjs",
  ".prettierrc.yaml",
  ".prettierrc.yml",
  ".prettierrc.toml",
  "prettier.config.js",
  "prettier.config.cjs",
  "prettier.config.mjs",
}

-- Pass 1 — Prettier for markup/style/data files (js/ts are handled by the eslint LSP).
vim.api.nvim_create_autocmd("BufWritePre", {
  group = format_group,
  pattern = { "*.html", "*.css", "*.scss", "*.yaml", "*.yml", "*.md", "*.json", "*.jsonc" },
  callback = function(args)
    local fname = vim.api.nvim_buf_get_name(args.buf)
    if fname == "" or not vim.fs.root(fname, PRETTIER_CONFIGS) then
      return
    end
    pcall(function()
      require("conform").format({
        bufnr = args.buf,
        formatters = { "prettier" },
        async = false,
        timeout_ms = 3000,
      })
    end)
  end,
})

-- Pass 2 — ESLint --fix for JSON. Runs EVERY auto-fixable rule the flat config maps
-- to the file (not just sort-keys); non-fixable violations (e.g. an invalid schema
-- property) are reported by :lint but left untouched here.
--
-- We feed the buffer to ESLint over stdin with --stdin-filename set to the real
-- path, because ESLint 9 flat config matches rules by file path (e.g. sort-keys
-- only applies to **/{nl,fr}.json), so a temp file elsewhere would match nothing.
-- --fix-dry-run + --format json returns the fixed source in the `output` field.
-- ESLint 9 needs its CWD to be the directory containing eslint.config.*.
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
