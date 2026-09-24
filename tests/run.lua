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

-- CPP compile_flags.txt: the nearest one above the file feeds the single-file
-- build (here -std=c++20 for std::span and a relative -I resolved from its dir).
print('[cpp / compile_flags.txt]')
if vim.fn.executable('c++') == 1 or vim.fn.executable('g++') == 1 or vim.fn.executable('clang++') == 1 then
  local ptmp = vim.fn.tempname()
  vim.fn.mkdir(ptmp .. '/inc', 'p')
  vim.fn.mkdir(ptmp .. '/src', 'p')
  vim.fn.writefile({ '-std=c++20', '', '# comment', '-Iinc' }, ptmp .. '/compile_flags.txt')
  vim.fn.writefile({ '#include <span>', 'inline int first(std::span<const int> v) { return v[0]; }' }, ptmp .. '/inc/lib.hpp')
  vim.fn.writefile({ '#include "lib.hpp"', 'int main() { int a[] = {7}; return first(a) == 7 ? 0 : 1; }' }, ptmp .. '/src/main.cpp')
  local flags, dir = cpp.project_flags(ptmp .. '/src/main.cpp')
  check('compile_flags.txt found upward and parsed', dir == ptmp and vim.deep_equal(flags, { '-std=c++20', '-Iinc' }), vim.inspect(flags))
  local pbin = cpp.compile_single(ptmp .. '/src/main.cpp', 'cpp', autodap.config)
  check('C++20 file with relative -I compiles via compile_flags.txt', pbin ~= nil and vim.fn.executable(pbin) == 1, pbin)
  check('no compile_flags.txt -> no extra flags', #cpp.project_flags(vim.fn.tempname() .. '/x.cpp') == 0)
else
  print('  skip - no C++ compiler on PATH')
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

-- TEST UNDER CURSOR: framework detection + nearest-test extraction + config.
local testmod = require('autodap.test')

print('[test / jest]')
vim.cmd.edit(fx .. '/jest-proj/sum.test.js')
vim.bo.filetype = 'javascript'
vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- inside it('adds numbers')
local jt = testmod.config(0)
check('jest: nearest test captured', jt ~= nil and jt.name:find('adds numbers', 1, true) ~= nil, jt and jt.name)
check('jest: program is jest/bin/jest.js', jt ~= nil and tostring(jt.program):find('jest/bin/jest.js', 1, true) ~= nil, jt and jt.program)
check(
  'jest: args carry -t <title> and --runInBand',
  jt ~= nil and vim.tbl_contains(jt.args, '-t') and vim.tbl_contains(jt.args, '--runInBand')
    and jt.args[3]:find('adds numbers', 1, true) ~= nil,
  jt and table.concat(jt.args, ' ')
)

vim.cmd.edit(fx .. '/jest-proj/paren.test.js')
vim.bo.filetype = 'javascript'
vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- inside it('adds (two) numbers')
local jp = testmod.config(0)
check(
  'jest: -t title is regex-escaped',
  jp ~= nil and vim.tbl_contains(jp.args, 'adds \\(two\\) numbers'),
  jp and table.concat(jp.args, ' ')
)

print('[test / vitest]')
vim.cmd.edit(fx .. '/vitest-proj/sum.test.ts')
vim.bo.filetype = 'typescript'
vim.api.nvim_win_set_cursor(0, { 4, 0 }) -- inside test('multiplies')
local vt = testmod.config(0)
check('vitest: detected over jest', vt ~= nil and vt.name:find('multiplies', 1, true) ~= nil, vt and vt.name)
check('vitest: program is vitest.mjs', vt ~= nil and tostring(vt.program):find('vitest/vitest.mjs', 1, true) ~= nil, vt and vt.program)
check('vitest: args start with run', vt ~= nil and vt.args[1] == 'run' and vim.tbl_contains(vt.args, 'multiplies'), vt and table.concat(vt.args, ' '))

print('[test / pytest]')
vim.cmd.edit(fx .. '/pytest-proj/tests/test_math.py')
vim.bo.filetype = 'python'
vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- inside TestMath.test_add
local pt = testmod.config(0)
check('pytest: module is pytest', pt ~= nil and pt.module == 'pytest', pt and pt.module)
check(
  'pytest: node id is relative file::Class::func',
  pt ~= nil and pt.args[1] == 'tests/test_math.py::TestMath::test_add',
  pt and pt.args[1]
)
check('pytest: interpreter from project venv', pt ~= nil and pt.pythonPath:find('.venv/bin/python', 1, true) ~= nil, pt and pt.pythonPath)

-- :checkhealth opens its own tabpage, so the buffer it asks about lives in a
-- window somewhere else. The nearest test must still be found from there.
print('[test / buffer in another tabpage]')
vim.cmd.edit(fx .. '/pytest-proj/tests/test_math.py')
vim.bo.filetype = 'python'
vim.api.nvim_win_set_cursor(0, { 3, 0 })
local other_tab_buf = vim.api.nvim_get_current_buf()
vim.cmd('tabnew')
local tt = testmod.config(other_tab_buf)
check(
  'test under cursor found from a different tabpage',
  tt ~= nil and tt.args[1] == 'tests/test_math.py::TestMath::test_add',
  tt and tt.args[1]
)
vim.cmd('tabclose')

print('[test / non-test file]')
vim.cmd.edit(fx .. '/node-monorepo/packages/app/src/index.ts')
vim.bo.filetype = 'typescript'
check('a non-test file yields no test config', testmod.config(0) == nil)

-- NEAREST-TEST RESOLUTION VIA TREESITTER. The regex scanner reads one line at a
-- time, so it cannot see nesting, decorators, or where a title actually ends.
-- These are the cases that only come out right when the file is parsed.
-- `vim.treesitter.language.add` reports success for a language it never found,
-- so the only honest probe is to ask for a parser the way autodap does.
local function parser_installed(lang)
  local buf = vim.api.nvim_create_buf(false, true)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, lang, { error = false })
  vim.api.nvim_buf_delete(buf, { force = true })
  return ok and parser ~= nil
