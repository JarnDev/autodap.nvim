-- Config-generation tests. These do not start a live debug session (impossible
-- headless); they assert that the right configurations are produced for real
-- project layouts, which is the whole value of the plugin.

local autodap = require('autodap')
autodap.setup({ auto_install = false })

local failures = 0
local function check(name, cond, detail)
  if cond then
    print('  ok   - ' .. name)
  else
    failures = failures + 1
    print('  FAIL - ' .. name .. (detail and ('  :: ' .. tostring(detail)) or ''))
  end
end

local function has(configs, needle)
  for _, c in ipairs(configs) do
    if c.name:find(needle, 1, true) then
      return c
    end
  end
  return nil
end

local function names(configs)
  local t = {}
  for _, c in ipairs(configs) do
    t[#t + 1] = c.name
  end
  return table.concat(t, ', ')
end

local function target_names(list)
  local t = {}
  for _, e in ipairs(list) do
    t[#t + 1] = e.name
  end
  return t
end

local fx = vim.uv.cwd() .. '/tests/fixtures'

-- NODE: a TS file deep inside a monorepo workspace package.
print('[node monorepo]')
vim.cmd.edit(fx .. '/node-monorepo/packages/app/src/index.ts')
vim.bo.filetype = 'typescript'
local ncfg = autodap.configs_for_buf(0)
check('script "dev" discovered', has(ncfg, 'npm run dev') ~= nil, names(ncfg))
check('script "build" discovered', has(ncfg, 'npm run build') ~= nil, names(ncfg))
check('launch current file present', has(ncfg, 'Launch current file') ~= nil, names(ncfg))
check('attach present', has(ncfg, 'Attach to process') ~= nil, names(ncfg))
local dev = has(ncfg, 'npm run dev')
check(
  'cwd is the nearest package, not the repo root',
  dev ~= nil and dev.cwd:find('packages/app', 1, true) ~= nil,
  dev and dev.cwd
)
local nlaunch = has(ncfg, 'Launch current file')
check(
  'TS runtime resolves to hoisted root node_modules/.bin/tsx',
  nlaunch ~= nil and tostring(nlaunch.runtimeExecutable):find('node_modules/.bin/tsx', 1, true) ~= nil,
  nlaunch and nlaunch.runtimeExecutable
)

-- PYTHON: interpreter resolves to the project virtualenv.
print('[python]')
vim.cmd.edit(fx .. '/python/src/main.py')
vim.bo.filetype = 'python'
local pcfg = autodap.configs_for_buf(0)
local launch = has(pcfg, 'Launch current file')
check('launch present', launch ~= nil, names(pcfg))
check(
  'venv interpreter resolved',
  launch ~= nil and launch.pythonPath:find('.venv/bin/python', 1, true) ~= nil,
  launch and launch.pythonPath
)

-- PYTHON monorepo: package with no local venv resolves to the single root venv.
print('[python monorepo]')
vim.cmd.edit(fx .. '/python-monorepo/packages/svc/main.py')
vim.bo.filetype = 'python'
local pmono = has(autodap.configs_for_buf(0), 'Launch current file')
check(
  'root venv resolved from a nested package',
  pmono ~= nil
    and pmono.pythonPath:find('python%-monorepo/%.venv/bin/python') ~= nil
    and pmono.pythonPath:find('packages/svc', 1, true) == nil,
  pmono and pmono.pythonPath
)

-- CPP: CMake File API reply gives named executable targets, libraries excluded.
print('[cpp / cmake file api]')
local cpp = require('autodap.adapters.cpp')
local t1 = target_names(cpp.find_targets(fx .. '/cpp', autodap.config))
check('executable target "app" found', vim.tbl_contains(t1, 'app'), table.concat(t1, ', '))
check('shared library not a target', not vim.tbl_contains(t1, 'libfoo.so'), table.concat(t1, ', '))

-- CPP: no File API -> bounded scan, still excludes .so and CMakeFiles/.
print('[cpp / scan fallback]')
local t2 = target_names(cpp.find_targets(fx .. '/cpp-noapi', autodap.config))
check('scan finds executable "app"', vim.tbl_contains(t2, 'app'), table.concat(t2, ', '))
check('scan excludes libfoo.so', not vim.tbl_contains(t2, 'libfoo.so'), table.concat(t2, ', '))
check('scan skips CMakeFiles/ decoy', not vim.tbl_contains(t2, 'decoy'), table.concat(t2, ', '))

-- CPP single-file auto-compile: a lone .c with no build system compiles with -g
-- and becomes debuggable. Runs the real compiler; skips if none is installed.
print('[cpp / single-file auto-compile]')
if vim.fn.executable('cc') == 1 or vim.fn.executable('gcc') == 1 or vim.fn.executable('clang') == 1 then
  local ctmp = vim.fn.tempname()
  vim.fn.mkdir(ctmp, 'p')
  local csrc = ctmp .. '/lone.c'
  vim.fn.writefile({ 'int main(void){return 0;}' }, csrc)
  local bin = cpp.compile_single(csrc, 'c', autodap.config)
  check('lone .c compiles to a binary', bin ~= nil and vim.fn.filereadable(bin) == 1, bin)
  check('compiled binary is executable', bin ~= nil and vim.fn.executable(bin) == 1, bin)
  local broken = ctmp .. '/broken.c'
  vim.fn.writefile({ 'int main(void){ return nope; }' }, broken)
  check('compile error returns nil (no crash)', cpp.compile_single(broken, 'c', autodap.config) == nil)
else
  print('  skip - no C compiler on PATH')
end

-- SINGLE FILE: a loose file with no project markers at all still debugs — the
-- large-project focus is additive, never a gate on the basic launch config.
print('[single file / no project]')
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({ 'print(1)' }, tmp .. '/lone.py')
vim.cmd.edit(tmp .. '/lone.py')
vim.bo.filetype = 'python'
local single = autodap.configs_for_buf(0)
local sl = has(single, 'Launch current file')
check('loose python file still has a launch config', sl ~= nil, names(single))
check('cwd falls back to the file directory', sl ~= nil and sl.cwd == tmp, sl and sl.cwd)
check(
  'no venv -> system interpreter (no crash)',
  sl ~= nil and sl.pythonPath:find('.venv', 1, true) == nil,
  sl and sl.pythonPath
)

-- COMPOSABILITY: the pitch is that we register as a provider + lazy adapters
-- that resolve fresh, rather than clobbering the user's setup.
print('[composability]')
local dap = require('dap')
check('registered as a dap config provider', type(dap.providers.configs.autodap) == 'function')
check('python adapter is lazy (function form)', type(dap.adapters.python) == 'function')
check('node adapter is lazy (function form)', type(dap.adapters['pwa-node']) == 'function')
local shape
dap.adapters.python(function(a) shape = a end, {})
check('python adapter resolves an executable table', shape ~= nil and shape.type == 'executable', shape and shape.type)

print(('\n%d failure(s)'):format(failures))
if failures > 0 then
  vim.cmd('cquit 1')
else
  vim.cmd('quitall!')
end
