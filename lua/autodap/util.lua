local M = {}

function M.read_json(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local data = f:read('*a')
  f:close()
  if not data or data == '' then return nil end
  local ok, decoded = pcall(vim.json.decode, data)
  if ok then return decoded end
  return nil
end

function M.is_file(path)
  return vim.fn.filereadable(path) == 1
end

function M.is_dir(path)
  return vim.fn.isdirectory(path) == 1
end

-- Expand a list of directory patterns (globs allowed) under `root` into the
-- set of directories that actually exist. Keeps large-project build layouts
-- like `cmake-build-*` and `out/build/*` working without hardcoding a name.
function M.expand_dirs(root, patterns)
  local out = {}
  for _, p in ipairs(patterns) do
    for _, hit in ipairs(vim.fn.glob(root .. '/' .. p, false, true)) do
      if M.is_dir(hit) then
        out[#out + 1] = hit
      end
    end
  end
  return out
end

return M
