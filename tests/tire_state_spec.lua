local source=assert(testTireStateSource)
local privateNames={'visualSwapDone','tireLatchActivated','tireLatchReleased','tireLatchActivationLength',
  'dualCarcassActivated','pairedNextSectorByWheel','tireWatchLast','autoDebeadingState',
  'detachedTireSelfCollisionPending','detachedTireSelfCollisionApplied','detachedTireSelfCollisionOriginal',
  'preDetachCollisionFrictionActive','meshProtectionArmed','seenBrokenReinf','seenBrokenExtra',
  'releasedTriangleCids','beamFlagOriginalByCid'}
local declarations,fields={},{}
for _,name in ipairs(privateNames) do declarations[#declarations+1]='local '..name..'={}'
  fields[#fields+1]=name..'='..name end
local modSource=table.concat(declarations,'\n')..[[
local M={calls=0,resets=0,restores=0,collisionEnables=0,visual={}}
M.testState=function() return {]]..table.concat(fields,',')..[[} end
M._handleVehicleReset=function() M.resets=M.resets+1; return M.testState() end
M.onReset=M._handleVehicleReset
M.onVehicleResetted=M._handleVehicleReset
M.updateGFX=function() M.calls=M.calls+1; return M.testState() end
M._hubImpactDeflation={version='0.5.3.0.41.81',state={clock=0,steps=0,phase='GROUNDED',issued={},pending={},records={}},
  observe=function() M.calls=M.calls+1 end,physicsStep=function() M.calls=M.calls+1 end}
M._meshSwapPolicy={finalizedWheels={}}
M._beadStressIntegration={records={FL={stress=12}},windows={},baseline={}}
M._pressureCoupling={applied={}}
M._rolloverDetach={records={},previousOmega={},previousOmegaValid=false,filteredAlpha={}}
M._alphaReassert={pending={}}
M._detachedSpeedoIsolation={excluded={}}
M._visualLifecycle={shouldReplacementBeVisible=function(raw) return visualSwapDone[raw.name]==true end}
M._visualLifecycle.syncCurrentVisualState=function()
  for _,raw in pairs(v.data.wheels) do M.visual[raw.name]=M._visualLifecycle.shouldReplacementBeVisible(raw) end
end
M.forceRestoreStockTireCollisionState=function() M.restores=M.restores+1; M._collisionMutationLedger={}; return true end
M.enableDetachedTireSelfCollision=function(name) M.collisionEnables=M.collisionEnables+1; detachedTireSelfCollisionApplied[name]=true end
return M
]]
local function fixture(kind)
  local env=setmetatable({},{__index=_G})
  env.extensions={hookUpdate=function() end}
  env.log=function() end
  env.v={data={wheels={[0]={cid=0,wheelID=0,name='FL',node1=1,node2=2,pressureGroup='FL'}},
    pressureGroups={FL=0},nodes={},beams={[0]={}},flexbodies={}}}
  local runtime={name='FL',node1=1,node2=2,isTireDeflated=false,isPunctured=false,punctureAngle=0}
  env.wheels={wheels={[0]=runtime},wheelRotators={[0]=runtime}}
  local native={pressure=300000,deflations=0,springs={}}
  env.obj={getGroupPressure=function() return native.pressure end,
    setGroupPressure=function(_,_,value) native.pressure=value end,
    beamIsBroken=function() return false end,
    setBeamSpringDamp=function(_,cid,spring,damp) native.springs[cid]={spring,damp} end}
  env.beamstate={deflateTire=function() native.deflations=native.deflations+1; runtime.isTireDeflated=true end}
  local mod
  if kind~='absent' then
    mod=setfenv(assert(loadstring(modSource,'@tireDebeadingDebug.lua')),env)()
    -- Give the discoverable native entry point direct references to named state.
    mod._handleVehicleReset=mod.testState
    mod.onReset=mod.testState
    if kind=='unsupported' then mod._hubImpactDeflation.version='future' end
    if kind=='schema' then mod._pressureCoupling=nil end
    env.extensions.tireDebeadingDebug=mod
  end
  local adapter=setfenv(assert(loadstring(source,'@horizonRewindTires.lua')),env)()
  return adapter,env,mod,native,runtime
end
local count=0
local function test(name,fn) fn();count=count+1;print('TIRE_STATE_PASS '..name) end
test('missing and unsupported mods stay inert',function()
  for _,kind in ipairs({'absent','unsupported','schema'}) do
    local a,_,m=fixture(kind)
    local original=m and m.updateGFX
    assert(a.capture()==nil)
    a.begin(nil);a.prepare(nil);a.finish();a.abort();a.onReset();a.onExtensionUnloaded()
    assert(not a.status().active and (not m or m.updateGFX==original))
  end
end)
test('snapshots are independent and native pressure and helper coefficients return',function()
  local a,env,m,native,wheel=fixture()
  local private=m.testState()
  private.dualCarcassActivated.FL=true
  m._pressureCoupling.applied.FL={sideScale=0.6,reinfScale=0.3}
  env.v.data.flexbodies={{_tireDebeadingWheel='FL',_tireDebeadingHubDuplicateActivationEntries={{cid=7,spring=100,damp=10,family='side-copy'}}}}
  wheel.isTireDeflated=true;wheel.isPunctured=true;native.pressure=110000
  local state=assert(a.capture())
  private.autoDebeadingState.FL={completed=true}
  m._beadStressIntegration.records.FL.stress=99
  wheel.isTireDeflated=false;wheel.isPunctured=false;native.pressure=300000
  a.begin(state);a.prepare(state);assert(a.restore(state));a.finish()
  assert(private.autoDebeadingState.FL==nil and m._beadStressIntegration.records.FL.stress==12)
  assert(wheel.isTireDeflated and wheel.isPunctured and native.pressure==110000 and native.deflations==1)
  assert(native.springs[7][1]==60 and native.springs[7][2]==6)
end)
test('capture failure cannot gate reset or updates',function()
  local a,_,m=fixture()
  m.testState().autoDebeadingState.bad=function() end
  assert(a.capture()==nil)
  a.begin(nil);m.updateGFX();a.prepare(nil)
  assert(m.calls==1 and not a.status().active)
end)
test('only the prepared reset is suppressed; external reset releases guards',function()
  local a,_,m=fixture()
  local state=assert(a.capture())
  a.begin(state);m.updateGFX();assert(m.calls==0)
  assert(type(m.onReset())=='table','External reset callback was swallowed')
  a.onReset();m.updateGFX();assert(m.calls==1 and not a.status().active)
  a.begin(state);a.prepare(state);assert(m.onReset()==nil)
  a.onReset();assert(a.status().active)
  a.finish();m.updateGFX();assert(m.calls==2)
end)
test('preview changes only selected mesh visibility and restores owned callbacks',function()
  local a,_,m=fixture()
  local healthy=assert(a.capture())
  m.testState().visualSwapDone.FL=true
  local detached=assert(a.capture())
  local original=m._visualLifecycle.shouldReplacementBeVisible
  a.begin(detached);a.preview(healthy);assert(m.visual.FL==false)
  a.preview(detached);assert(m.visual.FL==true and m._visualLifecycle.shouldReplacementBeVisible==original)
  a.abort()
end)
test('hook cleanup preserves later wrappers and module replacements',function()
  local a,env,m=fixture()
  local base=m.updateGFX
  local state=assert(a.capture())
  local wrapper=m.updateGFX
  local later=function(...) return wrapper(...) end
  m.updateGFX=later
  a.begin(state);a.onExtensionUnloaded()
  assert(m.updateGFX==later)
  m.updateGFX();assert(m.calls==1)
  env.extensions.tireDebeadingDebug=nil
  assert(a.capture()==nil and not a.status().detachable)
end)
test('collision restoration is delayed and genuine reset cancels stale work',function()
  local a,_,m=fixture()
  local private=m.testState()
  private.detachedTireSelfCollisionApplied.FL=true
  local state=assert(a.capture())
  a.begin(state);a.prepare(state);a.restore(state);a.finish()
  a.updateGFX(0.4);assert(m.restores==0 and a.status().collisionPending)
  a.updateGFX(0.41);assert(m.restores==1 and m.collisionEnables==1 and not a.status().collisionPending)
  a.begin(state);a.prepare(state);a.restore(state);a.finish();a.onReset();a.updateGFX(1)
  assert(m.restores==1 and not a.status().collisionPending)
end)
test('consecutive restores replace pending collision targets and reject old owners',function()
  local a,env,m=fixture()
  local healthy=assert(a.capture())
  m.testState().detachedTireSelfCollisionApplied.FL=true
  local loose=assert(a.capture())
  a.begin(loose);a.prepare(loose);a.restore(loose);a.finish()
  a.begin(healthy);a.prepare(healthy);a.restore(healthy);a.finish();a.updateGFX(1)
  assert(m.restores==1 and m.collisionEnables==0, 'Old detach target survived a newer restore')
  a.begin(loose);a.prepare(loose);a.restore(loose);a.finish()
  env.extensions.tireDebeadingDebug={}
  a.updateGFX(1)
  assert(m.restores==1 and not a.status().collisionPending, 'Deferred work mutated a replaced module')
end)
test('Tire Impact Punctures retains detector history and remains optional',function()
  local a,env,_,native,wheel=fixture('absent')
  env.jsonReadFile=function() return {resource_id=39354,version_string='1.4'} end
  local puncture= setfenv(assert(loadstring([[
    local wheelContactLatched,wheelLastDistance,virtualContactState={},{},{}
    local triangleGateArmed,triangleGateReason,triangleGateArmInfo={},{},{}
    local M={calls=0}
    M.testState=function() return {wheelContactLatched=wheelContactLatched,wheelLastDistance=wheelLastDistance,
      virtualContactState=virtualContactState,triangleGateArmed=triangleGateArmed,
      triangleGateReason=triangleGateReason,triangleGateArmInfo=triangleGateArmInfo} end
    M.updateGFX=function() M.calls=M.calls+1;return M.testState() end
    M.onReset=M.testState
    M.dumpStatus=M.testState
    return M
  ]],'@selfPunctureGlobal.lua')),env)()
  env.extensions.selfPunctureGlobal=puncture
  puncture.testState().wheelContactLatched[0]=true
  puncture.testState().wheelLastDistance[0]=math.huge
  wheel.isPunctured=true;native.pressure=180000
  local state=assert(a.capture())
  assert(a.status().puncture and not a.status().detachable)
  puncture.testState().wheelContactLatched[0]=false
  wheel.isPunctured=false;native.pressure=300000
  a.begin(state);puncture.updateGFX();assert(puncture.calls==0)
  a.prepare(state);a.restore(state);a.finish();puncture.updateGFX()
  assert(puncture.calls==1 and puncture.testState().wheelContactLatched[0] and wheel.isPunctured and native.pressure==180000)
end)
test('partial detach queues and rebound impact pointers survive the safe reset settle',function()
  local a,env,m,_,wheel=fixture()
  local private=m.testState()
  private.autoDebeadingState.FL={physicalDetachActive=true,physicalDetachTimer=0.006,requestedStage=6}
  private.detachedTireSelfCollisionPending.FL={delay=0.01,reason='cascade',allowPartialAttachments=true}
  m._physicalDetachActiveWheels={FL=true}
  m._hubImpactDeflation.state.records[0]={raw=env.v.data.wheels[0],rw=wheel}
  m._hubImpactDeflation.state.pending[0]={raw=env.v.data.wheels[0],runtime=wheel,generation=1,action='DETACH'}
  local state=assert(a.capture())
  assert(state.impact.pending[0].raw==nil and state.impact.pending[0].runtime==nil)
  private.autoDebeadingState.FL.completed=true
  m._hubImpactDeflation.state.generation=7
  a.begin(state);a.prepare(state);a.restore(state);a.finish()
  assert(private.autoDebeadingState.FL.completed==nil and m._physicalDetachActiveWheels.FL)
  assert(m._hubImpactDeflation.state.pending[0].raw==env.v.data.wheels[0]
    and m._hubImpactDeflation.state.pending[0].runtime==wheel and m._hubImpactDeflation.state.pending[0].generation==7)
  m.updateGFX(0.02);m._hubImpactDeflation.observe();assert(m.calls==0 and a.status().settling)
  a.updateGFX(0.79);m.updateGFX(0.02);assert(m.calls==0)
  a.updateGFX(0.02);m.updateGFX(0.02)
  assert(m.calls==1 and not a.status().settling and private.detachedTireSelfCollisionPending.FL.delay==0.01)
end)
print('TIRE_STATE_SPEC_DONE '..count)
