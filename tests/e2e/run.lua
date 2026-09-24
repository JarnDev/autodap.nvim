-- End-to-end: real debug sessions, driven the way a user drives them.
--
-- Unlike tests/run.lua (which asserts on generated configurations), this starts
-- the real debug adapters from a clean Neovim config, hits a breakpoint in a
-- sample project, reads a variable out of the stopped frame and runs to
-- completion. Environment is prepared by scripts/e2e.sh, which passes the
-- project paths; a language whose adapter could not be prepared is skipped.

local failures = 0
local function check(name, cond, detail)
  if cond then
    print('  ok   - ' .. name)
  else
    failures = failures + 1
    print('  FAIL - ' .. name .. (detail and ('  :: ' .. tostring(detail)) or ''))
  end
end

local dap = require('dap')

-- Pick a configuration out of the <F5> picker by name, as the user would.
local function pick(name)
  vim.ui.select = function(items, _, on_choice)
    for _, item in ipairs(items) do
      if item.name == name then
        return on_choice(item)
      end
    end
    on_choice(items[1])
  end
end

-- Set a breakpoint on `line`, start debugging, and report where it stopped and
-- what `expression` evaluates to there.
local function debug_to_breakpoint(file, line, expression)
  -- The previous language's session is still closing down when its terminated
  -- event fires — js-debug in particular keeps a parent session around for a
  -- moment. dap.continue() with a session still attached resumes *that* one
  -- instead of launching ours, so wait it out and start from a clean slate.
  vim.wait(20000, function() return dap.session() == nil end, 50)
  dap.clear_breakpoints()

  vim.cmd.edit(file)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  dap.toggle_breakpoint()

  local terminated = false
  dap.listeners.after.event_terminated['e2e'] = function()
    terminated = true
  end

  require('autodap').continue()

  -- nvim-dap fills in current_frame asynchronously after the stopped event, so
  -- poll for a fully resolved stop rather than reading it inside a listener.
  vim.wait(120000, function()
    local s = dap.session()
    return s ~= nil and s.stopped_thread_id ~= nil and s.current_frame ~= nil
  end, 100)

  local frame = dap.session() and dap.session().current_frame
  local evaluated
  if frame then
    -- 'watch', not 'repl': codelldb reads repl input as an lldb command first,
    -- so a bare variable name comes back as "not a valid command".
    dap.session():request(
      'evaluate',
      { expression = expression, frameId = frame.id, context = 'watch' },
      function(err, resp)
        evaluated = err and ('error: ' .. tostring(err)) or (resp and resp.result)
      end
    )
    vim.wait(20000, function() return evaluated ~= nil end, 50)
  end

  if dap.session() then
    dap.session():request('continue', { threadId = dap.session().stopped_thread_id })
  end
  local ran_out = vim.wait(30000, function() return terminated end, 100)

  return { line = frame and frame.line, evaluated = evaluated, terminated = ran_out }
end

local function config_named(bufnr, name)
  for _, c in ipairs(require('autodap').configs_for_buf(bufnr)) do
    if c.name == name then
      return c
    end
  end
  return nil
end