end

local have_parsers = true
for _, l in ipairs({ 'python', 'javascript', 'typescript' }) do
  have_parsers = have_parsers and parser_installed(l)
end

-- `-t` is a regex the runner applies to the full test name, so assert on what it
-- matches rather than on its spelling. Vim's \v magic is close enough to a JS
-- RegExp for these patterns.
local function matches(pattern, name)
  return vim.fn.match(name, '\\v' .. pattern) >= 0
end

local function arg_after(cfg, flag)
  for i, a in ipairs(cfg.args or {}) do
    if a == flag then
      return cfg.args[i + 1]
    end
  end
  return nil
end

if not have_parsers then
  print('[test / treesitter]')
  if vim.env.AUTODAP_REQUIRE_TREESITTER ~= nil and vim.env.AUTODAP_REQUIRE_TREESITTER ~= '' then
    check('treesitter parsers are available (AUTODAP_REQUIRE_TREESITTER is set)', false)
  else
    print('  skip - no treesitter parsers built (see tests/minimal_init.lua)')
  end
else
  print('[test / treesitter :: python]')
  vim.cmd.edit(fx .. '/pytest-proj/tests/test_nested.py')
  vim.bo.filetype = 'python'

  check('python: resolver reports treesitter', testmod.resolver(0) == 'treesitter', testmod.resolver(0))

  -- The cursor is on the @pytest.mark.parametrize line. The decorator is part of
  -- the test, but it sits *above* `def`, so the regex scanner finds nothing.
  vim.api.nvim_win_set_cursor(0, { 6, 0 })
  local dec = testmod.config(0)
  check(
    'pytest: cursor on a decorator resolves to the test it decorates',
    dec ~= nil and dec.args[1] == 'tests/test_nested.py::TestOuter::TestInner::test_param',
    dec and dec.args[1]
  )

  -- Nested classes: the node id needs every enclosing Test* class, not just the
  -- innermost one the indentation heuristic stops at.
  vim.api.nvim_win_set_cursor(0, { 12, 0 })
  local nested = testmod.config(0)
  check(
    'pytest: nested classes give the full Outer::Inner::test node id',
    nested ~= nil and nested.args[1] == 'tests/test_nested.py::TestOuter::TestInner::test_param',
    nested and nested.args[1]
  )

  -- Line 10 is inside `def test_helper()`, a plain closure. pytest does not
  -- collect it, so the answer is still the enclosing test.
  vim.api.nvim_win_set_cursor(0, { 10, 0 })
  local inner = testmod.config(0)
  check(
    'pytest: a def nested inside a test is not itself a test',
    inner ~= nil and inner.args[1] == 'tests/test_nested.py::TestOuter::TestInner::test_param',
    inner and inner.args[1]
  )

  vim.api.nvim_win_set_cursor(0, { 15, 0 })
  local sibling = testmod.config(0)
  check(
    'pytest: a sibling method takes only its own enclosing class',
    sibling ~= nil and sibling.args[1] == 'tests/test_nested.py::TestOuter::test_outer_only',
    sibling and sibling.args[1]
  )

  vim.api.nvim_win_set_cursor(0, { 19, 0 })
  local modlevel = testmod.config(0)
  check(
    'pytest: a module-level test carries no class',
    modlevel ~= nil and modlevel.args[1] == 'tests/test_nested.py::test_module_level',
    modlevel and modlevel.args[1]
  )

  print('[test / treesitter :: node]')
  vim.cmd.edit(fx .. '/jest-proj/nested.test.js')
  vim.bo.filetype = 'javascript'

  check('node: resolver reports treesitter', testmod.resolver(0) == 'treesitter', testmod.resolver(0))

  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  local deep = testmod.config(0)
  local deep_t = deep and arg_after(deep, '-t')
  check(
    'jest: nested describes are part of the -t pattern',
    deep_t ~= nil and matches(deep_t, 'outer suite > inner suite > adds (two) numbers'),
    deep_t
  )
  check(
    'jest: the -t pattern does not match a same-named test in another suite',
    deep_t ~= nil and not matches(deep_t, 'somewhere else > adds (two) numbers'),
    deep_t
  )
  check('jest: the label shows the whole path', deep ~= nil and deep.name == 'Debug test: outer suite > inner suite > adds (two) numbers', deep and deep.name)

  -- it.each interpolates the row into the title; `%i` never reaches the name the
  -- runner reports, so matching it literally would match nothing at all.
  vim.api.nvim_win_set_cursor(0, { 8, 0 })
  local each_t = arg_after(testmod.config(0) or {}, '-t')
  check(
    'jest: it.each placeholders become wildcards',
    each_t ~= nil and matches(each_t, 'outer suite > inner suite > adds 1 and 2')
      and matches(each_t, 'outer suite > inner suite > adds 3 and 4'),
    each_t
  )

  -- Same for a template literal: `${...}` is only known at runtime.
  vim.api.nvim_win_set_cursor(0, { 12, 0 })
  local tpl_t = arg_after(testmod.config(0) or {}, '-t')
  check(
    'jest: template substitutions become wildcards',
    tpl_t ~= nil and matches(tpl_t, 'outer suite > inner suite > interpolates x in the title'),
    tpl_t
  )

  -- Between the tests, still inside the outer describe: the answer is that
  -- suite, not whichever test happens to sit above the cursor.
  vim.api.nvim_win_set_cursor(0, { 16, 0 })
  local suite = testmod.config(0)
  check(
    'jest: a cursor outside every it() resolves to the enclosing suite',
    suite ~= nil and suite.name == 'Debug suite: outer suite',
    suite and suite.name
  )

  vim.cmd.edit(fx .. '/vitest-proj/sum.test.ts')
  vim.bo.filetype = 'typescript'
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  local vts = testmod.config(0)
  check(
    'vitest: typescript is resolved with treesitter too',
    testmod.resolver(0) == 'treesitter' and vts ~= nil and vim.tbl_contains(vts.args, 'multiplies'),
    vts and table.concat(vts.args, ' ')
  )
