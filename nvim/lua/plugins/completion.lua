-- Accepting a completion inserts the identifier and nothing else — no `()`, no
-- argument placeholders to tab through.
--
-- This lives in one file rather than in each language's plugin spec because it's
-- a single preference, but it has to be asserted in several places: the behaviour
-- comes from two independent sources, and the second one has no general switch.
--
--   1. The *client* (blink.cmp) appending brackets after the identifier.
--   2. Each *language server* returning a snippet with the call already written
--      out and tabstops over the arguments. LSP has no capability for this, so
--      every server spells it differently — and LazyVim's language extras turn
--      it on for each of them.
--
-- The only truly cross-language lever is telling every server we don't support
-- snippets at all (`snippetSupport = false` in the client capabilities), but that
-- also throws away legitimate snippet completions, so it's deliberately not used.
return {
  {
    "saghen/blink.cmp",
    opts = {
      completion = {
        accept = {
          -- Client-side `()` insertion. Applies to every filetype.
          auto_brackets = { enabled = false },
        },
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- TypeScript / JavaScript. LazyVim's typescript extra enables both of
        -- these; vtsls has no combined key, and these two are its whole scope.
        vtsls = {
          settings = {
            -- Not in vtsls' configuration schema (LazyVim sets it to true and
            -- nothing reads it) — mirrored here only so a future vtsls that does
            -- honour it doesn't silently re-enable the behaviour.
            complete_function_calls = false,
            typescript = { suggest = { completeFunctionCalls = false } },
            javascript = { suggest = { completeFunctionCalls = false } },
          },
        },
        -- Go. LazyVim's go extra sets usePlaceholders = true.
        gopls = {
          settings = {
            gopls = { usePlaceholders = false },
          },
        },
      },
    },
  },

  {
    -- Rust. rust-analyzer's own default is "fill_arguments"; "none" inserts the
    -- bare name ("add_parentheses" would still append `()`).
    "mrcjkb/rustaceanvim",
    opts = {
      server = {
        default_settings = {
          ["rust-analyzer"] = {
            completion = { callable = { snippets = "none" } },
          },
        },
      },
    },
  },
}
