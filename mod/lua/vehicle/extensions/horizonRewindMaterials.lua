-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Record the stock material-switch state independently of beam breakage. Glass
-- can crack through deformation before its supporting beams actually break.
local M = {}
local owner, stateCell, brokenCell, slots

local function cell(fn, wanted, seen, depth)
  if type(fn) ~= 'function' or seen[fn] or depth > 4 then return end
  seen[fn] = true
  for index = 1, 40 do
    local name, value = debug.getupvalue(fn, index)
    if not name then break end
    if name == wanted and type(value) == 'table' then return {fn=fn, index=index, name=name} end
    if type(value) == 'function' then
      local found = cell(value, wanted, seen, depth+1)
      if found then return found end
    end
  end
end

local function read(c)
  if not c then return end
  local name, value = debug.getupvalue(c.fn, c.index)
  if name == c.name and type(value) == 'table' then return value end
end

local function bind()
  if type(material) ~= 'table' or not debug or not debug.getupvalue
    or type(obj.switchMaterial) ~= 'function' or type(obj.resetMaterials) ~= 'function' then return end
  if owner ~= material then
    owner = material
    stateCell = cell(material.switchBrokenMaterial, 'matState', {}, 0)
    brokenCell = cell(material.switchBrokenMaterial, 'brokenSwitches', {}, 0)
    slots = {}
    for _, beam in pairs(v.data.beams or {}) do
      for slot in pairs(beam.deformSwitches or {}) do slots[slot] = true end
    end
  end
  return read(stateCell), read(brokenCell)
end

function M.capture()
  local states, broken = bind()
  if not states or not broken then return end
  local frame = {states={}, broken={}}
  for slot in pairs(slots) do
    local value = states[slot]
    if value == nil or value == false or type(value) == 'string' then
      frame.states[slot] = value or false
      frame.broken[slot] = broken[slot] == true
    end
  end
  return frame
end

function M.apply(frame)
  if type(frame) ~= 'table' or type(frame.states) ~= 'table' or type(frame.broken) ~= 'table' then return end
  local states, broken = bind()
  if not states or not broken then return end
  for slot, value in pairs(frame.states) do
    if slots[slot] and (value == false or type(value) == 'string') then
      if (states[slot] or false) ~= value then
        if value then obj:switchMaterial(slot, value) else obj:resetMaterials(slot) end
      end
      states[slot] = value
      broken[slot] = frame.broken[slot] and true or nil
    end
  end
end

M.onReset = function() end -- Read fresh upvalue tables after the stock reset.
return M
