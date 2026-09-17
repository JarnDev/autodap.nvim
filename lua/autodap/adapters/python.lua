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

-- Resolve the interpreter the debuggee should run under. Precedence, most
-- explicit first: an interpreter/venv pinned via `python.venv` in setup(), then
-- an active VIRTUAL_ENV, then the nearest virtualenv walking up (monorepo root
-- `.venv` included), then system python3. Exposed for the test runner to reuse.
local function resolve_python(root, cfg)
  local pinned = cfg and cfg.python and cfg.python.venv
  if type(pinned) == 'string' and pinned ~= '' and pinned ~= 'auto' then
    if vim.fn.executable(pinned) == 1 then
      return pinned -- a direct interpreter path
    end
    local py = pinned .. '/bin/python'
    if vim.fn.executable(py) == 1 then
      return py -- a venv directory
    end
    vim.notify(
      '[autodap] python.venv set to ' .. pinned .. ' but no interpreter found there',
      vim.log.levels.WARN
    )
  end

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

M.resolve_python = resolve_python

function M.configs(root, cfg, _)
  local py = resolve_python(root, cfg)
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
