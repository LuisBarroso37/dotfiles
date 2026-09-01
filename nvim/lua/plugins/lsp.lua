return {
  "neovim/nvim-lspconfig",
  opts = {
    -- Editor-wide LazyVim LSP options — applying to every server, not to any one of
    -- them.
    --
    -- inlay_hints: off because of an nvim 0.12.4 bug (invalid col in
    -- inlay_hint.lua:362). Re-enable once that is fixed upstream.
    inlay_hints = { enabled = false },
  },
}
