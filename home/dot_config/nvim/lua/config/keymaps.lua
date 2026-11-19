-- Vertical scroll and center
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

-- Find and center
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- Preserve the yank register when replacing or deleting text.
vim.keymap.set("x", "<leader>p", [["_dP]], { desc = "Paste over selection (keep yank)" })
-- This intentionally takes LazyVim's debug prefix.
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]], { desc = "Delete to black hole register" })

-- Override LazyVim's git log mapping after its default keymaps load.
vim.keymap.set("n", "<leader>gL", "<cmd>.DiffviewFileHistory --follow<cr>", { desc = "History: current line" })

-- Yank relative path to system clipboard
vim.keymap.set("n", "<leader>yp", function()
  vim.fn.setreg("+", vim.fn.expand("%:."))
end, { desc = "Yank relative path" })

-- Yank absolute path
vim.keymap.set("n", "<leader>yP", function()
  vim.fn.setreg("+", vim.fn.expand("%:p"))
end, { desc = "Yank absolute path" })
