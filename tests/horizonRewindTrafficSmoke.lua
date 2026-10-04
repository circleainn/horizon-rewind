local M = {}
local phase, timer, total = 'boot', 0, 0
local player, other, mod, events, results = nil, nil, nil, {}, {}
local resumeReply
local delayedPreview
local function finish(ok, message)
  phase = 'done'
  jsonWriteFile('horizon-rewind-traffic.json', {ok=ok, message=message, results=results, events=events}, true)
  shutdown(ok and 0 or 1)
end
local function advance(value)
  phase, timer = value, 0
  jsonWriteFile('horizon-rewind-traffic-progress.json', {phase=phase, total=total, events=events}, true)
end
local function pos(car) return vec3(car:getPosition()) end
local function distance(car, point) return pos(car):distance(vec3(point)) end
local function coords(car) local p=pos(car);return {p.x,p.y,p.z} end
local function update(real, sim)
  if phase == 'done' then return end
  total, timer = total+real, timer+real
  if delayedPreview and total>=delayedPreview.due then
    local d=delayedPreview;delayedPreview=nil
    d.deliver(d.id,d.token,d.event,d.data)
    events[d.id][d.event]=d.data
  end
  if total > 100 then error('Timeout at '..phase) end
  if phase == 'boot' then
    player = be:getPlayerVehicle(0)
    mod = extensions.horizonRewind
    if not player or not mod or core_gamestate.state.state ~= 'freeroam' then return end
    local original = mod.onVehicleMessage
    mod.onVehicleMessage = function(id, token, event, data)
      if event=='previewed' and other and id==other:getID() and phase=='cancelSeek' then
        delayedPreview={due=total+.18,deliver=original,id=id,token=token,event=event,data=data}
        return
      end
      if event=='previewed' and id==player:getID() and delayedPreview then
        results.playerFramesWhileTrafficPending=(results.playerFramesWhileTrafficPending or 0)+1
      end
      original(id, token, event, data)
      events[id] = events[id] or {};events[id][event] = data or {}
      if event == 'error' then error('Vehicle '..id..': '..tostring(data.message)) end
    end
    other = core_vehicles.spawnNewVehicle('covet', {pos=pos(player)+vec3(12,0,0),rot=quat(0,0,0,1),autoEnterVehicle=false})
    advance('spawn')
  elseif phase == 'spawn' and timer > 3 then
    assert(other and other:getID() ~= player:getID(), 'Traffic vehicle missing')
    gameplay_traffic.insertTraffic(other:getID(), false, true)
    local entry=gameplay_traffic.getTrafficData()[other:getID()]
    entry.enableRespawn,entry.enableAutoPooling=false,false
    -- Keep the traffic registration/AI settings while using a deterministic
    -- straight-line coast on smallgrid (which has no traffic road graph).
    other:queueLuaCommand("ai.setMode('disabled'); input.event('parkingbrake',0,1)")
    player:queueLuaCommand("input.event('parkingbrake',0,1)")
    mod.setHistorySeconds(60);mod.setTrafficEnabled(true);mod.setSpeed(1)
    advance('settle')
  elseif phase == 'settle' and timer > 2 then
    local drive="ai.setMode('disabled'); controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('brake',0,1); input.event('throttle',1,1)"
    player:queueLuaCommand(drive);other:queueLuaCommand(drive)
    advance('drive')
  elseif phase == 'drive' and timer > 7 then
    local duration,count = extensions.horizonRewindTraffic.status(60)
    assert(count==1 and duration>3, 'Traffic history unavailable: '..count..' / '..duration)
    results.duration,results.count=duration,count
    results.livePlayer,results.liveTraffic=coords(player),coords(other)
    results.liveSpeed=vec3(other:getVelocity()):length()
    assert(results.liveSpeed>5,'Traffic test drive did not build road speed')
    mod.beginRewind();advance('cancelSeek')
  elseif phase == 'cancelSeek' and events[other:getID()] and events[other:getID()].previewed
    and events[other:getID()].previewed.rewindSeconds > 1.5 then
    assert(distance(other, results.liveTraffic)>5,'Traffic did not move backward')
    assert((results.playerFramesWhileTrafficPending or 0)>=3,'Slow traffic stalled player preview')
    results.previewDistance=distance(other,results.liveTraffic)
    mod.cancelRewind();advance('cancel')
  elseif phase == 'cancel' and not simTimeAuthority.getPause() then
    results.cancelDistance=distance(other,results.liveTraffic)
    assert(distance(other,results.liveTraffic)<3,'Cancel failed to restore traffic')
    results.cancelDistance=distance(other,results.liveTraffic)
    events[other:getID()].previewed=nil
    mod.beginRewind();advance('commitSeek')
  elseif phase == 'commitSeek' and events[other:getID()].previewed and events[other:getID()].previewed.rewindSeconds>1.5 then
    results.commitPose=coords(other)
    mod.endRewind();advance('commit')
  elseif phase == 'commit' and not simTimeAuthority.getPause() then
    results.commitDistance=distance(other,results.commitPose)
    assert(distance(other,results.commitPose)<3,'Traffic release jumped away from preview')
    local velocity=events[other:getID()].restored.velocity
    results.expectedResumeSpeed=math.sqrt(velocity[1]^2+velocity[2]^2+velocity[3]^2)
    advance('resuming')
  elseif phase == 'resuming' and timer>.2 then
    other:queueLuaCommand("obj:queueGameEngineLua('extensions.horizonRewindTrafficSmoke.receive('..serialize({speed=obj:getVelocity():length(),mode=ai.mode})..')')")
    advance('resumeReply')
  elseif phase == 'resumeReply' and resumeReply then
    results.resumedSpeed=resumeReply.speed
    assert(resumeReply.speed > results.expectedResumeSpeed*.8 and resumeReply.speed < results.expectedResumeSpeed*1.3,
      'Traffic physical momentum out of range: '..resumeReply.speed..' expected '..results.expectedResumeSpeed)
    mod.setTrafficEnabled(false)
    local _,count=extensions.horizonRewindTraffic.status(60)
    assert(count==0,'Traffic recorder not detached')
    finish(true,'Traffic preview, cancellation, synchronized restore and velocity passed with 60-second configuration')
  end
end
M.onUpdate=function(...) local ok,err=pcall(update,...);if not ok then finish(false,tostring(err)) end end
M.onExtensionLoaded=function() setExtensionUnloadMode(M,'manual') end
M.receive=function(data) resumeReply=data end
return M
