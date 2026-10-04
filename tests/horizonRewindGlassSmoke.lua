local M={}
local phase,timer,total='boot',0,0
local reply,events,results=nil,{},{}
local function finish(ok,message)
  phase='done';jsonWriteFile('horizon-rewind-glass.json',{ok=ok,message=message,results=results},true);shutdown(ok and 0 or 1)
end
local function advance(nextPhase)
  phase,timer=nextPhase,0
  jsonWriteFile('horizon-rewind-glass-progress.json',{phase=phase,total=total,events=events},true)
end
local function command(code) be:getPlayerVehicle(0):queueLuaCommand(code) end
local function inspect()
  reply=nil
  command([[local s=extensions.horizonRewindMaterials.capture();obj:queueGameEngineLua('extensions.horizonRewindGlassSmoke.receive('..serialize({state=s.states[hrGlassSlot],broken=s.broken[hrGlassSlot]})..')')]])
end
local function update(real,sim)
  if phase=='done' then return end
  total,timer=total+real,timer+real
  if total>95 then error('Timeout '..phase) end
  local car=be:getPlayerVehicle(0)
  if phase=='boot' then
    if not car or not extensions.horizonRewind or not core_gamestate or core_gamestate.state.state~='freeroam' then return end
    core_vehicles.replaceVehicle('covet');advance('ready')
    local original=extensions.horizonRewind.onVehicleMessage
    extensions.horizonRewind.onVehicleMessage=function(id,token,event,data) original(id,token,event,data);events[event]=data or {} end
  elseif phase=='ready' and timer>4 then
    command([[hrGlassSlot=nil;for _,b in pairs(v.data.beams) do for slot,g in pairs(b.deformSwitches or {}) do local name=(tostring(g.dmgMat)..tostring(g.mesh)..tostring(g.deformGroup)):lower();if name:find('glass') or name:find('windshield') then hrGlassBeam=b;hrGlassSlot=slot;break end end if hrGlassSlot then break end end;assert(hrGlassSlot,'No glass material slot');material.switchBrokenMaterial(hrGlassBeam)]])
    advance('damaged')
  elseif phase=='damaged' and timer>.5 then inspect();advance('damageReply')
  elseif phase=='damageReply' and reply then
    assert(reply.broken and type(reply.state)=='string','Glass damage was not applied');results.damaged=reply
    extensions.horizonRewind.beginRewind();advance('begin')
  elseif phase=='begin' and events.began then
    events.previewed=nil;extensions.horizonRewind.setSpeed(.25);advance('seek')
  elseif phase=='seek' and events.previewed and (events.previewed.rewindSeconds or 0)>1 then
    inspect();advance('previewReply')
  elseif phase=='previewReply' and reply then
    assert(reply.state==false and reply.broken==false,'Glass did not visually reset during preview');results.preview=reply
    events.restored=nil;extensions.horizonRewind.cancelRewind();advance('cancel')
  elseif phase=='cancel' and events.restored then inspect();advance('cancelReply')
  elseif phase=='cancelReply' and reply then
    assert(reply.state==results.damaged.state and reply.broken,'Cancel did not restore shattered material');results.cancel=reply
    advance('secondReady')
  elseif phase=='secondReady' and timer>.4 then
    events.began=nil;events.previewed=nil;events.restored=nil;extensions.horizonRewind.beginRewind();advance('secondBegin')
  elseif phase=='secondBegin' and events.began then advance('secondSeek')
  elseif phase=='secondSeek' and events.previewed and (events.previewed.rewindSeconds or 0)>1.5 then
    extensions.horizonRewind.endRewind();advance('commit')
  elseif phase=='commit' and events.restored then inspect();advance('commitReply')
  elseif phase=='commitReply' and reply then
    assert(reply.state==false and reply.broken==false,'Committed glass damage returned');results.commit=reply
    finish(true,'Glass material changes in preview, cancels to damage and commits to intact')
  end
end
M.receive=function(data) reply=data end
M.onUpdate=function(...) local ok,err=pcall(update,...);if not ok then finish(false,tostring(err)) end end
M.onExtensionLoaded=function() setExtensionUnloadMode(M,'manual') end
return M
