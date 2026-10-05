-- Treesitter-based nearest-test resolution.
--
-- The regex scanner in autodap.test walks lines upward, which stops being right
-- as soon as a file nests: it cannot tell "the cursor is inside this test" from
-- "this test happens to be above the cursor", it loses the enclosing
-- describe/class chain, and it cannot see that a decorator belongs to the test
-- *below* it. Here we parse instead — the answer is the innermost test whose
-- range actually contains the cursor, plus everything that encloses it.
--
-- None of this is a dependency. When no parser is installed for the buffer's
-- language `nearest()` returns no language, and autodap.test falls back to the
-- regex scanner, so autodap keeps working without nvim-treesitter.
local M = {}

-- ---- queries ----------------------------------------------------------------

-- Every `<something>('title', ...)` call; which of them are tests is decided in
-- Lua from the callee, because the modifiers are open-ended (`it.only`,
-- `describe.each([...])`, ``test.each`table` ``, `it.concurrent.failing`, …) and
-- query predicates cannot express that.
local JS_QUERY = [[
  ; it('…', fn) / test('…', fn) / describe('…', fn)
  (call_expression
    function: (identifier) @fn
    arguments: (arguments . [(string) (template_string)] @title)) @call

  ; it.only('…', fn) / describe.skip('…', fn)
  (call_expression
    function: (member_expression) @fn
    arguments: (arguments . [(string) (template_string)] @title)) @call

  ; it.each([…])('…', fn) and it.each`table`('…', fn) — here the *callee* is
  ; itself the call that produced the test function.
  (call_expression
    function: (call_expression function: (member_expression) @fn)
    arguments: (arguments . [(string) (template_string)] @title)) @call
]]

-- Definitions; the `test*` / `Test*` naming convention pytest collects on is
-- applied in Lua, as is the rule that only module- and class-level definitions
-- are collectable at all.
local PY_QUERY = [[
  (function_definition name: (identifier) @name) @def
  (class_definition name: (identifier) @name) @def
]]

-- Treesitter language -> which of the two resolvers handles it.
local RESOLVER = {
  python = 'python',
  javascript = 'js',
  jsx = 'js',
  typescript = 'js',
  tsx = 'js',
}

-- ---- treesitter plumbing ----------------------------------------------------

local function parser_for(bufnr)
  -- get_parser throws on 0.10 and returns nil on 0.11+ when the parser is
  -- missing; `error = false` is ignored by the former. Cover both.
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, nil, { error = false })
  if not ok or not parser then
    return nil
  end
  return parser
end

