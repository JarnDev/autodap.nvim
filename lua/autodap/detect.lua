local M = {}

-- Nearest-first markers per language. In a monorepo the closest package.json /
-- pyproject / CMakeLists is the unit you actually want to debug, not the repo
-- root, so detection walks up and stops at the first hit.
local lang_root_markers = {
  node   = { 'package.json' },
  python = { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile' },
  cpp    = { 'compile_commands.json', 'CMakeLists.txt', 'meson.build', 'Makefile' },
}

local repo_markers = { '.git', '.hg', '.svn' }

local ft_to_lang = {
  javascript = 'node',
  javascriptreact = 'node',
  ['javascript.jsx'] = 'node',
  typescript = 'node',
  typescriptreact = 'node',
  ['typescript.tsx'] = 'node',
  python = 'python',
  c = 'cpp',
  cpp = 'cpp',
  objc = 'cpp',
  objcpp = 'cpp',
  cuda = 'cpp',
}

function M.lang_for_buf(bufnr)
  bufnr = bufnr or 0
  local ft = vim.bo[bufnr].filetype
  return ft_to_lang[ft], ft
end

local function normalize_start(start)
  if not start or start == '' then
    start = vim.fn.expand('%:p:h')
  end
  if not start or start == '' then
    start = vim.uv.cwd()
  end
  return start
end

-- Nearest language-specific project root (monorepo-aware). Falls back to the
-- repository root, then to the starting directory.
function M.lang_root(lang, start)
  start = normalize_start(start)
  local markers = lang_root_markers[lang]
  if markers then
    local hit = vim.fs.find(markers, { path = start, upward = true })[1]
    if hit then
      return vim.fs.dirname(hit)
    end
  end
  local repo = vim.fs.find(repo_markers, { path = start, upward = true })[1]
  if repo then
    return vim.fs.dirname(repo)
  end
  return start
end

function M.repo_root(start)
  start = normalize_start(start)
  local repo = vim.fs.find(repo_markers, { path = start, upward = true })[1]
  return repo and vim.fs.dirname(repo) or start
end

return M
