-- Isolated native test of historical broken-beam replay with installed DDP.
local M={}
local stage,timer,elapsed,simElapsed='boot',0,0,0
local events,latest,probes={}, {}, {}
local carId,reloaded

local function report(ok,detail)
  jsonWriteFile('horizon-rewind-damage-effects-smoke.json',{
    ok=ok,detail=detail,stage=stage,events=events,probes=probes,latest=latest},true)
end
local function done(ok,detail)
  if stage=='done' then return end
  stage='done';report(ok,detail)
  log(ok and 'I' or 'E','HR_DAMAGE_EFFECTS',detail);shutdown(ok and 0 or 1)
end
local function advance(value) stage,elapsed=value,0;report(nil,'Running') end

local function update(dtReal,dtSim)
  if stage=='done' then return end
  timer,elapsed=timer+(dtReal or 0),elapsed+(dtReal or 0)
  if timer>90 or elapsed>25 then done(false,'Timeout at '..stage);return end
  local car=be:getPlayerVehicle(0)
  if stage=='boot' then
    local root=extensions.horizonRewind
    local particles=extensions.horizonRewindParticles
    probes.boot={car=car and car:getID(),root=root~=nil,particles=particles and particles.getStatus(),
      ddpGlobal=type(crashDebris),ddpRawGlobal=type(rawget(_G,'crashDebris')),ddpRawExtension=type(rawget(extensions,'crashDebris'))}
    if not car or not root or not particles or not particles.getStatus().supported then return end
    -- Headless -level can spawn its initial car before repo ZIPs are mounted.
    -- Reload once so the installed mod's ordinary vehicle auto-loader runs.
    if not reloaded then reloaded=true;core_vehicle_manager.reloadVehicle(0);return end
    carId=car:getID()
    local original=root.onVehicleMessage
    root.onVehicleMessage=function(id,token,event,data)
      original(id,token,event,data)
      if id~=carId then return end
      latest[event]=data or {}
      if event~='recording' and event~='previewed' then events[#events+1]={kind='coordinator',event=event,data=data} end
    end
    advance('wait-recording')
  elseif stage=='wait-recording' then
    if not latest.recording then return end
    car:queueLuaCommand([[
      local effect=assert(extensions.horizonRewindEffects)
      local particles=assert(rawget(_G,'crashParticles') or rawget(extensions,'crashParticles'))
      local index,physics=0,0
      local function emit(kind,id)
        index=index+1
        obj:queueGameEngineLua('extensions.horizonRewindDamageEffectsSmoke.probe('..serialize({kind=kind,id=id,index=index,physics=physics,active=effect.isActive()})..')')
      end
      local oldStep=onPhysicsStep
      onPhysicsStep=function(dt) physics=physics+1;return oldStep(dt) end
      local oldBreak=onBeamBroke
      onBeamBroke=function(id,energy)
        if id==1 or id==2 then emit('native-beam',id) end
        return oldBreak(id,energy)
      end
      local oldParticle=particles.onBeamBroke
      particles.onBeamBroke=function(id,energy)
        if id==1 or id==2 then emit('ddp-beam',id) end
        return oldParticle(id,energy)
      end
      extensions.hookUpdate('onBeamBroke')
      local oldFinish=effect.finish
      effect.finish=function(...)
        emit('before-finish');local result=oldFinish(...);emit('after-finish');return result
      end
      emit('installed');obj:breakBeam(1);emit('after-original-break',1)
    ]])
    simElapsed=0;advance('damaged-history')
  elseif stage=='damaged-history' then
    simElapsed=simElapsed+(dtSim or 0)
    if simElapsed>2 and not probes.laterBroken then
      probes.laterBroken=true;car:queueLuaCommand('obj:breakBeam(2)')
    end
    if simElapsed<3 or not latest.recording or latest.recording.availableSeconds<2.5 then return end
    latest.began=nil;latest.previewed=nil;latest.restored=nil
    car:queueLuaCommand('recovery.startRecovering()');advance('hold')
  elseif stage=='hold' then
    if not latest.previewed or (latest.previewed.rewindSeconds or 0)<1.8 then return end
    car:queueLuaCommand('recovery.stopRecovering(0)');advance('restoring')
  elseif stage=='restoring' then
    if not latest.restored or simTimeAuthority.getPause() then return end
    simElapsed=0;advance('drain-callbacks')
  elseif stage=='drain-callbacks' then
    simElapsed=simElapsed+(dtSim or 0)
    if simElapsed<.15 then return end
    car:queueLuaCommand([[
      obj:queueGameEngineLua('extensions.horizonRewindDamageEffectsSmoke.state('..serialize({beam1=obj:beamIsBroken(1),beam2=obj:beamIsBroken(2),guardActive=extensions.horizonRewindEffects.isActive()})..')')
    ]])
    advance('inspect')
  elseif stage=='inspect' then
    if not probes.state then return end
    if not probes.state.beam1 or probes.state.beam2 then done(false,'Partial damage restore did not preserve the historical broken beam');return end
    if probes.state.guardActive then done(false,'Particle guard still blocked resumed gameplay');return end
    local beforeFinish,afterFinish,restoredNative,leaked=0,0,0,0
    for _,event in ipairs(events) do
      if event.kind=='before-finish' then beforeFinish=event.index end
      if event.kind=='after-finish' then afterFinish=event.index end
      if event.kind=='native-beam' and event.id==1 and event.active then restoredNative=restoredNative+1 end
      if event.kind=='ddp-beam' and event.id==1 and afterFinish>0 and event.index>afterFinish then leaked=leaked+1 end
    end
    probes.restoreNativeCallbacks,probes.leakedRestorationCallbacks=restoredNative,leaked
    if beforeFinish==0 or afterFinish<=beforeFinish then done(false,'Effects finish callback not observed');return end
    if restoredNative<1 then done(false,'No native replay of the saved broken beam was observed');return end
    if leaked~=0 then done(false,'Historical break reached DDP after its guard finished');return end
    car:queueLuaCommand('obj:breakBeam(2)');simElapsed=0;advance('new-user-break')
  elseif stage=='new-user-break' then
    simElapsed=simElapsed+(dtSim or 0)
    if simElapsed<.1 then return end
    local afterFinish,delivered=0,0
    for _,event in ipairs(events) do
      if event.kind=='after-finish' then afterFinish=event.index end
      if afterFinish>0 and event.kind=='ddp-beam' and event.id==2 and event.index>afterFinish and not event.active then delivered=delivered+1 end
    end
    probes.resumedBreakDeliveries=delivered
    if delivered<1 then done(false,'A fresh resumed beam break did not reach DDP');return end
    done(true,'Saved broken-beam callbacks fired synchronously under the active DDP guard before finish; no delayed replay emissions, and new resumed breaks reached DDP.')
  end
  if latest.error then done(false,'Recorder error: '..tostring(latest.error.message)) end
end
M.probe=function(data) events[#events+1]=data end
M.state=function(data) probes.state=data end
M.onUpdate=function(...) local ok,err=pcall(update,...);if not ok then done(false,tostring(err)) end end
M.onExtensionLoaded=function() setExtensionUnloadMode(M,'manual') end
return M
