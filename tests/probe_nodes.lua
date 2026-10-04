require('lua/console/console-lib').initConsole()
local engine = initBeamEngine(2000)
local bundle = require('jbeam/loader').loadVehicleStage1(1, 'vehicles/pickup/', nil)
local car = engine:spawnObject2(1, 'vehicles/pickup/', lpack.encode({vdata=bundle.vdata, config=bundle.config}), Vector3(0,0,30))
car:queueLuaCommand([[
  local a=obj:getPosition(); local n=obj:getNodePosition(0); print('NODES_BEFORE '..tostring(a)..' '..tostring(n))
  local all={}; for _,nd in pairs(v.data.nodes) do all[nd.cid]=obj:getNodePosition(nd.cid) end
  for id,p in pairs(all) do obj:setNodePosition(id, p+vec3(10,0,0)) end
  obj:commitLoad()
  print('NODES_AFTER '..tostring(obj:getPosition())..' '..tostring(obj:getNodePosition(0)))
]])
for i=1,3 do engine:update(0,0.016) end
car:queueLuaCommand([[print('NODES_LATER '..tostring(obj:getPosition())..' '..tostring(obj:getNodePosition(0)))]])
for i=1,3 do engine:update(0,0.016) end
print('NODES_DONE')

