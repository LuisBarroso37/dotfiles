-- Use Diffview for review and lazygit for staging and commits.
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
    -- The conflicting <leader>gL mapping is overridden in config/keymaps.lua.
    keys = {
      {
        -- Compare tracked changes against the main fork point. Use <leader>gv for untracked files.
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
      -- Review uncommitted changes, including untracked files.
      { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Uncommitted changes (incl. untracked)" },
      { "<leader>gV", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
      -- Follow file history across renames.
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
