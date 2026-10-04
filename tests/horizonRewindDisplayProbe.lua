-- Native GE placement characterization; isolated test mod, no rewind loaded.
local M={}
local stage,timer,stageTime='boot',0,0
local index,results,pending=0,{},nil
local names={'setOriginalTransform'}
local current
local function poseInfo(car)
  local q=quat(car:getRotation())
  local cluster=quat(car:getClusterRotationSlow(car:getRefNodeId()))
  local spawn=quat(car:getSpawnWorldOOBB():getMatrix():toQuatF())
  return {rotation={q.x,q.y,q.z,q.w},clusterRotation={cluster.x,cluster.y,cluster.z,cluster.w},spawnRotation={spawn.x,spawn.y,spawn.z,spawn.w},originalPosition=vec3(car:getOriginalPosition()):toTable()}
end
local function finish(ok,detail)
  if stage=='done' then return end
  stage='done'
  jsonWriteFile('horizon-display-probe.json',{ok=ok,detail=detail,results=results},true)
  log(ok and 'I' or 'E','HR_DISPLAY',detail)
  shutdown(ok and 0 or 1)
end
local function advance(name) stage,stageTime=name,0 end
local function callback(data) pending=data end
M.receive=callback
local function queue(code) be:getPlayerVehicle(0):queueLuaCommand(code) end
local function update(dt)
  timer,stageTime=timer+dt,stageTime+dt
  if stage=='done' then return end
  if timer>70 then finish(false,'Timeout at '..stage); return end
  local car=be:getPlayerVehicle(0)
  if stage=='boot' then
    if not car or not core_gamestate or core_gamestate.state.state~='freeroam' or stageTime<2 then return end
    simTimeAuthority.pause(true)
    local nativeMethods={}
    local meta=getmetatable(car)
    if type(meta)=='table' then
      for key,value in pairs(type(meta.__index)=='table' and meta.__index or meta) do
        if type(key)=='string' and (key:lower():find('transform') or key:lower():find('position') or key:lower():find('render') or key:lower():find('update') or key:lower():find('sync') or key:lower():find('original')) then nativeMethods[#nativeMethods+1]=key end
      end
    end
    results.nativeMethods=nativeMethods
    queue([[extensions.load('horizonRewindDisplayWatcher')]])
    advance('next')
  elseif stage=='next' and stageTime>.1 then
    index=index+1
    if not names[index] then finish(true,'Native placement methods characterized'); return end
    current={method=names[index]}; results[#results+1]=current
    current.originalPosition=vec3(car:getOriginalPosition()):toTable()
    current.poseBefore=poseInfo(car)
    queue([[
      hrDisplayBeam=hrDisplayBeam or v.data.beams[0].cid
      obj:breakBeam(hrDisplayBeam)
      local ref=v.data.refNodes[0].ref
      local node=ref==0 and 1 or 0
      local pos=obj:getNodePosition(node)
      obj:setNodePosition(node,pos+vec3(.13,0,0)); obj:commitLoad()
      local q={obj:getInitialQuaternion()}
      obj:queueGameEngineLua('extensions.horizonRewindDisplayProbe.receive('..serialize({kind='prepared',resetCount=hrDisplayResetCount or 0,broken=obj:beamIsBroken(hrDisplayBeam),position=vec3(obj:getPosition()):toTable(),nodeId=node,nodePosition=vec3(obj:getNodePosition(node)):toTable(),initialQuaternion=q})..')')
    ]])
    advance('prepared')
  elseif stage=='prepared' and pending then
    current.before,pending=pending,nil
    local target=vec3(car:getPosition())+vec3(10,0,0)
    current.target=target:toTable()
    current.geBefore=vec3(car:getPosition()):toTable()
    local name=current.method
    local ok,err=pcall(function()
      if name=='setOriginalTransform' or name=='setPositionRotation' then car[name](car,target.x,target.y,target.z,0,0,math.sqrt(.5),math.sqrt(.5))
      elseif name=='setPositionXYZ' then car:setPositionXYZ(target.x,target.y,target.z)
      elseif name=='setVehicleTransform' or name=='setTransformF' then
        local p,r={},{}
        local transform=car:getTransformF(p,r)
        current.transformPosition,current.transformRotation=p,r
        current.transformType,current.transformValue=type(transform),tostring(transform)
        if type(transform)=='string' then
          local parts={}; for part in transform:gmatch('%S+') do parts[#parts+1]=part end
          assert(#parts==7,'Unknown TransformF serialization')
          parts[1],parts[2],parts[3]=target.x,target.y,target.z
          transform=table.concat(parts,' ')
        end
        if #p==3 and #r==4 then p[1],p[2],p[3]=target.x,target.y,target.z; car[name](car,p,r)
        else car[name](car,transform) end
      elseif name=='setTransform' then local matrix=car:getTransform(); matrix:setPosition(target); car:setTransform(matrix)
      elseif name=='setClusterPosRelRot' then car:setClusterPosRelRot(car:getRefNodeId(),target.x,target.y,target.z,0,0,0,1)
      else car[name](car,target) end
    end)
    current.callSucceeded,current.callError=ok,ok and nil or tostring(err)
    current.geImmediate=vec3(car:getPosition()):toTable()
    current.poseImmediate=poseInfo(car)
    current.immediateError=vec3(car:getPosition()):distance(target)
    advance('after')
  elseif stage=='after' and stageTime>.15 then
    current.geAfter=vec3(car:getPosition()):toTable()
    current.poseAfter=poseInfo(car)
    queue([[
      local ref=v.data.refNodes[0].ref
      local node=ref==0 and 1 or 0
      local q={obj:getInitialQuaternion()}
      obj:queueGameEngineLua('extensions.horizonRewindDisplayProbe.receive('..serialize({kind='after',resetCount=hrDisplayResetCount or 0,broken=obj:beamIsBroken(hrDisplayBeam),position=vec3(obj:getPosition()):toTable(),nodePosition=vec3(obj:getNodePosition(node)):toTable(),initialQuaternion=q})..')')
    ]])
    advance('sample')
  elseif stage=='sample' and pending then
    current.after,pending=pending,nil
    current.resetDelta=current.after.resetCount-current.before.resetCount
    log('I','HR_DISPLAY',serialize(current))
    if current.method=='setOriginalTransform' then
      queue('obj:requestReset(RESET_PHYSICS)')
      advance('reset-baseline')
    else advance('next') end
  elseif stage=='reset-baseline' and stageTime>.2 then
    current.afterRequestedReset=vec3(car:getPosition()):toTable()
    current.poseAfterReset=poseInfo(car)
    current.resetBaselineError=vec3(car:getPosition()):distance(vec3(current.target))
    queue([[local q={obj:getInitialQuaternion()}; obj:queueGameEngineLua('extensions.horizonRewindDisplayProbe.receive('..serialize({initialQuaternion=q})..')')]])
    advance('reset-quaternion')
  elseif stage=='reset-quaternion' and pending then
    current.resetQuaternion,pending=pending.initialQuaternion,nil
    local p,q=current.originalPosition,current.before.initialQuaternion
    car:setOriginalTransform(p[1],p[2],p[3],q[1],q[2],q[3],q[4])
    queue('obj:requestReset(RESET_PHYSICS)')
    advance('revert-baseline')
  elseif stage=='revert-baseline' and stageTime>.2 then
    current.revertedPosition=vec3(car:getPosition()):toTable()
    current.poseAfterRevert=poseInfo(car)
    queue([[local q={obj:getInitialQuaternion()}; obj:queueGameEngineLua('extensions.horizonRewindDisplayProbe.receive('..serialize({initialQuaternion=q})..')')]])
    advance('revert-quaternion')
  elseif stage=='revert-quaternion' and pending then
    current.revertedQuaternion,pending=pending.initialQuaternion,nil
    advance('next')
  end
end
M.onUpdate=function(dt) local ok,err=pcall(update,dt); if not ok then finish(false,tostring(err)) end end
M.onExtensionLoaded=function() setExtensionUnloadMode(M,'manual') end
return M
