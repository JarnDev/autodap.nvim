if vim.g.loaded_autodap then
  return
end
vim.g.loaded_autodap = 1

vim.api.nvim_create_user_command('AutodapContinue', function()
  require('autodap').continue()
end, { desc = 'autodap: configure the current project and start/continue debugging' })

vim.api.nvim_create_user_command('AutodapReset', function()
  if package.loaded['autodap.adapters.cpp'] then
    require('autodap.adapters.cpp').reset()
  end
  vim.notify('[autodap] cleared remembered executable choices', vim.log.levels.INFO)
end, { desc = 'autodap: forget the remembered C/C++ executable for the current project' })
