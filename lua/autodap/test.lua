-- Debug the test under the cursor: framework detection, nearest-test extraction,
-- and dap config generation for jest / vitest / pytest.
local M = {}
local util = require('autodap.util')

-- ---- file classification ----------------------------------------------------

local function is_js_test_file(name)
  return name:match('%.test%.[jt]sx?$') ~= nil
    or name:match('%.spec%.[jt]sx?$') ~= nil
    or name:match('/__tests__/') ~= nil
end

local function is_py_test_file(name)
  local base = vim.fn.fnamemodify(name, ':t')
  return base:match('^test_.*%.py$') ~= nil or base:match('_test%.py$') ~= nil
end

-- ---- node module resolution (hoist-aware) -----------------------------------

local function resolve_node_module(root, rel)
  local mods = vim.fs.find('node_modules', {
    path = root,
    upward = true,
    type = 'directory',
    limit = math.huge,
  })
  for _, nm in ipairs(mods) do
    local p = nm .. '/' .. rel
    if util.is_file(p) then
      return p
    end
  end
  return nil
end

-- ---- framework detection ----------------------------------------------------

local function has_dep(pkg, dep)
  if type(pkg) ~= 'table' then
    return false
  end
  for _, field in ipairs({ 'devDependencies', 'dependencies' }) do
    if type(pkg[field]) == 'table' and pkg[field][dep] then
      return true
    end
  end
  return false
end

local function has_config(root, patterns)
  for _, p in ipairs(patterns) do
    if #vim.fn.glob(root .. '/' .. p, false, true) > 0 then
      return true
    end
  end
  return false
end

-- Returns 'jest' | 'vitest' | 'pytest' | nil. For JS, the installed module
-- (resolved upward, so hoisted workspaces count) is the most reliable signal,
-- then package.json deps, then a config file.
function M.framework(bufnr, root)
  bufnr = bufnr or 0
  local ft = vim.bo[bufnr].filetype
  local name = vim.api.nvim_buf_get_name(bufnr)

  if ft == 'python' then
    return is_py_test_file(name) and 'pytest' or nil
  end

  if ft:match('^javascript') or ft:match('^typescript') then
    if not is_js_test_file(name) then
      return nil
    end
    local pkg = util.read_json(root .. '/package.json')
    if resolve_node_module(root, 'vitest/vitest.mjs')
      or has_dep(pkg, 'vitest')
      or has_config(root, { 'vitest.config.*', 'vitest.workspace.*' })
    then
      return 'vitest'
    end
    if resolve_node_module(root, 'jest/bin/jest.js')
      or has_dep(pkg, 'jest')
      or has_config(root, { 'jest.config.*' })
    then
      return 'jest'
    end
    return nil
  end

  return nil
end

-- ---- nearest test extraction ------------------------------------------------

-- Nearest it()/test()/describe() above the cursor. Regex-based (no Treesitter
-- dependency); handles modifiers like it.only / test.each.
local function js_nearest(bufnr, cursor_row)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, cursor_row, false)
  for i = #lines, 1, -1 do
    local line = lines[i]
    for _, kw in ipairs({ 'it', 'test', 'describe' }) do
      local title = line:match('%f[%a]' .. kw .. "[%.%w]*%s*%(%s*['\"`]([^'\"`]+)")
      if title then
        return { title = title, kind = kw == 'describe' and 'suite' or 'test' }
      end
    end
  end
  return nil
end

-- Nearest `def test_*` above the cursor and its enclosing `class Test*`, as the
-- pytest node-id suffix `<Class>::<func>` (class omitted for module-level tests).
local function py_nearest(bufnr, cursor_row)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, cursor_row, false)
  local func_i, func, func_indent
  for i = #lines, 1, -1 do
    local indent, name = lines[i]:match('^(%s*)def%s+(test[%w_]*)')
    if name then
      func_i, func, func_indent = i, name, #indent
      break
    end
  end
  if not func then
    return nil
  end
  local cls
  for i = func_i - 1, 1, -1 do
    local indent, name = lines[i]:match('^(%s*)class%s+([%w_]+)')
    if name and #indent < func_indent then
      cls = name
      break
    end
  end
  return { suffix = (cls and (cls .. '::') or '') .. func }
end

-- ---- config building --------------------------------------------------------

-- jest's and vitest's -t is a regex; a title with (), [], ., etc. must be escaped
-- so it matches literally.
local function js_regex_escape(s)
  return (s:gsub('[%^%$%(%)%[%]%{%}%.%*%+%?%|%\\]', '\\%0'))
end

local function extra_args(fw)
  local ok, autodap = pcall(require, 'autodap')
  if not ok then
    return {}
  end
  local t = autodap.config and autodap.config.test
  return (t and t.extra_args and t.extra_args[fw]) or {}
end

-- Cursor row of the window showing `bufnr`. "Under the cursor" only means
-- something for a displayed buffer, so a hidden buffer yields no test config.
local function cursor_row_for(bufnr)
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return nil
  end
  return vim.api.nvim_win_get_cursor(win)[1]
end

-- Build a dap config for the test under the cursor, or nil if there is none.
function M.config(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local detect = require('autodap.detect')
  local file = vim.api.nvim_buf_get_name(bufnr)
  local ft = vim.bo[bufnr].filetype
  local cursor_row = cursor_row_for(bufnr)
  if not cursor_row then
    return nil
  end

  if ft == 'python' then
    if not is_py_test_file(file) then
      return nil
    end
    local near = py_nearest(bufnr, cursor_row)
    if not near then
      return nil
    end
    local root = detect.lang_root('python', vim.fs.dirname(file))
    local args = { util.relpath(root, file) .. '::' .. near.suffix }
    vim.list_extend(args, extra_args('pytest'))
    return {
      type = 'python',
      request = 'launch',
      name = 'Debug test: ' .. near.suffix,
      module = 'pytest',
      args = args,
      cwd = root,
      pythonPath = require('autodap.adapters.python').resolve_python(root, require('autodap').config),
      console = 'integratedTerminal',
      justMyCode = false,
    }
  end

  if ft:match('^javascript') or ft:match('^typescript') then
    local root = detect.lang_root('node', vim.fs.dirname(file))
    local fw = M.framework(bufnr, root)
    if not fw then
      return nil
    end
    local near = js_nearest(bufnr, cursor_row)
    if not near then
      return nil
    end
    local label = (near.kind == 'suite' and 'Debug suite: ' or 'Debug test: ') .. near.title
    local pattern = js_regex_escape(near.title)
    if fw == 'jest' then
      local args = { file, '-t', pattern, '--runInBand' }
      vim.list_extend(args, extra_args('jest'))
      return {
        type = 'pwa-node',
        request = 'launch',
        name = label,
        program = resolve_node_module(root, 'jest/bin/jest.js')
          or (root .. '/node_modules/jest/bin/jest.js'),
        args = args,
        cwd = root,
        console = 'integratedTerminal',
        sourceMaps = true,
        skipFiles = { '<node_internals>/**' },
      }
    end
    -- vitest
    local args = { 'run', file, '-t', pattern }
    vim.list_extend(args, extra_args('vitest'))
    return {
      type = 'pwa-node',
      request = 'launch',
      name = label,
      program = resolve_node_module(root, 'vitest/vitest.mjs')
        or (root .. '/node_modules/vitest/vitest.mjs'),
      args = args,
      cwd = root,
      console = 'integratedTerminal',
      sourceMaps = true,
      skipFiles = { '<node_internals>/**' },
    }
  end

  return nil
end

return M
