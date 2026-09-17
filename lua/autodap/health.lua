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
    local mason = install.registry[lang] and install.registry[lang].mason
    if path then
      H.ok(('%s: %s'):format(lang, path))
    else
      H.warn(('%s: adapter not found (installs on first use)'):format(lang), {
        mason and (':MasonInstall ' .. mason) or nil,
      })
    end
  end
end

local function check_buffer()
  H.start('autodap: current buffer')
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, detect = pcall(require, 'autodap.detect')
  if not ok then
    return
  end
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
