return {
  "neovim/nvim-lspconfig",
  opts = {
    -- Editor-wide LazyVim LSP options — applying to every server, not to any one of
    -- them. That is why this file is lsp.lua: it was vtsls.lua until the only
    -- genuinely vtsls-specific setting in it turned out to restate what LazyVim's
    -- typescript extra already sets (autoUseWorkspaceTsdk), leaving a file named
    -- after a server it no longer configures.
    --
    -- inlay_hints: off because of an nvim 0.12.4 bug (invalid col in
    -- inlay_hint.lua:362). Re-enable once that is fixed upstream.
    inlay_hints = { enabled = false },
  },
}
