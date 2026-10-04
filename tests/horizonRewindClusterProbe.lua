-- Isolated graphics/physics publication probe. Never loads production mods.
local M={}
local elapsed,stage,stageTime=0,'boot',0
local prepared,topology,pending,caseIndex
local modes={'root','all','anchors'}
local results={}
local function finish(ok,detail)
  if stage=='done' then return end
  stage='done'
  jsonWriteFile('horizon-cluster-probe.json',{ok=ok,detail=detail,results=results,topology=topology},true)
  log(ok and 'I' or 'E','HR_CLUSTER',detail)
  shutdown(ok and 0 or 1)
end
local function nextStage(value) stage,stageTime=value,0 end
local function callback(data) pending=data end
M.receive=callback
local function queue(code) be:getPlayerVehicle(0):queueLuaCommand(code) end
local function update(dt)
  elapsed,stageTime=elapsed+dt,stageTime+dt
  if elapsed>90 then finish(false,'Timeout at '..stage); return end
  local car=be:getPlayerVehicle(0)
  if stage=='done' then return end
  if stage=='boot' then
    if not car or not getCurrentLevelIdentifier() then return end
    core_vehicles.replaceVehicle('covet',{config='vehicles/covet/15se_M.pc'})
    nextStage('spawn')
  elseif stage=='spawn' then
    if not car or car:getJBeamFilename()~='covet' or stageTime<2 then return end
    queue([[
      obj:setGravity(0); obj:setGhostEnabled(true)
      clusterProbeNodes={}
      for _,n in pairs(v.data.nodes) do
        if n.partPath and n.partPath:find('/covet_door_L/',1,true) then clusterProbeNodes[n.cid]=true end
      end
      assert(next(clusterProbeNodes), 'No door nodes selected')
      for _,b in pairs(v.data.beams) do
        if (clusterProbeNodes[b.id1] or false)~=(clusterProbeNodes[b.id2] or false) then obj:breakBeam(b.cid) end
      end
      beamstate.breakHinges()
      for cid,connection in pairs(beamstate.attachedCouplers) do
        if clusterProbeNodes[cid] or (connection.obj2id==obj:getId() and clusterProbeNodes[connection.obj2nodeId]) then obj:detachCoupler(cid,math.huge) end
      end
    ]])
    nextStage('detach')
  elseif stage=='detach' and stageTime>0.3 then
    queue([[
      clusterProbeInitial={}; clusterProbeAnchors={}
      local origin=vec3(obj:getPosition())
      local ref=v.data.refNodes[0].ref
      local rootCluster=obj:getNodeCluster(ref)
      local door
      for _,n in pairs(v.data.nodes) do
        clusterProbeInitial[n.cid]=vec3(obj:getNodePosition(n.cid))+origin
        local cluster=obj:getNodeCluster(n.cid)
        clusterProbeAnchors[cluster]=clusterProbeAnchors[cluster] or n.cid
        if clusterProbeNodes[n.cid] and cluster~=rootCluster then door=door or n.cid end
      end
      assert(door,'Door did not form a detached cluster')
      clusterProbeRef,clusterProbeDoor=ref,door
      obj:queueGameEngineLua('extensions.horizonRewindClusterProbe.receive('..serialize({kind='topology',ref=ref,door=door,rootCluster=rootCluster,doorCluster=obj:getNodeCluster(door),clusters=tableSize(clusterProbeAnchors)})..')')
    ]])
    nextStage('topology')
  elseif stage=='topology' and pending then
    topology,pending=pending,nil
    simTimeAuthority.pause(true)
    caseIndex=0
    nextStage('next')
  elseif stage=='next' and stageTime>0.1 then
    caseIndex=caseIndex+1
    if not modes[caseIndex] then finish(true,'Measured all three detached-cluster publication paths'); return end
    queue(string.format([[
      local target,anchors={},{}
      local origin=vec3(obj:getPosition())
      for cid,initial in pairs(clusterProbeInitial) do
        target[cid]=initial+vec3(%d*10,clusterProbeNodes[cid] and %d*5 or 0,0)
        obj:setNodePosition(cid,target[cid]-origin)
      end
      obj:commitLoad()
      for _,cid in pairs(clusterProbeAnchors) do anchors[#anchors+1]={cid=cid,position=target[cid]:toTable()} end
      clusterProbeTarget=target
      obj:queueGameEngineLua('extensions.horizonRewindClusterProbe.receive('..serialize({kind='target',anchors=anchors,ref=target[clusterProbeRef]:toTable(),door=target[clusterProbeDoor]:toTable()})..')')
    ]],caseIndex,caseIndex))
    nextStage('target')
  elseif stage=='target' and pending then
    prepared,pending=pending,nil
    local mode=modes[caseIndex]
    if mode=='anchors' then
      for _,anchor in ipairs(prepared.anchors) do
        local p=anchor.position
        car:setClusterPosRelRot(anchor.cid,p[1],p[2],p[3],0,0,0,1)
      end
    else
      local p=prepared.ref
      car:setClusterPosRelRot(mode=='all' and -1 or car:getRefNodeId(),p[1],p[2],p[3],0,0,0,1)
    end
    nextStage('published')
  elseif stage=='published' and stageTime>0.2 then
    local origin=vec3(car:getPosition())
    local rootPosition=origin+vec3(car:getNodePosition(topology.ref))
    local doorPosition=origin+vec3(car:getNodePosition(topology.door))
    local result={mode=modes[caseIndex],rootError=rootPosition:distance(vec3(prepared.ref)),
      doorError=doorPosition:distance(vec3(prepared.door)),rootPosition=rootPosition:toTable(),doorPosition=doorPosition:toTable(),target=prepared}
    results[#results+1]=result
    log('I','HR_CLUSTER',serialize(result))
    nextStage('next')
  end
end
M.onUpdate=function(dt)
  local ok,err=pcall(update,dt)
  if not ok then finish(false,tostring(err)) end
end
M.onExtensionLoaded=function() setExtensionUnloadMode(M,'manual') end
return M
