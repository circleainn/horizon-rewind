-- Read-only game physics probe: writes no game or user data.
require('lua/console/console-lib').initConsole()
local engine = initBeamEngine(2000)
local bundle = require('jbeam/loader').loadVehicleStage1(1, 'vehicles/pickup/', nil)
assert(bundle and bundle.vdata, 'Could not load stock pickup')
local car = engine:spawnObject2(1, 'vehicles/pickup/', lpack.encode({vdata=bundle.vdata, config=bundle.config}), Vector3(0,0,30))
assert(car, 'Could not spawn stock pickup')
car:queueLuaCommand([[
  local names = {'applyForceVector','applyForceVectorTime','applyClusterLinearAngularAccel','getNodeVelocityVector','setNodeVelocity','setNodeVelocityVector','setNodeVelocityXYZ','setNodeVelocityVectorXYZ','applyNodeImpulse','applyImpulse','setVelocity','getPhysicsDt','getPhysicsFPS','getNodeMass','getNodePosition','commitLoad','getPhysicsState','setPhysicsState','getState','setState','serialize','deserialize','getClusterVelocityWithoutWheels'}
  for _, name in ipairs(names) do local ok, value = pcall(function() return obj[name] end); print('VELOCITY_METHOD '..name..' '..tostring(ok and type(value) or value)) end
  local mt = getmetatable(obj)
  print('VELOCITY_MT '..type(mt))
  if type(mt) == 'table' then
    for key, value in pairs(mt) do print('VELOCITY_META '..tostring(key)..' '..type(value)) end
    if type(mt.__index) == 'table' then for key,value in pairs(mt.__index) do if tostring(key):lower():find('vel') or tostring(key):lower():find('force') or tostring(key):lower():find('state') then print('VELOCITY_INDEX '..tostring(key)..' '..type(value)) end end end
  end
  print('VELOCITY_DT '..tostring(physicsDt)..' '..tostring(obj:getPhysicsDt()))
  print('VELOCITY_BASE '..tostring(obj:getVelocity()))
]])
for i=1,20 do engine:update(0.0005, 0.0005) end
car:queueLuaCommand([[
  for _, n in pairs(v.data.nodes) do
    local m = obj:getNodeMass(n.cid)
    obj:applyForceVector(n.cid, vec3(m * 10 / physicsDt,0,0))
  end
  print('VELOCITY_APPLIED_FORCE')
]])
for i=1,20 do engine:update(0.0005, 0.0005) end
car:queueLuaCommand([[
  print('VELOCITY_AFTER_FORCE '..tostring(obj:getVelocity()))
  print('VELOCITY_NODE_AFTER_FORCE '..tostring(obj:getNodeVelocityVector(0)))
  for _, n in pairs(v.data.nodes) do
    local m = obj:getNodeMass(n.cid)
    local delta = vec3(0,0,0) - vec3(obj:getNodeVelocityVector(n.cid))
    obj:applyForceVector(n.cid, delta * (m / physicsDt))
  end
]])
for i=1,20 do engine:update(0.0005, 0.0005) end
car:queueLuaCommand([[
  print('VELOCITY_AFTER_CANCEL '..tostring(obj:getVelocity()))
  print('VELOCITY_NODE_AFTER_CANCEL '..tostring(obj:getNodeVelocityVector(0)))
  for _, n in pairs(v.data.nodes) do
    local m = obj:getNodeMass(n.cid)
    obj:applyForceVectorTime(n.cid, vec3(m * 10 / physicsDt,0,0), physicsDt)
  end
  print('VELOCITY_APPLIED_TIME_FORCE')
]])
for i=1,20 do engine:update(0.0005, 0.0005) end
car:queueLuaCommand([[
  print('VELOCITY_AFTER_TIME_FORCE '..tostring(obj:getVelocity()))
  print('VELOCITY_NODE_AFTER_TIME_FORCE '..tostring(obj:getNodeVelocityVector(0)))
]])
for i=1,20 do engine:update(0.0005, 0.0005) end
car:queueLuaCommand([[
  local connected = 0
  for _, b in pairs(v.data.beams) do
    if b.id1 == 0 or b.id2 == 0 then obj:breakBeam(b.cid); connected = connected + 1 end
  end
  print('VELOCITY_DETACHED_NODE '..tostring(v.data.nodes[0].name)..' connected='..tostring(connected))
  local ok, err = pcall(function() obj:setGravity(0) end)
  print('VELOCITY_ZERO_GRAVITY '..tostring(ok)..' '..tostring(err))
  obj:setGhostEnabled(true)
]])
for i=1,20 do engine:update(0.0005, 0.0005) end
car:queueLuaCommand([[
  local target = vec3(17,-4,8)
  local current = vec3(obj:getNodeVelocityVector(0))
  obj:applyForceVector(0, (target - current) * (obj:getNodeMass(0) / physicsDt))
  print('VELOCITY_DETACHED_FORCE_TARGET '..tostring(target)..' before='..tostring(current))
]])
for i=1,20 do engine:update(0.0005, 0.0005) end
car:queueLuaCommand([[
  print('VELOCITY_DETACHED_FORCE_RESULT '..tostring(obj:getNodeVelocityVector(0)))
  assert((vec3(obj:getNodeVelocityVector(0)) - vec3(17,-4,8)):length() < 0.0001, 'Per-node impulse did not reach target velocity')
  local target = vec3(-6,11,-3)
  local current = vec3(obj:getNodeVelocityVector(0))
  obj:applyForceVectorTime(0, (target - current) * (obj:getNodeMass(0) / physicsDt), physicsDt)
  print('VELOCITY_DETACHED_TIME_TARGET '..tostring(target)..' before='..tostring(current))
]])
for i=1,20 do engine:update(0.0005, 0.0005) end
car:queueLuaCommand([[
  print('VELOCITY_DETACHED_TIME_RESULT '..tostring(obj:getNodeVelocityVector(0)))
  assert((vec3(obj:getNodeVelocityVector(0)) - vec3(-6,11,-3)):length() < 0.0001, 'Timed per-node impulse did not reach target velocity')
  print('VELOCITY_ASSERTIONS_PASSED')
]])
for i=1,20 do engine:update(0.0005, 0.0005) end
print('VELOCITY_PROBE_DONE')

