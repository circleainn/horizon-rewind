-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Optional, schema-checked adapter for the installed Dynamic Damage Particles 2.0.
-- This is original integration code, not a copy of the third-party simulator.
-- Its public API has no live seek operation, so this adapter uses named Lua
-- upvalues only after validating the known state layout. Unknown layouts stay off.
local M = {}
local ffiOk, ffi = pcall(require, 'ffi')
local id, session, binding
local clock, sampleClock, bytes = 0, 0, 0
local history, live, gates = {}, nil, {}
local phase, grace = 'idle', 0
local vehicleRef
local abort, fail
local applyCache
local reason = 'Dynamic Damage Particles is not loaded.'
local budget = 16 * 1024 * 1024 -- total retained packed history + cancellation frame
local interval, maxSeconds = 0.1, 20
local identities = setmetatable({}, {__mode = 'k'})
local nextIdentity = 0
local discoveryClock = 0
local nan = 0 / 0

local fields = {'px','py','pz','ppx','ppy','ppz','proll','sx','sy','sz',
  'vx','vy','vz','ivx','ivy','ivz','roll','rollVel','ttl','age','contact','stuck',
  'wnx','wny','wnz','wnt','ax','ay','az','escape','resting','size','mass',
  'fricMul','restMul','drag','ki','bl','nid','dragMul','gnx','gny','gnz','rc','rs'}
local fieldIndex, allowed = {}, {ai=true, vid=true, pp=true, tri=true, gk=true, gi=true, gone=true}
for i, key in ipairs(fields) do fieldIndex[key], allowed[key] = i-1, true end
local stride = #fields

local function finite(value)
  return type(value) == 'number' and value == value and math.abs(value) < math.huge
end

local function mod()
  return rawget(_G, 'crashDebris') or (extensions and rawget(extensions, 'crashDebris'))
end

local function read(cell)
  local name, value = debug.getupvalue(cell.fn, cell.index)
  if name ~= cell.name then error('Dynamic Damage Particles state changed.') end
  return value
end

local function discover()
  local target = mod()
  if not ffiOk or not debug or not debug.getupvalue
    or type(target) ~= 'table' then return nil end
  for _, name in ipairs({'burst','sparks','rubber','tireStrip','getConfig','onPreRender',
    'onVehicleResetted','onVehicleDestroyed','requestConfig','setWheelNodes','setNodeMaterials'}) do
    if type(target[name]) ~= 'function' then return nil end
  end
  local cells, functions, seen = {}, {}, {}
  local function visit(fn, depth)
    if seen[fn] or depth > 14 then return end
    seen[fn] = true
    local info = debug.getinfo(fn, 'S')
    if not info or info.what ~= 'Lua' then return end
    for index = 1, 160 do
      local name, value = debug.getupvalue(fn, index)
      if not name then break end
      if not cells[name] then cells[name] = {fn=fn, index=index, name=name} end
      if type(value) == 'function' then
        functions[name] = value
        visit(value, depth+1)
      end
    end
  end
  visit(target.onPreRender, 0)
  visit(target.burst, 0)
  visit(target.onVehicleResetted, 0)
  for _, name in ipairs({'actives','activeCount','sparkCount','debrisCount','pending',
    'pendingCount','spawnClock','env','cfg','PEND_STRIDE','SPARK','wheelPrev',
    'sparkAccum','debrisAccum'}) do if not cells[name] then return nil end end
  local env, cfg = read(cells.env), read(cells.cfg)
  if read(cells.PEND_STRIDE) ~= 12 or read(cells.SPARK) ~= 9
    or type(env) ~= 'table' or type(env.gadd) ~= 'function'
    or type(env.settled) ~= 'function' or type(env.clear) ~= 'function'
    or type(env.grid) ~= 'table' or type(env.sq) ~= 'table'
    or type(cfg) ~= 'table' or cfg.sparkHz == nil or cfg.particleHz == nil
    or cfg.glassCutsTires == nil or cfg.keepOnReset == nil
    or cfg.flickDebris == nil or cfg.glassShards == nil
    or not finite(cfg.staticCap) or not finite(cfg.movingCap) or not finite(cfg.sparkCap)
    or type(functions.drawActives) ~= 'function'
    or type(functions.spawnPiece) ~= 'function' or type(functions.spawnSpark) ~= 'function'
    or type(functions.queuePending) ~= 'function'
    or type(functions.removeActive) ~= 'function' then return nil end
  for _, key in ipairs({'actives','pending','wheelPrev'}) do
    if type(read(cells[key])) ~= 'table' then return nil end
  end
  for _, key in ipairs({'activeCount','sparkCount','debrisCount','pendingCount','spawnClock'}) do
    if not finite(read(cells[key])) then return nil end
  end
  return {target=target, cells=cells, draw=functions.drawActives,
    spawnPiece=functions.spawnPiece, spawnSpark=functions.spawnSpark,
    queuePending=functions.queuePending, removeActive=functions.removeActive,
    clearVehicle=target.onVehicleDestroyed}
