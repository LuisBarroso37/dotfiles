return {
  "neovim/nvim-lspconfig",
  opts = {
    -- Editor-wide LazyVim LSP options — applying to every server, not to any one of
    -- them.
    --
    -- Still needed with Neovim 0.12.5: inlay_hint.lua:362 calls
    -- nvim_buf_set_extmark at the unbounded hint position and can raise
    -- "Invalid 'col': out of range" after edits shorten a line. Recheck the
    -- installed runtime before enabling again (neovim/neovim#39772).
    inlay_hints = { enabled = false },
    servers = {
      terraformls = {},
    },
  },
}
