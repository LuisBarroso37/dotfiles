return {
  "folke/snacks.nvim",
  opts = {
    -- Disable snacks smooth-scroll animation: it animates the two scroll
    -- targets from <C-d>zz / <C-u>zz separately, landing the cursor off-center
    -- first and then floating it up to center. Turning it off makes those maps
    -- jump instantly and land centered.
    scroll = { enabled = false },
    -- LazyVim auto-loads a default explorer extra (snacks_explorer) when no
    -- explorer extra is explicitly imported. Disable it here since mini.files
    -- is used instead (opened manually via <leader>fm).
    explorer = { enabled = false },
  },
}
