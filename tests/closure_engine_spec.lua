require('lua/console/console-lib').initConsole()
local engine=initBeamEngine(2000)
local bundle=assert(require('jbeam/loader').loadVehicleStage1(1,'vehicles/covet/',jsonReadFile('vehicles/covet/15se_M.pc')))
local car=assert(engine:spawnObject2(1,'vehicles/covet/',lpack.encode({vdata=bundle.vdata,config=bundle.config}),Vector3(0,0,30)))
local restored,errors,resetReady=0,0,0
closureAssertions=0
extensions.horizonRewind={onVehicleMessage=function(id,token,event,data)
  if event=='error' then errors=errors+1; print('CLOSURE_ERROR '..serialize(data)) end
  if event=='restorePrepared' then
    assert(#data.position==3 and #data.rotation==4, 'Missing native reset baseline')
    car:queueLuaCommand('extensions.horizonRewindVehicle.executeRestore('..token..')')
  end
  if event=='resetReady' then resetReady=resetReady+1; car:queueLuaCommand('extensions.horizonRewindVehicle.completeRestore('..token..')') end
  if event=='restored' then
    restored=restored+1
    assert(data.resetFlexMesh==true, 'Native restoration was not atomic')
    assert(type(data.actualSelectedSeconds)=='number' and data.actualSelectedSeconds==data.rewindSeconds)
    if token==73 then assert(data.actualSelectedSeconds==0, 'Cancellation consumed history') end
  end
  if event=='configured' or event=='began' or event=='previewed' then print('CLOSURE_EVENT '..event..' '..serialize(data)) end
end}
local function pump(dt,count) for _=1,count or 8 do engine:update(dt>0 and dt or 0.001,dt) end end
local function queue(command,dt,count) car:queueLuaCommand(command); pump(dt or 0,count) end
queue(string.format([[
  package.loaded['horizonRewind/history']=assert(loadstring(%q))()
  package.loaded['horizonRewind/wheelInterpolation']=assert(loadstring(%q))()
  package.loaded.horizonRewindVehicle=assert(loadstring(%q))()
  extensions.load('horizonRewindVehicle')
  obj:setGravity(0); obj:setGhostEnabled(true)
  closureOriginalReset=onVehicleReset
  closureNames={'door_L_coupler','hoodLatchCoupler','hoodCatchCoupler','tailgateCoupler'}
  function closureReport(label)
    local states={}
    for _,name in ipairs(closureNames) do states[name]=controller.getController(name).getGroupState() end
    print('CLOSURE_STATES '..label..' '..serialize(states))
  end
  function closureAssert(attached,label)
    closureReport(label)
    for _,name in ipairs(closureNames) do
      assert((controller.getController(name).getGroupState()=='attached')==attached, name..' wrong state at '..label)
    end
    for _,cid in ipairs({1,21,22,38}) do
      assert((obj:getNodeCoupler(cid)>=0)==attached, 'Native latch wrong state at '..label)
    end
    obj:queueGameEngineLua('closureAssertions=closureAssertions+1')
  end
]],assert(testHistorySource),assert(testWheelSource),assert(testVehicleSource)))
pump(0.01,30)
queue([[
  closureReport('initial')
  closureClosed={}; closureClosedOrigin=vec3(obj:getPosition())
  closureClosedLengths={}
  for _,node in pairs(v.data.nodes) do closureClosed[node.cid]=vec3(obj:getNodePosition(node.cid))+closureClosedOrigin end
  for _,cid in ipairs({1,21,22,38}) do closureClosedLengths[cid]=obj:nodeLength(cid,v.data.refNodes[0].ref) end
  extensions.horizonRewindVehicle.configure(71,true)
]])
pump(0.01,40)
queue([[
  for _,name in ipairs({'doorL_latch','hood_latch','tailgate_latch'}) do beamstate.breakBreakGroup(name) end
]])
pump(0.01,20)
queue([[
  closureReport('broken')
  extensions.horizonRewindVehicle.begin(71)
  extensions.horizonRewindVehicle.seek(71,20)
]])
queue([[
  input.event('steering',0.65,1)
  input.state.steering.smootherKBD:set(0.65)
  input.state.steering.smootherPAD:set(0.65)
]])
queue('extensions.horizonRewindVehicle.finish(71,false)',0,20)
assert(restored==1 and errors==0, 'Restore failed')
queue([[
  assert(onVehicleReset==closureOriginalReset, 'Temporary reset callback was not removed')
  assert(math.abs(input.state.steering.smootherKBD:value()-0.65)<1e-6, 'Keyboard smoother was reset')
  assert(math.abs(input.state.steering.smootherPAD:value()-0.65)<1e-6, 'Controller smoother was reset')
  assert(input.state.steering.val==0.65, 'Current input changed')
  for _,cid in ipairs({1,21,22,38}) do
    local error=math.abs(obj:nodeLength(cid,v.data.refNodes[0].ref)-closureClosedLengths[cid])
    print('CLOSURE_GEOMETRY_ERROR '..cid..' '..error)
    assert(error<0.003, 'Physical restored panel geometry differs from historical pose')
  end
  obj:queueGameEngineLua('closureAssertions=closureAssertions+1')
]])
pump(0.0005,1)
queue([[
  closureAssert(true,'closed-after-one-physics-step')
]])
assert(closureAssertions==2, 'Closed-state or input assertions did not complete')
-- An intentionally open historical panel must not be forced closed.
queue([[
  for _,name in ipairs(closureNames) do controller.getController(name).detachGroup() end
]])
pump(0.01,80)
queue([[
  closureAssert(false,'manually-open-before-recording')
  extensions.horizonRewindVehicle.configure(72,true)
]])
pump(0.01,30)
queue([[
  extensions.horizonRewindVehicle.begin(72)
  extensions.horizonRewindVehicle.seek(72,20)
]])
queue('extensions.horizonRewindVehicle.finish(72,false)',0,20)
assert(restored==2 and errors==0)
pump(0.001,20)
queue([[closureAssert(false,'historically-open-after-restoration')]])
assert(closureAssertions==4, 'Historical-open state assertions did not complete')
-- Cancellation returns to the open/broken live state, not the closed preview.
queue('obj:requestReset(RESET_PHYSICS)',0,10)
pump(0.01,30)
queue([[
  closureAssert(true,'reset-closed-before-cancel-case')
  extensions.horizonRewindVehicle.configure(73,true)
]])
pump(0.01,30)
queue([[
  for _,name in ipairs({'doorL_latch','hood_latch','tailgate_latch'}) do beamstate.breakBreakGroup(name) end
]])
pump(0.01,20)
queue([[
  closureAssert(false,'broken-live-before-cancellation')
  extensions.horizonRewindVehicle.begin(73)
  extensions.horizonRewindVehicle.seek(73,20)
]])
queue('extensions.horizonRewindVehicle.finish(73,true)',0,20)
assert(restored==3 and errors==0)
pump(0.001,20)
queue([[
  closureAssert(false,'cancellation-preserves-broken-live-latches')
  for _,name in ipairs(closureNames) do assert(controller.getController(name).getGroupState()=='broken', 'Broken latch metadata lost') end
]])
assert(closureAssertions==7 and resetReady==0, 'Closure regression or atomic reset failed')
print('CLOSURE_ENGINE_SPEC_DONE assertions='..closureAssertions..' atomicRestores='..restored)
