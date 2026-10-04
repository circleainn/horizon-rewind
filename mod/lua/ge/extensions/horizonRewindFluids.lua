-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Optional Fluid Spill 1.3.0 compatibility. Puddles lose their originating
-- vehicle on merge, so this records the SINGLEPLAYER WORLD fluid state.
-- This does not reverse engine particles. Fluid Spill's own Lua droplets,
-- streams, powder and decals can be shown from their sampled historical state.
local M = {}
local Compat = require('horizonRewind/fluidCompat')
local fields = {'puddles', 'smears', 'trails', 'streams', 'droplets', 'splashes', 'absorbs', 'grains'}
local expected = {mergeTimer='number', animTime='number', stateDirty='boolean', ownDirty='boolean',
  broadcastState='function', drawFluidFX='function', updateStarve='number', updateTicks='number',
  recovering='table', upTime='number'}
for _, name in ipairs(fields) do expected[name] = 'table' end
local exports = {'mpOwnChunks', 'mpApplyOwner', 'reportLeaks', 'reportWheelTracks',
  'reportPour', 'vehicleRecovering', 'onVehicleResetted', 'onUpdate', 'onPreRender'}
local HISTORY_BYTES, SNAPSHOT_BYTES, MAX_ITEMS = 12 * 1024 * 1024, 2 * 1024 * 1024, 4096
-- Estimated retained allocations <=12 MiB history +2 MiB live +2 MiB restore
-- scratch. Snapshot traversal stops before allocation can grow without bound.
local module, bindings, seenModule, wrappers, originals = nil, nil, nil, {}, {}
local hookEntry
local frames, head, tail, count, historyBytes = {}, 1, 0, 0, 0
local vehicleId, session, clock, accumulator = nil, nil, 0, 0
local active, live, liveTime, nativePending, armed = false, nil, 0, false, false
local reason, warned = 'Fluid Spill is not loaded', {}

local function warn(message)
  reason = message
  if not warned[message] then
    warned[message] = true
    if log then log('W', 'horizonRewindFluids', message) end
  end
end

local function multiplayer()
  local mp = extensions and rawget(extensions, 'fluidspill_mp')
  return mp and type(mp.active) == 'function' and mp.active() == true
end

local function clearHistory()
  frames, head, tail, count, historyBytes = {}, 1, 0, 0, 0
end

local function detachHooks()
  if hookEntry then hookEntry.attached = false end
  if module then
    for name, fn in pairs(wrappers) do if module[name] == fn then module[name] = originals[name] end end
    if extensions.hookUpdate then
      extensions.hookUpdate('onUpdate'); extensions.hookUpdate('onVehicleResetted')
    end
  end
  module, bindings, wrappers, originals, hookEntry = nil, nil, {}, {}, nil
  active, live, nativePending, armed = false, nil, false, false
end

local function snapshot()
  local state = {}
  for _, name in ipairs(fields) do state[name] = Compat.get(bindings, name) end
  return Compat.copy(state, {items = MAX_ITEMS + 9, bytes = SNAPSHOT_BYTES, depth = 3})
end

local function apply(state, broadcast)
  -- Clone first: the live mod will mutate these tables after resume, while the
  -- retained history and cancellation snapshot must remain immutable.
  local copy, err = Compat.copy(state, {items = MAX_ITEMS + 9, bytes = SNAPSHOT_BYTES, depth = 3})
  if not copy then warn(err); return false end
  for _, name in ipairs(fields) do Compat.set(bindings, name, copy[name]) end
  if broadcast then Compat.get(bindings, 'broadcastState')() end
  return true
end

local function discover()
  local found = extensions and rawget(extensions, 'fluidspill_main')
  if found ~= seenModule then
    if active and module and live and seenModule == module then apply(live, false) end
    detachHooks(); clearHistory(); seenModule = found
    if not found then reason = 'Fluid Spill is not loaded'; return false end
    if not Compat.versionSupported() then warn('Fluid compatibility requires installed Fluid Spill 1.3.0'); return false end
    local refs, err = Compat.discover(found, exports, expected, 'fluidspill/main.lua')
    if not refs then warn('Unsupported Fluid Spill private state: '..tostring(err)); return false end
    module, bindings = found, refs
    local entry = {attached = true}
    hookEntry = entry
    local function wrap(name, fn)
      originals[name] = module[name]
      wrappers[name] = fn
      module[name] = fn
    end
    local originalUpdate = module.onUpdate
    wrap('onUpdate', function(dtReal, dtSim)
      return originalUpdate(dtReal, entry.attached and active and 0 or dtSim)
    end)
    for _, name in ipairs({'reportLeaks', 'reportWheelTracks', 'reportPour'}) do
      local key = name
      local original = module[key]
      wrap(key, function(...) if not entry.attached or not active then return original(...) end end)
    end
    local originalRecovering = module.vehicleRecovering
    wrap('vehicleRecovering', function(id)
      if entry.attached and id == vehicleId and (active or armed) and not multiplayer() then nativePending = true; return end
      return originalRecovering(id)
    end)
    local originalReset = module.onVehicleResetted
    wrap('onVehicleResetted', function(id)
      if entry.attached and active and id == vehicleId then return end
      return originalReset(id)
    end)
    if extensions.hookUpdate then
      extensions.hookUpdate('onUpdate'); extensions.hookUpdate('onVehicleResetted')
    end
    reason = 'Fluid Spill 1.3.0 world-state history active'
  end
  return module ~= nil and not multiplayer()
