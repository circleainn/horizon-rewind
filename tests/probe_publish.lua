require('lua/console/console-lib').initConsole()
local engine=initBeamEngine(2000)
local bundle=require('jbeam/loader').loadVehicleStage1(1,'vehicles/pickup/',nil)
local car=engine:spawnObject2(1,'vehicles/pickup/',lpack.encode({vdata=bundle.vdata,config=bundle.config}),Vector3(0,0,30))
local function methods(object,label)
  local meta=getmetatable(object)
  if type(meta)=='table' then
    local entries=type(meta.__index)=='table' and meta.__index or meta
    for k,v in pairs(entries) do print('PUBLISH_'..label..' '..tostring(k)..' '..type(v)) end
  end
end
methods(car,'WRAPPER')
methods(engine,'ENGINE')
car:queueLuaCommand([[
  local meta=getmetatable(obj)
  for key,value in pairs(meta.__index) do
    local s=tostring(key):lower()
    if s:find('graph') or s:find('render') or s:find('sync') or s:find('update') or s:find('send') or s:find('reset') or s:find('load') or s:find('step') or s:find('cluster') or s:find('time') or s:find('position') then print('PUBLISH_OBJ '..tostring(key)..' '..type(value)) end
  end
  print('PUBLISH_BASE '..tostring(obj:getPosition())..' graphics='..tostring(obj:getGraphicsStepCount())..' ui='..tostring(obj:getUpdateUIflag()))
  local pts={}
  for _,nd in pairs(v.data.nodes) do pts[nd.cid]=vec3(obj:getNodePosition(nd.cid)) end
  for id,p in pairs(pts) do obj:setNodePosition(id,p+vec3(15,0,0)) end
  obj:commitLoad()
  print('PUBLISH_IMMEDIATE '..tostring(obj:getPosition())..' graphics='..tostring(obj:getGraphicsStepCount()))
]])
for i=1,4 do engine:update(0.016,0) end
car:queueLuaCommand([[print('PUBLISH_PAUSED '..tostring(obj:getPosition())..' graphics='..tostring(obj:getGraphicsStepCount())..' node='..tostring(obj:getNodePosition(0))) ]])
for i=1,4 do engine:update(0.016,0) end
for i=1,4 do engine:update(0.016,0.0005) end
car:queueLuaCommand([[print('PUBLISH_STEPPED '..tostring(obj:getPosition())..' graphics='..tostring(obj:getGraphicsStepCount())..' node='..tostring(obj:getNodePosition(0))) ]])
for i=1,4 do engine:update(0.016,0) end
print('PUBLISH_DONE')
