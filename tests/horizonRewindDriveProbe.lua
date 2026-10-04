local M={}
local mode,elapsed,nextSample,samples='idle',0,0,{}
local impactPending=false
local function state()
  local d={time=elapsed,speed=obj:getVelocity():length(),input={},electrics={},devices={},controller=controller.getState()}
  for _,key in ipairs({'throttle','brake','clutch','parkingbrake'}) do
    local s=input.state[key];d.input[key]=s and s.val
  end
  for _,key in ipairs({'throttle','throttle_input','brake','brake_input','parkingbrake','clutch','rpm','gearIndex','ignitionLevel','engineRunning','postCrashBrakeTriggered'}) do d.electrics[key]=electrics.values[key] end
  d.sensors={gx=sensors.gx,gy=sensors.gy,gz=sensors.gz,gx2=sensors.gx2,gy2=sensors.gy2,gz2=sensors.gz2}
  for _,definition in pairs(v.data.controller or {}) do
    if (definition.fileName or ''):find('postCrashBrake',1,true) then d.postCrashAvailable=true end
  end
  for name,device in pairs(powertrain.getDevices()) do
    local item={type=device.type}
    for _,key in ipairs({'gearIndex','gearRatio','desiredGearRatio','mode','outputAV1','outputAV2','inputAV','virtualMassAV','isDisabled','isStalled','ignitionCoef','starterEngagedCoef','clutchRatio','lockCoef'}) do item[key]=device[key] end
    d.devices[name]=item
  end
  return d
end
local function emit(tag,value)
  obj:queueGameEngineLua('extensions.horizonRewindDriveSmoke.receive('..serialize({tag=tag,data=value})..')')
end
function M.start()
  input.event('parkingbrake',0,1);input.event('brake',0,1);input.event('throttle',1,1)
  mode,elapsed,nextSample,samples='drive',0,0,{}
end
function M.mark(tag) emit(tag,state()) end
function M.resume()
  emit('before-first-step',state())
  mode,elapsed,nextSample,samples='resume',0,0,{}
end
function M.impact() mode,elapsed,nextSample,samples,impactPending='impact',0,0,{},true;enablePhysicsStepHook() end
function M.onPhysicsStep(dt)
  if not impactPending or dt<=0 then return end
  impactPending=false
  -- A new external deceleration impulse must still trigger crash protection.
  for _,node in pairs(v.data.nodes) do obj:applyForceVector(node.cid,obj:getNodeVelocityVector(node.cid)*(-obj:getNodeMass(node.cid)/dt)) end
end
function M.updateGFX(dt)
  if mode=='idle' or dt<=0 then return end
  elapsed=elapsed+dt
  if elapsed>=nextSample then samples[#samples+1]=state();nextSample=elapsed+.025 end
  if mode=='resume' and elapsed>=3 then emit('trace',samples);mode='idle' end
  if mode=='impact' and elapsed>=.3 then emit('new-impact',state());mode='idle' end
end
return M
