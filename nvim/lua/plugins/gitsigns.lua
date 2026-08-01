-- Extra gitsigns toggles LazyVim doesn't map by default. Merges into LazyVim's
-- existing gitsigns spec (matched by name); the `keys` add extra load triggers.
return {
  "lewis6991/gitsigns.nvim",
  -- stylua: ignore
  keys = {
    -- Show removed lines inline, in place, without leaving the buffer.
    --
    -- toggle_deleted is marked @deprecated upstream (gitsigns/actions.lua) in favour
    -- of preview_hunk_inline(), which LazyVim already maps as <leader>ghp. It is kept
    -- because the two are NOT equivalent: this shows every deleted line in the buffer
    -- at once, preview_hunk_inline only the hunk under the cursor. It still works and
    -- emits no warning; if a gitsigns bump ever removes it, <leader>ghp is the
    -- supported per-hunk replacement.
    { "<leader>gtd", function() require("gitsigns").toggle_deleted() end, desc = "Toggle deleted lines (inline)" },
    -- Intra-line word-level diff highlighting on changed lines.
    { "<leader>gtw", function() require("gitsigns").toggle_word_diff() end, desc = "Toggle word diff" },
    -- Editable side-by-side diff of THIS file against the fork point with main
    -- — the diffview <leader>gr replacement. Native nvim diff (the same engine
    -- diffview used, so it looks identical): left window is the base and is
    -- read-only, the right window is your real buffer, so you can edit against
    -- the diff and :w as usual. Close it with :q on the base window.
    --
    -- LazyVim already maps the other two bases: <leader>ghd vs the index and
    -- <leader>ghD vs HEAD~. Only the merge-base case was missing.
    {
      "<leader>gr",
      function()
        local base = vim.trim(vim.fn.system({ "git", "merge-base", "main", "HEAD" }))
        if vim.v.shell_error ~= 0 or base == "" then
          base = vim.trim(vim.fn.system({ "git", "merge-base", "origin/main", "HEAD" }))
        end
        if vim.v.shell_error ~= 0 or base == "" then
          vim.notify("gitsigns: no merge-base with main / origin/main", vim.log.levels.ERROR)
          return
        end
        require("gitsigns").diffthis(base)
      end,
      desc = "Diff file vs merge-base with main (editable)",
    },
  },
}
