return {
  "neovim/nvim-lspconfig",
  opts = {
    -- Editor-wide LazyVim LSP option (all servers, not just vtsls): disabled due to
    -- an nvim 0.12.4 bug (invalid col in inlay_hint.lua:362) — re-enable in a future
    -- version.
    --
    -- Nothing else belongs here: LazyVim's typescript extra already sets every vtsls
    -- setting this config used to restate (autoUseWorkspaceTsdk included).
    inlay_hints = { enabled = false },
  },
}
