return {
  "neovim/nvim-lspconfig",
  opts = {
    -- disabled due to nvim 0.12.4 bug (invalid col in inlay_hint.lua:362) — re-enable in future versions
    inlay_hints = { enabled = false },
    servers = {
      vtsls = {
        -- Give the TS server the same memory headroom VS Code does
        cmd_env = {
          NODE_OPTIONS = "--max-old-space-size=8192",
        },
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
