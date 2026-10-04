-- Integration checks using BeamNG's own console physics engine.
-- Run from the game root; does not install or alter any game files.
require('lua/console/console-lib').initConsole()
local historySource=assert(testHistorySource, 'Use run_vehicle_engine_spec.ps1 to inject current source through the console VFS')
local vehicleSource=assert(testVehicleSource, 'Use run_vehicle_engine_spec.ps1 to inject current source through the console VFS')
local wheelSource=assert(testWheelSource, 'Missing wheel interpolation source')
local engine = initBeamEngine(2000)
local bundle = require('jbeam/loader').loadVehicleStage1(1, 'vehicles/pickup/', nil)
assert(bundle and bundle.vdata)
local car = assert(engine:spawnObject2(1, 'vehicles/pickup/', lpack.encode({vdata=bundle.vdata,config=bundle.config}), Vector3(0,0,30)))
local messages = {}
local token = 71
local errorCount, restoreCount = 0, 0
local lastConfigured, lastBegan, meshResetCount = nil, nil, 0
local abortOnError = false
local vehicleWrapper = {
  resetBrokenFlexMesh = function() meshResetCount = meshResetCount + 1 end,
  queueLuaCommand = function(_, command) car:queueLuaCommand(command) end
}
be = { getObjectByID = function(_, id) if id == 1 then return vehicleWrapper end end }
extensions.horizonRewind = {
  onVehicleMessage = function(id, session, event, data)
    messages[event] = data
    if event ~= 'recording' and event ~= 'previewed' then print('ENGINE_EVENT '..event..' '..serialize(data)) end
    if event == 'configured' then lastConfigured = session end
    if event == 'began' then lastBegan = session end
    if event == 'error' then
      errorCount = errorCount + 1
      if abortOnError then car:queueLuaCommand('extensions.horizonRewindVehicle.abort('..session..')') end
    end
    if event == 'restorePrepared' then
      assert(#data.position == 3 and #data.rotation == 4, 'Missing native reset baseline')
      car:queueLuaCommand('extensions.horizonRewindVehicle.executeRestore('..session..')')
    end
    if event == 'resetReady' then car:queueLuaCommand('extensions.horizonRewindVehicle.completeRestore('..session..')') end
    if event == 'restored' then
      restoreCount = restoreCount + 1
      if data.resetFlexMesh then meshResetCount = meshResetCount + 1 end
    end
  end
}
local geAdapter = extensions.horizonRewind
local function pump(dt, count)
  for i = 1, count or 8 do engine:update(dt > 0 and dt or 0.001, dt) end
end
local function queue(code, dt, count)
  car:queueLuaCommand(code)
  pump(dt or 0, count or 8)
end
queue(string.format([[
  package.loaded['horizonRewind/history'] = assert(loadstring(%q))()
  package.loaded['horizonRewind/wheelInterpolation'] = assert(loadstring(%q))()
  package.loaded.horizonRewindVehicle = assert(loadstring(%q))()
  extensions.load('horizonRewindVehicle')
  assert(extensions.horizonRewindVehicle, 'Rewind extension failed to load')
  obj:setGravity(0)
  obj:setGhostEnabled(true)
  for _, storage in pairs(energyStorage.getStorages()) do
    if storage.setRemainingRatio then storage:setRemainingRatio(0.35) end
  end
  extensions.horizonRewindVehicle.configure(%d, true)
]], historySource, wheelSource, vehicleSource, token))
assert(messages.configured, 'Missing configured event')
queue([[
  for _, node in pairs(v.data.nodes) do
    local delta = vec3(12,0,0) - vec3(obj:getNodeVelocityVector(node.cid))
    obj:applyForceVector(node.cid, delta * (obj:getNodeMass(node.cid) / physicsDt))
  end
]], 0.0005, 8)
pump(0.01, 70)
queue([[
  integrationState = {liveOrigin=vec3(obj:getPosition()), liveVelocity=vec3(obj:getVelocity()),
    originalBeamLength=obj:getBeamRestLength(0), fuel=energyStorage.getStorage('mainTank').storedEnergy}
  obj:setBeamLength(0, integrationState.originalBeamLength * 0.85)
  obj:breakBeam(1)
]])
pump(0.01, 20)
queue('extensions.horizonRewindVehicle.begin('..token..')')
assert(messages.began, 'Missing began event')
queue('extensions.horizonRewindVehicle.seek('..token..',0.5)')
queue([[
  local now=vec3(obj:getPosition())
  print('ENGINE_PREVIEW_ORIGIN '..tostring(now)..' previous='..tostring(integrationState.liveOrigin))
  assert(now.x < integrationState.liveOrigin.x - 1, 'Preview did not move the car backwards')
]])
queue('extensions.horizonRewindVehicle.finish('..token..',false)', 0, 20)
assert(restoreCount == 1, 'Missing restoration handshake')
pump(0.0005, 8)
queue([[
  local velocity=vec3(obj:getVelocity())
  local fuel=energyStorage.getStorage('mainTank').storedEnergy
  print('ENGINE_RESTORE beam1broken='..tostring(obj:beamIsBroken(1))..' length='..tostring(obj:getBeamRestLength(0))..' fuel='..tostring(fuel)..' expectedFuel='..tostring(integrationState.fuel)..' velocity='..tostring(velocity))
  assert(not obj:beamIsBroken(1), 'Previously intact beam stayed broken')
  assert(math.abs(obj:getBeamRestLength(0)-integrationState.originalBeamLength)<0.002, 'Beam rest length was not restored')
  assert(math.abs(fuel-integrationState.fuel) < 10000, 'Fuel was not restored')
  assert(math.abs(velocity.x-12)<1, 'Forward momentum was not restored')
  print('ENGINE_RESTORE_ASSERTIONS_PASSED')
]])
pump(0.01, 30)
queue([[
  obj:breakBeam(1)
]])
pump(0.01, 12)
queue([[
  integrationState.cancelOrigin=vec3(obj:getPosition())
  integrationState.cancelFuel=energyStorage.getStorage('mainTank').storedEnergy
  integrationState.cancelVelocity=vec3(obj:getVelocity())
  extensions.horizonRewindVehicle.begin(71)
]])
queue('extensions.horizonRewindVehicle.seek('..token..',0.25)')
queue('extensions.horizonRewindVehicle.finish('..token..',true)', 0, 20)
assert(restoreCount == 2, 'Missing cancellation restore handshake')
queue([[
  local origin=vec3(obj:getPosition())
  print('ENGINE_CANCEL_ORIGIN '..tostring(origin)..' expected='..tostring(integrationState.cancelOrigin))
  assert((origin-integrationState.cancelOrigin):length()<0.02, 'Cancel did not restore latest position')
  assert(obj:beamIsBroken(1), 'Cancel repaired damage at live rewind origin')
  assert(math.abs(energyStorage.getStorage('mainTank').storedEnergy-integrationState.cancelFuel)<10000, 'Cancel refilled fuel')
  print('ENGINE_CANCEL_ASSERTIONS_PASSED')
]])
pump(0.0005, 8)
queue([[
  local velocity=vec3(obj:getVelocity())
  print('ENGINE_CANCEL_VELOCITY '..tostring(velocity)..' expected='..tostring(integrationState.cancelVelocity))
  assert((velocity-integrationState.cancelVelocity):length()<1, 'Cancel did not restore velocity')
  print('ENGINE_CANCEL_VELOCITY_PASSED')
]])
assert(errorCount == 0, 'Vehicle extension reported an error')
queue([[
  -- Use paused explicit GFX samples for deterministic damage-only snapshots.
  integrationState.damagedLength=integrationState.originalBeamLength*0.91
  obj:setBeamLength(0,integrationState.damagedLength)
  assert(obj:beamIsBroken(1), 'Test needs pre-existing broken beam')
  assert(not obj:beamIsBroken(2), 'Test needs a second intact beam')
  extensions.horizonRewindVehicle.configure(72,true)
  extensions.horizonRewindVehicle.updateGFX(0.1)
  obj:breakBeam(2)
  obj:setBeamLength(0,integrationState.originalBeamLength*0.7)
  extensions.horizonRewindVehicle.updateGFX(0.1)
  extensions.horizonRewindVehicle.begin(72)
  extensions.horizonRewindVehicle.seek(72,0.15)
  extensions.horizonRewindVehicle.finish(72,false)
]],0,24)
assert(restoreCount == 3, 'Missing damaged checkpoint restore')
queue([[
  print('ENGINE_PARTIAL_DAMAGE beam1='..tostring(obj:beamIsBroken(1))..' beam2='..tostring(obj:beamIsBroken(2))..' rest='..tostring(obj:getBeamRestLength(0))..' expected='..integrationState.damagedLength)
  assert(obj:beamIsBroken(1), 'Rewind healed damage that existed at the checkpoint')
  assert(not obj:beamIsBroken(2), 'Rewind retained damage introduced after the checkpoint')
  assert(math.abs(obj:getBeamRestLength(0)-integrationState.damagedLength)<0.0001, 'Rewind lost earlier permanent deformation')
  print('ENGINE_PARTIAL_DAMAGE_ASSERTIONS_PASSED')
]])
assert(errorCount == 0, 'Vehicle extension reported an error')
pump(0.0005,8) -- Finish the prior checkpoint's pending momentum impulse.
queue([[
  function integrationPreparePreview(token)
    extensions.horizonRewindVehicle.configure(token,true)
    local positions={}
    for _,n in pairs(v.data.nodes) do positions[n.cid]=vec3(obj:getNodePosition(n.cid)) end
    for id,p in pairs(positions) do obj:setNodePosition(id,p+vec3(8,0,0)) end
    obj:commitLoad()
    extensions.horizonRewindVehicle.updateGFX(0.15)
    integrationState.abortOrigin=vec3(obj:getPosition())
    integrationState.abortVelocity=vec3(obj:getVelocity())
    assert(integrationState.abortVelocity:length()>5,'Abort coverage requires a moving vehicle')
    integrationState.abortFuel=energyStorage.getStorage('mainTank').storedEnergy
    extensions.horizonRewindVehicle.begin(token)
    extensions.horizonRewindVehicle.seek(token,0.12)
    assert(obj:getPosition().x<integrationState.abortOrigin.x-1,'Abort test did not enter a displaced preview')
  end
  integrationPreparePreview(73)
  extensions.horizonRewindVehicle.abort(73)
  -- Must defer until the outstanding native reset/restore has completed.
  extensions.horizonRewindVehicle.configure(74,true)
]],0,24)
assert(restoreCount == 4, 'Abort did not perform live restore')
assert(lastConfigured == 74, 'Immediate reconfiguration was lost during abort')
queue([[
  local origin=vec3(obj:getPosition())
  assert((origin-integrationState.abortOrigin):length()<0.02,'Abort+configure lost original position')
  assert(obj:beamIsBroken(1),'Abort+configure healed current damage')
  assert(math.abs(energyStorage.getStorage('mainTank').storedEnergy-integrationState.abortFuel)<10000,'Abort+configure lost fuel')
  print('ENGINE_ABORT_RECONFIGURE_ASSERTIONS_PASSED')
]])
pump(0.0005,8)
queue([[
  assert((vec3(obj:getVelocity())-integrationState.abortVelocity):length()<1,'Abort+configure lost momentum')
  print('ENGINE_ABORT_RECONFIGURE_VELOCITY_PASSED')
]])
pump(0.01,16)
queue('extensions.horizonRewindVehicle.begin(74)')
assert(lastBegan == 74, 'New configured session did not resume recording')
queue('extensions.horizonRewindVehicle.seek(74,10); extensions.horizonRewindVehicle.finish(74,false)',0,24)
assert(restoreCount == 5,'New session could not restore its first recorded frame')
pump(0.0005,8)
queue([[
  assert((vec3(obj:getVelocity())-integrationState.abortVelocity):length()<1,'Reconfigured initial frame lost the pending momentum impulse')
  print('ENGINE_RECONFIGURED_FIRST_FRAME_VELOCITY_PASSED')
]])

queue('integrationPreparePreview(75)')
local meshBeforeUnload=meshResetCount
extensions.horizonRewind=false -- Simulate the GE manager already being gone.
queue('extensions.horizonRewindVehicle.abort(75)',0,24)
assert(meshResetCount>meshBeforeUnload,'Detached restore required the unloaded GE manager')
queue([[
  assert((vec3(obj:getPosition())-integrationState.abortOrigin):length()<0.02,'GE unload abort lost original position')
  assert(obj:beamIsBroken(1),'GE unload abort healed current damage')
  print('ENGINE_UNLOADED_GE_ABORT_ASSERTIONS_PASSED')
]])
pump(0.0005,8)
queue([[
  assert((vec3(obj:getVelocity())-integrationState.abortVelocity):length()<1,'GE unload abort lost momentum')
  print('ENGINE_UNLOADED_GE_ABORT_VELOCITY_PASSED')
]])
extensions.horizonRewind=geAdapter

queue('integrationPreparePreview(76)')
abortOnError=true
queue('extensions.horizonRewindVehicle.seek(76,0/0)',0,24)
abortOnError=false
assert(errorCount==1,'Runtime-error scenario did not report exactly one failure')
assert(restoreCount==6,'Runtime-error abort did not restore live state')
queue([[
  assert((vec3(obj:getPosition())-integrationState.abortOrigin):length()<0.02,'Runtime error abort lost original position')
  assert(obj:beamIsBroken(1),'Runtime error abort healed current damage')
  print('ENGINE_RUNTIME_ERROR_ABORT_ASSERTIONS_PASSED')
]])
pump(0.0005,8)
queue([[
  assert((vec3(obj:getVelocity())-integrationState.abortVelocity):length()<1,'Runtime error abort lost momentum')
  print('ENGINE_RUNTIME_ERROR_ABORT_VELOCITY_PASSED')
]])
print('ENGINE_SPEC_DONE restoreCount='..restoreCount..' expectedErrors='..errorCount)
