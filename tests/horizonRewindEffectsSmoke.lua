-- Full-game compatibility proof with the user's unmodified optional mod ZIPs.
-- Seeds oil through Fluid Spill's public placement API and uses stock recovery.
local M = {}
local timer, elapsed, stage = 0, 0, 'boot'
local events, latest, probes, checks = {}, {}, {}, {}
local hook, original, carId, travelStart, liveFluid, previewFluid
local begunAt, simElapsed, operation = nil, 0, 0
local ddp, activeParticles, activeCount, otherPiece, liveParticles
local seededSpark, seededLate, sawPastSpark = false, false, false
local otherOwner = -774001 -- isolated ownership key; no second physical car needed

local function namedState(fn,wanted,seen)
  seen=seen or {}; if seen[fn] then return end; seen[fn]=true
  for index=1,160 do
    local name,value=debug.getupvalue(fn,index); if not name then break end
    if name==wanted then return function() return select(2,debug.getupvalue(fn,index)) end end
    if type(value)=='function' then
      local found=namedState(value,wanted,seen); if found then return found end
    end
  end
end

local function particleState()
  local result={debris=0,sparks=0,other=0,otherSame=true}
  local pieces=activeParticles()
  for i=1,activeCount() do
    local piece=pieces[i]
    if piece.vid==carId then
      local field=piece.ki==9 and 'sparks' or 'debris'; result[field]=result[field]+1
    elseif piece.vid==otherOwner then
      result.other=result.other+1
      if not otherPiece then otherPiece=piece end
      result.otherSame=result.otherSame and piece==otherPiece
    end
  end
  return result
end

local function seedParticles(car,owner,count,sparks)
  local p=car:getPosition()
  -- Public simulator emissions, in clear air alongside the moving test car.
  if sparks then ddp.sparks(owner,p.x+20,p.y+20,p.z+8,8,0,0,count,20,nil)
  else ddp.burst(owner,p.x+20,p.y+20,p.z+8,8,0,0,count,0,0,0,0,0,0,0,0,nil,1) end
end

local function fluidState()
  local module = rawget(extensions, 'fluidspill_main')
  local litres, count = 0, 0
  for _, chunk in ipairs(module.mpOwnChunks(120)) do
    for _, puddle in ipairs(chunk.p) do litres, count = litres + puddle.vol, count + 1 end
  end
  return {litres = litres, puddles = count}
end

local function report(ok, detail)
  local fluids = rawget(extensions, 'horizonRewindFluids')
  local particles = rawget(extensions, 'horizonRewindParticles')
  jsonWriteFile('horizon-rewind-effects-smoke.json', {ok=ok, detail=detail, stage=stage,
    elapsedSeconds=timer, checks=checks, events=events, probes=probes,
    fluidStatus=fluids and fluids.getStatus(), particleStatus=particles and particles.getStatus()}, true)
end

local function done(ok, detail)
  if stage == 'done' then return end
  stage='done'; report(ok,detail); log(ok and 'I' or 'E','HR_EFFECTS_SMOKE',detail)
  shutdown(ok and 0 or 1)
end

local function advance(nextStage)
  stage,elapsed=nextStage,0
  log('I','HR_EFFECTS_SMOKE',nextStage)
  report(nil,'Running')
end