end

-- THE FALLBACK. autodap must not require nvim-treesitter, so with no parser for
-- the buffer the regex scanner has to keep answering. Stubbing get_parser is
-- what a machine without the parser installed actually looks like from here.
print('[test / regex fallback without a parser]')
local real_get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function()
  error('no parser for this buffer')
end
local ok_fallback, fallback_err = pcall(function()
  vim.cmd.edit(fx .. '/jest-proj/sum.test.js')
  vim.bo.filetype = 'javascript'
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  check('resolver reports the regex fallback', testmod.resolver(0) == 'regex', testmod.resolver(0))
  local fb = testmod.config(0)
  check(
    'jest still resolves the nearest test without a parser',
    fb ~= nil and arg_after(fb, '-t') == 'adds numbers',
    fb and table.concat(fb.args, ' ')
  )

  vim.cmd.edit(fx .. '/pytest-proj/tests/test_math.py')
  vim.bo.filetype = 'python'
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  local fp = testmod.config(0)
  check(
    'pytest still resolves the nearest test without a parser',
    fp ~= nil and fp.args[1] == 'tests/test_math.py::TestMath::test_add',
    fp and fp.args[1]
  )
end)
vim.treesitter.get_parser = real_get_parser
check('the fallback path raised nothing', ok_fallback, fallback_err)

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

