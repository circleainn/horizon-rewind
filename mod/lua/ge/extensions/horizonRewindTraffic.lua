-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Opt-in, synchronized physical history for active singleplayer traffic cars.
local M = {}
local members, playerId, seconds, serial = {}, nil, 20, 1000000
local enabled, operation, fault = false, nil, nil
local hooks = {}
local scanClock = 0
local cancelled = false
local carLimit=0 -- zero keeps all active traffic, matching the original behavior
local loadVehicle = "extensions.load('horizonRewindEffects'); extensions.load('horizonRewindFluids'); extensions.load('horizonRewindTires'); extensions.load('horizonRewindMaterials'); extensions.load('horizonRewindTransmission'); extensions.load('horizonRewindDirt'); extensions.load('horizonRewindVehicle'); "

local function bundle(id)
  return core_vehicle_manager and core_vehicle_manager.getVehicleData(id)
end

local function carFor(id, member)
  local car = be:getObjectByID(id)
  if not car or (member.bundle and bundle(id) ~= member.bundle) then return nil end
  return car
end

local function poolFor(id)
  local manager=core_vehicleActivePooling
  local pool=manager and manager.getPoolOfVeh and manager.getPoolOfVeh(id)
  -- Only stock traffic pools can safely recycle a car absent at the selected
  -- time. Custom/manual AI without a pool retains the conservative limit.
  return pool and pool.name=='autoTraffic' and pool or nil
end

local function showOriginal(id,member)
  local car=carFor(id,member)
  if car and member.originalHidden~=nil then car:setHidden(member.originalHidden) end
end

local function queue(id, member, method, args)
  local car = carFor(id, member)
  if car then
    member.pendingAge=0
    car:queueLuaCommand('if extensions.horizonRewindVehicle then extensions.horizonRewindVehicle.'
      ..method..'('..member.token..(args and ','..args or '')..') end')
    return true
  end
end

local function seekMember(id,member)
  if member.pending or member.wanted==nil then return end
  local amount=member.wanted
  member.wanted=nil
  local car=carFor(id,member)
  member.beforeBirth=member.pool and amount>member.historyAtBegin
  if car then car:setHidden(member.originalHidden or member.beforeBirth==true) end
  -- Hidden future cars need no node/texture work. They are pooled on commit
  -- or restored to their live frame on cancel.
  if not member.noHistory and not member.beforeBirth then
    member.pending='previewed'
    queue(id,member,'seek',string.format('%.9g',amount))
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
  for id, member in pairs(members) do showOriginal(id,member);queue(id, member, 'abort') end
  members, operation, fault = {}, nil, nil
  unhook()
end

function M.configure(id, active, duration)
  M.abort()
  playerId, enabled, seconds, scanClock = id, active == true, duration or 20, 1
end

function M.setLimit(value)
  if operation or (value~=0 and value~=2 and value~=4 and value~=8) then return end
  carLimit,scanClock=value,1
end

function M.invalidate(id)
  if members[id] then
    -- Spawn/destruction notifications can refer to an already replaced VM.
    members[id] = nil
  end
end

