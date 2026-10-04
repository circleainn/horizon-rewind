local M={}
local stage,timer,elapsed,simElapsed='boot',0,0,0
local latest,events,samples,checks={}, {}, {}, {}
local reloaded,carId,operation,previewRequests=false,nil,0,0
local model=rawget(_G,'hrTireSmokeModel') or 'pickup'
local targets={.8,2.5,2.5}
local function report(ok,detail)
  jsonWriteFile('horizon-rewind-tire-smoke.json',{ok=ok,detail=detail,model=model,stage=stage,events=events,samples=samples,checks=checks},true)
end
local function done(ok,detail)
  if stage=='done' then return end
  stage='done';report(ok,detail);log(ok and 'I' or 'E','HR_TIRE_SMOKE',detail);shutdown(ok and 0 or 1)
end
local function advance(name) stage,elapsed=name,0;report(nil,'Running') end
local function command(code) be:getPlayerVehicle(0):queueLuaCommand(code) end
local function ask(tag) command('extensions.horizonRewindTireProbe.sample('..string.format('%q',tag)..')') end
local function begin()
  operation=operation+1;latest.began=nil;latest.previewed=nil;latest.restored=nil
  command('recovery.startRecovering()')
  advance('hold')
end
local function update(dtReal,dtSim)
  if stage=='done' then return end
  timer,elapsed=timer+(dtReal or 0),elapsed+(dtReal or 0)
  if timer>150 or elapsed>35 then done(false,'Timeout at '..stage);return end
  local car=be:getPlayerVehicle(0)
  if stage=='boot' then
    if not car or not rawget(extensions,'horizonRewind') or not core_gamestate or core_gamestate.state.state~='freeroam' then return end
    if not reloaded then
      reloaded=true
      if model=='pickup' then core_vehicle_manager.reloadVehicle(0) else core_vehicles.replaceVehicle(model) end
      return
    end
    if car:getJBeamFilename()~=model then return end
    carId=car:getID();local original=extensions.horizonRewind.onVehicleMessage
    extensions.horizonRewind.onVehicleMessage=function(id,token,event,data)
      original(id,token,event,data)
      if id~=carId then return end
      data=data or {};latest[event]=data
      if event~='recording' and event~='previewed' then events[#events+1]={event=event,data=data,time=timer} end
      if event=='began' then command('extensions.horizonRewindTireProbe.setTracking(false)') end
      if event=='previewed' then
        previewRequests=previewRequests+1
        if previewRequests%4==0 then ask('preview-'..operation..'-'..previewRequests) end
      end
    end
    advance('recording')
  elseif stage=='recording' then
    if not latest.recording then return end
    command("extensions.load('horizonRewindTireProbe'); extensions.horizonRewindTireProbe.prepare()")
    advance('prepared')
  elseif stage=='prepared' then
    local value=samples.prepared;if not value then return end
    if value.groups.tread.count<16 or value.groups.helper.count<16 then done(false,'Actual tire tread/helper topology missing');return end
    if not value.adapter or not value.adapter.detachable or not value.adapter.puncture then done(false,'Installed tire compatibility adapter did not recognize both real mods');return end
    command('input.event("parkingbrake",0,1); input.event("brake",0,1); input.event("throttle",0.35,1)')
    local dir=car:getDirectionVector();dir.z=0;dir:normalize()
    car:applyClusterVelocityScaleAdd(car:getRefNodeId(),0,dir.x*20,dir.y*20,0)
    simElapsed=0;advance('attached-drive')
  elseif stage=='attached-drive' then
    simElapsed=simElapsed+(dtSim or 0)
    if simElapsed<3 or latest.recording.availableSeconds<2.5 then return end
    ask('attached-live');begin()
  elseif stage=='hold' then
    if not latest.previewed or (latest.previewed.rewindSeconds or 0)<targets[operation] then return end
    ask('selected-'..operation)
    if operation<=2 then extensions.horizonRewind.cancelRewind() end
    command('recovery.stopRecovering(0)');advance('restore')
  elseif stage=='restore' then
    if not latest.restored or simTimeAuthority.getPause() then return end
    ask('restored-'..operation);simElapsed=0;advance('settle')
  elseif stage=='settle' then
    simElapsed=simElapsed+(dtSim or 0)
    if simElapsed<1 then return end
    ask('settled-'..operation);advance('verify')
  elseif stage=='verify' then
    local state=samples['settled-'..operation];if not state then return end
    if operation==1 then
      if state.detached or state.deflated then done(false,'Healthy tire changed attachment/pressure after cancel');return end
      command('extensions.horizonRewindTireProbe.setTracking(true); extensions.horizonRewindTireProbe.detach()')
      simElapsed=0;advance('detached-drive')
    elseif operation==2 then
      if not state.detached or not state.deflated then done(false,'Cancel lost detached tire state after delayed reset normalization');return end
      local live=samples['detached-live']
      if not state.replacement or state.treadFlags.selfCollision~=live.treadFlags.selfCollision or state.collisionLedgerNodes~=live.collisionLedgerNodes then done(false,'Cancel lost detached tire visual/collision ownership');return end
      if math.abs(state.pressure-live.pressure)>500 or state.adapter.collisionPending then done(false,'Cancel did not finish restoring detached pressure/collision state');return end
      -- Record one extra second, then seek sufficiently far before detachment.
      targets[3]=6;simElapsed=0;advance('cancelled-detached-drive')
    else
      if state.detached or state.deflated then done(false,'Commit before detach failed to restore attached inflated tire');return end
      if state.pressure<samples.prepared.pressure*.8 then done(false,'Commit left historical attached tire pressure too low');return end
      if state.replacement or state.collisionLedgerNodes~=0 or state.treadFlags.selfCollision~=samples.prepared.treadFlags.selfCollision or state.adapter.collisionPending then done(false,'Commit did not restore attached tire visual/collision ownership');return end
      done(true,'Native attached/loose tire previews, cancellation and rewind across detachment preserved geometry and restored tire state after the mod delayed reset window.')
    end
  elseif stage=='detached-drive' then
    if samples['detached-command'] and not samples['detached-command'].ok then done(false,'Installed public detach command refused');return end
    simElapsed=simElapsed+(dtSim or 0)
    if simElapsed<1.5 then return end
    ask('detached-live');begin()
  elseif stage=='cancelled-detached-drive' then
    simElapsed=simElapsed+(dtSim or 0)
    if simElapsed<1 then return end
    begin()
  end
  if latest.error then done(false,'Recorder error: '..tostring(latest.error.message)) end
end
M.receive=function(value)
  samples[value.tag]=value
  if value.tag:find('preview-',1,true) then
    for name,g in pairs(value.groups or {}) do
      local b=value.bounds[name]
      if b and b.samples>2 and g.count>0 then
        local before=value.bracket and value.bracket.aGroups[name]
        local after=value.bracket and value.bracket.bGroups[name]
        local maximum=before and math.max(before.maxEdgeRatio,after.maxEdgeRatio) or b.maxEdgeRatio
        local maximumRadius=before and math.max(before.maxRadius,after.maxRadius) or b.maxRadius
        local minimumRms=before and math.min(before.rms,after.rms) or b.minRms
        local ratio=g.maxEdgeRatio/(maximum+1e-8)
        checks.maximumPreviewEdgeGrowth=math.max(checks.maximumPreviewEdgeGrowth or 0,ratio)
        if ratio>1.5 or g.maxRadius>maximumRadius*1.5+.05 then done(false,'Rewind stretched actual '..name..' geometry beyond recorded bracket');return end
        if g.rms<minimumRms*.75 then done(false,'Actual '..name..' collapsed below both recorded bracket frames');return end
      end
    end
  end
end
M.onUpdate=function(...) local ok,err=pcall(update,...);if not ok then done(false,tostring(err)) end end
M.onExtensionLoaded=function() setExtensionUnloadMode(M,'manual') end
return M
