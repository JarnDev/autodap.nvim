local M = {}
local install = require('autodap.install')
local util = require('autodap.util')

-- Lazy (function-form) adapter: resolves the binary at launch time, so a
-- mason install that finishes after startup is used without a restart.
function M.register(dap, _)
  -- Don't clobber an adapter the user (or mason-nvim-dap) already registered.
  if dap.adapters['pwa-node'] ~= nil then
    return
  end
  dap.adapters['pwa-node'] = function(cb)
    cb({
      type = 'server',
      host = 'localhost',
      port = '${port}',
      executable = {
        command = install.bin_path('node') or 'js-debug-adapter',
        args = { '${port}' },
      },
    })
  end
end

-- Resolve tsx/ts-node walking `node_modules` upward — hoisted workspaces
-- (pnpm/yarn/npm) keep a single `.bin` at the workspace root, not in each package.
local function ts_runtime(root)
  local mods = vim.fs.find('node_modules', {
    path = root,
    upward = true,
    type = 'directory',
    limit = math.huge,
  })
  for _, nm in ipairs(mods) do
    for _, tool in ipairs({ 'tsx', 'ts-node' }) do
      local p = nm .. '/.bin/' .. tool
      if vim.fn.executable(p) == 1 then
        return p
      end
    end
  end
  for _, tool in ipairs({ 'tsx', 'ts-node' }) do
    if vim.fn.executable(tool) == 1 then
      return tool
    end
  end
  return nil
end

-- `root` is the nearest package.json directory (monorepo-aware), so scripts and
-- cwd belong to the workspace member the file lives in, not the repo root.
function M.configs(root, _, bufnr)
  local ft = vim.bo[bufnr].filetype
  local is_ts = ft == 'typescript' or ft == 'typescriptreact'
  local runtime, hint = 'node', ''
  if is_ts then
    local t = ts_runtime(root)
    if t then
      runtime = t
    else
      hint = ' (install tsx for TS)'
    end
  end

  local pkg_name = vim.fn.fnamemodify(root, ':t')
  local out = {
    {
      type = 'pwa-node',
      request = 'launch',
      name = 'Launch current file' .. hint,
      program = '${file}',
      cwd = root,
      runtimeExecutable = runtime,
      sourceMaps = true,
      console = 'integratedTerminal',
      skipFiles = { '<node_internals>/**' },
    },
  }

  local pkg = util.read_json(root .. '/package.json')
  if pkg and type(pkg.scripts) == 'table' then
    local names = {}
    for k in pairs(pkg.scripts) do
      names[#names + 1] = k
    end
    table.sort(names)
    for _, name in ipairs(names) do
      out[#out + 1] = {
        type = 'pwa-node',
        request = 'launch',
        name = ('npm run %s  [%s]'):format(name, pkg_name),
        runtimeExecutable = 'npm',
        runtimeArgs = { 'run', name },
        cwd = root,
        console = 'integratedTerminal',
        sourceMaps = true,
        skipFiles = { '<node_internals>/**' },
      }
    end
  end

  out[#out + 1] = {
    type = 'pwa-node',
    request = 'attach',
    name = 'Attach to process',
    processId = function()
      return require('dap.utils').pick_process()
    end,
    cwd = root,
    sourceMaps = true,
    skipFiles = { '<node_internals>/**' },
  }
  return out
end

return M
