return {
  "folke/snacks.nvim",
  opts = {
    -- Disable snacks smooth-scroll animation: it animates the two scroll
    -- targets from <C-d>zz / <C-u>zz separately, landing the cursor off-center
    -- first and then floating it up to center. Turning it off makes those maps
    -- jump instantly and land centered.
    scroll = { enabled = false },
    -- The snacks explorer stays ENABLED on purpose. It is the tree on <leader>e;
    -- mini.files is the separate, complementary picker on <leader>fm. Setting
    -- `explorer = { enabled = false }` here did NOT remove the tree — that flag
    -- only gates Snacks.setup()'s event dispatcher, so all four of the extra's
    -- keymaps (<leader>e/E/fe/fE) stayed live. All it actually switched off was
    -- the directory-buffer hijack, which then handed `nvim .` to netrw and cost
    -- a netrw disable plus a UIEnter dashboard reconstruction to paper over.
  },
}
