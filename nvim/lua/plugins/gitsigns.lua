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
  },
}
