-- Headless test bootstrap. Run from the repo root:
--   nvim --headless -u tests/minimal_init.lua -l tests/run.lua
-- Clones nvim-dap into tests/.deps on first run so the tests exercise the real
-- provider/adapter API rather than a mock, and builds the treesitter parsers the
-- nearest-test tests need from pinned grammar sources.

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

-- Treesitter parsers for the nearest-test tests. Pinned, and deliberately built
-- here rather than pulled in via nvim-treesitter: the plugin does not depend on
-- nvim-treesitter, only on a parser being loadable, and that is exactly what the
-- tests should be asserting against. ABI 14, so any Neovim >= 0.10 can load them.
--
-- Without a C compiler or network the parsers are simply absent and the
-- treesitter cases report themselves as skipped — except under
-- AUTODAP_REQUIRE_TREESITTER (which CI sets), where a skip is a failure, so a
-- broken bootstrap cannot quietly stop testing the treesitter path.
local grammars = {
  { lang = 'python',     repo = 'tree-sitter-python',     tag = 'v0.23.6', src = 'src' },
  { lang = 'javascript', repo = 'tree-sitter-javascript', tag = 'v0.23.1', src = 'src' },
  { lang = 'typescript', repo = 'tree-sitter-typescript', tag = 'v0.23.2', src = 'typescript/src' },
}

local ts_dir = deps .. '/ts'

local function compiler()
  local candidates = { 'cc', 'gcc', 'clang' }
  if vim.env.CC and vim.env.CC ~= '' then
    table.insert(candidates, 1, vim.env.CC)
  end
  for _, c in ipairs(candidates) do
    if vim.fn.executable(c) == 1 then
      return c
    end
  end
  return nil
end

local function build_parsers()
  local cc = compiler()
  vim.fn.mkdir(ts_dir .. '/parser', 'p')
  for _, g in ipairs(grammars) do
    local so = ('%s/parser/%s.so'):format(ts_dir, g.lang)
    if vim.fn.filereadable(so) == 0 then
      if not cc then
        io.stderr:write('[tests] no C compiler — skipping treesitter parsers\n')
        return
      end
      local repo = deps .. '/' .. g.repo
      if vim.fn.isdirectory(repo) == 0 then
        io.stderr:write(('[tests] cloning %s %s…\n'):format(g.repo, g.tag))
        vim.fn.system({
          'git', 'clone', '--quiet', '--depth', '1', '--branch', g.tag,
          'https://github.com/tree-sitter/' .. g.repo, repo,
        })
        if vim.v.shell_error ~= 0 then
          return
        end
      end
      local src = repo .. '/' .. g.src
      local cmd = { cc, '-O1', '-shared', '-fPIC', '-I', src, src .. '/parser.c' }
      if vim.fn.filereadable(src .. '/scanner.c') == 1 then
        cmd[#cmd + 1] = src .. '/scanner.c'
      end
      vim.list_extend(cmd, { '-o', so })
      io.stderr:write(('[tests] building the %s parser…\n'):format(g.lang))
      vim.fn.system(cmd)
      if vim.v.shell_error ~= 0 then
        vim.fn.delete(so)
        return
      end
    end
  end
end

build_parsers()

vim.opt.runtimepath:append(root)
vim.opt.runtimepath:append(dap_dir)
vim.opt.runtimepath:append(ts_dir)
