local M={}
local model=HR_DRIVE_MODEL or 'bastion'
local coast=HR_DRIVE_COAST==true
local stage,total,timer='boot',0,0
local configured,replaced,vehicleId=false,false,nil
local data,events,last,velocityTrace={},{},{},{}
local function finish(ok,message)
  if stage=='done' then return end
  stage='done'
  jsonWriteFile('horizon-rewind-drive.json',{ok=ok,message=message,model=model,data=data,events=events,velocityTrace=velocityTrace},true)
  log(ok and 'I' or 'E','HR_DRIVE',message);shutdown(ok and 0 or 1)
end
local function command(code) be:getPlayerVehicle(0):queueLuaCommand(code) end
local function advance(s) stage,timer=s,0 end
local function update(dtReal,dtSim)
  if stage=='done' then return end
  total,timer=total+dtReal,timer+(dtSim or 0)
  if total>130 then finish(false,'Timeout at '..stage);return end
  local car=be:getPlayerVehicle(0)
  if stage=='boot' then
    if not car or not rawget(extensions,'horizonRewind') or not core_gamestate or core_gamestate.state.state~='freeroam' then return end
    if not replaced then replaced=true;core_vehicles.replaceVehicle(model);return end
    if car:getJBeamFilename()~=model then return end
    if not configured then
      configured=true;vehicleId=car:getID()
      local original=extensions.horizonRewind.onVehicleMessage
      extensions.horizonRewind.onVehicleMessage=function(id,token,event,value)
        original(id,token,event,value)
        if id==vehicleId then
          last[event]=value or {}
          if event~='recording' and event~='previewed' then events[#events+1]={event=event,time=total,data=value} end
          if event=='restored' then command("extensions.horizonRewindDriveProbe.resume()") end
        end
      end
      advance('ready')
    end
  elseif stage=='ready' then
    if timer<3 or not last.recording then return end
    command("extensions.load('horizonRewindDriveProbe'); extensions.horizonRewindDriveProbe.start()")
    advance('drive')
  elseif stage=='drive' then
    if timer<7 then return end
    command("extensions.horizonRewindDriveProbe.mark('live'); recovery.startRecovering()")
    advance('rewind')
  elseif stage=='rewind' then
    if not last.previewed or (last.previewed.rewindSeconds or 0)<1.5 then return end
    if coast then command('input.event("throttle",0,1)') end
    command('recovery.stopRecovering(0)');advance('resume')
  elseif stage=='resume' then
    velocityTrace[#velocityTrace+1]={time=timer,speed=car:getVelocity():length(),paused=simTimeAuthority.getPause()}
    if data.trace then
      if (data.live.speed or 0)<5 then finish(false,'Vehicle failed to accelerate before rewind');return end
      local minimum=math.huge
      for _,sample in ipairs(data.trace) do
        if sample.time>.1 then
          minimum=math.min(minimum,sample.speed)
          if sample.input.throttle~=(coast and 0 or 1) or sample.input.brake~=0 or sample.input.parkingbrake~=0 or sample.electrics.postCrashBrakeTriggered==1 then
            finish(false,'Resume changed driver inputs or falsely triggered post-crash braking');return
          end
        end
      end
      data.minimumResumeSpeed=minimum
      local v=last.restored.velocity
      local selectedSpeed=math.sqrt(v[1]^2+v[2]^2+v[3]^2)
      data.selectedSpeed=selectedSpeed
      if minimum<selectedSpeed*.85 then finish(false,'Resume lost selected momentum');return end
      if data.live.postCrashAvailable then command('extensions.horizonRewindDriveProbe.impact()');advance('impact')
      else finish(true,'Momentum and current controls preserved through resume') end
    end
  elseif stage=='impact' and data['new-impact'] then
    finish(data['new-impact'].electrics.postCrashBrakeTriggered==1,'Momentum preserved; post-crash braking checked against a new impact')
  end
end
M.receive=function(value) data[value.tag]=value.data end
M.onUpdate=function(...) local ok,err=pcall(update,...);if not ok then finish(false,tostring(err)) end end
M.onExtensionLoaded=function() setExtensionUnloadMode(M,'manual') end
return M
