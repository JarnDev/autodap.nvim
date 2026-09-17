local M = {}
local detect = require('autodap.detect')

M.defaults = {
  -- Lazy / on-demand: the adapter for a language is installed via mason the
  -- first time you actually debug that language, not at startup — this keeps the
  -- machine lean (mirrors mason-lspconfig's `automatic_installation`). Requires
  -- mason.nvim; without it, autodap uses whatever adapter is already on PATH.
  auto_install = true,
  languages = { 'node', 'python', 'cpp' },
  python = { venv = 'auto' },
  cpp = {
    adapter = 'codelldb',
    build_dirs = nil,
    auto_compile = true, -- compile a lone .c/.cpp with -g when there is no build system
    compile_flags = { '-g', '-O0' },
  },
  -- Extra CLI args appended to the generated "debug the test under the cursor"
  -- command, per framework — an escape hatch for version-specific flags (e.g.
  -- vitest single-thread flags for reliable breakpoints).
  test = {
    extra_args = { jest = {}, vitest = {}, pytest = {} },
  },
}

M.config = vim.deepcopy(M.defaults)

local lang_modules = {
  node   = 'autodap.adapters.node',
  python = 'autodap.adapters.python',
  cpp    = 'autodap.adapters.cpp',
}

local function enabled(lang)
  for _, l in ipairs(M.config.languages) do
    if l == lang then
      return true
    end
  end
  return false
end

local function adapter_mod(lang)
  return require(lang_modules[lang])
end

-- Build debug configurations for the current buffer's language, rooted at the
-- nearest project (monorepo-aware). Returns {} for buffers we do not handle, so
-- the provider merges cleanly with other config sources.
function M.configs_for_buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lang = detect.lang_for_buf(bufnr)
  if not lang or not enabled(lang) then
    return {}
  end
  local start = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
  local root = detect.lang_root(lang, start)
  -- Pure: no install side effects here. dap.continue() calls providers on every
  -- run; the friendly M.continue() owns adapter installation.
  local configs = adapter_mod(lang).configs(root, M.config, bufnr)
  -- Surface a "Debug test under cursor" entry at the top when the buffer is a
  -- test file, so it shows up in the same picker as the launch configs.
  local tcfg = require('autodap.test').config(bufnr)
  if tcfg then
    table.insert(configs, 1, tcfg)
  end
  return configs
end

local function register_adapters(dap)
  for _, lang in ipairs(M.config.languages) do
    adapter_mod(lang).register(dap, M.config)
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  local ok, dap = pcall(require, 'dap')
  if not ok then
    vim.notify('[autodap] nvim-dap not found; autodap disabled', vim.log.levels.ERROR)
    return
  end
  register_adapters(dap)
  -- Register as a config provider rather than filling dap.configurations, so we
  -- compose with launch.json and any user-defined configs instead of clobbering.
  dap.providers.configs['autodap'] = function(bufnr)
    return M.configs_for_buf(bufnr)
  end
end

-- Friendly entrypoint — map this to your debug key (e.g. <F5>). Unlike a bare
-- dap.continue(), it checks the adapter exists first and kicks off a mason
-- install instead of throwing a DAP stack trace on a fresh machine.
function M.continue()
  local ok, dap = pcall(require, 'dap')
  if not ok then
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local lang = detect.lang_for_buf(bufnr)
  if lang and enabled(lang) then
    local install = require('autodap.install')
    if not install.available(lang) then
      install.ensure(lang, M.config)
      vim.notify(
        ('[autodap] installing the %s debug adapter — run again once it finishes.'):format(lang),
        vim.log.levels.INFO
      )
      return
    end
  end
  dap.continue()
end

-- Debug the test under the cursor directly (jest / vitest / pytest), bypassing
-- the config picker. Map this to e.g. <leader>dt.
function M.debug_test()
  local ok, dap = pcall(require, 'dap')
  if not ok then
    return
  end
  local cfg = require('autodap.test').config()
  if not cfg then
    vim.notify('[autodap] no test found under the cursor', vim.log.levels.INFO)
    return
  end
  local lang = cfg.type == 'python' and 'python' or 'node'
  local install = require('autodap.install')
  if not install.available(lang) then
    install.ensure(lang, M.config)
    vim.notify(
      ('[autodap] installing the %s debug adapter — run again once it finishes.'):format(lang),
      vim.log.levels.INFO
    )
    return
  end
  dap.run(cfg)
end

return M