local function update(realDt,simDt)
  if stage=='done' then return end
  timer,elapsed=timer+(realDt or 0),elapsed+(realDt or 0)
  if timer>100 or elapsed>30 then done(false,'Timeout at '..stage); return end
  local car=be:getPlayerVehicle(0)
  if stage=='boot' then
    if not car or not rawget(extensions,'horizonRewind') or not rawget(extensions,'fluidspill_main') then return end
    if not rawget(extensions,'horizonRewindFluids') then return end
    local status=extensions.horizonRewindFluids.getStatus()
    if not status.supported then
      if elapsed>10 then done(false,'Fluid adapter unsupported: '..tostring(status.reason)) end
      return
    end
    local particleAdapter=rawget(extensions,'horizonRewindParticles')
    if not particleAdapter or not particleAdapter.getStatus().supported then
      if elapsed>10 then done(false,'Dynamic Damage Particles adapter unsupported') end
      return
    end
    ddp=rawget(extensions,'crashDebris') or crashDebris
    activeParticles=assert(namedState(ddp.onPreRender,'actives'),'DDP active table missing')
    activeCount=assert(namedState(ddp.onPreRender,'activeCount'),'DDP active counter missing')
    carId=car:getID()
    original=extensions.horizonRewind.onVehicleMessage
    hook=function(id,token,event,data)
      original(id,token,event,data)
      if id~=carId then return end
      data=data or {}; latest[event]=data
      if event~='recording' and event~='previewed' then events[#events+1]={time=timer,event=event,data=data} end
      if event=='began' then
        begunAt=timer
        -- The live snapshot is taken after the native hold threshold, while
        -- tires may still have displaced oil between key-down and takeover.
        liveFluid=fluidState(); checks['live'..operation]=liveFluid
        liveParticles=particleState(); checks['particleLive'..operation]=liveParticles
      elseif event=='previewed' and begunAt then
        local state=particleState()
        if state.sparks>0 and liveParticles and liveParticles.sparks==0 then sawPastSpark=true end
        if state.other~=1 or not state.otherSame then latest.error={message='Unrelated particle identity changed while rewinding'} end
      end
    end
    extensions.horizonRewind.onVehicleMessage=hook
    advance('wait-for-vehicle-helper')
  elseif stage=='wait-for-vehicle-helper' then
    if not latest.recording then return end
    car:queueLuaCommand([[
      local fluid = extensions.horizonRewindFluids
      local snapshot = fluid and fluid.capture and fluid.capture()
      local effects = extensions.horizonRewindEffects
      obj:queueGameEngineLua('extensions.horizonRewindEffectsSmoke.vehicleProbe('..serialize({id=obj:getId(),fluidLoaded=fluid~=nil,fluidSnapshot=snapshot~=nil,effectsLoaded=effects~=nil})..')')
    ]])
    advance('wait-for-probe')
  elseif stage=='wait-for-probe' then
    if not probes.vehicle then return end
    if not probes.vehicle.fluidSnapshot then done(false,'Vehicle-side Fluid Spill snapshot compatibility unavailable'); return end
    if not probes.vehicle.effectsLoaded then done(false,'Vehicle-side particle emission guard unavailable'); return end
    seedParticles(car,carId,4,false); seedParticles(car,otherOwner,1,false)
    car:queueLuaCommand('input.event("parkingbrake",0,1); input.event("brake",0,1); input.event("throttle",0.25,1)')
    local dir=car:getDirectionVector(); dir.z=0; dir:normalize()
    car:applyClusterVelocityScaleAdd(car:getRefNodeId(),0,dir.x*12,dir.y*12,0)
    travelStart=vec3(car:getPosition()); simElapsed=0
    extensions.fluidspill_main.startPlacing('oil')
    advance('pour-and-drive')
  elseif stage=='pour-and-drive' or stage=='pour-second-trail' then
    simElapsed=simElapsed+(simDt or 0)
    if simElapsed>.8 and not seededSpark then seedParticles(car,carId,8,true); seededSpark=true end
    if simElapsed>1.8 and not seededLate then seedParticles(car,carId,3,false); seededLate=true end
    particleState() -- retain the unrelated piece's original object identity
    if simElapsed<2.5 or not latest.recording or latest.recording.availableSeconds<1.5 then return end
    extensions.fluidspill_main.stopPlacing()
    liveFluid=fluidState()
    if liveFluid.litres<.5 or liveFluid.puddles<2 then done(false,'Public fluid placement did not create a moving oil trail'); return end
    operation=operation+1; checks['live'..operation]=liveFluid
    begunAt=nil; latest.began=nil; latest.restored=nil; latest.previewed=nil
    car:queueLuaCommand('recovery.startRecovering()')
    advance('hold-'..operation)
  elseif stage=='hold-1' or stage=='hold-2' then
    if not begunAt or timer-begunAt<1.6 or not latest.previewed then return end
    previewFluid=fluidState(); checks['preview'..operation]=previewFluid
    if previewFluid.litres>=liveFluid.litres-.15 then
      done(false,'Fluid world state did not rewind: live='..liveFluid.litres..' preview='..previewFluid.litres); return
    end
    if not extensions.horizonRewindFluids.getStatus().active then done(false,'Fluid adapter was not active during held rewind'); return end
    local particlePreview=particleState(); checks['particlePreview'..operation]=particlePreview
    checks['pastSparksReturned'..operation]=sawPastSpark
    if liveParticles.sparks~=0 then done(false,'Seeded sparks did not expire before live capture'); return end
    if particlePreview.debris>=liveParticles.debris then done(false,'Future particle births remained after seeking backwards'); return end
    if not sawPastSpark then done(false,'Expired sparks did not reappear while seeking through history'); return end
    if particlePreview.other~=1 or not particlePreview.otherSame then done(false,'Unrelated particle changed during seek'); return end
    if operation==1 then extensions.horizonRewind.cancelRewind() end
    car:queueLuaCommand('recovery.stopRecovering(0)')
    advance('restore-'..operation)
  elseif stage=='restore-1' or stage=='restore-2' then
    if not latest.restored or simTimeAuthority.getPause() then return end
    local restored=fluidState(); checks['restored'..operation]=restored
    local particleRestored=particleState(); checks['particleRestored'..operation]=particleRestored
    if particleRestored.other~=1 or not particleRestored.otherSame then done(false,'Unrelated particle changed during restoration'); return end
    if extensions.horizonRewindFluids.getStatus().active then done(false,'Fluid adapter remained frozen after release'); return end
    if operation==1 then
      if not latest.restored.cancelled then done(false,'Cancel was not acknowledged'); return end
      if math.abs(restored.litres-liveFluid.litres)>.03 or restored.puddles~=liveFluid.puddles then
        done(false,'Cancel did not restore the exact live fluid world'); return
      end
      if particleRestored.debris~=liveParticles.debris or particleRestored.sparks~=liveParticles.sparks then
        done(false,'Cancel did not restore live player particle population'); return
      end
      simElapsed=0
      seededSpark,seededLate,sawPastSpark=false,false,false
      extensions.fluidspill_main.startPlacing('oil')
      advance('pour-second-trail')
    else
      if latest.restored.cancelled then done(false,'Commit unexpectedly cancelled'); return end
      if restored.litres>=liveFluid.litres-.15 then done(false,'Commit retained future oil marks'); return end
      if math.abs(restored.litres-previewFluid.litres)>.5 then done(false,'Committed fluid world disagrees with final preview'); return end
      if particleRestored.debris>=liveParticles.debris then done(false,'Commit retained future particle births'); return end
      travelStart=vec3(car:getPosition()); simElapsed=0
      advance('resumed')
    end
  elseif stage=='resumed' then
    simElapsed=simElapsed+(simDt or 0)
    if simElapsed<.5 then return end
    checks.resumedDistance=travelStart:distance(vec3(car:getPosition()))
    if checks.resumedDistance<.1 then done(false,'Vehicle did not resume motion after fluid rewind'); return end
    if simTimeAuthority.getPause() then done(false,'Simulation remained paused'); return end
    done(true,'Installed Fluid Spill and Dynamic Damage Particles autoloaded; native holds reversed oil trails and debris births, resurrected expired sparks, preserved unrelated particles, restored live state on cancel, removed future effects on commit, and resumed driving.')
  end
  if latest.error then done(false,'Vehicle rewind error: '..tostring(latest.error.message)) end
end

M.vehicleProbe=function(value) probes.vehicle=value end
M.onExtensionLoaded=function() setExtensionUnloadMode(M,'manual') end
M.onUpdate=function(realDt,simDt) local ok,err=pcall(update,realDt,simDt); if not ok then done(false,tostring(err)) end end
return M
