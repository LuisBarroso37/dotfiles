-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Vertical scroll and center
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

-- Find and center
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- Registers: paste/delete without clobbering the yank register
-- Paste over a visual selection while keeping what you originally yanked
vim.keymap.set("x", "<leader>p", [["_dP]])
-- Delete to the black hole register (delete without saving to a register)
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]])

-- Yank relative path to system clipboard
vim.keymap.set("n", "<leader>yp", function()
  vim.fn.setreg("+", vim.fn.expand("%"))
end, { desc = "Yank relative path" })

-- Yank absolute path
vim.keymap.set("n", "<leader>yP", function()
  vim.fn.setreg("+", vim.fn.expand("%:p"))
end, { desc = "Yank absolute path" })