-- UI: with config.ui = 'auto' and nvim-dap-ui installed, autodap registers
-- listeners that open the UI on launch/attach. It must NOT auto-close on
-- terminate/exit — the UI stays up for post-run inspection.
-- nvim-dap-ui is not a test dependency, so we stub it via package.loaded.
print('[ui / nvim-dap-ui auto-open]')
local dapui_calls = { open = 0, close = 0 }
package.loaded.dapui = {
  open = function() dapui_calls.open = dapui_calls.open + 1 end,
  close = function() dapui_calls.close = dapui_calls.close + 1 end,
}
for _, when in ipairs({ 'launch', 'attach', 'event_terminated', 'event_exited' }) do
  dap.listeners.before[when].autodap_ui = nil
end
autodap.setup({ auto_install = false, ui = 'auto' })
check('ui=auto registers an open listener on launch', type(dap.listeners.before.launch.autodap_ui) == 'function')
check('ui=auto registers an open listener on attach', type(dap.listeners.before.attach.autodap_ui) == 'function')
check('ui=auto does NOT register a close on terminate', dap.listeners.before.event_terminated.autodap_ui == nil)
check('ui=auto does NOT register a close on exit', dap.listeners.before.event_exited.autodap_ui == nil)
dap.listeners.before.launch.autodap_ui({}, {})
check('launch listener opens the UI', dapui_calls.open == 1, dapui_calls.open)
check('the UI is never auto-closed', dapui_calls.close == 0, dapui_calls.close)

-- Opt-out: ui = false registers nothing, even with nvim-dap-ui present.
for _, when in ipairs({ 'launch', 'attach', 'event_terminated', 'event_exited' }) do
  dap.listeners.before[when].autodap_ui = nil
end
autodap.setup({ auto_install = false, ui = false })
check('ui=false registers no UI listeners', dap.listeners.before.launch.autodap_ui == nil)
package.loaded.dapui = nil

-- An adapter the user registered first is left alone, and autodap knows it is
-- not ours — the install guard must not block a session on a binary we would
-- never launch.
local mine = function(cb) cb({ type = 'executable', command = 'my-own-debugpy' }) end
dap.adapters.python = mine
autodap.setup({ auto_install = false })
check('a pre-existing adapter is not clobbered', dap.adapters.python == mine)
check('autodap reports it does not own that adapter', autodap.owns('python') == false)
check('autodap still owns the ones it registered', autodap.owns('cpp') == true)
dap.adapters.python = nil
autodap.setup({ auto_install = false })
check('autodap owns the adapter again once the user drops theirs', autodap.owns('python') == true)

-- The install guard's three outcomes. 'installing' is the only one that should
-- ever tell the user to run again; with auto_install off nothing is installing,
-- so the message has to be actionable instead.
print('[install guard]')
local install = require('autodap.install')
check(
  'auto_install = false reports unavailable, not installing',
  install.ensure('python', { auto_install = false }) == 'unavailable'
    or install.available('python'), -- adapter present on this machine: nothing to report
  install.ensure('python', { auto_install = false })
)
check(
  'missing mason reports unavailable rather than a phantom install',
  install.ensure('python', { auto_install = true }) == 'unavailable' or install.available('python'),
  install.ensure('python', { auto_install = true })
)
check(
  'hint names both the mason package and the binary',
  install.install_hint('python'):find('debugpy', 1, true) ~= nil
    and install.install_hint('python'):find('debugpy-adapter', 1, true) ~= nil,
  install.install_hint('python')
)

print(('\n%d failure(s)'):format(failures))
if failures > 0 then
  vim.cmd('cquit 1')
else
  vim.cmd('quitall!')
end
