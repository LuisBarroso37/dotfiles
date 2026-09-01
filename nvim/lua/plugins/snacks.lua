return {
  "folke/snacks.nvim",
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
        -- `exclude` is required alongside these flags: snacks' files/explorer
        -- sources ship no default exclude, so `hidden + ignored` also surfaces
        -- .git internals and node_modules (measured here: 122 files -> 623, 107
        -- of them under .git/). Showing dotfiles and .env is the intent; showing
        -- object files is not.
        files = {
          hidden = true, -- Shows dotfiles
          ignored = true, -- Shows git-ignored files (e.g. .env files)
          exclude = { ".git", "node_modules" },
        },
        -- 2. Fixes the tree explorer sidebar (<leader>e)
        explorer = {
          hidden = true, -- Shows dotfiles in the tree sidebar
          ignored = true, -- Shows git-ignored files in the tree sidebar
          exclude = { ".git", "node_modules" },
        },
      },
    },
  },
}