-- 0.11 changed iter_matches to hand back a list of nodes per capture. Normalise
-- to capture name -> node so the rest of the file does not care.
local function captures_of(query, match)
  local caps = {}
  for id, node in pairs(match) do
    local name = query.captures[id]
    if name then
      caps[name] = (type(node) == 'table') and node[#node] or node
    end
  end
  return caps
end

local function each_match(bufnr, root, lang, src, fn)
  local ok, query = pcall(vim.treesitter.query.parse, lang, src)
  if not ok then
    return false
  end
  for _, match in query:iter_matches(root, bufnr, 0, -1) do
    fn(captures_of(query, match))
  end
  return true
end

-- ---- javascript / typescript ------------------------------------------------

local JS_SUITE = {
  describe = true, context = true, suite = true,
  xdescribe = true, fdescribe = true, ddescribe = true,
}
local JS_TEST = {
  it = true, test = true, specify = true, bench = true,
  xit = true, fit = true, iit = true, xtest = true,
}

local SIMPLE_ESCAPE = {
  n = '\n', t = '\t', r = '\r', f = '\f', v = '\v', b = '\b',
  ['\\'] = '\\', ["'"] = "'", ['"'] = '"', ['`'] = '`', ['$'] = '$', ['/'] = '/',
}

-- A title is a list of parts: literal text we can match exactly, and everything
-- else (a `${}` substitution, an `%s` placeholder) which can only be a wildcard.
local function add_part(parts, text, literal)
  local last = parts[#parts]
  if last and literal and last.literal then
    last.text = last.text .. text
  else
    parts[#parts + 1] = { text = text, literal = literal }
  end
end

local function js_title_parts(node, bufnr)
  local parts = {}
  for child in node:iter_children() do
    local ct = child:type()
    if ct == 'string_fragment' then
      add_part(parts, vim.treesitter.get_node_text(child, bufnr), true)
    elseif ct == 'escape_sequence' then
      local raw = vim.treesitter.get_node_text(child, bufnr)
      local simple = #raw == 2 and SIMPLE_ESCAPE[raw:sub(2, 2)] or nil
      -- `\u{1f600}` and friends: we would have to reimplement the language's
      -- own unescaping to know what the title really says, so treat it as
      -- unknown text rather than matching the source spelling literally.
      add_part(parts, simple or raw, simple ~= nil)
    elseif ct == 'template_substitution' then
      add_part(parts, vim.treesitter.get_node_text(child, bufnr), false)
    end
  end
  if #parts == 0 then
    parts[1] = { text = '', literal = true }
  end
  return parts
end

-- Turn every occurrence of `pattern` inside a literal part into a wildcard part.
local function split_literals(parts, pattern)
  local out = {}
  for _, p in ipairs(parts) do
    if not p.literal then
      out[#out + 1] = p
    else
      local s, i = p.text, 1
      while true do
        local a, b = s:find(pattern, i)
        if not a then
          break
        end
        if a > i then
          out[#out + 1] = { text = s:sub(i, a - 1), literal = true }
        end
        out[#out + 1] = { text = s:sub(a, b), literal = false }
        i = b + 1
      end
      if i <= #s then
        out[#out + 1] = { text = s:sub(i), literal = true }
      end
    end
  end
  return out
end

-- `it.each` interpolates the row into the title with printf specifiers
-- (`adds %i + %i`) or `$column` references; neither survives into the name the
-- runner reports, so they have to become wildcards too.
local function js_expand_each(parts)
  return split_literals(split_literals(parts, '%%[%%%a#]'), '%$[%a_][%w_%.]*')
end

local function js_matches(bufnr, root, lang)
  local out, seen = {}, {}
  local ran = each_match(bufnr, root, lang, JS_QUERY, function(caps)
    if not (caps.fn and caps.title and caps.call) then
      return
    end
    local callee = vim.treesitter.get_node_text(caps.fn, bufnr)
    local base = callee:match('^[%a_$][%w_$]*')
    local kind = base and (JS_SUITE[base] and 'suite' or (JS_TEST[base] and 'test' or nil))
    if not kind then
      return
    end
    local parts = js_title_parts(caps.title, bufnr)
    if callee:find('%f[%w]each%f[%W]') or callee:find('%f[%w]for%f[%W]') then
      parts = js_expand_each(parts)
    end
    -- One call_expression can satisfy more than one alternative of the query;
    -- keep the first answer so the ancestry map below has a single entry per node.
    local id = caps.call:id()
    if seen[id] then
      return
    end
    seen[id] = true
    local srow, scol, erow, ecol = caps.call:range()
    local text = {}
    for _, p in ipairs(parts) do
      text[#text + 1] = p.text
    end
    out[#out + 1] = {
      node = caps.call,
      srow = srow,
      scol = scol,
      erow = erow,
      ecol = ecol,
      kind = kind,
      parts = parts,
      text = table.concat(text),
    }
  end)
  return ran and out or nil
end

-- ---- python -----------------------------------------------------------------

-- pytest only collects definitions at module or class level; a `def test_helper`
-- nested inside another test is not a test, so the cursor being in it must
-- resolve to the enclosing one.
local function py_collectable(node)
  local p = node:parent()
  while p do
    local t = p:type()
    if t == 'function_definition' then
      return false
    end
    if t == 'class_definition' or t == 'module' then
      return true
    end
    p = p:parent()
  end
  return true
end

-- Decorators sit outside the definition node, so `@pytest.mark.parametrize(...)`
-- with the cursor on it is not "inside" the test unless we widen the range.
local function py_range(node)
  local p = node:parent()
  if p and p:type() == 'decorated_definition' then
    return p:range()
  end
  return node:range()
end

local function py_matches(bufnr, root, lang)
  local out = {}
  local ran = each_match(bufnr, root, lang, PY_QUERY, function(caps)
    if not (caps.name and caps.def) then
      return
    end
    local name = vim.treesitter.get_node_text(caps.name, bufnr)
    local is_class = caps.def:type() == 'class_definition'
    local wanted = is_class and name:match('^Test') or (not is_class and name:match('^test'))
    if not wanted or not py_collectable(caps.def) then
      return
    end
    local srow, scol, erow, ecol = py_range(caps.def)
    out[#out + 1] = {
      -- The definition node, not the widened decorated_definition: ancestry is
      -- walked from here and a decorator is never somebody's enclosing class.
      node = caps.def,
      srow = srow,
      scol = scol,
      erow = erow,
      ecol = ecol,
      kind = is_class and 'suite' or 'test',
      name = name,
    }
  end)
  return ran and out or nil
end

-- ---- selection --------------------------------------------------------------

local function before(r1, c1, r2, c2)
  return r1 < r2 or (r1 == r2 and c1 < c2)
end

-- Ranges are compared on (row, column), not row alone: two tests can share a
-- line (`it('a', fn); it('b', fn);`, a minified or prettier-collapsed file), and
-- a row-only test would call the first one an ancestor of the second and hand
-- the runner a filter matching neither. `col` may be nil, meaning "anywhere on
-- this row", for callers that only know a line number.
local function contains(m, row, col)
  if row < m.srow or row > m.erow then
    return false
  end
  if col == nil then
    return true
  end
  if row == m.srow and col < m.scol then
    return false
  end
  -- The end column from `range()` is exclusive.
  if row == m.erow and col >= m.ecol then
    return false
  end
  return true
end

local function starts_at_or_before(m, row, col)
  if col == nil then
    return m.srow <= row
  end
  return not before(row, col, m.srow, m.scol)
end

-- The innermost match containing the cursor, or — when the cursor sits between
-- tests rather than in one — the nearest match starting before it, which is what
-- the regex scanner has always done and is still the useful answer there.
local function target_for(matches, row, col)
  local best
  for _, m in ipairs(matches) do
    if contains(m, row, col) then
      -- Properly nested ranges: the one starting last is the innermost, and on a
      -- tie the one ending first.
      if
        not best
        or before(best.srow, best.scol, m.srow, m.scol)
        or (m.srow == best.srow and m.scol == best.scol and before(m.erow, m.ecol, best.erow, best.ecol))
      then
        best = m
      end
    end
  end
  if best then
    return best
  end
  for _, m in ipairs(matches) do
    if starts_at_or_before(m, row, col) and (not best or before(best.srow, best.scol, m.srow, m.scol)) then
      best = m
    end
  end
  return best
end

-- The target plus everything enclosing it, outermost first. Enclosure is read
-- off the syntax tree — walk the target's actual parents and keep the ones that
-- are themselves tests or suites — so a neighbour that merely overlaps the
-- target's lines can never be mistaken for a parent.
local function chain_for(matches, target)
  local by_node = {}
  for _, m in ipairs(matches) do
    by_node[m.node:id()] = m
  end
  local reversed = { target }
  local parent = target.node:parent()
  while parent do
    local m = by_node[parent:id()]
    if m then
      reversed[#reversed + 1] = m
    end
    parent = parent:parent()
  end
  local path = {}
  for i = #reversed, 1, -1 do
    path[#path + 1] = reversed[i]
  end
  return path
end

-- A cursor in a line's leading indentation means the first thing on that line;
-- without this, `0` on an indented `def test_x` would land to the left of the
-- test's range and resolve to whatever encloses it instead.
local function snap_to_line_start(bufnr, row, col)
  if col == nil then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  local first = line and line:find('%S')
  if first and col < first - 1 then
    return first - 1
  end
  return col
end

-- ---- public -----------------------------------------------------------------

-- The treesitter language autodap would use for this buffer, or nil when no
-- parser is installed for it (or it is not a language we have a query for).
function M.lang(bufnr)
  local parser = parser_for(bufnr)
  if not parser then
    return nil
  end
  local lang = parser:lang()
  return RESOLVER[lang] and lang or nil
end

-- Nearest test for the cursor at `cursor_row` (1-based) and `cursor_col`
-- (0-based, as `nvim_win_get_cursor` reports it). `cursor_col` may be omitted,
-- which means "anywhere on that row" and cannot tell two tests on one line apart.
--
-- Returns `hit, lang`. A nil second return means treesitter could not answer at
-- all (no parser / unsupported language / parse failure) and the caller should
-- fall back; `nil, lang` means treesitter looked and there is genuinely no test.
--
-- Python hits carry `suffix` — the pytest node-id tail `Class::Nested::test_x`.
-- JS hits carry `title` (display) and `path` (a list of title part-lists,
-- outermost suite first) so the caller can build the runner's `-t` regex.
function M.nearest(bufnr, cursor_row, cursor_col)
  local parser = parser_for(bufnr)
  if not parser then
    return nil, nil
  end
  local lang = parser:lang()
  local resolver = RESOLVER[lang]
  if not resolver then
    return nil, nil
  end
  local ok, trees = pcall(parser.parse, parser)
  if not ok or not trees or not trees[1] then
    return nil, nil
  end
  local root = trees[1]:root()

  local matches = (resolver == 'python' and py_matches or js_matches)(bufnr, root, lang)
  if not matches then
    return nil, nil -- the query did not compile against this parser
  end

  local row = cursor_row - 1
  local target = target_for(matches, row, snap_to_line_start(bufnr, row, cursor_col))
  if not target then
    return nil, lang
  end
  local path = chain_for(matches, target)

  if resolver == 'python' then
    local names = {}
    for _, m in ipairs(path) do
      names[#names + 1] = m.name
    end
    return { kind = target.kind, suffix = table.concat(names, '::') }, lang
  end

  local parts, titles = {}, {}
  for _, m in ipairs(path) do
    parts[#parts + 1] = m.parts
    titles[#titles + 1] = m.text
  end
  return { kind = target.kind, title = table.concat(titles, ' > '), path = parts }, lang
end

return M
