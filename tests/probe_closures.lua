require('lua/console/console-lib').initConsole()
local engine=initBeamEngine(2000)
local bundle=assert(require('jbeam/loader').loadVehicleStage1(1,'vehicles/covet/',jsonReadFile('vehicles/covet/15se_M.pc')))
local car=assert(engine:spawnObject2(1,'vehicles/covet/',lpack.encode({vdata=bundle.vdata,config=bundle.config}),Vector3(0,0,30)))
local function queue(command,dt,count)
  car:queueLuaCommand(command)
  for _=1,count or 8 do engine:update(dt and dt>0 and dt or 0.001,dt or 0) end
end
queue([[
  obj:setGravity(0); obj:setGhostEnabled(true)
  for key,value in pairs(_G) do if type(key)=='string' and key:find('RESET',1,true) then print('CLOSURE_RESET_CONSTANT '..key..' '..tostring(value)) end end
  for name,fn in pairs(getmetatable(obj).__index) do
    local lower=name:lower()
    if lower:find('cluster') or lower:find('coupl') or lower:find('reset') or lower:find('init') or lower:find('orig') or lower:find('position') or lower:find('load') then print('CLOSURE_API '..name..' '..type(fn)) end
  end
  for _,entry in pairs(v.data.controller) do
    if entry.fileName=='advancedCouplerControl' then print('CLOSURE_CONTROLLER '..entry.name..' '..serialize(entry.couplerNodes)) end
  end
  print('CLOSURE_STATE '..serialize(controller.getState()))
  print('CLOSURE_ATTACHED '..serialize(beamstate.attachedCouplers))
  for _,cid in ipairs({0,1,3,28,29,21,108,22,264,38,338}) do
    print('CLOSURE_NODE '..cid..' '..v.data.nodes[cid].name..' cluster='..tostring(obj:getNodeCluster(cid))..' coupler='..serialize(obj:getNodeCoupler(cid)))
  end
  closureInitial={}
  for _,node in pairs(v.data.nodes) do closureInitial[node.cid]=vec3(obj:getNodePosition(node.cid)) end
]],0.001,10)
queue([[
  print('CLOSURE_STATE_STEPPED '..serialize(controller.getState()))
  print('CLOSURE_ATTACHED_STEPPED '..serialize(beamstate.attachedCouplers))
  local p=obj:getPosition()
  local ok,err=pcall(function() obj:setClusterPosRelRot(v.data.refNodes[0].ref,p.x,p.y,p.z,0,0,0,1) end)
  print('CLOSURE_VLUA_PUBLISH_NUMERIC '..tostring(ok)..' '..tostring(err))
]])
queue([[
  beamstate.breakBreakGroup('doorL_latch')
  beamstate.breakBreakGroup('hood_latch')
  beamstate.breakBreakGroup('tailgate_latch')
]],0.01,20)
queue([[
  print('CLOSURE_BROKEN_STATE '..serialize(controller.getState()))
  for _,cid in ipairs({0,1,3,28,29,21,108,22,264,38,338}) do
    print('CLOSURE_BROKEN_NODE '..cid..' '..v.data.nodes[cid].name..' cluster='..tostring(obj:getNodeCluster(cid))..' coupler='..serialize(obj:getNodeCoupler(cid)))
  end
]])
print('CLOSURE_PROBE_DONE')
