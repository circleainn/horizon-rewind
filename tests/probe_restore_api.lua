require('lua/console/console-lib').initConsole()
local engine=initBeamEngine(2000)
local bundle=require('jbeam/loader').loadVehicleStage1(1,'vehicles/pickup/',nil)
local car=engine:spawnObject2(1,'vehicles/pickup/',lpack.encode({vdata=bundle.vdata,config=bundle.config}),Vector3(0,0,30))
car:queueLuaCommand([[
  local meta=getmetatable(obj)
  for key,value in pairs(meta.__index) do
    local s=tostring(key):lower()
    if s:find('beam') or s:find('reset') or s:find('load') or s:find('sync') or s:find('graph') or s:find('render') or s:find('original') or s:find('init') or s:find('position') then print('RESTORE_API '..key..' '..type(value)) end
  end
]])
for i=1,4 do engine:update(.01,0) end
print('RESTORE_API_DONE')
