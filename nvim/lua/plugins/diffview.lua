-- diffview-plus.nvim: git review UI (file panel + side-by-side diffs), independent of
-- lazygit. Use lazygit for staging/committing; diffview for reviewing a branch.
return {
  {
    "dlyongemallo/diffview-plus.nvim",
    cmd = {
      "DiffviewOpen",
      "DiffviewClose",
      "DiffviewToggleFiles",
      "DiffviewFocusFiles",
      "DiffviewRefresh",
      "DiffviewFileHistory",
    },
    -- <leader>gL (current-line history) conflicts with LazyVim's Snacks cwd git_log.
    -- snacks.lua's init disables that mapping after VeryLazy; see that file.
    -- All other keys are free: <leader>gr/gv/gV/gH/gA have no LazyVim defaults.
    keys = {
      {
        -- Whole-branch diff vs the fork point with main: committed + staged +
        -- unstaged TRACKED changes. Untracked/new files are NOT shown — git
        -- can't diff them against a commit, and diffview refuses to on purpose
        -- (see :h diffview; use <leader>gv for those). This is the pre-push /
        -- PR review: it's exactly what your branch adds once committed.
        "<leader>gr",
        function()
          local base = vim.trim(vim.fn.system({ "git", "merge-base", "main", "HEAD" }))
          if vim.v.shell_error ~= 0 or base == "" then
            base = vim.trim(vim.fn.system({ "git", "merge-base", "origin/main", "HEAD" }))
          end
          if vim.v.shell_error ~= 0 or base == "" then
            vim.notify("Diffview: no merge-base with main / origin/main", vim.log.levels.ERROR)
            return
          end
          vim.cmd("DiffviewOpen " .. base)
        end,
        desc = "Review branch vs main (tracked, incl. committed)",
      },
      -- Working tree vs index: unstaged + staged + UNTRACKED new files. This is
      -- the pre-commit review (the only view that shows untracked files).
      { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Uncommitted changes (incl. untracked)" },
      { "<leader>gV", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
      -- History (git log -L style: shows the actual diff at each change).
      -- --follow traces the file/line across renames.
      { "<leader>gH", "<cmd>DiffviewFileHistory --follow %<cr>", desc = "History: file (follow renames)" },
      {
        "<leader>gH",
        "<Esc><cmd>'<,'>DiffviewFileHistory --follow<cr>",
        mode = "v",
        desc = "History: selected range",
      },
      { "<leader>gA", "<cmd>DiffviewFileHistory<cr>", desc = "History: whole repo" },
    },
    opts = {
      enhanced_diff_hl = true, -- richer add/change highlighting in the diff windows
    },
  },
}
