-- The fzy matching algorithm
--
-- by Seth Warn <https://github.com/swarn>
-- a lua port of John Hawthorn's fzy <https://github.com/jhawthorn/fzy>
--
-- > fzy tries to find the result the user intended. It does this by favouring
-- > matches on consecutive letters and starts of words. This allows matching
-- > using acronyms or different parts of the path." - J Hawthorn

local os_aliases = {
  ['osx'] = 'darwin',
}

local arch_aliases = {
  ['x64'] = 'x86_64',
}

local ffi = require'ffi'

local os   = (arch_aliases[jit.os:lower()] or jit.os:lower())
local arch = (arch_aliases[jit.arch:lower()] or jit.arch:lower())


-- ffi.load() doesn't respect anything but the actual path OR a system library path
local dirname = string.sub(debug.getinfo(1).source, 2, string.len('/native.lua') * -1)
local library_path = dirname .. '../static/libfzy-' .. os .. '-' .. arch .. '.so'

local native = ffi.load(library_path)


ffi.cdef[[
int has_match(const char *needle, const char *haystack, int is_case_sensitive);

// typedef double score_t;
// match* originally returns score_t;

double match(const char *needle, const char *haystack, int is_case_sensitive);
double match_positions(const char *needle, const char *haystack, uint32_t *positions, int is_case_sensitive);

]]

-- @param positions - the C positions object
-- @param length - length of positions
-- @returns - lua array of positions, 1-indexed
local function positions_to_lua(positions, length)
  local result = {}
  for i = 0, length - 1, 1  do
    table.insert(result, positions[i] + 1)
  end
  return result
end


-- Constants

local SCORE_GAP_LEADING = -0.005
local SCORE_GAP_TRAILING = -0.005
local SCORE_GAP_INNER = -0.01
local SCORE_MATCH_CONSECUTIVE = 1.0
local SCORE_MATCH_SLASH = 0.9
local SCORE_MATCH_WORD = 0.8
local SCORE_MATCH_CAPITAL = 0.7
local SCORE_MATCH_DOT = 0.6
local SCORE_MAX = math.huge
local SCORE_MIN = -math.huge
local MATCH_MAX_LENGTH = 1024

local fzy = {}

function fzy.has_match(needle, haystack)
  local is_case_sensitive = false
  return native.has_match(needle, haystack, is_case_sensitive) == 1
end

function fzy.score(needle, haystack)
  local length = #needle
  local is_case_sensitive = false
  local score = native.match_positions(needle, haystack, is_case_sensitive)
  return score
end

function fzy.positions(needle, haystack)
  local length = #needle
  local positions = ffi.new('uint32_t[' .. length .. ']', {})
  local is_case_sensitive = false

  -- TODO: return score
  local score = native.match_positions(needle, haystack, positions, is_case_sensitive)

  return positions_to_lua(positions, length)
end



-- If strings a or b are empty or too long, `fzy.score(a, b) == fzy.get_score_min()`.
function fzy.get_score_min()
  return SCORE_MIN
end

-- For exact matches, `fzy.score(s, s) == fzy.get_score_max()`.
function fzy.get_score_max()
  return SCORE_MAX
end

-- For all strings a and b that
--  - are not covered by either `fzy.get_score_min()` or fzy.get_score_max()`, and
--  - are matched, such that `fzy.has_match(a, b) == true`,
-- then `fzy.score(a, b) > fzy.get_score_floor()` will be true.
function fzy.get_score_floor()
  return (MATCH_MAX_LENGTH + 1) * SCORE_GAP_INNER
end


function fzy.filter(needle, lines)
  results = {}

  for i = 1, #lines do
    local line = lines[i]
    if native.has_match(needle, line, false) == 1 then
      local positions = fzy.positions(needle, line)
      table.insert(results, { line, positions })
    end
  end
  return results
end

return fzy
