return {
  "neovim/nvim-lspconfig",
  opts = {
    -- Global LazyVim LSP option, not a vtsls one: disabled due to an nvim 0.12.4
    -- bug (invalid col in inlay_hint.lua:362) — re-enable in a future version.
    inlay_hints = { enabled = false },
    servers = {
      vtsls = {
        settings = {
          vtsls = {
            -- Use the workspace's own TypeScript (same as VS Code's typescript.tsdk)
            autoUseWorkspaceTsdk = true,
          },
        },
      },
    },
  },
}
