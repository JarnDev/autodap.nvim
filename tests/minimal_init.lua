-- Headless test bootstrap. Run from the repo root:
--   nvim --headless -u tests/minimal_init.lua -l tests/run.lua
-- Clones nvim-dap into tests/.deps on first run so the tests exercise the real
-- provider/adapter API rather than a mock.

local root = vim.uv.cwd()
local deps = root .. '/tests/.deps'
local dap_dir = deps .. '/nvim-dap'

if vim.fn.isdirectory(dap_dir) == 0 then
  vim.fn.mkdir(deps, 'p')
  io.stderr:write('[tests] cloning nvim-dap…\n')
  vim.fn.system({
    'git', 'clone', '--depth', '1',
    'https://github.com/mfussenegger/nvim-dap', dap_dir,
  })
end

vim.opt.runtimepath:append(root)
vim.opt.runtimepath:append(dap_dir)
