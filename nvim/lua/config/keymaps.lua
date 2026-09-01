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
vim.keymap.set("x", "<leader>p", [["_dP]], { desc = "Paste over selection (keep yank)" })
-- Delete to the black hole register (delete without saving to a register)
-- Deliberately shadows LazyVim's `debug` which-key group: nothing here uses DAP, and
-- the only maps under it are the profiler's <leader>dpp / <leader>dph, which still
-- work if typed inside `timeoutlen` (300ms).
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]], { desc = "Delete to black hole register" })

-- <leader>gL: LazyVim's config/keymaps.lua sets this to Snacks git_log (cwd) with a
-- raw vim.keymap.set. lazyvim.config.keymaps is loaded before config.keymaps, so
-- re-setting it here simply wins. DiffviewFileHistory is in diffview's `cmd` list,
-- so the command stub still lazy-loads the plugin on first press.
vim.keymap.set("n", "<leader>gL", "<cmd>.DiffviewFileHistory --follow<cr>", { desc = "History: current line" })

-- Yank relative path to system clipboard
vim.keymap.set("n", "<leader>yp", function()
  vim.fn.setreg("+", vim.fn.expand("%:."))
end, { desc = "Yank relative path" })

-- Yank absolute path
vim.keymap.set("n", "<leader>yP", function()
  vim.fn.setreg("+", vim.fn.expand("%:p"))
end, { desc = "Yank absolute path" })
