local M = {}

-- lang -> mason package name + the executable it exposes on mason's bin dir.
M.registry = {
  node   = { mason = 'js-debug-adapter', bin = 'js-debug-adapter' },
  python = { mason = 'debugpy',          bin = 'debugpy-adapter' },
  cpp    = { mason = 'codelldb',         bin = 'codelldb' },
}

local function mason_root()
  local env = vim.env.MASON
  if env and env ~= '' then
    return env
  end
  local ok, settings = pcall(require, 'mason.settings')
  if ok and settings.current and settings.current.install_root_dir then
    return settings.current.install_root_dir
  end
  return vim.fn.stdpath('data') .. '/mason'
end

-- Resolved fresh on every call so an adapter installed *after* nvim started is
-- picked up without a restart. Adapters are registered in lazy function form so
-- they call this at launch time, not at setup time.
function M.bin_path(lang)
  local entry = M.registry[lang]
  if not entry then
    return nil
  end
  local mbin = mason_root() .. '/bin/' .. entry.bin
  if vim.fn.executable(mbin) == 1 then
    return mbin
  end
  local onpath = vim.fn.exepath(entry.bin)
  if onpath ~= '' then
    return onpath
  end
  return nil
end

function M.available(lang)
  return M.bin_path(lang) ~= nil
end

-- Best-effort, on-demand, non-blocking install through mason when the adapter is
-- missing. Returns true only when the adapter is already available right now; a
-- kicked-off install returns false so callers can tell the user to retry.
function M.ensure(lang, opts)
  if M.available(lang) then
    return true
  end
  if not (opts and opts.auto_install) then
    return false
  end
  local entry = M.registry[lang]
  if not entry then
    return false
  end
  local ok, reg = pcall(require, 'mason-registry')
  if not ok then
    vim.notify(
      ('[autodap] %s missing and mason is unavailable — install %s manually')
        :format(entry.bin, entry.mason),
      vim.log.levels.WARN
    )
    return false
  end
  local function do_install()
    if reg.is_installed(entry.mason) then
      return
    end
    local pkg = reg.get_package(entry.mason)
    vim.notify(('[autodap] installing %s via mason…'):format(entry.mason), vim.log.levels.INFO)
    pkg:install()
  end
  if reg.refresh then
    reg.refresh(do_install)
  else
    do_install()
  end
  return false
end

return M
