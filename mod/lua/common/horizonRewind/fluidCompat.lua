-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Narrow, original compatibility utilities for Fluid Spill 1.3.0. No foreign
-- source is edited, and no engine userdata, vectors, or function environments
-- are copied or replaced. Unknown schemas are rejected before any write.
local M = {}

function M.versionSupported()
  if type(jsonReadFile) ~= 'function' then return false end
  local ok, info = pcall(jsonReadFile, 'mod_info/ML3WUXJ6G/info.json')
  return ok and type(info) == 'table' and info.tagid == 'ML3WUXJ6G'
    and info.version_string == '1.3.0' and info.resource_id == 38681
end

function M.discover(module, exports, expected, sourceSuffix)
  if not debug or not debug.getupvalue then return nil, 'debug upvalue inspection unavailable' end
  local bindings, visited, visitedCount = {}, {}, 0
  local function walk(fn, depth)
    if visited[fn] or depth > 12 then return end
    visited[fn], visitedCount = true, visitedCount + 1
    if visitedCount > 256 then error('closure graph too large') end
    local source = debug.getinfo(fn, 'S').source:gsub('\\', '/')
    if sourceSuffix and not source:find(sourceSuffix, 1, true) then return end
    for index = 1, 128 do
      local name, value = debug.getupvalue(fn, index)
      if not name then break end
      if expected[name] then
        if type(value) ~= expected[name] then error('unexpected type for '..name) end
        if not bindings[name] then bindings[name] = {fn = fn, index = index} end
      end
      if type(value) == 'function' then walk(value, depth + 1) end
    end
  end
  local ok, err = pcall(function()
    for _, name in ipairs(exports) do
      if type(module[name]) ~= 'function' then error('missing export '..name) end
      walk(module[name], 0)
    end
    for name in pairs(expected) do if not bindings[name] then error('missing state '..name) end end
  end)
  if not ok then return nil, tostring(err) end
  return bindings
end

function M.get(bindings, name)
  local ref = bindings[name]
  local _, value = debug.getupvalue(ref.fn, ref.index)
  return value
end

function M.set(bindings, name, value)
  -- BeamNG intentionally blocks debug.setupvalue. Use normal table updates,
  -- keeping the original upvalue binding and table identity intact.
  local target = M.get(bindings, name)
  assert(type(target) == 'table' and type(value) == 'table', 'only plain fluid tables are writable')
  for key in pairs(target) do target[key] = nil end
  for key, entry in pairs(value) do target[key] = entry end
end

function M.copy(value, limits)
  limits = limits or {}
  local bytes, items = 0, 0
  local seen = {}
  local function clone(v, depth)
    local kind = type(v)
    if kind == 'number' then
      if v ~= v or v == math.huge or v == -math.huge then error('nonfinite fluid value') end
      bytes = bytes + 24
      return v
    elseif kind == 'boolean' or kind == 'nil' then bytes = bytes + 16; return v
    elseif kind == 'string' then bytes = bytes + 48 + #v; return v
    elseif kind ~= 'table' then error('unsupported fluid value '..kind) end
    if depth > (limits.depth or 4) or getmetatable(v) or seen[v] then error('unsupported fluid table shape') end
    seen[v] = true
    bytes, items = bytes + 96, items + 1
    if items > (limits.items or 8192) then error('fluid item budget exceeded') end
    local out = {}
    for key, entry in pairs(v) do
      if type(key) ~= 'number' and type(key) ~= 'string' then error('unsupported fluid key') end
      bytes = bytes + 48
      out[clone(key, depth + 1)] = clone(entry, depth + 1)
      if bytes > (limits.bytes or 2097152) then error('fluid snapshot byte budget exceeded') end
    end
    seen[v] = nil
    return out
  end
  local ok, result = pcall(clone, value, 0)
  if not ok then return nil, tostring(result) end
  return result, bytes
end

return M
