-- `:checkhealth autodap` — verifies the environment and shows what autodap
-- detects for the current buffer (language, project root, adapter, targets).
local M = {}

local H = vim.health

local function check_core()
  H.start('autodap: core')

  if vim.fn.has('nvim-0.10') == 1 then
    H.ok('Neovim ' .. tostring(vim.version()))
  else
    H.error('Neovim >= 0.10 is required')
  end

  if pcall(require, 'dap') then
    H.ok('nvim-dap is installed')
  else
    H.error('nvim-dap not found', { 'Install mfussenegger/nvim-dap' })
  end

  if pcall(require, 'mason-registry') then
    H.ok('mason.nvim is available (adapters can be auto-installed)')
  else
    H.warn('mason.nvim not found — adapters must be on your PATH', {
      'Install williamboman/mason.nvim, or set auto_install = false',
    })
  end
end

local function check_adapters()
  local ok, autodap = pcall(require, 'autodap')
  if not ok then
    return
  end
  local install = require('autodap.install')
  H.start('autodap: adapters')
  for _, lang in ipairs(autodap.config.languages or {}) do
    local path = install.bin_path(lang)
    if not autodap.owns(lang) then
      H.ok(('%s: adapter registered outside autodap — left untouched'):format(lang))
    elseif path then
      H.ok(('%s: %s'):format(lang, path))
    elseif autodap.config.auto_install and pcall(require, 'mason-registry') then
      H.warn(('%s: adapter not found (installs on first use)'):format(lang), {
        install.install_hint(lang),
      })
    else
      H.warn(('%s: adapter not found and it will not be installed'):format(lang), {
        install.install_hint(lang),
      })
    end
  end
end

-- Lexicographic comparison of two rank tuples, highest key first.
local function outranks(a, b)
  for i = 1, #a do
    if a[i] ~= b[i] then
      return a[i] > b[i]
    end
  end
  return false
end

-- `:checkhealth` runs with its own scratch buffer focused, so "the current
-- buffer" has to mean the file you were last editing, not the report itself.
--
-- `lastused` is only accurate to the second, so opening a file and running
-- `:checkhealth` straight away leaves the new buffer tied with the one before
-- it, and comparing with `>` then keeps whichever the buffer list yielded
-- first — the report describes the file you just left. Rank candidates on a
-- total order instead, highest first:
--
--   1. still displayed in a window: you cannot edit a buffer without entering
--      it, so a visible file beats a hidden one a tie made look as recent;
--   2. `lastused`, the real signal whenever the seconds do differ;
--   3. the buffer number, which only grows, so the file opened last wins the
--      remaining ties.
--
-- Exported because the tie is what `:checkhealth` actually hits, and the tests
-- pin it.
function M.subject_buf()
  local cur = vim.api.nvim_get_current_buf()
  if vim.bo[cur].buftype == '' and vim.api.nvim_buf_get_name(cur) ~= '' then
    return cur
  end
  local best, best_rank
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if info.name ~= '' and vim.bo[info.bufnr].buftype == '' then
      local rank = { #(info.windows or {}) > 0 and 1 or 0, info.lastused, info.bufnr }
      if not best_rank or outranks(rank, best_rank) then
        best, best_rank = info.bufnr, rank
      end
    end
  end
  return best
end

local function check_buffer()
  H.start('autodap: current buffer')
  local bufnr = M.subject_buf()
  local ok, detect = pcall(require, 'autodap.detect')
  if not ok then
    return
  end
  if not bufnr then
    H.info('no file open — open a source file and run this again')
    return
  end
  H.info(('buffer: %s'):format(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':~:.')))
  local lang, ft = detect.lang_for_buf(bufnr)
  if not lang then
    H.info(('filetype %q is not handled by autodap'):format(ft or ''))
    return
  end
  local file = vim.api.nvim_buf_get_name(bufnr)
  local root = detect.lang_root(lang, file ~= '' and vim.fs.dirname(file) or nil)
  H.info(('language: %s'):format(lang))
  H.info(('project root: %s'):format(root))

  if lang == 'cpp' then
    local targets = require('autodap.adapters.cpp').find_targets(root, require('autodap').config)
    if #targets > 0 then
      local names = {}
      for _, t in ipairs(targets) do
        names[#names + 1] = t.name
      end
      H.ok(('%d executable target(s): %s'):format(#targets, table.concat(names, ', ')))
    else
      H.info('no prebuilt targets found (a lone file is compiled on launch)')
    end
  end

  local tcfg = require('autodap.test').config(bufnr)
  if tcfg then
    H.ok('test under cursor: ' .. tcfg.name)
  end
end

function M.check()
  check_core()
  check_adapters()
  check_buffer()
end

return M
