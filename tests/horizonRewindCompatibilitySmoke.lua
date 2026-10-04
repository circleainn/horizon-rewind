local M={}
local phase,timer,total='boot',0,0
local reply,events,results=nil,{},{}
local function finish(ok,message)
  phase='done';jsonWriteFile('horizon-rewind-compatibility.json',{ok=ok,message=message,results=results},true);shutdown(ok and 0 or 1)
end
local function advance(nextPhase)
  phase,timer=nextPhase,0
  jsonWriteFile('horizon-rewind-compatibility-progress.json',{phase=phase,total=total,events=events},true)
end
local function command(code) be:getPlayerVehicle(0):queueLuaCommand(code) end
local function inspect()
  reply=nil
  command([[local c=extensions.dynamicDirtCore or dynamicDirtCore;local s=extensions.dynamicDirtSkin or dynamicDirtSkin;local d=extensions.horizonRewindDirt;local f=d.capture();obj:queueGameEngineLua('extensions.horizonRewindCompatibilitySmoke.receive('..serialize({average=c and c.average(),skin=s and s.status(),adapter=d.getStatus(),captured=f~=nil,calls=hrDirtCalls})..')')]])
end
local function update(real,sim)
  if phase=='done' then return end
  total,timer=total+real,timer+real
  if total>110 then error('Timeout '..phase) end
  local mod=extensions.horizonRewind
  if phase=='boot' then
    if not be:getPlayerVehicle(0) or not mod or core_gamestate.state.state~='freeroam' then return end
    core_vehicles.replaceVehicle('pickup',{config={parts={paint_design='pickup_skin_dynamicdirt'}}})
    local original=mod.onVehicleMessage
    mod.onVehicleMessage=function(id,token,event,data) original(id,token,event,data);events[event]=data or {} end
    advance('ready')
  elseif phase=='ready' and timer>6 then
    command([[extensions.load('dynamicDirtCore');extensions.load('dynamicDirtSkin');hrDirtCalls={};local html=require('htmlTexture');local original=html.call;html.call=function(tag,method,data) hrDirtCalls[method]=(hrDirtCalls[method] or 0)+1;return original(tag,method,data) end]])
    inspect();advance('cleanReply')
  elseif phase=='cleanReply' and reply then
    results.clean=reply
    assert(reply.captured,'Grime capture unavailable: '..reply.adapter.reason)
    command("(extensions.dynamicDirtCore or dynamicDirtCore).soak(0.7)")
    advance('dirty')
  elseif phase=='dirty' and timer>.8 then inspect();advance('dirtyReply')
  elseif phase=='dirtyReply' and reply then
    results.dirty=reply;assert(reply.average>.2,'Dirt was not applied')
    mod.setSpeed(4);mod.beginRewind();advance('preview')
  elseif phase=='preview' and events.previewed and events.previewed.rewindSeconds>1.8 then
    results.audio=extensions.horizonRewindAudio.getStatus()
    assert(not results.audio.failed and results.audio.sourceId and results.audio.volume>.1,'Audio source failed')
    assert(results.audio.cue=='rewind_400.wav','Wrong sound for 4x speed')
    inspect();advance('previewReply')
  elseif phase=='previewReply' and reply then
    results.preview=reply;assert(reply.average<.01,'Preview did not remove future dirt')
    assert((reply.calls.washDirt or 0)>0,'Body canvas was not rebuilt')
    mod.cancelRewind();advance('cancel')
  elseif phase=='cancel' and events.restored and not simTimeAuthority.getPause() then inspect();advance('cancelReply')
  elseif phase=='cancelReply' and reply then
    results.cancel=reply;assert(reply.average>.2,'Cancel lost dirty live state')
    events.previewed,events.restored=nil,nil;mod.beginRewind();advance('secondPreview')
  elseif phase=='secondPreview' and events.previewed and events.previewed.rewindSeconds>2.4 then
    mod.endRewind();advance('commit')
  elseif phase=='commit' and events.restored and not simTimeAuthority.getPause() then advance('settle')
  elseif phase=='settle' and timer>.3 then inspect();advance('commitReply')
  elseif phase=='commitReply' and reply then
    results.commit=reply;assert(reply.average<.01,'Committed dirt returned after resuming')
    finish(true,'Grime clean preview, dirty cancellation, clean commit and native audio source controls passed')
  end
end
M.receive=function(data) reply=data end
M.onUpdate=function(...) local ok,err=pcall(update,...);if not ok then finish(false,tostring(err)) end end
M.onExtensionLoaded=function() setExtensionUnloadMode(M,'manual') end
return M
