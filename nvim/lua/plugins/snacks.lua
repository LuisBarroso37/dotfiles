return {
  "folke/snacks.nvim",
  -- LazyVim's keymaps.lua registers <leader>gL (Snacks cwd git_log) unconditionally
  -- via raw vim.keymap.set, not through the plugin keys spec — so keys = { false }
  -- won't work (it runs before keymaps.lua and gets overwritten). VeryLazy+schedule
  -- runs after keymaps.lua and wins.
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      once = true,
      callback = function()
        vim.schedule(function()
          -- Free up <leader>gL for diffview-plus's current-line history.
          -- DiffviewFileHistory is in diffview's cmd list, so pressing the key
          -- before diffview loads still triggers lazy-loading via cmd interception.
          pcall(vim.keymap.del, "n", "<leader>gL")
          vim.keymap.set(
            "n",
            "<leader>gL",
            "<cmd>.DiffviewFileHistory --follow<cr>",
            { desc = "History: current line" }
          )
        end)
      end,
    })
  end,
  opts = {
    -- Disable snacks smooth-scroll animation: it animates the two scroll
    -- targets from <C-d>zz / <C-u>zz separately, landing the cursor off-center
    -- first and then floating it up to center. Turning it off makes those maps
    -- jump instantly and land centered.
    scroll = { enabled = false },
    -- replace_netrw=false: don't auto-open the tree when entering a directory
    -- buffer (e.g. `nvim .`). The <leader>e/E/fe/fE keymaps still open it.
    explorer = { replace_netrw = false },
    picker = {
      sources = {
        -- 1. Fixes the default file finder (<leader><leader>)
        files = {
          hidden = true, -- Shows dotfiles
          ignored = true, -- Shows git-ignored files (e.g. .env files)
        },
        -- 2. Fixes the tree explorer sidebar (<leader>e)
        explorer = {
          hidden = true, -- Shows dotfiles in the tree sidebar
          ignored = true, -- Shows git-ignored files in the tree sidebar
        },
      },
    },
  },
}