local function config_names(bufnr)
  local t = {}
  for _, c in ipairs(require('autodap').configs_for_buf(bufnr)) do
    t[#t + 1] = c.name
  end
  return table.concat(t, ', ')
end

print('[e2e] clean config, real nvim-dap, real debug adapters')
check('autodap is registered as a dap config provider', type(dap.providers.configs.autodap) == 'function')

-- ---- python -----------------------------------------------------------------
local proj = assert(vim.env.E2E_PROJ, 'E2E_PROJ must point at the sample python project')
print('[e2e / python]')
vim.cmd.edit(proj .. '/src/main.py')
local pbuf = vim.api.nvim_get_current_buf()
check('the sample file is detected as python', vim.bo[pbuf].filetype == 'python', vim.bo[pbuf].filetype)

-- Nothing language-specific was configured: the configs come from the project.
local launch = config_named(pbuf, 'Launch current file')
check('a launch config exists with no user configuration', launch ~= nil, config_names(pbuf))
check('cwd is the project root', launch ~= nil and launch.cwd == proj, launch and launch.cwd)
check(
  'the interpreter is the project virtualenv',
  launch ~= nil and launch.pythonPath == proj .. '/.venv/bin/python',
  launch and launch.pythonPath
)

pick('Launch current file')
local py = debug_to_breakpoint(proj .. '/src/main.py', 2, 'a + b')
check('debugpy launched and stopped at the breakpoint', py.line == 2, 'line ' .. tostring(py.line))
check('locals are readable in the stopped frame', py.evaluated == '5', py.evaluated)
check('the program runs to completion after continue', py.terminated)

-- ---- node -------------------------------------------------------------------
local nproj = vim.env.E2E_NODE_PROJ
if nproj == nil or nproj == '' then
  print('[e2e / node]')
  print('  skip - js-debug-adapter unavailable')
else
  print('[e2e / node]')
  vim.cmd.edit(nproj .. '/src/index.js')
  local nbuf = vim.api.nvim_get_current_buf()
  check('npm scripts are discovered from package.json',
    config_named(nbuf, 'npm run start  [' .. vim.fn.fnamemodify(nproj, ':t') .. ']') ~= nil,
    config_names(nbuf))

  pick('Launch current file')
  local js = debug_to_breakpoint(nproj .. '/src/index.js', 2, 'a + b')
  check('js-debug launched and stopped at the breakpoint', js.line == 2, 'line ' .. tostring(js.line))
  check('locals are readable in the stopped frame', js.evaluated == '5', js.evaluated)
  check('the program runs to completion after continue', js.terminated)
end

-- ---- c / c++ ----------------------------------------------------------------
local cproj = vim.env.E2E_CPP_PROJ
print('[e2e / c++]')
if cproj == nil or cproj == '' then
  print('  skip - ' .. (vim.env.E2E_CPP_SKIP ~= '' and vim.env.E2E_CPP_SKIP or 'toolchain unavailable'))
else
  vim.cmd.edit(cproj .. '/src/main.cpp')
  local cbuf = vim.api.nvim_get_current_buf()
  check('the sample file is detected as c++', vim.bo[cbuf].filetype == 'cpp', vim.bo[cbuf].filetype)

  local target = config_named(cbuf, 'Launch target')
  check('a launch config exists with no user configuration', target ~= nil, config_names(cbuf))
  check('cwd is the project root', target ~= nil and target.cwd == cproj, target and target.cwd)
  -- `program` is resolved lazily by nvim-dap; calling it is what picks the
  -- executable out of the build tree, which is the part worth asserting.
  local program = target and type(target.program) == 'function' and target.program()
  check('the built executable is discovered in build/', program == cproj .. '/build/app', program)

  pick('Launch target')
  local cc = debug_to_breakpoint(cproj .. '/src/main.cpp', 5, 'total')
  check('codelldb launched and stopped at the breakpoint', cc.line == 5, 'line ' .. tostring(cc.line))
  check('locals are readable in the stopped frame', cc.evaluated == '5', cc.evaluated)
  check('the program runs to completion after continue', cc.terminated)

  -- A lone .c with no build system at all: autodap compiles it with -g itself.
  local lone = vim.env.E2E_CPP_LONE
  print('[e2e / lone c file]')
  vim.cmd.edit(lone .. '/hello.c')
  local lbuf = vim.api.nvim_get_current_buf()
  check('a launch config exists for a file with no project', config_named(lbuf, 'Launch target') ~= nil,
    config_names(lbuf))

  pick('Launch target')
  local lc = debug_to_breakpoint(lone .. '/hello.c', 5, 'total')
  check('autodap compiled the lone file and stopped at the breakpoint', lc.line == 5, 'line ' .. tostring(lc.line))
  check('locals are readable in the stopped frame', lc.evaluated == '5', lc.evaluated)
  check('the program runs to completion after continue', lc.terminated)
end

print(('\n%d failure(s)'):format(failures))
if failures > 0 then
  vim.cmd('cquit 1')
else
  vim.cmd('quitall!')
end