end

local function trim(extra)
  while #history > 0 and (bytes + extra > budget
    or clock - history[1].time > maxSeconds) do
    bytes = bytes - history[1].bytes
    table.remove(history, 1)
  end
end

local function scalar(piece, key)
  local value = piece[key]
  if value == nil then return nan end
  if key == 'resting' then
    if type(value) ~= 'boolean' then error('Unsupported particle resting flag.') end
    return value and 1 or 0
  end
  if not finite(value) then error('Unsupported particle field: '..key) end
  return value
end

local function capture()
  local c = binding.cells
  local actives, count = read(c.actives), read(c.activeCount)
  local pending, pendingCount = read(c.pending), read(c.pendingCount)
  if count < 0 or count > 10000 or count ~= math.floor(count)
    or pendingCount < 0 or pendingCount > 32768 or pendingCount ~= math.floor(pendingCount) then
    error('Unsupported particle counts.')
  end
  local owned, pendingOwned = 0, 0
  for i=1,count do
    local piece = actives[i]
    if type(piece) ~= 'table' or not finite(piece.vid) then error('Unsupported particle owner.') end
    if piece.vid == id then
      for key in pairs(piece) do if not allowed[key] then error('Unknown particle field: '..tostring(key)) end end
      if not finite(piece.px) or not finite(piece.py) or not finite(piece.pz)
        or not finite(piece.ki) or piece.ki < 1 or piece.ki > 19
        or type(piece.tri) ~= 'table' then error('Unsupported particle geometry.') end
      owned = owned + 1
    end
  end
  for row=0,pendingCount-1 do if pending[row*12+2] == id then pendingOwned = pendingOwned+1 end end
  -- Geometry/palette tables are shared immutable references, never copied.
  local cost = owned * (stride*8 + 80) + pendingOwned*12*8 + 512
  if cost > budget/2 then error('Particle population exceeds the adapter memory budget.') end
  trim(cost + (live and live.bytes or 0))
  local frame = {time=clock, count=owned, bytes=cost, ids={}, refs={}, pending={},
    data=ffi.new('double[?]', math.max(1, owned*stride)), spawnClock=read(c.spawnClock)}
  local cfg = read(c.cfg)
  frame.sparkAlpha = cfg.interpSparks == 1 and math.min(1, read(c.sparkAccum)*math.max(4,cfg.sparkHz)) or 1
  frame.debrisAlpha = cfg.interpParticles == 1 and math.min(1, read(c.debrisAccum)*math.max(4,cfg.particleHz)) or 1
  local index = 0
  for i=1,count do
    local piece = actives[i]
    if piece.vid == id then
      if not identities[piece] then nextIdentity=nextIdentity+1; identities[piece]=nextIdentity end
      frame.ids[index+1] = identities[piece]
      frame.refs[index+1] = {piece.tri, piece.pp}
      for j,key in ipairs(fields) do frame.data[index*stride+j-1] = scalar(piece,key) end
      index=index+1
    end
  end
  for row=0,pendingCount-1 do
    local base=row*12
    if pending[base+2] == id then
      for col=1,12 do
        local value=pending[base+col]
        if value ~= nil and not finite(value) then error('Unsupported pending particle.') end
        frame.pending[#frame.pending+1] = value == nil and nan or value
      end
    end
  end
  return frame
end

local function value(frame, index, key)
  return tonumber(frame.data[(index-1)*stride+fieldIndex[key]])
end

local function visible(frame, index, key, previous)
  local alpha=value(frame,index,'ki') == 9 and frame.sparkAlpha or frame.debrisAlpha
  return value(frame,index,previous)*(1-alpha) + value(frame,index,key)*alpha
end

local interpolationPairs={{'px','ppx'},{'py','ppy'},{'pz','ppz'},{'roll','proll'}}

local function interpolate(cache, alpha)
  local frame,later=cache.frame,cache.later
  for i,piece in ipairs(cache.pieces) do
    local nextIndex=cache.mapping[frame.ids[i]]
    for _,pair in ipairs(interpolationPairs) do
      local p=visible(frame,i,pair[1],pair[2])
      if nextIndex then p=p+(visible(later,nextIndex,pair[1],pair[2])-p)*alpha end
      piece[pair[1]],piece[pair[2]]=p,p
    end
    if nextIndex then
      local ttl,age=value(frame,i,'ttl'),value(frame,i,'age')
      piece.ttl=ttl+(value(later,nextIndex,'ttl')-ttl)*alpha
      piece.age=age+(value(later,nextIndex,'age')-age)*alpha
    end
  end
  cache.alpha=alpha
end

local function apply(frame, later, alpha, preview)
  local c = binding.cells
  local current, count = read(c.actives), read(c.activeCount)
  if preview and applyCache and applyCache.frame==frame and applyCache.later==later then
    local valid=true
    for _,piece in ipairs(applyCache.pieces) do
      if current[piece.ai]~=piece then valid=false; break end
    end
    if valid then
      if applyCache.alpha~=alpha then interpolate(applyCache,alpha) end
      return
    end
  end
  local wanted,existing,mapping={}, {}, {}
  local otherDebris,wantedDebris=0,0
  for i=1,count do
    local piece=current[i]
    if piece.vid~=id then
      if piece.ki~=9 then otherDebris=otherDebris+1 end
    elseif identities[piece] then existing[identities[piece]]=piece end
  end
  for i,identity in ipairs(frame.ids) do
    wanted[identity]=true
    if value(frame,i,'ki')~=9 then wantedDebris=wantedDebris+1 end
  end
  if otherDebris+wantedDebris>4000 then error('Restored debris exceeds the simulator capacity.') end
  if later then for i,identity in ipairs(later.ids) do mapping[identity]=i end end

  -- The engine disallows private scalar writes. Use the simulator's own
  -- removal/spawn/queue functions so its counters remain internally consistent.
  -- Only the first seek and final restore clear this vehicle's pending queue.
  -- Intermediate seeks reuse piece objects and allocate only actual births.
  if not preview or not applyCache then
    binding.clearVehicle(id)
    existing={}
  else
    for i=read(c.activeCount),1,-1 do
      local piece=current[i]
      if piece.vid==id and not wanted[identities[piece]] then
        binding.removeActive(i)
      end
    end
  end
  local cfg=read(c.cfg)
  local staticCap,movingCap,sparkCap=cfg.staticCap,cfg.movingCap,cfg.sparkCap
  -- Synchronous placeholders must not retire unrelated vehicles' debris.
  cfg.staticCap,cfg.movingCap,cfg.sparkCap=10001,10001,10001
  local pieces={}
  local ok,err=pcall(function()
    for i,identity in ipairs(frame.ids) do
      local actual=existing[identity]
      if not actual then
        local previous=read(c.activeCount)
        local ki,x,y,z,nid=value(frame,i,'ki'),value(frame,i,'px'),value(frame,i,'py'),value(frame,i,'pz'),value(frame,i,'nid')
        if nid~=nid then nid=nil end
        if ki==9 then binding.spawnSpark(id,x,y,z,0,0,0,1,1,nid)
        else binding.spawnPiece(id,ki,x,y,z,0,0,0,0,1,nid) end
        if read(c.activeCount)~=previous+1 then error('Historical particle allocation was rejected.') end
        actual=read(c.actives)[previous+1]
      end
      local ai=actual.ai
      for key in pairs(actual) do actual[key]=nil end
      actual.ai,actual.vid,actual.tri,actual.pp=ai,id,frame.refs[i][1],frame.refs[i][2]
      for j,key in ipairs(fields) do
        local number=tonumber(frame.data[(i-1)*stride+j-1])
        if number==number then actual[key]=number end
      end
      actual.resting=value(frame,i,'resting')==1
      identities[actual]=identity; pieces[i]=actual
    end
  end)
  cfg.staticCap,cfg.movingCap,cfg.sparkCap=staticCap,movingCap,sparkCap
  if not ok then error(err) end
  applyCache=preview and {frame=frame,later=later,pieces=pieces,mapping=mapping} or nil
  if preview then interpolate(applyCache,alpha) end
  -- Rebuild indices from the merged population, retaining other vehicles'
  -- actual piece objects. While paused, same-sample interpolation only updates
  -- drawing fields; caches are rebuilt on sample changes and final restoration.
  local env=read(c.env)
  env.clear()
  local merged=read(c.actives)
  for i,piece in ipairs(merged) do
    piece.ai,piece.gk,piece.gi=i,nil,nil
    if piece.resting then
      env.settled(piece)
      if piece.ki~=3 then env.gadd(piece,piece.px,piece.py) end
    end
  end
  if not preview then
    local spawnClock=read(c.spawnClock)
    for base=0,#frame.pending-1,12 do
      local row={}
      for col=1,12 do
        local number=frame.pending[base+col]
        if number==number then row[col]=col==1 and (spawnClock+number-frame.spawnClock) or number end
      end
      binding.queuePending(unpack(row,1,12))
    end
  end
  -- Prevent a restored wheel from sweeping across its abandoned future path.
  local wheelPrev=read(c.wheelPrev)
  for key in pairs(wheelPrev) do
    if type(key)=='number' and math.floor(key/4096)==id then wheelPrev[key]=nil end
  end
end

local function refresh()
  if extensions and extensions.hookUpdate then
    extensions.hookUpdate('onPreRender'); extensions.hookUpdate('onVehicleResetted')
  end
end

local function releaseGates()
  for _,gate in ipairs(gates) do
    gate.active=false
    if gate.target[gate.name]==gate.wrapper then gate.target[gate.name]=gate.original end
  end
  gates={}; refresh()
end

local function gate(name, callback)
  local entry={target=binding.target,name=name,original=binding.target[name],active=true}
  entry.wrapper=function(...)
    if entry.active then return callback(entry.original,...) end
    return entry.original(...)
  end
  entry.target[name]=entry.wrapper; gates[#gates+1]=entry
end

local function installGates()
  for _,name in ipairs({'burst','sparks','rubber','tireStrip'}) do
    gate(name,function(original,vehicleId,...)
      if phase=='rewinding' and vehicleId==id then return end
      return original(vehicleId,...)
    end)
  end
  gate('onVehicleResetted',function(original,vehicleId,...)
    if phase~='idle' and vehicleId==id then return end
    return original(vehicleId,...)
  end)
  gate('onPreRender',function(original,...)
    if phase~='rewinding' then return original(...) end
    local pos=core_camera and core_camera.getPosition and core_camera.getPosition()
    if pos then
      local ok,err=pcall(binding.draw,pos,1,1)
      if not ok then fail('particle drawing failed: '..tostring(err)) end
    end
  end)
  refresh()
end

local function choose(secondsAgo)
  local target=clock-math.max(0,tonumber(secondsAgo) or 0)
  local first=history[1] or live
  local a,b=first,live or history[#history]
  for _,frame in ipairs(history) do
    if frame.time<=target then a=frame else b=frame; break end
  end
  a=a or b; b=b or a
  local alpha=b.time>a.time and math.max(0,math.min(1,(target-a.time)/(b.time-a.time))) or 0
  return a,b,alpha,target
end

abort = function()
  local sameVehicle=not vehicleRef or (be and be:getObjectByID(id)==vehicleRef)
  if phase=='rewinding' and live and binding and mod()==binding.target and sameVehicle then
    local ok,err=pcall(apply,live,nil,0,false)
    if not ok then reason=tostring(err) end
  end
  phase,grace,live,applyCache='idle',0,nil,nil
  releaseGates()
end

fail = function(err)
  abort()
  binding=nil; history={}; bytes=0
  reason='Dynamic Damage Particles adapter unavailable: '..tostring(err)
  return false
end

local function configure(vehicleId,token,seconds)
  if seconds == 20 or seconds == 40 or seconds == 60 then maxSeconds = seconds end
  abort()
  id,session=vehicleId,token
  vehicleRef=be and be:getObjectByID(id) or nil
  clock,sampleClock,bytes=0,0,0
  discoveryClock=0
  history,identities={},setmetatable({}, {__mode='k'})
  nextIdentity=0
  local ok,result=pcall(discover)
  binding=ok and result or nil
  reason=binding and 'Sampled Dynamic Damage Particles history.' or 'Dynamic Damage Particles 2.0 state layout not available.'
  if binding then
    local captured,frame=pcall(capture)
    if not captured then return fail(frame) end
    history[1],bytes=frame,frame.bytes
  end
  return binding~=nil
end

local function record(dtSim)
  if not finite(dtSim) or dtSim<=0 then return false end
  if not binding then
    -- Optional modScripts can load after the player's initial configuration.
    -- Observe a loaded module without triggering BeamNG's lazy module loader.
    discoveryClock=discoveryClock+dtSim
    if discoveryClock<1 then return false end
    discoveryClock=0
    if type(mod())~='table' or not configure(id,session) then return false end
  end
  if mod()~=binding.target or phase=='rewinding' then return false end
  clock,sampleClock=clock+dtSim,sampleClock+dtSim
  if sampleClock<interval then return true end
  sampleClock=sampleClock%interval
  local ok,frame=pcall(capture)
  if not ok then return fail(frame) end
  history[#history+1]=frame; bytes=bytes+frame.bytes
  return true
end

local function begin(vehicleId,token)
  if vehicleId~=id or token~=session or not binding or mod()~=binding.target then return false end
  if phase=='rewinding' then return true end
  releaseGates()
  local ok,frame=pcall(capture)
  if not ok then return fail(frame) end
  live=frame; phase='rewinding'; applyCache=nil
  installGates()
  return true
end

local function seek(secondsAgo)
  if phase~='rewinding' or not live then return false end
  local a,b,alpha=choose(secondsAgo)
  local ok,err=pcall(apply,a,b,alpha,true)
  if not ok then return fail(err) end
  return true
end

local function finish(secondsAgo,cancel)
  if phase~='rewinding' or not live then return false end
  local frame,_,_,target=choose(secondsAgo)
  if cancel then frame=live end
  local ok,err=pcall(apply,frame,nil,0,false)
  if not ok then return fail(err) end
  live=nil
  if not cancel then
    while #history>0 and history[#history].time>target do
      bytes=bytes-history[#history].bytes; history[#history]=nil
    end
    clock=math.max(0,target); sampleClock=0
  end
  phase,grace='settling',2
  return true
end

local function onUpdate()
  if binding and mod()~=binding.target then fail('the effects extension was replaced'); return end
  if phase=='settling' then
    grace=grace-1
    if grace<=0 then phase='idle'; releaseGates() end
  end
end

local function reset() return configure(id,session) end
M.configure,M.record,M.begin,M.seek,M.finish=configure,record,begin,seek,finish
M.abort,M.reset,M.onUpdate=abort,reset,onUpdate
M.getStatus=function() return {supported=binding~=nil, message=reason,
  availableSeconds=history[1] and math.max(0,clock-history[1].time) or 0,
  bytes=bytes+(live and live.bytes or 0), budgetBytes=budget, sampleHz=1/interval} end
M.onExtensionUnloaded,M.onClientEndMission=abort,abort
M.onSerialize=function() abort(); history={}; bytes=0; return {} end
return M
