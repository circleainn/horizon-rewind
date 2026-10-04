-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Opt-in, synchronized physical history for active singleplayer traffic cars.
local M = {}
local members, playerId, seconds, serial = {}, nil, 20, 1000000
local enabled, operation, fault = false, nil, nil
local hooks = {}
local scanClock = 0
local loadVehicle = "extensions.load('horizonRewindEffects'); extensions.load('horizonRewindFluids'); extensions.load('horizonRewindTires'); extensions.load('horizonRewindMaterials'); extensions.load('horizonRewindTransmission'); extensions.load('horizonRewindVehicle'); "

local function bundle(id)
  return core_vehicle_manager and core_vehicle_manager.getVehicleData(id)
end

local function carFor(id, member)
  local car = be:getObjectByID(id)
  if not car or (member.bundle and bundle(id) ~= member.bundle) then return nil end
  return car
end

local function queue(id, member, method, args)
  local car = carFor(id, member)
  if car then
    car:queueLuaCommand('if extensions.horizonRewindVehicle then extensions.horizonRewindVehicle.'
      ..method..'('..member.token..(args and ','..args or '')..') end')
    return true
  end
end

local function unhook()
  for _, h in ipairs(hooks) do
    h.active = false
    if h.target[h.name] == h.wrapper then h.target[h.name] = h.original end
  end
  hooks = {}
  if extensions.hookUpdate then
    extensions.hookUpdate('onUpdate'); extensions.hookUpdate('onVehicleResetted')
  end
end

local function freezeTraffic()
  local traffic = gameplay_traffic
  if not traffic then return end
  -- Stop real-time recycling and GE damage reactions while every participant
  -- is paused. Keep wrappers chain-safe if another extension wraps them later.
  for _, name in ipairs({'onUpdate', 'onVehicleResetted'}) do
    if type(traffic[name]) == 'function' then
      local h = {target=traffic, name=name, original=traffic[name], active=true}
      h.wrapper = function(...)
        local id = ...
        if h.active and (h.name == 'onUpdate' or members[id]) then return end
        return h.original(...)
      end
      traffic[name] = h.wrapper
      hooks[#hooks+1] = h
    end
  end
  if extensions.hookUpdate then
    extensions.hookUpdate('onUpdate'); extensions.hookUpdate('onVehicleResetted')
  end
end

function M.abort()
  for id, member in pairs(members) do queue(id, member, 'abort') end
  members, operation, fault = {}, nil, nil
  unhook()
end

function M.configure(id, active, duration)
  M.abort()
  playerId, enabled, seconds, scanClock = id, active == true, duration or 20, 1
end

function M.invalidate(id)
  if members[id] then
    -- Spawn/destruction notifications can refer to an already replaced VM.
    members[id] = nil
  end
end

function M.update(dt)
  if not enabled then return end
  if operation then
    for id, member in pairs(members) do
      local car = carFor(id, member)
      if not car or not be:getObjectActive(id) then
        -- No history can be restored into a different or inactive vehicle.
        if car then queue(id, member, 'abort') end
        members[id] = nil
      elseif member.pending == 'visible' then
        local p, wanted = car:getPosition(), member.restored.position
        local close = not wanted or (p.x-wanted[1])^2+(p.y-wanted[2])^2+(p.z-wanted[3])^2 < 0.0025
        member.visible = close and member.visible+1 or 0
        if member.visible >= 2 then member.pending = nil end
      end
    end
    return
  end
  scanClock = scanClock + (dt or 0)
  if scanClock < 0.25 then return end
  scanClock = 0
  local traffic = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
  for id, member in pairs(members) do
    if id == playerId or not traffic[id] or not traffic[id].isAi or not be:getObjectActive(id) or not carFor(id, member) then
      queue(id, member, 'abort'); members[id] = nil
    end
  end
  for id, data in pairs(traffic) do
    if id ~= playerId and data.isAi and be:getObjectActive(id) and not members[id] then
      local car = be:getObjectByID(id)
      if car then
        serial = serial+1
        local member = {token=serial, bundle=bundle(id), available=0}
        members[id] = member
        car:queueLuaCommand(loadVehicle..'extensions.horizonRewindVehicle.configure('..serial..',true,'..seconds..',true)')
      end
    end
  end
end

function M.status(limit)
  local count = 0
  for _, member in pairs(members) do
    count = count+1
    limit = math.min(limit, member.available)
  end
  return limit, count, fault
end

function M.begin()
  if not enabled then return end
  operation, fault = 'rewinding', nil
  freezeTraffic()
  for id, member in pairs(members) do
    member.pending = 'began'
    queue(id, member, 'begin')
  end
end

function M.ready()
  if fault then return false end
  for _, member in pairs(members) do if member.pending then return false end end
  return true
end

function M.seek(amount)
  for id, member in pairs(members) do
    member.pending = 'previewed'
    queue(id, member, 'seek', string.format('%.9g', amount))
  end
end

function M.finish(cancel)
  if not enabled then return end
  operation = 'restoring'
  for id, member in pairs(members) do
    member.pending = 'restorePrepared'
    queue(id, member, 'finish', tostring(cancel == true))
  end
end

function M.commit()
  for id, member in pairs(members) do
    local car, data = carFor(id, member), member.restored
    if car and data and data.velocity then
      local v = data.velocity
      car:applyClusterVelocityScaleAdd(car:getRefNodeId(), 0, v[1], v[2], v[3])
    end
    member.restored, member.pending = nil, nil
  end
  operation = nil
  unhook()
end

function M.onVehicleMessage(id, token, event, data)
  local member = members[id]
  if not member or member.token ~= token then return false end
  data = data or {}
  if event == 'error' then fault = 'Traffic vehicle '..id..': '..tostring(data.message); return true end
  if event == 'reset' then
    member.available = 0
    if operation then fault = 'A traffic car reset during rewind.' end
    return true
  end
  if data.availableSeconds then member.available = data.availableSeconds end
  if not operation then return true end
  if event == 'empty' then fault = 'A traffic car has no history.'; return true end
  local car = carFor(id, member)
  if not car then members[id] = nil; return true end
  if event == 'began' and member.pending == 'began' then member.pending = nil
  elseif event == 'previewed' and member.pending == 'previewed' then
    local p = data.position
    if p then car:setClusterPosRelRot(car:getRefNodeId(), p[1], p[2], p[3], 0, 0, 0, 1) end
    member.pending = nil
  elseif event == 'restorePrepared' and member.pending == 'restorePrepared' then
    local p, r = data.position, data.rotation
    car:setOriginalTransform(p[1],p[2],p[3],r[1],r[2],r[3],r[4])
    member.pending = 'restored'
    queue(id, member, 'executeRestore')
  elseif event == 'resetReady' and member.pending == 'restored' then
    car:resetBrokenFlexMesh(); queue(id, member, 'completeRestore')
  elseif event == 'restored' and member.pending == 'restored' then
    if data.resetFlexMesh then car:resetBrokenFlexMesh() end
    local p = data.position
    if p then car:setClusterPosRelRot(car:getRefNodeId(),p[1],p[2],p[3],0,0,0,1) end
    member.restored, member.pending, member.visible = data, 'visible', 0
  end
  return true
end

M.onExtensionUnloaded = M.abort
return M
