-- Both native smooth scrolling and snacks.scroll interfere with <C-d>zz / <C-u>zz centering.
vim.opt.smoothscroll = false

-- Keep project-specific configuration in local files. Neovim requires trust before loading them.
vim.o.exrc = true
