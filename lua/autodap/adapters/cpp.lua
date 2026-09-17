local M = {}
local install = require('autodap.install')
local util = require('autodap.util')

-- Remembered executable per project root, so the second launch does not
-- re-prompt. Cleared by :AutodapReset.
local last_program = {}

function M.reset()
  last_program = {}
end

function M.register(dap, _)
  if dap.adapters.codelldb ~= nil then
    return
  end
  dap.adapters.codelldb = function(cb)
    cb({
      type = 'server',
      port = '${port}',
      executable = {
        command = install.bin_path('cpp') or 'codelldb',
        args = { '--port', '${port}' },
      },
    })
  end
end

-- Extensions that are never a debuggable target (libraries, objects, build junk).
local BAD_EXT = {
  so = true, dylib = true, dll = true, a = true, lib = true,
  o = true, obj = true, d = true, ninja = true, cmake = true,
  json = true, txt = true, make = true, log = true, tmp = true,
}

local function looks_like_lib(name)
  if name:match('%.so%.%d') then
    return true
  end
  local ext = name:match('%.([%w]+)$')
  return ext ~= nil and BAD_EXT[ext:lower()] == true
end

-- Fast, exact path for large CMake projects: read the CMake File API reply and
-- pull every EXECUTABLE target with its real artifact path and name. No
-- filesystem crawling, and it survives huge build trees.
local function cmake_targets(build_dirs)
  local out = {}
  for _, bd in ipairs(build_dirs) do
    local reply = bd .. '/.cmake/api/v1/reply'
    if util.is_dir(reply) then
      for _, tf in ipairs(vim.fn.glob(reply .. '/target-*.json', false, true)) do
        local t = util.read_json(tf)
        if t and t.type == 'EXECUTABLE' and type(t.artifacts) == 'table' then
          for _, a in ipairs(t.artifacts) do
            local p = a.path
            if p and not p:match('^/') then
              p = bd .. '/' .. p
            end
            if p and util.is_file(p) then
              out[#out + 1] = { name = t.name or vim.fn.fnamemodify(p, ':t'), path = p }
            end
          end
        end
      end
    end
  end
  return out
end

-- Fallback when there is no File API reply: bounded scan of the build dirs,
-- skipping CMake internals / fetched deps and anything that looks like a library.
local function scan_targets(build_dirs)
  local out = {}
  for _, bd in ipairs(build_dirs) do
    local found = vim.fs.find(function(name, path)
      if #out >= 100 then
        return false
      end
      local full = path .. '/' .. name
      if full:match('/CMakeFiles/') or full:match('/_deps/') or full:match('/Testing/') then
        return false
      end
      if looks_like_lib(name) then
        return false
      end
      return vim.fn.executable(full) == 1
    end, { path = bd, type = 'file', limit = 100 })
    for _, f in ipairs(found) do
      out[#out + 1] = { name = vim.fn.fnamemodify(f, ':t'), path = f }
    end
  end
  return out
end

function M.find_targets(root, cfg)
  local patterns = (cfg and cfg.cpp and cfg.cpp.build_dirs)
    or { 'build', 'cmake-build-*', 'out/build/*', 'builddir', 'out' }
  local dirs = util.expand_dirs(root, patterns)
  local exes = cmake_targets(dirs)
  if #exes == 0 then
    exes = scan_targets(dirs)
  end
  return exes
end

local function compiler_for(ft, cfg)
  local override = cfg and cfg.cpp and cfg.cpp.compiler
  if override and vim.fn.executable(override) == 1 then
    return override
  end
  local list = ft == 'cpp' and { 'c++', 'g++', 'clang++' } or { 'cc', 'gcc', 'clang' }
  for _, c in ipairs(list) do
    if vim.fn.executable(c) == 1 then
      return c
    end
  end
  return nil
end

local function cache_dir()
  local d = vim.fn.stdpath('cache') .. '/autodap'
  vim.fn.mkdir(d, 'p')
  return d
end

-- Compile a single translation unit with debug info so a lone .c/.cpp is
-- debuggable without any build system. Returns the binary path, or nil on
-- failure (missing compiler / compile error, both reported to the user).
function M.compile_single(src, ft, cfg)
  if ft ~= 'c' and ft ~= 'cpp' then
    return nil
  end
  if not src or src == '' or vim.fn.filereadable(src) ~= 1 then
    return nil
  end
  local cc = compiler_for(ft, cfg)
  if not cc then
    vim.notify('[autodap] no C/C++ compiler found on PATH', vim.log.levels.WARN)
    return nil
  end
  local flags = (cfg and cfg.cpp and cfg.cpp.compile_flags) or { '-g', '-O0' }
  local out = ('%s/%s-%s'):format(cache_dir(), vim.fn.fnamemodify(src, ':t:r'), vim.fn.sha256(src):sub(1, 8))
  local cmd = { cc }
  vim.list_extend(cmd, flags)
  vim.list_extend(cmd, { src, '-o', out })
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify('[autodap] compile failed:\n' .. result, vim.log.levels.ERROR)
    return nil
  end
  return out
end

local function pick_program(root, cfg, src, ft)
  return function()
    local cached = last_program[root]
    if cached and vim.fn.executable(cached) == 1 then
      return cached
    end
    local exes = M.find_targets(root, cfg)
    if #exes == 0 then
      -- No build system: compile the current single file on the fly. Not cached,
      -- so every launch rebuilds and picks up your edits.
      local auto = not (cfg and cfg.cpp and cfg.cpp.auto_compile == false)
      if auto and (ft == 'c' or ft == 'cpp') then
        local bin = M.compile_single(src, ft, cfg)
        if bin then
          return bin
        end
      end
      local chosen = vim.fn.input('Path to executable: ', root .. '/', 'file')
      last_program[root] = chosen
      return chosen
    elseif #exes == 1 then
      last_program[root] = exes[1].path
      return exes[1].path
    end
    local items = { 'Select target:' }
    for i, e in ipairs(exes) do
      items[i + 1] = ('%d: %s  (%s)'):format(i, e.name, vim.fn.fnamemodify(e.path, ':~:.'))
    end
    local choice = vim.fn.inputlist(items)
    local sel = (exes[choice] and exes[choice].path) or exes[1].path
    last_program[root] = sel
    return sel
  end
end

function M.configs(root, cfg, bufnr)
  local src = bufnr and vim.api.nvim_buf_get_name(bufnr) or ''
  local ft = bufnr and vim.bo[bufnr].filetype or ''
  local program = pick_program(root, cfg, src, ft)
  return {
    {
      type = 'codelldb',
      request = 'launch',
      name = 'Launch target',
      program = program,
      cwd = root,
      stopOnEntry = false,
      args = {},
    },
    {
      type = 'codelldb',
      request = 'launch',
      name = 'Launch target (with args)',
      program = program,
      cwd = root,
      stopOnEntry = false,
      args = function()
        return vim.split(vim.fn.input('Args: '), ' ', { trimempty = true })
      end,
    },
  }
end

return M
