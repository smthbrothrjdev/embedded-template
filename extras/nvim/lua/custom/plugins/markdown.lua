return {
  {
    'OXY2DEV/markview.nvim',
    ft = { 'markdown', 'markdown.mdx', 'rmd' },
    opts = {
      -- I recommend "manual toggle" so it behaves like an IDE preview pane.
      preview = { enable = false },
    },
    config = function(_, opts)
      require('markview').setup(opts)

      -- Toggle preview for current buffer
      vim.keymap.set('n', '<leader>mp', '<cmd>Markview toggle<CR>', { desc = '[M]arkdown [P]review (toggle)' })

      -- If you want a global on/off instead, markview also supports :Markview (no args) in some setups;
      -- but :Markview toggle is the explicit one documented.
    end,
  },
}
