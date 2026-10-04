require('lua/console/console-lib').initConsole()
local engine=initBeamEngine(2000)
local bundle=assert(require('jbeam/loader').loadVehicleStage1(1,'vehicles/pickup/',nil))
local car=assert(engine:spawnObject2(1,'vehicles/pickup/',lpack.encode({vdata=bundle.vdata,config=bundle.config}),Vector3(0,0,30)))
local function queue(code,dt,count)
  car:queueLuaCommand(code)
  for _=1,count or 8 do engine:update(dt and dt>0 and dt or 0.001,dt or 0) end
end
queue([[
  obj:setGravity(0); obj:setGhostEnabled(true)
  function fastpathReport(label)
    local broken,deformed={},{}
    for _,b in pairs(v.data.beams) do
      if obj:beamIsBroken(b.cid) then broken[#broken+1]={cid=b.cid,type=b.beamType,group=b.breakGroup} end
      local d=obj:getBeamDeformation(b.cid)
      if d>0 then deformed[#deformed+1]={cid=b.cid,value=d,type=b.beamType} end
    end
    print('FASTPATH '..label..' brokenCount='..#broken..' deformedCount='..#deformed..' groups='..serialize(beamstate.brokenBreakGroups))
    for i=1,math.min(4,#broken) do print('FASTPATH_BROKEN '..serialize(broken[i])) end
    for i=1,math.min(4,#deformed) do print('FASTPATH_DEFORMED '..serialize(deformed[i])) end
    print('FASTPATH_CONTROLLERS '..serialize(controller.getState()))
  end
  fastpathReport('spawn')
]],0.01,40)
queue([[
  fastpathReport('settled')
  for _,n in pairs(v.data.nodes) do obj:applyForceVector(n.cid,(vec3(0,-12,0)-vec3(obj:getNodeVelocityVector(n.cid)))*(obj:getNodeMass(n.cid)/physicsDt)) end
]],0.01,200)
queue([[fastpathReport('moving')]])
print('FASTPATH_PROBE_DONE')
