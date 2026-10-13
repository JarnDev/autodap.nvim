-- Remembers which file buffer you were last in, so `:checkhealth autodap` can
-- report on the file you came from rather than on its own report buffer.
--
-- Nothing Vim already records answers that question:
--
--   * `lastused` has whole-second granularity, so opening a file and running
--     `:checkhealth` straight away leaves the two newest buffers tied;
--   * the alternate file (`#`) is overwritten by the next `:edit` in the same
--     window, so after `:checkhealth`, `:tabclose`, `:edit other` it points at
--     the file you left, not the one you are in;
--   * the buffer number only says which buffer was created first.
--
-- So keep the one fact that does answer it: the order in which real file
-- buffers were last entered. A `BufEnter` autocmd stamps a monotonic ordinal
-- on each one and the health check picks the highest. The ordinal lives in a
-- buffer variable, so a wiped buffer takes its ordinal with it and there is no
-- table to keep in sync.
local M = {}

local VAR = 'autodap_focus'
local seq = 0

-- Only real files are candidates: the report buffer itself, and every other
-- `nofile`/unnamed scratch buffer, must never win.
local function trackable(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == ''
    and vim.api.nvim_buf_get_name(buf) ~= ''
end

local function stamp(buf)
  if not trackable(buf) then
    return
  end
  seq = seq + 1
  vim.b[buf][VAR] = seq
end

-- The entry ordinal of `buf`, or 0 for a buffer that has not been entered
-- since autodap loaded — which sorts below every stamped buffer.
function M.ordinal(buf)
  local ok, value = pcall(function()
    return vim.b[buf][VAR]
  end)
  return (ok and type(value) == 'number') and value or 0
end

function M.track()
  vim.api.nvim_create_autocmd('BufEnter', {
    group = vim.api.nvim_create_augroup('autodap_focus', { clear = true }),
    desc = 'autodap: remember which file buffer you were last in',
    callback = function(args)
      stamp(args.buf)
    end,
  })
  -- Lazy-loaded, autodap missed the `BufEnter` for the file that is already
  -- open, and that file is the likeliest subject of the next `:checkhealth`.
  stamp(vim.api.nvim_get_current_buf())
end

return M
