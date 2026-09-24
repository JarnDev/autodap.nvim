-- The Neovim config the end-to-end check runs against: a brand new config whose
-- only plugins are nvim-dap and autodap, installed exactly the way the README
-- tells a user to install them. Nothing from the developer's own config leaks in
-- — scripts/e2e.sh points XDG_CONFIG_HOME/XDG_DATA_HOME at a throwaway directory.
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    'git', 'clone', '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git', '--branch=stable', lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  {
    'JarnDev/autodap.nvim',
    dir = assert(vim.env.AUTODAP_DIR, 'AUTODAP_DIR must point at the plugin checkout'),
    dependencies = { 'mfussenegger/nvim-dap' },
    config = function()
      require('autodap').setup()
      vim.keymap.set('n', '<F5>', function() require('autodap').continue() end)
    end,
  },
}, { install = { missing = true }, change_detection = { enabled = false } })
