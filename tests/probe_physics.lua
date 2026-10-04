-- Run from the BeamNG installation using Bin64/console.x64.exe file <this file>.
require('lua/console/console-lib').initConsole()
local engine = initBeamEngine(2000)
local bundle = require('jbeam/loader').loadVehicleStage1(1, 'vehicles/pickup/', nil)
assert(bundle and bundle.vdata, 'Could not load stock pickup')
local car = engine:spawnObject2(1, 'vehicles/pickup/', lpack.encode({vdata=bundle.vdata, config=bundle.config}), Vector3(0,0,3))
assert(car, 'Could not spawn stock pickup')
for _, name in ipairs({'getNodePosition', 'getNodeVelocityVector', 'setNodePosition', 'setNodeVelocity', 'setNodeVelocityVector', 'setNodeVelocityXYZ', 'applyNodeForce', 'applyClusterVelocityScaleAdd', 'applyClusterLinearAngularAccel', 'getClusterAngularVelocity', 'setBeamLength', 'commitLoad', 'requestReset', 'queueLuaCommand', 'getPhysicsState', 'setPhysicsState', 'getState', 'setState', 'serialize', 'deserialize'}) do
  local ok, value = pcall(function() return car[name] end)
  print('REWIND_PROBE '..name..' '..tostring(ok and type(value) or value))
end
car:queueLuaCommand([[for _, name in ipairs({'getNodePosition', 'getNodeVelocityVector', 'setNodePosition', 'setNodeVelocity', 'setNodeVelocityVector', 'setNodeVelocityXYZ', 'applyNodeForce', 'applyClusterVelocityScaleAdd', 'applyClusterLinearAngularAccel', 'getClusterAngularVelocity', 'setBeamLength', 'commitLoad', 'requestReset', 'getPhysicsState', 'setPhysicsState', 'getState', 'setState', 'serialize', 'deserialize'}) do local ok, value = pcall(function() return obj[name] end); print('REWIND_VEH '..name..' '..tostring(ok and type(value) or value)) end]])
engine:update(0.01, 0.01)
print('REWIND_PROBE_DONE')
