return {
  {
    "nvim-mini/mini.surround",
    opts = {
      mappings = {
        add = "sa",
        delete = "sd",
        find = "sf",
        find_left = "sF",
        highlight = "sh",
        replace = "sr",
        update_n_lines = "sn",
      },
    },
  },
  -- LazyVim unconditionally registers `gs` as the which-key surround group
  -- (from its own editor.lua). Since all surround ops are remapped to `s`
  -- prefix above, `gs` is an empty ghost group in which-key. Fix: remove it
  -- and label `s` instead so the popup is useful.
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      -- Remove LazyVim's gs surround group
      table.insert(opts.spec, { "gs", hidden = true })
      -- Label our s prefix
      table.insert(opts.spec, { "s", group = "surround", mode = { "n", "x", "o" } })
    end,
  },
}
