local M = {}
local install = require('autodap.install')
local util = require('autodap.util')

-- The adapter function we installed, so a second setup() can tell its own
-- registration apart from one the user made.
local ours

-- Lazy (function-form) adapter: resolves the binary at launch time, so a
-- mason install that finishes after startup is used without a restart.
-- Returns true when autodap owns the adapter, false when we left an existing
-- one alone.
function M.register(dap, _)
  -- Don't clobber an adapter the user (or mason-nvim-dap) already registered.
  local current = dap.adapters['pwa-node']
  if current ~= nil and current ~= ours then
    return false
  end
  ours = function(cb)
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
  dap.adapters['pwa-node'] = ours
  return true
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

-- Node >= 22.18 (and every 23.6+) runs erasable-syntax TypeScript natively by
-- replacing types with whitespace, so lines and columns stay put and
-- breakpoints bind without source maps. Used only when there's no tsx/ts-node.
local node_version_cache
function M.node_version()
  if node_version_cache == nil then
    node_version_cache = false
    local ok, res = pcall(function()
      return vim.system({ 'node', '--version' }, { text = true }):wait(2000)
    end)
    if ok and res and res.code == 0 then
      local major, minor = (res.stdout or ''):match('^v(%d+)%.(%d+)')
      if major then
        node_version_cache = { tonumber(major), tonumber(minor) }
      end
    end
  end
  return node_version_cache or nil
end

local function node_strips_types()
  local v = M.node_version()
  if not v then
    return false
  end
  local major, minor = v[1], v[2]
  return major > 23 or (major == 23 and minor >= 6) or (major == 22 and minor >= 18)
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
    elseif not node_strips_types() then
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
