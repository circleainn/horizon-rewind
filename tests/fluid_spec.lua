-- Run via run_fluid_specs.ps1 or Lua 5.1 with the source paths below.
local base = debug.getinfo(1, 'S').source:gsub('^@', ''):gsub('\\', '/'):match('^(.*)/') or '.'
local function source(name, path)
  if _G[name] then return _G[name] end
  local f = assert(io.open(base..'/../'..path, 'r')); local text = f:read('*a'); f:close(); return text
end
local compatSource = source('HR_FLUID_COMPAT_SOURCE', 'mod/lua/common/horizonRewind/fluidCompat.lua')
local geSource = source('HR_FLUID_GE_SOURCE', 'mod/lua/ge/extensions/horizonRewindFluids.lua')
local vehicleSource = source('HR_FLUID_VEHICLE_SOURCE', 'mod/lua/vehicle/extensions/horizonRewindFluids.lua')
local passed = 0
local function eq(a, b) assert(a == b, 'expected '..tostring(b)..', got '..tostring(a)) end
local function near(a, b) assert(math.abs(a-b) < 1e-7, tostring(a)..' differs from '..tostring(b)) end
local function test(name, fn) fn(); passed = passed + 1; print('PASS '..name) end
local function chunk(text, name, env) local f=assert(loadstring(text, '@'..name)); setfenv(f,env); return f() end
local function environment(version)
  local env = setmetatable({extensions = {}, warnings = {}, hooks = {}}, {__index = _G})
  env.jsonReadFile = function() return {tagid='ML3WUXJ6G', version_string=version or '1.3.0', resource_id=38681} end
  env.log = function(_, _, message) env.warnings[#env.warnings+1] = message end
  env.extensions.hookUpdate = function(name) env.hooks[#env.hooks+1] = name end
  local compat = chunk(compatSource, 'fluidCompat.lua', env)
  env.require = function(name) eq(name, 'horizonRewind/fluidCompat'); return compat end
  return env, compat
end

local geFixture = [====[
local puddles, smears, trails, streams, droplets, splashes, absorbs, grains = {}, {}, {}, {}, {}, {}, {}, {}
local mergeTimer, animTime, updateStarve, updateTicks, upTime = 0, 0, 0, 0, 0
local stateDirty, ownDirty, recovering = true, false, {}
local calls = {broadcast=0, draw=0, reset=0, recovering=0, leaks=0}
local function broadcastState() calls.broadcast=calls.broadcast+1 end
local function drawFluidFX() calls.draw=calls.draw+1 end
local function touch()
  return puddles, smears, trails, streams, droplets, splashes, absorbs, grains,
    mergeTimer, animTime, updateStarve, updateTicks, upTime, stateDirty, ownDirty, recovering,
    broadcastState, drawFluidFX
end
local M={}
M.mpOwnChunks=touch; M.mpApplyOwner=touch; M.reportWheelTracks=touch; M.reportPour=touch; M.onPreRender=touch
M.onUpdate=function(real,sim) touch(); upTime=upTime+real; animTime=animTime+sim; if droplets[1] then droplets[1].age=droplets[1].age+sim end end
M.reportLeaks=function() touch(); calls.leaks=calls.leaks+1 end
M.vehicleRecovering=function(id) touch(); calls.recovering=calls.recovering+1; recovering[id]=upTime end
M.onVehicleResetted=function() touch(); calls.reset=calls.reset+1; puddles={} end
M.seed=function(value, amount)
  puddles={}; for i=1,amount or 1 do puddles[i]={x=i,y=value,z=0,vol=value,type=1,r=1,t0=.01,rot=0,peak=value} end
  smears={{x=value}}; trails={a={x=value}}; streams={a={rate=value}}
  droplets={{x=value,age=value}}; splashes={{age=value}}; absorbs={{kg=value}}; grains={{kg=value}}
end
M.inspect=function() return {puddles=puddles,smears=smears,trails=trails,streams=streams,droplets=droplets,splashes=splashes,absorbs=absorbs,grains=grains,calls=calls} end
return M
]====]

local function geHarness(version)
  local env, compat = environment(version)
  local fluid = chunk(geFixture, 'lua/ge/extensions/fluidspill/main.lua', env)
  env.extensions.fluidspill_main = fluid
  local adapter = chunk(geSource, 'horizonRewindFluids.lua', env)
  adapter.configure(7, 1)
  return adapter, fluid, env, compat
end

test('world marks and Lua droplets seek together; cancel restores immutable live state', function()
  local a,f = geHarness()
  for i=1,10 do f.seed(i); a.record(.2) end
  eq(a.begin(7,1),true); eq(a.seek(1),true)
  local s=f.inspect(); near(s.puddles[1].vol,5); near(s.smears[1].x,5); near(s.droplets[1].age,5)
  s.puddles[1].vol=999; eq(a.seek(1),true); near(f.inspect().puddles[1].vol,5)
  f.onUpdate(1,1); f.reportLeaks(); f.onVehicleResetted(7)
  eq(f.inspect().calls.leaks,0); eq(f.inspect().calls.reset,0); near(f.inspect().droplets[1].age,5)
  eq(a.finish(1,true),true); near(f.inspect().puddles[1].vol,10)
  eq(f.inspect().calls.broadcast,1)
end)

test('committing fluid history deletes its future and records a new branch', function()
  local a,f=geHarness()
  for i=1,10 do f.seed(i); a.record(.2) end
  a.begin(7,1); a.seek(1); a.finish(1,false)
  near(f.inspect().puddles[1].vol,5)
  f.seed(77); a.record(.2); a.begin(7,1); a.seek(.2)
  near(f.inspect().puddles[1].vol,5)
  a.finish(0,true); near(f.inspect().puddles[1].vol,77)
end)

test('fluid clock follows fractional vehicle cursor without cumulative sample rounding', function()
  local a,f=geHarness()
  for i=1,10 do f.seed(i); a.record(.2) end
  a.begin(7,1); a.finish(.87,false)
  near(a.getStatus().availableSeconds,.93)
  f.seed(88); a.record(.2); a.begin(7,1); a.finish(.13,false)
  near(a.getStatus().availableSeconds,1)
end)

test('abort restores native callbacks and reset can resume compatibility', function()
  local a,f=geHarness()
  f.seed(1); a.record(.2); a.arm(7,1); f.vehicleRecovering(7)
  eq(f.inspect().calls.recovering,0)
  a.releaseNative(); eq(f.inspect().calls.recovering,1)
  f.vehicleRecovering(7); eq(f.inspect().calls.recovering,2)
  a.begin(7,1); a.abort(); f.onVehicleResetted(7); f.reportLeaks()
  eq(f.inspect().calls.reset,1); eq(f.inspect().calls.leaks,1)
  f.vehicleRecovering(7); eq(f.inspect().calls.recovering,3)
  a.configure(7,2); f.seed(2); a.record(.2); a.reset(); f.seed(3); a.record(.2)
  eq(a.begin(7,2),true)
end)

test('fluid history enforces time, sample, item and memory limits', function()
  local a,f=geHarness()
  for i=1,120 do f.seed(i,500); a.record(.2) end
  local status=a.getStatus()
  assert(status.samples <=101); assert(status.estimatedHistoryBytes<=status.budgetBytes)
  assert(status.availableSeconds<=20.21)
  f.seed(999,4200); a.record(.2)
  a.arm(7,1); f.vehicleRecovering(7)
  eq(f.inspect().calls.recovering,0)
  eq(a.getStatus().samples,0); eq(a.begin(7,1),false)
  eq(f.inspect().calls.recovering,1)
  f.vehicleRecovering(7); eq(f.inspect().calls.recovering,2)
end)

test('wrong versions and multiplayer never alter foreign callbacks', function()
  local a,f,env=geHarness('1.4.0')
  eq(a.getStatus().supported,false); eq(a.begin(7,1),false)
  f.onVehicleResetted(7); eq(f.inspect().calls.reset,1)
  local warnings=#env.warnings; a.record(.2); a.record(.2); eq(#env.warnings,warnings)
  a,f,env=geHarness(); env.extensions.fluidspill_mp={active=function() return true end}
  f.seed(1); a.record(.2); eq(a.getStatus().samples,0); eq(a.begin(7,1),false)
  a.arm(7,1); f.vehicleRecovering(7); eq(f.inspect().calls.recovering,1)
end)

test('late-loaded Fluid Spill is detected without autoloading it', function()
  local env=environment()
  local a=chunk(geSource,'horizonRewindFluids.lua',env)
  a.configure(7,1); eq(a.getStatus().supported,false)
  local f=chunk(geFixture,'lua/ge/extensions/fluidspill/main.lua',env)
  env.extensions.fluidspill_main=f; f.seed(3); a.record(.2)
  eq(a.getStatus().supported,true); eq(a.getStatus().samples,1)
end)

test('foreign wrapper chains retain safe native delegation after adapter abort', function()
  local a,f=geHarness()
  local update,reset,recover,leak=f.onUpdate,f.onVehicleResetted,f.vehicleRecovering,f.reportLeaks
  f.onUpdate=function(...) return update(...) end
  f.onVehicleResetted=function(...) return reset(...) end
  f.vehicleRecovering=function(...) return recover(...) end
  f.reportLeaks=function(...) return leak(...) end
  f.seed(1); a.record(.2); a.begin(7,1); a.abort()
  f.onUpdate(1,1); f.onVehicleResetted(7); f.vehicleRecovering(7); f.reportLeaks()
  local calls=f.inspect().calls
  eq(calls.reset,1); eq(calls.recovering,1); eq(calls.leaks,1)
end)

test('module replacement restores the old live state without changing the new module', function()
  local a,f,env=geHarness()
  f.seed(1); a.record(.2); f.seed(2); a.record(.2); a.begin(7,1); a.seek(.2)
  near(f.inspect().puddles[1].vol,1)
  local replacement=chunk(geFixture,'lua/ge/extensions/fluidspill/main.lua',env)
  replacement.seed(99); env.extensions.fluidspill_main=replacement
  a.record(.2)
  near(f.inspect().puddles[1].vol,2); near(replacement.inspect().puddles[1].vol,99)
end)

test('plain table validation rejects userdata-like/metatable/cyclic state without mutation', function()
  local _,compat=environment()
  eq(compat.copy({bad=setmetatable({}, {})}),nil)
  local cycle={}; cycle.self=cycle; eq(compat.copy(cycle),nil)
  eq(compat.copy({n=math.huge}),nil)
end)

-- Loading the unmodified installed source additionally proves that the exact
-- expected closures exist; tests do not distribute a copy of that mod.
if HR_INSTALLED_FLUID_GE_SOURCE then
  test('installed Fluid Spill 1.3.0 private GE signature is recognized', function()
    local env=environment()
    env.getAllVehicles=function() return {} end
    env.guihooks={trigger=function() end}
    env.deepcopy=function(value)
      if type(value)~='table' then return value end
      local t={}; for k,v in pairs(value) do t[k]=env.deepcopy(v) end; return t
    end
    local f=chunk(HR_INSTALLED_FLUID_GE_SOURCE,'lua/ge/extensions/fluidspill/main.lua',env)
    env.extensions.fluidspill_main=f
    local a=chunk(geSource,'horizonRewindFluids.lua',env)
    a.configure(7,1); eq(a.getStatus().supported,true)
    a.record(.2); eq(a.getStatus().samples,1); eq(a.begin(7,1),true); eq(a.seek(.1),true)
    a.onExtensionUnloaded()
  end)
end

if HR_INSTALLED_FLUID_VEHICLE_SOURCE then
  test('installed Fluid Spill vehicle state captures and restores reservoir/grip without refill', function()
    local env,compat=environment()
    env.recovery=nil; env.wheels={wheels={}}
    local f=chunk(HR_INSTALLED_FLUID_VEHICLE_SOURCE,'lua/vehicle/extensions/fluidspill/fluid.lua',env)
    env.extensions.fluidspill_fluid=f
    local a=chunk(vehicleSource,'horizonRewindFluids.lua',env)
    local snapshot=a.capture(); assert(snapshot,'installed vehicle schema unsupported')
    snapshot.reservoir={o=2.25,c=4}; snapshot.burstLeft.o=.17; snapshot.slick[1]={o=.5,c=.2}
    a.setRewinding(true); f.onReset(); eq(a.restore(snapshot),true)
    local restored=a.capture(); near(restored.reservoir.o,2.25); near(restored.burstLeft.o,.17); near(restored.slick[1].o,.5)
    restored.reservoir.o=999; near(a.capture().reservoir.o,2.25)
    a.setRewinding(false); f.onReset(); eq(a.capture().reservoir.o,nil)
    a.onExtensionUnloaded()
  end)
end

print('FLUID_SPECS_PASSED '..passed)