function M.update(dt,realDt)
  if not enabled then return end
  if operation then
    for id, member in pairs(members) do
      local car = carFor(id, member)
      if not car or not be:getObjectActive(id) then
        -- No history can be restored into a different or inactive vehicle.
        if car then showOriginal(id,member); queue(id, member, 'abort') end
        members[id] = nil
      elseif member.pending == 'visible' then
        local p, wanted = car:getPosition(), member.restored.position
        local close = not wanted or (p.x-wanted[1])^2+(p.y-wanted[2])^2+(p.z-wanted[3])^2 < 0.0025
        member.visible = close and member.visible+1 or 0
        if member.visible >= 2 then member.pending = nil end
      end
      if members[id]==member and member.pending then
        member.pendingAge=(member.pendingAge or 0)+(realDt or dt or 0)
        if member.pendingAge>5 then fault='Traffic vehicle '..id..' did not respond.' end
      end
    end
    return
  end
  scanClock = scanClock + (dt or 0)
  if scanClock < 0.25 then return end
  scanClock = 0
  local traffic = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
  local candidates,selected={},{}
  local player=playerId and be:getObjectByID(playerId)
  local origin=player and player:getPosition()
  for id,data in pairs(traffic) do
    local car=id~=playerId and data.isAi and be:getObjectActive(id) and be:getObjectByID(id)
    if car then
      local distance=0
      if carLimit>0 and origin then
        local p=car:getPosition()
        distance=(p.x-origin.x)^2+(p.y-origin.y)^2+(p.z-origin.z)^2
      end
      -- Keep existing buffers when cars are at similar distances. An incoming
      -- car must be about 20% nearer to replace an established recorder.
      local existing=members[id] and carFor(id,members[id])
      candidates[#candidates+1]={id=id,score=distance*(existing and .64 or 1)}
    end
  end
  if carLimit>0 then
    table.sort(candidates,function(a,b) return a.score==b.score and a.id<b.id or a.score<b.score end)
  end
  for i,candidate in ipairs(candidates) do
    if carLimit==0 or i<=carLimit then selected[candidate.id]=true end
  end
  for id, member in pairs(members) do
    if not selected[id] or not carFor(id, member) then
      queue(id, member, 'abort'); members[id] = nil
    end
  end
  for id, data in pairs(traffic) do
    if selected[id] and not members[id] then
      local car = be:getObjectByID(id)
      if car then
        serial = serial+1
        local member = {token=serial, bundle=bundle(id), available=0, pool=poolFor(id)}
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
    if not member.pool then limit = math.min(limit, member.available) end
  end
  return limit, count, fault
end

function M.begin()
  if not enabled then return end
  operation, fault = 'rewinding', nil
  cancelled=false
  freezeTraffic()
  for id, member in pairs(members) do
    local car=carFor(id,member)
    member.originalHidden=car and car:isHidden() or false
    member.historyAtBegin=member.available
    member.beforeBirth,member.restored,member.pending,member.wanted=false,nil,nil,nil
    member.noHistory=member.pool and member.available<0.1
    if not member.noHistory then
      member.pending = 'began'
      queue(id, member, 'begin')
    end
  end
end

function M.ready()
  if fault then return false end
  for _, member in pairs(members) do if member.pending then return false end end
  return true
end

function M.seek(amount)
  for id, member in pairs(members) do
    -- At most one in-flight seek per VM, plus the latest requested cursor.
    -- A slower traffic car does not block the player's next preview frame.
    member.wanted=amount
    seekMember(id,member)
  end
end

function M.finish(cancel)
  if not enabled then return end
  operation = 'restoring'
  cancelled=cancel==true
  for id, member in pairs(members) do
    if cancelled then showOriginal(id,member) end
    if not member.noHistory then
      member.pending = 'restorePrepared'
      queue(id, member, 'finish', tostring(cancel == true))
    end
  end
end

function M.commit()
  for id, member in pairs(members) do
    local car, data = carFor(id, member), member.restored
    if car and member.beforeBirth and not cancelled then
      -- This car had not joined this timeline. Return it to the stock pool;
      -- traffic can spawn it at a safe road position instead of leaving a
      -- future car overlapping a restored one. No vehicles are deleted.
      queue(id,member,'abort')
      member.pool:setVeh(id,false)
      showOriginal(id,member)
      members[id]=nil
    elseif car and data and data.velocity then
      local v = data.velocity
      car:applyClusterVelocityScaleAdd(car:getRefNodeId(), 0, v[1], v[2], v[3])
    end
    showOriginal(id,member)
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
  if event == 'began' and member.pending == 'began' then member.pending = nil;seekMember(id,member)
  elseif event == 'previewed' and member.pending == 'previewed' then
    local p = data.position
    if p then car:setClusterPosRelRot(car:getRefNodeId(), p[1], p[2], p[3], 0, 0, 0, 1) end
    member.pending = nil
    seekMember(id,member)
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
