return {
  "akinsho/bufferline.nvim",
  init = function()
    local function update_tabline()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if
          vim.bo[buf].buflisted
          and vim.bo[buf].buftype == ""
          and (vim.api.nvim_buf_get_name(buf) ~= "" or vim.bo[buf].modified)
        then
          vim.o.showtabline = 2
          return
        end
      end
      vim.o.showtabline = 0
    end

    vim.api.nvim_create_autocmd({ "BufEnter", "BufAdd", "BufDelete", "BufFilePost", "BufModifiedSet" }, {
      group = vim.api.nvim_create_augroup("BufferlineVisibility", { clear = true }),
      callback = function()
        vim.schedule(update_tabline)
      end,
    })
    update_tabline()
  end,
  opts = {
    options = {
      always_show_bufferline = true,
      auto_toggle_bufferline = false,
    },
  },
}
