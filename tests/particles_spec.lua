-- Uses the user's installed DDP source through a temporary test runner only.
-- No third-party source is checked into the project or included in the mod.
local particlesSource=assert(testDynamicParticlesSource, 'Inject installed Dynamic Damage Particles source')
local adapterSource=assert(testParticlesAdapterSource, 'Inject current adapter source')
local effectsSource=assert(testEffectsAdapterSource, 'Inject current vehicle effects source')
local passed=0
local function eq(a,b,label) assert(a==b,(label or 'value')..': '..tostring(a)..' ~= '..tostring(b)) end
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a)..' ~= '..tostring(b)) end
local function test(name,fn)
  local ok,err=pcall(fn); if not ok then error(name..': '..tostring(err),0) end
  passed=passed+1; print('PASS particles '..name)
end
local function find(fn,wanted,seen)
  seen=seen or {}; if seen[fn] then return end; seen[fn]=true
  for i=1,160 do
    local name,value=debug.getupvalue(fn,i); if not name then break end
    if name==wanted then return function() return select(2,debug.getupvalue(fn,i)) end end
    if type(value)=='function' then local found=find(value,wanted,seen); if found then return found end end
  end
end
local function harness()
  local h={errors={},hooks={}}
  local env=setmetatable({
    core_replay={state={state='inactive'}},core_camera={getPosition=function() return nil end},
    be={getPlayerVehicle=function() return nil end,getObjectByID=function() return nil end},
    scenetree={},getAllVehicles=function() return {} end,
    castRayStatic=function(_,_,length) return length end,
    extensions={hookUpdate=function(name) h.hooks[name]=true end},
    log=function(level,tag,message) if level=='E' then h.errors[#h.errors+1]=tag..': '..message end end
  },{__index=_G})
  env._G=env
  local chunk=assert(loadstring(particlesSource,'@installed-dynamic-damage-particles-2.0'))
  setfenv(chunk,env); h.ddp=chunk(); env.crashDebris=h.ddp
  local adapter=assert(loadstring(adapterSource,'@horizonRewindParticles.lua'))
  setfenv(adapter,env); h.adapter=adapter(); h.env=env
  h.actives=assert(find(h.ddp.onPreRender,'actives'))
  h.count=assert(find(h.ddp.onPreRender,'activeCount'))
  h.sparkCount=assert(find(h.ddp.onPreRender,'sparkCount'))
  h.debrisCount=assert(find(h.ddp.onPreRender,'debrisCount'))
  h.pending=assert(find(h.ddp.onPreRender,'pending'))
  h.pendingCount=assert(find(h.ddp.onPreRender,'pendingCount'))
  h.nativeRender=h.ddp.onPreRender
  function h.spawn(owner,count)
    h.ddp.burst(owner,0,0,20,5,0,0,count or 1,0,0,0,0,0,0,0,0,nil,1)
    h.nativeRender(0,0,0)
  end
  function h.pieces(owner)
    local result={}; for i=1,h.count() do local p=h.actives()[i]; if p.vid==owner then result[#result+1]=p end end
    return result
  end
  function h.tick(dt) h.ddp.onPreRender(dt,dt,dt); h.adapter.record(dt) end
  return h
end

test('binds actual installed schema and captures bounded samples',function()
  local h=harness(); h.spawn(1); h.spawn(2)
  assert(h.adapter.configure(1,77),h.adapter.getStatus().message)
  for i=1,15 do h.tick(.1) end
  local status=h.adapter.getStatus()
  eq(status.supported,true); assert(status.availableSeconds>1)
  assert(status.bytes<=status.budgetBytes); eq(#h.errors,0,table.concat(h.errors,'\n'))
end)

test('seek moves real simulated pieces backwards and removes future births',function()
  local h=harness(); h.spawn(1); h.spawn(2)
  local original=h.pieces(1)[1]; local oldX=original.ppx
  local other=h.pieces(2)[1]
  assert(h.adapter.configure(1,77),h.adapter.getStatus().message)
  for i=1,5 do h.tick(.1) end
  h.spawn(1)
  h.tick(.1)
  local liveX=h.pieces(1)[1].px
  eq(#h.pieces(1),2)
  assert(h.adapter.begin(1,77)); assert(h.adapter.seek(.6),h.adapter.getStatus().message)
  eq(#h.pieces(1),1); near(h.pieces(1)[1].px,oldX)
  assert(liveX>h.pieces(1)[1].px)
  eq(h.pieces(2)[1],other)
  eq(h.count(),2); eq(h.debrisCount(),2); eq(h.sparkCount(),0)
  eq(#h.errors,0,table.concat(h.errors,'\n'))
  h.adapter.abort()
end)

test('cancel restores live particles and pending births without touching other vehicles',function()
  local h=harness(); h.spawn(1); h.spawn(2)
  assert(h.adapter.configure(1,77),h.adapter.getStatus().message)
  for i=1,5 do h.tick(.1) end
  h.ddp.burst(1,10,0,20,0,0,0,3,0,0,0,0,0,0,0,0,nil,1)
  h.ddp.burst(2,10,0,20,0,0,0,2,0,0,0,0,0,0,0,0,nil,1)
  local pendingBefore=h.pendingCount()
  local x=h.pieces(1)[1].px
  local other=h.pieces(2)[1]
  assert(h.adapter.begin(1,77)); assert(h.adapter.seek(.4),h.adapter.getStatus().message)
  assert(h.adapter.finish(.4,true),h.adapter.getStatus().message)
  near(h.pieces(1)[1].px,x); eq(h.pieces(2)[1],other)
  eq(h.pendingCount(),pendingBefore)
  h.adapter.onUpdate(); h.adapter.onUpdate()
  eq(h.ddp.onPreRender,h.nativeRender)
end)

test('commit branches particle history and restores native behavior',function()
  local h=harness(); h.spawn(1)
  assert(h.adapter.configure(1,77),h.adapter.getStatus().message)
  for i=1,10 do h.tick(.1) end
  assert(h.adapter.begin(1,77)); assert(h.adapter.seek(.7))
  assert(h.adapter.finish(.7,false),h.adapter.getStatus().message)
  assert(h.adapter.getStatus().availableSeconds<.4)
  local x=h.pieces(1)[1].px
  h.adapter.onUpdate(); h.adapter.onUpdate()
  h.tick(.1)
  assert(h.pieces(1)[1].px>x)
  eq(#h.errors,0,table.concat(h.errors,'\n'))
end)

test('sparks settled debris and spatial caches restore with native counters',function()
  local h=harness(); h.spawn(1); h.spawn(2)
  h.ddp.sparks(1,0,0,20,2,0,0,1,10,nil); h.nativeRender(0,0,0)
  local env=assert(find(h.nativeRender,'env'))()
  local own=h.pieces(1)[1]; own.resting=true; env.settled(own); env.gadd(own,own.px,own.py)
  local other=h.pieces(2)[1]; other.resting=true; env.settled(other); env.gadd(other,other.px,other.py)
  local cfg=h.ddp.getConfig()
  assert(h.adapter.configure(1,77),h.adapter.getStatus().message)
  own.px=own.px+100; own.resting=false
  h.adapter.record(.1)
  assert(h.adapter.begin(1,77)); assert(h.adapter.seek(.1),h.adapter.getStatus().message)
  eq(h.count(),3); eq(h.sparkCount(),1); eq(h.debrisCount(),2); eq(env.statN,2)
  eq(h.pieces(2)[1],other)
  for _,piece in ipairs(h.actives()) do
    if piece.resting and piece.ki~=3 then eq(env.grid[piece.gk][piece.gi],piece) end
  end
  local newCfg=h.ddp.getConfig()
  eq(newCfg.staticCap,cfg.staticCap); eq(newCfg.movingCap,cfg.movingCap); eq(newCfg.sparkCap,cfg.sparkCap)
  h.adapter.abort()
  eq(env.statN,1)
end)

test('restore reset hook and emissions are gated only for the target vehicle',function()
  local h=harness(); h.spawn(1); h.spawn(2)
  assert(h.adapter.configure(1,77)); assert(h.adapter.begin(1,77))
  local before=h.pendingCount()
  h.ddp.burst(1,0,0,20,0,0,0,1,0,0,0,0,0,0,0,0,nil,1)
  eq(h.pendingCount(),before)
  h.ddp.burst(2,0,0,20,0,0,0,1,0,0,0,0,0,0,0,0,nil,1)
  eq(h.pendingCount(),before+1)
  h.ddp.onVehicleResetted(1); eq(#h.pieces(1),1)
  h.ddp.onVehicleResetted(2); eq(#h.pieces(2),0)
  h.adapter.abort(); eq(h.ddp.onPreRender,h.nativeRender)
end)

test('overwritten wrappers become inert after abort',function()
  local h=harness(); h.spawn(1)
  assert(h.adapter.configure(1,77)); assert(h.adapter.begin(1,77))
  local wrapped=h.ddp.burst
  local later=function(...) return wrapped(...) end
  h.ddp.burst=later
  h.adapter.abort()
  eq(h.ddp.burst,later)
  local count=h.pendingCount()
  h.ddp.burst(1,0,0,20,0,0,0,1,0,0,0,0,0,0,0,0,nil,1)
  eq(h.pendingCount(),count+1)
end)

test('memory remains capped when the particle population is large',function()
  local h=harness()
  h.spawn(1,400)
  for i=1,3 do h.nativeRender(.05,.05,.05) end
  assert(h.adapter.configure(1,77),h.adapter.getStatus().message)
  for i=1,150 do assert(h.adapter.record(.1),h.adapter.getStatus().message) end
  local status=h.adapter.getStatus()
  assert(status.bytes<=status.budgetBytes)
  assert(status.availableSeconds<15,'Expected budget-limited history')
  assert(h.adapter.begin(1,77)); assert(h.adapter.getStatus().bytes<=status.budgetBytes)
  h.adapter.abort()
end)

test('dense preview reuses pieces within and across sampled frames',function()
  local h=harness(); h.spawn(1,500)
  for i=1,3 do h.nativeRender(.05,.05,.05) end
  eq(#h.pieces(1),500)
  assert(h.adapter.configure(1,77),h.adapter.getStatus().message)
  local started=os.clock()
  for i=1,100 do
    for _,piece in ipairs(h.pieces(1)) do piece.px=piece.px+.25 end
    assert(h.adapter.record(.1),h.adapter.getStatus().message)
  end
  local captureMs=(os.clock()-started)*1000/100
  assert(h.adapter.begin(1,77)); assert(h.adapter.seek(.15))
  local first=h.pieces(1)[1]
  assert(h.adapter.seek(.16)); eq(h.pieces(1)[1],first,'same-sample piece reuse')
  assert(h.adapter.seek(.26)); eq(h.pieces(1)[1],first,'cross-sample piece reuse')
  started=os.clock()
  for i=1,600 do assert(h.adapter.seek(.3+i/120),h.adapter.getStatus().message) end
  local seekMs=(os.clock()-started)*1000/600
  eq(h.pieces(1)[1],first,'dense seek retained identity')
  print(string.format('PARTICLES_PERF 500 pieces: capture %.3f ms/sample; seek %.3f ms/call',captureMs,seekMs))
  h.adapter.abort()
end)

test('unknown particle schema fails closed before modifying effects',function()
  local h=harness(); h.spawn(1)
  local piece=h.pieces(1)[1]; piece.unknownFutureState={1,2,3}
  eq(h.adapter.configure(1,77),false)
  eq(h.pieces(1)[1],piece); eq(h.ddp.onPreRender,h.nativeRender)
  eq(h.adapter.getStatus().supported,false)
end)

test('an optional mod loaded after configure binds during recording',function()
  local h=harness();h.env.crashDebris=nil
  eq(h.adapter.configure(1,77),false)
  h.env.crashDebris=h.ddp
  for i=1,12 do h.adapter.record(.1) end
  eq(h.adapter.getStatus().supported,true)
  assert(h.adapter.begin(1,77));h.adapter.abort()
end)

test('vehicle guard blocks only the known optional extension and restores ownership',function()
  local calls,refreshed=0,{}
  local function called() calls=calls+1 end
  local target={applyConfig=called,sendNodeMaterials=called,sendWheelNodes=called,
    onBeamBroke=called,onBeamDeformed=called,updateGFX=called,debrisSlip=called,setGlassPoints=called}
  local filter={setConfig=called,nodeCollision=called}
  local env=setmetatable({crashParticles=target,particlefilter=filter,
    extensions={hookUpdate=function(name) refreshed[name]=true end}},{__index=_G})
  env._G=env
  local chunk=assert(loadstring(effectsSource,'@horizonRewindEffects.lua')); setfenv(chunk,env)
  local guard=chunk(); assert(guard.begin())
  target.onBeamBroke(); target.onBeamDeformed(); target.updateGFX(); target.debrisSlip(); filter.nodeCollision()
  eq(calls,0); assert(refreshed.onBeamBroke and refreshed.updateGFX)
  local wrapper=target.onBeamBroke
  local later=function(...) return wrapper(...) end
  target.onBeamBroke=later
  guard.finish(); eq(target.onBeamBroke,later)
  target.onBeamBroke(); filter.nodeCollision(); eq(calls,2)
  eq(target.updateGFX,called)
end)

test('missing optional modules never trigger extension autoload',function()
  local environment=setmetatable({extensions=setmetatable({}, {__index=function(_,key)
    error('Unexpected optional extension autoload: '..key)
  end})},{__index=_G})
  environment._G=environment
  local effects=assert(loadstring(effectsSource));setfenv(effects,environment)
  eq(effects().begin(),false)
  local particles=assert(loadstring(adapterSource));setfenv(particles,environment)
  -- configure refreshes known extension hooks; supply that real public method.
  environment.extensions.hookUpdate=function() end
  eq(particles().configure(1,77),false)
end)

print('PARTICLES_SPECS_PASSED '..passed)
