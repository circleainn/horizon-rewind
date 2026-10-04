-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Optional, bounded snapshots of Fluid Spill 1.3.0 reservoir and tire state.
-- Static vehicle geometry, live config, userdata and engine objects are kept
-- under their original ownership. Only named scalar/plain-table state moves.
local M = {}
local Compat = require('horizonRewind/fluidCompat')
local tables = {'slick', 'reportGrace', 'treadAcc', 'appliedMult', 'reservoir', 'burstLeft',
  'burstRate', 'lastDmgRate', 'flux', 'fluxTarget', 'tankBroken', 'fuelNodes', 'telemetry'}
local numbers = {'prevSpeed', 'fuelLeft', 'fuelRate', 'leakTimer', 'trackTimer', 'telTimer'}
local booleans = {'engBroken', 'synthOil', 'synthCool', 'telWasActive'}
local expected = {applyWheelFriction = 'function'}
for _, name in ipairs(tables) do expected[name] = 'table' end
for _, name in ipairs(numbers) do expected[name] = 'number' end
for _, name in ipairs(booleans) do expected[name] = 'boolean' end
local module, seenModule, bindings, originalUpdate, originalReset, updateWrapper, resetWrapper
local rewinding, warned, hookEntry = false, {}, nil

local function warn(message)
  if not warned[message] then
    warned[message] = true
    if log then log('W', 'horizonRewindFluids', message) end
  end
end

local function detach()
  if hookEntry then hookEntry.attached = false end
  if module then
    if module.updateGFX == updateWrapper then module.updateGFX = originalUpdate end
    if module.onReset == resetWrapper then module.onReset = originalReset end
    if extensions.hookUpdate then extensions.hookUpdate('updateGFX'); extensions.hookUpdate('onReset') end
  end
  module, bindings, hookEntry = nil, nil, nil
end

local function discover()
  local found = extensions and rawget(extensions, 'fluidspill_fluid')
  if found ~= seenModule then
    detach(); seenModule = found
    if not found then return false end
    if not Compat.versionSupported() then warn('Fluid compatibility requires installed Fluid Spill 1.3.0'); return false end
    local refs, err = Compat.discover(found, {'setState', 'updateGFX', 'onReset'}, expected, 'fluidspill/fluid.lua')
    if not refs then warn('Unsupported vehicle fluid state: '..tostring(err)); return false end
    module, bindings = found, refs
    originalUpdate, originalReset = module.updateGFX, module.onReset
    local entry, update, reset = {attached = true}, originalUpdate, originalReset
    hookEntry = entry
    updateWrapper = function(...) if not entry.attached or not rewinding then return update(...) end end
    resetWrapper = function(...) if not entry.attached or not rewinding then return reset(...) end end
    module.updateGFX, module.onReset = updateWrapper, resetWrapper
    if extensions.hookUpdate then extensions.hookUpdate('updateGFX'); extensions.hookUpdate('onReset') end
  end
  return module ~= nil
end

function M.capture()
  if not discover() then return nil end
  local state = {}
  for _, list in ipairs({tables, numbers, booleans}) do
    for _, name in ipairs(list) do state[name] = Compat.get(bindings, name) end
  end
  local copy, err = Compat.copy(state, {bytes = 64 * 1024, items = 512, depth = 3})
  if not copy then warn(err) end
  return copy
end

function M.restore(state)
  if not state or not discover() then return false end
  local copy, err = Compat.copy(state, {bytes = 64 * 1024, items = 512, depth = 3})
  if not copy then warn(err); return false end
  for name, kind in pairs(expected) do
    if kind ~= 'function' and type(copy[name]) ~= kind then warn('Incomplete vehicle fluid snapshot: '..name); return false end
  end
  -- Scalar closure bindings are protected by BeamNG. Restore only the mod's
  -- existing mutable tables; scalar detection/timer flags remain live.
  for _, name in ipairs(tables) do Compat.set(bindings, name, copy[name]) end
  -- A native physics reset rebuilt friction. Reapply the historical multiplier
  -- now, rather than letting the mod's cache incorrectly skip an equal value.
  local applyFriction = Compat.get(bindings, 'applyWheelFriction')
  for id, multiplier in pairs(copy.appliedMult) do
    local wheel = wheels and wheels.wheels and wheels.wheels[id]
    if wheel and not wheel.isTireDeflated then applyFriction(wheel, multiplier) end
  end
  return true
end

function M.setRewinding(value)
  rewinding = value == true
  discover()
end

M.onExtensionUnloaded = function() rewinding = false; detach() end
return M
