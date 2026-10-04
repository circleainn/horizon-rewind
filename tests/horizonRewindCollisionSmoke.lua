local M={}
local phase,timer,total='boot',0,0
local player,other,late,mod,pool
local events,replies,results={},{},{}
local function finish(ok,message)
  phase='done';jsonWriteFile('horizon-rewind-collision.json',{ok=ok,message=message,results=results},true);shutdown(ok and 0 or 1)
end
local function advance(value)
  phase,timer=value,0
  jsonWriteFile('horizon-rewind-collision-progress.json',{phase=phase,total=total,events=events},true)
end
local function inspect(car)
  replies[car:getID()]=nil
  car:queueLuaCommand([[local broken,deformed=0,0;for _,b in pairs(v.data.beams) do if obj:beamIsBroken(b.cid) then broken=broken+1 end;if obj:getBeamDeformation(b.cid)>.05 then deformed=deformed+1 end end;obj:queueGameEngineLua('extensions.horizonRewindCollisionSmoke.receive('..obj:getId()..','..serialize({broken=broken,deformed=deformed,speed=obj:getVelocity():length()})..')')]])
end
local function update(real,sim)
  if phase=='done' then return end
  total,timer=total+real,timer+real
  if total>110 then error('Timeout at '..phase) end
  if phase=='boot' then
    player=be:getPlayerVehicle(0);mod=extensions.horizonRewind
    if not player or not mod or core_gamestate.state.state~='freeroam' then return end
    local original=mod.onVehicleMessage
    mod.onVehicleMessage=function(id,token,event,data)
      original(id,token,event,data);events[id]=events[id] or {};events[id][event]=data or {}
      if event=='error' then error(tostring(data.message)) end
    end
    other=core_vehicles.spawnNewVehicle('covet',{pos=player:getPosition()+vec3(0,-24,0),rot=quat(0,0,1,0),autoEnterVehicle=false})
    advance('spawn')
  elseif phase=='spawn' and timer>3 then
    gameplay_traffic.insertTraffic(other:getID(),false,false)
    local entry=gameplay_traffic.getTrafficData()[other:getID()]
    entry.enableRespawn,entry.enableAutoPooling=false,false
    pool=core_vehicleActivePooling.getPoolOfVeh(other:getID())
    assert(pool and pool.name=='autoTraffic','Stock pool not created')
    mod.setTrafficEnabled(true);mod.setSpeed(2)
    for _,car in ipairs({player,other}) do
      car:queueLuaCommand("ai.setMode('disabled');input.event('parkingbrake',0,1);input.event('throttle',0,1);input.event('brake',0,1)")
    end
    advance('record')
  elseif phase=='record' and timer>4 then
    inspect(player);inspect(other);advance('baseline')
  elseif phase=='baseline' and replies[player:getID()] and replies[other:getID()] then
    results.baseline={player=replies[player:getID()],traffic=replies[other:getID()]}
    player:applyClusterVelocityScaleAdd(player:getRefNodeId(),0,0,-18,0)
    other:applyClusterVelocityScaleAdd(other:getRefNodeId(),0,0,18,0)
    advance('collision')
  elseif phase=='collision' and timer>1.5 then inspect(player);inspect(other);advance('damage')
  elseif phase=='damage' and replies[player:getID()] and replies[other:getID()] then
    results.damage={player=replies[player:getID()],traffic=replies[other:getID()]}
    assert(results.damage.traffic.broken>results.baseline.traffic.broken or results.damage.traffic.deformed>results.baseline.traffic.deformed,'No collision damage')
    local p=player:getPosition()
    late=core_vehicles.spawnNewVehicle('covet',{pos=p+vec3(15,0,0),autoEnterVehicle=false})
    advance('lateSpawn')
  elseif phase=='lateSpawn' and timer>.5 then
    gameplay_traffic.insertTraffic(late:getID(),false,false)
    local entry=gameplay_traffic.getTrafficData()[late:getID()];entry.enableRespawn,entry.enableAutoPooling=false,false
    late:queueLuaCommand("ai.setMode('disabled')")
    advance('lateRecord')
  elseif phase=='lateRecord' and timer>.5 then
    local available,count=extensions.horizonRewindTraffic.status(15)
    results.historyAfterSpawn=available;assert(available==15 and count==2,'New traffic shortened history')
    mod.beginRewind();advance('seek')
  elseif phase=='seek' and events[player:getID()].previewed and events[player:getID()].previewed.rewindSeconds>4 then
    assert(late:isHidden(),'New traffic was visible before birth')
    mod.endRewind();advance('commit')
  elseif phase=='commit' and not simTimeAuthority.getPause() then
    assert(not be:getObjectActive(late:getID()),'Future traffic was not returned to pool')
    advance('resume')
  elseif phase=='resume' and timer>.3 then inspect(player);inspect(other);advance('verify')
  elseif phase=='verify' and replies[player:getID()] and replies[other:getID()] then
    results.resumed={player=replies[player:getID()],traffic=replies[other:getID()]}
    for _,key in ipairs({'player','traffic'}) do
      assert(results.resumed[key].broken<=results.baseline[key].broken,'New broken beams after rewind in '..key)
      assert(results.resumed[key].deformed<=results.baseline[key].deformed+2,'New deformation after rewind in '..key)
      assert(results.resumed[key].speed<1,'Restored resting car launched in '..key)
    end
    -- Inactive native objects report hidden even after setHidden(false).
    -- Verify visibility after reactivation, as the real traffic pool does.
    pool:setVeh(late:getID(),true,true)
    assert(not late:isHidden(),'Reactivated pooled car stayed hidden')
    finish(true,'Real two-car collision repaired without new beam damage; new traffic preserved history and returned to stock pool')
  end
end
M.receive=function(id,data) replies[id]=data end
M.onUpdate=function(...) local ok,err=pcall(update,...);if not ok then finish(false,tostring(err)) end end
M.onExtensionLoaded=function() setExtensionUnloadMode(M,'manual') end
return M
