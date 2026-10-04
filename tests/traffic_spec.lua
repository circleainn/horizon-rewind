local function fixture()
  local h={cars={},bundles={},traffic={},calls={},tokens={},updates=0,resets=0,pools={}}
  function h.add(id)
    local car={active=true,p={x=0,y=0,z=0}}
    function car:queueLuaCommand(cmd)
      local method,token,args=cmd:match('horizonRewindVehicle%.(%w+)%((%d+)(.-)%)')
      assert(method,'Unrecognized traffic command')
      h.calls[#h.calls+1]={id=id,method=method,args=args}
      h.tokens[id]=tonumber(token)
    end
    function car:getRefNodeId() return 0 end
    function car:getPosition() return self.p end
    function car:isHidden() return self.hidden or false end
    function car:setHidden(value) self.hidden=value end
    function car:setClusterPosRelRot(_,x,y,z) self.p={x=x,y=y,z=z} end
    function car:setOriginalTransform(...) self.baseline={...} end
    function car:resetBrokenFlexMesh() self.meshReset=true end
    function car:applyClusterVelocityScaleAdd(_,_,x,y,z) self.velocity={x,y,z} end
    h.cars[id],h.bundles[id],h.traffic[id]=car,{}, {isAi=true}
    return car
  end
  h.add(1);h.add(2);h.add(3)
  local env=setmetatable({
    be={getObjectByID=function(_,id) return h.cars[id] end,
      getObjectActive=function(_,id) return h.cars[id] and h.cars[id].active end},
    core_vehicle_manager={getVehicleData=function(id) return h.bundles[id] end},
    core_vehicleActivePooling={getPoolOfVeh=function(id) return h.pools[id] end},
    gameplay_traffic={getTrafficData=function() return h.traffic end,
      onUpdate=function() h.updates=h.updates+1 end,
      onVehicleResetted=function() h.resets=h.resets+1 end},
    extensions={hookUpdate=function() end}
  },{__index=_G})
  h.mod=setfenv(assert(loadstring(testTrafficSource)),env)()
  h.env=env
  function h.send(id,event,data,token) return h.mod.onVehicleMessage(id,token or h.tokens[id],event,data or {}) end
  function h.start()
    h.mod.configure(1,true,60);h.mod.update(1)
    h.send(2,'configured',{availableSeconds=6});h.send(3,'configured',{availableSeconds=5})
  end
  return h
end
local n=0
local function test(name,fn) fn();n=n+1;print('TRAFFIC_PASS '..name) end
test('off does no work; active AI only; common history excludes player',function()
  local h=fixture();h.mod.configure(1,false,20);h.mod.update(1);assert(#h.calls==0)
  h.cars[3].active=false;h.start()
  local time,count=h.mod.status(50);assert(time==6 and count==1)
  assert(#h.calls==1 and h.calls[1].id==2 and h.calls[1].args==',true,60,true')
end)
test('traffic remains frozen through both acknowledgments and geometry publication',function()
  local h=fixture();h.start();h.mod.begin()
  h.env.gameplay_traffic.onUpdate();h.env.gameplay_traffic.onVehicleResetted(2)
  assert(h.updates==0 and h.resets==0)
  h.send(2,'began');assert(not h.mod.ready());h.send(3,'began');assert(h.mod.ready())
  h.mod.seek(2);h.send(2,'previewed',{position={1,2,3}});h.send(3,'previewed',{position={4,5,6}})
  assert(h.cars[2].p.x==1 and h.mod.ready())
  h.mod.finish(false)
  for _,id in ipairs({2,3}) do
    h.send(id,'restorePrepared',{position={id,0,0},rotation={0,0,0,1}})
    h.send(id,'restored',{position={id,0,0},velocity={12,0,0},resetFlexMesh=true})
  end
  h.mod.update(0);assert(not h.mod.ready());h.mod.update(0);assert(h.mod.ready())
  h.mod.commit();assert(h.cars[2].velocity[1]==12 and h.cars[3].velocity[1]==12)
  h.env.gameplay_traffic.onUpdate();h.env.gameplay_traffic.onVehicleResetted(2)
  assert(h.updates==1 and h.resets==1)
end)
test('pool and VM replacement histories never survive into unrelated cars',function()
  local h=fixture();h.start();local oldToken=h.tokens[2]
  h.cars[2].active=false;h.mod.update(1)
  local _,count=h.mod.status(20);assert(count==1)
  h.cars[2].active=true;h.mod.update(1)
  assert(h.tokens[2]~=oldToken and not h.send(2,'error',{message='old'},oldToken))
  local newToken=h.tokens[2];h.bundles[2]={};h.mod.update(1)
  assert(h.tokens[2]~=newToken)
  assert(h.mod.status(20)==0,'Fresh car must bound common history')
end)
test('deletion during rewind releases the barrier without targeting replacement VM',function()
  local h=fixture();h.start();h.mod.begin();h.send(3,'began')
  h.bundles[2]={};local before=#h.calls;h.mod.update(0)
  assert(h.mod.ready() and #h.calls==before)
end)
test('abort removes owned wrappers without erasing later wrappers',function()
  local h=fixture();h.start();h.mod.begin()
  local prior=h.env.gameplay_traffic.onUpdate
  local later=function(...) return prior(...) end
  h.env.gameplay_traffic.onUpdate=later
  h.mod.abort();assert(h.env.gameplay_traffic.onUpdate==later)
  h.env.gameplay_traffic.onUpdate();assert(h.updates==1)
  local _,count=h.mod.status(20);assert(count==0)
end)
test('new pooled cars cannot shrink player history and cancel restores visibility',function()
  local h=fixture()
  h.pools[2],h.pools[3]={name='autoTraffic'},{name='autoTraffic'}
  h.start();h.send(3,'recording',{availableSeconds=0})
  assert(h.mod.status(50)==50,'New pooled traffic shortened player history')
  local before=#h.calls;h.mod.begin()
  assert(#h.calls==before+1 and h.calls[#h.calls].id==2,'Empty traffic received begin')
  h.send(2,'began');assert(h.mod.ready())
  h.mod.seek(8);h.send(2,'previewed',{})
  assert(h.cars[2].hidden and h.cars[3].hidden,'Future traffic remained visible')
  h.mod.finish(true)
  assert(not h.cars[2].hidden and not h.cars[3].hidden,'Cancel left traffic hidden')
  h.mod.abort();assert(not h.cars[3].hidden)
end)
test('traffic absent at selected time returns to its pool instead of overlapping restored cars',function()
  local h=fixture();h.cars[3].active=false
  h.pools[2]={name='autoTraffic',setVeh=function(_,id,active) h.cars[id].active=active end}
  h.start();h.send(2,'recording',{availableSeconds=0})
  h.mod.begin();h.mod.seek(4);assert(h.mod.ready())
  h.mod.finish(false);h.mod.commit()
  assert(not h.cars[2].active and not h.cars[2].hidden)
  local available,count=h.mod.status(40);assert(available==40 and count==0)
end)
print('TRAFFIC_SPEC_DONE '..n)
