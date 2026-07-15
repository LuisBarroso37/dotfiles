-- Extra gitsigns toggles LazyVim doesn't map by default. Merges into LazyVim's
-- existing gitsigns spec (matched by name); the `keys` add extra load triggers.
return {
  "lewis6991/gitsigns.nvim",
  keys = {
    -- Show removed lines inline, in place, without leaving the buffer.
    { "<leader>gtd", function() require("gitsigns").toggle_deleted() end, desc = "Toggle deleted lines (inline)" },
    -- Intra-line word-level diff highlighting on changed lines.
    { "<leader>gtw", function() require("gitsigns").toggle_word_diff() end, desc = "Toggle word diff" },
  },
}