end

local function dropOldest()
  historyBytes = historyBytes - frames[head].bytes
  frames[head], head, count = nil, head + 1, count - 1
end

local function push(state, bytes)
  if count > 0 and frames[tail].time == clock then
    historyBytes = historyBytes - frames[tail].bytes
    frames[tail], tail, count = nil, tail - 1, count - 1
  end
  while count > 0 and (count >= 101 or historyBytes + bytes > HISTORY_BYTES) do dropOldest() end
  tail, count = tail + 1, count + 1
  frames[tail] = {time = clock, state = state, bytes = bytes}
  historyBytes = historyBytes + bytes
  while count > 1 and frames[head + 1].time <= clock - 20 do dropOldest() end
end

local function selected(secondsAgo)
  local time = liveTime - math.max(0, tonumber(secondsAgo) or 0)
  if count == 0 or time >= liveTime then return live, liveTime end
  local lo, hi = head, tail
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if frames[mid].time <= time + 1e-8 then lo = mid else hi = mid - 1 end
  end
  return frames[lo].state, frames[lo].time
end

function M.configure(id, token)
  M.abort()
  vehicleId, session, clock, accumulator = id, token, 0, 0
  clearHistory(); discover()
end

function M.record(dtSim)
  if not vehicleId or not discover() or active then return end
  dtSim = tonumber(dtSim) or 0
  if dtSim <= 0 then return end
  clock, accumulator = clock + dtSim, accumulator + dtSim
  if accumulator < 0.2 then return end
  accumulator = accumulator % 0.2
  local state, bytes = snapshot()
  if not state then warn(bytes); clearHistory(); return end
  push(state, bytes)
end

function M.begin(id, token)
  if active or id ~= vehicleId or token ~= session or not discover() then return false end
  local state, bytes = snapshot()
  if not state then warn(bytes); M.releaseNative(); return false end
  live, liveTime, active, nativePending, armed = state, clock, true, false, false
  -- The live copy is also immutable, so the history can share it safely.
  push(state, bytes)
  return true
end

function M.seek(secondsAgo)
  if not active or not discover() then return false end
  local state = selected(secondsAgo)
  return state and apply(state, false) or false
end

function M.finish(secondsAgo, cancelled)
  if not active or not module then return false end
  local state, time = live, liveTime
  if not cancelled then state, time = selected(secondsAgo) end
  if not apply(state, true) then return false end
  if not cancelled then
    local exactTime = math.max(0, liveTime - math.max(0, tonumber(secondsAgo) or 0))
    while count > 0 and frames[tail].time > exactTime + 1e-8 do
      historyBytes = historyBytes - frames[tail].bytes
      frames[tail], tail, count = nil, tail - 1, count - 1
    end
    clock = exactTime
  end
  -- Fluid Spill's final recovery heartbeat may arrive after the rewind's
  -- release. Mark its grace period without invoking its clear-on-recover.
  Compat.get(bindings, 'recovering')[vehicleId] = Compat.get(bindings, 'upTime')
  active, live, accumulator, nativePending, armed = false, nil, 0, false, false
  return true
end

function M.arm(id, token)
  if id == vehicleId and token == session and discover() and not active then armed = true end
end

function M.releaseNative()
  if nativePending and not active and module then
    nativePending = false
    originals.vehicleRecovering(vehicleId)
  end
  armed = false
end

function M.abort()
  if active and module and live then
    apply(live, true)
    Compat.get(bindings, 'recovering')[vehicleId] = Compat.get(bindings, 'upTime')
  elseif nativePending then
    M.releaseNative()
  end
  active, live, nativePending, armed = false, nil, false, false
  vehicleId, session = nil, nil
  clearHistory()
  detachHooks(); seenModule = nil
end

function M.reset()
  local id, token = vehicleId, session
  M.abort(); vehicleId, session, clock, accumulator = id, token, 0, 0
  discover()
end

function M.getStatus()
  return {supported = module ~= nil and not multiplayer(), active = active, reason = reason,
    samples = count, estimatedHistoryBytes = historyBytes, budgetBytes = HISTORY_BYTES,
    availableSeconds = count > 0 and clock - frames[head].time or 0, scope = 'singleplayer world'}
end

M.onExtensionUnloaded = function() M.abort(); detachHooks() end
return M
