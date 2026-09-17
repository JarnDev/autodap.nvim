local M = {}
local install = require('autodap.install')

function M.register(dap, _)
  if dap.adapters.python ~= nil then
    return
  end
  dap.adapters.python = function(cb)
    cb({
      type = 'executable',
      command = install.bin_path('python') or 'debugpy-adapter',
    })
  end
end

-- Resolve the interpreter the debuggee should run under. An active VIRTUAL_ENV
-- wins; otherwise the nearest virtualenv walking up (so a package inside a
-- monorepo with a single root `.venv` still finds it); otherwise system python3.
local function resolve_python(root)
  local venv = vim.env.VIRTUAL_ENV
  if venv and venv ~= '' and vim.fn.executable(venv .. '/bin/python') == 1 then
    return venv .. '/bin/python'
  end
  local found = vim.fs.find({ '.venv', 'venv', 'env' }, {
    path = root,
    upward = true,
    type = 'directory',
    limit = math.huge,
  })
  for _, d in ipairs(found) do
    local py = d .. '/bin/python'
    if vim.fn.executable(py) == 1 then
      return py
    end
  end
  local sys = vim.fn.exepath('python3')
  return sys ~= '' and sys or 'python'
end

function M.configs(root, _, _)
  local py = resolve_python(root)
  return {
    {
      type = 'python',
      request = 'launch',
      name = 'Launch current file',
      program = '${file}',
      cwd = root,
      pythonPath = py,
      console = 'integratedTerminal',
      justMyCode = true,
    },
    {
      type = 'python',
      request = 'launch',
      name = 'Launch current file (with args)',
      program = '${file}',
      cwd = root,
      pythonPath = py,
      console = 'integratedTerminal',
      justMyCode = true,
      args = function()
        return vim.split(vim.fn.input('Args: '), ' ', { trimempty = true })
      end,
    },
    {
      type = 'python',
      request = 'attach',
      name = 'Attach (localhost:5678)',
      connect = { host = '127.0.0.1', port = 5678 },
    },
  }
end

return M
