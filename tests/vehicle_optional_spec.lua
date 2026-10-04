-- Focused vehicle recorder checks for props and custom vehicle subsystems.
local source=assert(testVehicleSource, 'Inject the vehicle module source')
local History=testHistorySource and assert(loadstring(testHistorySource))() or require('horizonRewind/history')
local Wheel=testWheelSource and assert(loadstring(testWheelSource))() or require('horizonRewind/wheelInterpolation')
local realRequire=require
local function copy(value)
  if type(value)~='table' then return value end
  local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
local function vector(x,y,z)
  return {x=x or 0,y=y or 0,z=z or 0,set=function(self,a,b,c) self.x,self.y,self.z=a,b,c end}
end
local function fixture(systems)
  local env={}
  setmetatable(env,{__index=_G})
  local events,errors={},{}
  env.controller,env.powertrain,env.energyStorage,env.hydros=false,false,false,false
  for k,value in pairs(systems or {}) do env[k]=value end
  env.vec3,env.deepcopy=vector,copy
  env.v={data={nodes={{cid=0},{cid=1}},beams={{cid=0}}}}
  env.enablePhysicsStepHook=function() end
  env.log=function(_,_,message) errors[#errors+1]=message end
  env.beamstate={onBeamDeformed=function() end}
  env.serialize=function(data) env.__messageData=data; return '__messageData' end
  env.extensions={horizonRewind={onVehicleMessage=function(id,token,event,data) events[event]=copy(data) end}}
  env.require=function(name)
    if name=='horizonRewind/history' then return History end
    if name=='horizonRewind/wheelInterpolation' then return Wheel end
    return realRequire(name)
  end
  local state={length=1,broken=false,mass=2,nodes={vector(0,0,0),vector(1,0,0)},resetRequested=false}
  env.obj={
    getId=function() return 42 end,
    getPosition=function() return vector(0,0,0) end,
    getVelocity=function() return state.velocity or vector(0,0,0) end,
    getNodePosition=function(_,cid) return state.nodes[cid+1] end,
    getNodeVelocityVector=function() return state.velocity or vector(0,0,0) end,
    getNodeMass=function() return state.mass end,
    getBeamRestLength=function() return state.length end,
    getBeamDeformation=function() return 0 end,
    beamIsBroken=function() return state.broken end,
    setNodePosition=function(_,cid,value) state.nodes[cid+1]=copy(value) end,
    setNodeMass=function(_,cid,mass) state.mass=mass end,
    setBeamLength=function(_,cid,length) state.length=length end,
    breakBeam=function() state.broken=true end,
    commitLoad=function() end,
    applyForceVector=function(_,cid,force) state.lastForce=copy(force) end,
    requestReset=function() state.resetRequested=true; state.broken=false end,
    queueGameEngineLua=function(_,command) setfenv(assert(loadstring(command)),env)() end
  }
  local module=setfenv(assert(loadstring(source)),env)()
  env.extensions.horizonRewindVehicle=module
  env.be={getObjectByID=function()
    return {
      setOriginalTransform=function(_,...) state.baseline={...} end,
      resetBrokenFlexMesh=function() end,
      queueLuaCommand=function(_,command) state.pendingVehicleCommand=command end
    }
  end}
  local function restore()
    module.updateGFX(0.1); module.updateGFX(0.1)
    module.begin(1); module.seek(1,0.2)
    state.length=0.7; state.mass=1
    module.finish(1,false)
    assert(events.restorePrepared and not state.resetRequested, 'Reset started before GE prepared its baseline')
    module.executeRestore(1)
    assert(state.resetRequested, 'Structural reset was bypassed')
    if state.resetRequested then module.onReset(); module.completeRestore(1) end
    assert(#errors==0, errors[1])
    assert(events.restored and events.restored.position[1]==0, 'Missing final pose notification')
    assert(state.length==1 and state.mass==2, 'Optional systems prevented structural restoration')
  end
  module.configure(1,true)
  assert(events.configured and #errors==0, errors[1])
  return restore,env,state,module,events
end
local count=0
local function test(name,fn) fn(); count=count+1; print('VEHICLE_OPTIONAL_PASS '..name) end
local function throws() error('Custom subsystem callback failed') end
test('no drivetrain, controllers, storage, or hydros',function()
  local restore=fixture(); restore()
end)
test('missing optional callbacks and nil states',function()
  local restore=fixture({controller={},powertrain={getState=function() return nil end},energyStorage={},hydros={}})
  restore()
end)
test('throwing custom capture callbacks cannot disable geometry recording',function()
  local restore=fixture({controller={getState=throws},powertrain={getState=throws,getDevices=throws},energyStorage={getStorages=throws}})
  restore()
end)
test('throwing custom restore callbacks cannot prevent structural restoration',function()
  local restore=fixture({
    controller={getState=function() return {someState=true} end,setState=throws},
    powertrain={getState=function() return {someState=true} end,setState=throws,
      getDevices=function() return {gearbox={gearIndex=1,setGearIndex=throws}} end},
    energyStorage={getStorages=function() return {battery={storedEnergy=20,setStoredEnergy=throws}} end}
  })
  restore()
end)
test('valid optional state is copied and restored',function()
  local controllerState={gear=2}
  local device={gearIndex=2,outputAV1=30,lastOutputAV1=0,setGearIndex=function(self,gear) self.gearIndex=gear end}
  local tank={storedEnergy=40,energyCapacity=100,setRemainingRatio=function(self,ratio) self.storedEnergy=ratio*self.energyCapacity end}
  local restore=fixture({
    controller={getState=function() return controllerState end,setState=function(state) controllerState=state end},
    powertrain={getDevices=function() return {gearbox=device} end},
    energyStorage={getStorages=function() return {tank=tank} end}
  })
  controllerState.gear=5; device.outputAV1=90; device.gearIndex=4; tank.storedEnergy=10
  restore()
  assert(controllerState.gear==2 and device.outputAV1==30 and device.gearIndex==2 and tank.storedEnergy==40)
end)
test('release keeps exact preview position and interpolates momentum',function()
  local _,env,state,module,events=fixture()
  state.nodes={vector(10,0,0),vector(11,0,0)}
  state.velocity=vector(20,0,0)
  module.updateGFX(0.2)
  module.begin(1)
  module.seek(1,0.073)
  local preview=state.nodes[1].x
  assert(math.abs(preview-6.35)<1e-6, 'Test did not select an intermediate pose')
  state.velocity=vector(0,0,0)
  module.finish(1,false)
  module.executeRestore(1)
  if state.resetRequested then module.onReset(); module.completeRestore(1) end
  assert(math.abs(state.nodes[1].x-preview)<1e-6, 'Release snapped to preceding sample')
  assert(math.abs(events.restored.actualSelectedSeconds-0.073)<1e-9, 'Reported rewind cursor was quantized')
  assert(math.abs(events.restored.velocity[1]-12.7)<1e-6, 'GE momentum seed used a different cursor')
  module.onPhysicsStep(0.01)
  assert(math.abs(state.lastForce.x-2540)<0.001, 'Release used live or preceding-sample velocity')
end)
test('prepared abort performs an independent reset before reconfiguration',function()
  local _,env,state,module,events=fixture()
  state.nodes={vector(10,0,0),vector(11,0,0)}
  module.updateGFX(0.2)
  module.begin(1)
  module.seek(1,0.15)
  module.finish(1,false)
  assert(events.restorePrepared and not state.resetRequested)
  module.completeRestore(1)
  module.executeRestore(2)
  assert(not events.restored and not state.resetRequested, 'Unprepared or stale restore was accepted')
  module.abort(1)
  module.configure(2,true)
  module.executeRestore(1)
  assert(not state.resetRequested, 'Stale manager execute raced the detached live baseline')
  assert(state.baseline and #state.baseline==7 and state.pendingVehicleCommand)
  setfenv(assert(loadstring(state.pendingVehicleCommand)),env)()
  assert(state.resetRequested, 'Detached cancellation bypassed the native reset')
  module.onReset()
  module.completeRestore(1)
  assert(events.restored.cancelled and state.nodes[1].x==10, 'Prepared abort did not restore the live pose')
  module.onPhysicsStep(0.01)
  module.updateGFX(0.2)
  module.begin(2)
  assert(events.began, 'Pending reconfiguration was stranded')
end)
test('prepared baseline rotation follows the exact cursor through quaternion sign changes',function()
  local _,env,_,module,events=fixture()
  env.obj.getDirectionVector=function() return 1 end
  env.obj.getDirectionVectorUp=function() return 1 end
  env.quatFromDir=function() return {x=0,y=0,z=-math.sqrt(0.5),w=-math.sqrt(0.5)} end
  module.updateGFX(0.2)
  module.begin(1)
  module.seek(1,0.1)
  module.finish(1,false)
  local rotation=events.restorePrepared.rotation
  assert(math.abs(rotation[3]-math.sin(math.pi/8))<1e-9 and math.abs(rotation[4]-math.cos(math.pi/8))<1e-9,
    'Reset baseline rotation did not use shortest-arc interpolation at the displayed cursor')
end)
test('atomic reset retains held pedals and newer timestamped steering',function()
  local controls={throttle={val=1,filter=1,osClockHP=10},parkingbrake={val=0,filter=1,osClockHP=10},steering={val=.2,filter=1,osClockHP=10}}
  local _,env,_,module,events=fixture({input={state=controls}})
  env.onVehicleReset=function()
    controls.throttle.val,controls.throttle.osClockHP=0,nil
    controls.parkingbrake.val,controls.parkingbrake.osClockHP=1,nil
    controls.steering.val,controls.steering.osClockHP=.7,20
    module.onReset()
  end
  module.updateGFX(.2);module.begin(1);module.seek(1,.1);module.finish(1,false);module.executeRestore(1)
  env.onVehicleReset()
  assert(events.restored and controls.throttle.val==1 and controls.parkingbrake.val==0,'Reset overwrote live pedals')
  assert(controls.steering.val==.7 and controls.steering.osClockHP==20,'Newer input was overwritten')
end)
test('transmission resumes its actual ratio instead of shifting from reset neutral',function()
  local ratioAtInertia
  local gear={gearIndex=3,gearRatio=2.11,desiredGearRatio=2.11,gearRatioChangeRate=0,shiftLossCoef=1,
    setGearIndex=function(self,index) self.gearIndex=index;self.desiredGearRatio=2.11;self.gearRatioChangeRate=5.55;self.shiftLossCoef=.5 end}
  local restore=fixture({powertrain={getDevices=function() return {gearbox=gear} end,
    calculateTreeInertia=function() ratioAtInertia=gear.gearRatio end}})
  gear.gearRatio=1;gear.desiredGearRatio=0
  restore()
  assert(gear.gearRatio==2.11 and gear.gearRatioChangeRate==0 and gear.shiftLossCoef==1 and ratioAtInertia==2.11)
end)
test('20 40 and 60 second buffers retain and seek their selected window',function()
  for _, seconds in ipairs({20,40,60}) do
    local _,env,state,module,events=fixture()
    module.configure(1,true,seconds)
    for i=1,(seconds+5)*20 do module.updateGFX(.05) end
    assert(math.abs(events.recording.availableSeconds-seconds)<.1,'Wrong retained duration')
    module.begin(1);module.seek(1,seconds)
    assert(math.abs(events.previewed.rewindSeconds-seconds)<.1,'Long history could not be sought')
  end
end)
print('VEHICLE_OPTIONAL_SPEC_DONE '..count)
