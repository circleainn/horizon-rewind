-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Optional compatibility with the inspected Detachable Tires 0.5.3.0.41.81
-- and Tire Impact Punctures 1.4. No third-party source or configuration is copied.
local M = {}
local detachable, puncture, detachableRefs, punctureRefs
local seenDetach, seenPuncture, active, hooks = nil, nil, false, {}
local ownReset = false
local settleRemaining = 0
local warned, delayedCollision = {}, nil
local previewVisibility
local privateNames = {'visualSwapDone','tireLatchActivated','tireLatchReleased','tireLatchActivationLength',
  'dualCarcassActivated','pairedNextSectorByWheel','tireWatchLast','autoDebeadingState',
  'detachedTireSelfCollisionPending','detachedTireSelfCollisionApplied','detachedTireSelfCollisionOriginal',
  'preDetachCollisionFrictionActive','meshProtectionArmed','seenBrokenReinf','seenBrokenExtra',
  'releasedTriangleCids','beamFlagOriginalByCid'}
local punctureNames = {'wheelContactLatched','wheelLastDistance','virtualContactState',
  'triangleGateArmed','triangleGateReason','triangleGateArmInfo'}
local publicFields = {
  _beadStressIntegration = {'records','windows','baseline'},
  _pressureCoupling = {'applied'},
  _rolloverDetach = {'records','previousOmega','previousOmegaValid','filteredAlpha'},
  _alphaReassert = {'pending'},
  _detachedSpeedoIsolation = {'excluded'},
}
local function warn(message)
  if warned[message] then return end
  warned[message] = true
  if log then log('W','horizonRewindTires',message) end
end

-- Bounded plain state only. Native wheel objects, topology and callbacks retain
-- their existing ownership. Infinity is a legitimate detector distance sentinel.
local function copy(value)
  local count, seen = 0, {}
  local function visit(entry, depth)
    local kind = type(entry)
    if kind == 'nil' or kind == 'boolean' then return entry end
    if kind == 'number' then assert(entry == entry, 'NaN tire state'); return entry end
    if kind == 'string' then assert(#entry < 4096, 'oversized tire state string'); return entry end
    assert(kind == 'table' and not getmetatable(entry) and not seen[entry] and depth < 9, 'unsupported tire state')
    seen[entry] = true
    local out = {}
    for key, item in pairs(entry) do
      count = count + 1
      assert(count <= 16000 and (type(key) == 'string' or type(key) == 'number'), 'tire state budget exceeded')
      out[key] = visit(item, depth+1)
    end
    seen[entry] = nil
    return out
  end
  return visit(value,0)
end
local function replace(target, source)
  for key in pairs(target) do target[key] = nil end
  for key,value in pairs(source) do target[key] = value end
end
local function discoverRefs(roots, names, suffix)
  assert(debug and debug.getupvalue and debug.getinfo, 'closure inspection unavailable')
  local wanted, refs, seen, count = {}, {}, {}, 0
  for _,name in ipairs(names) do wanted[name] = true end
  local function walk(fn, depth)
    if type(fn) ~= 'function' or seen[fn] or depth > 18 then return end
    seen[fn], count = true, count+1
    assert(count <= 1024, 'tire closure graph exceeded budget')
    local info = debug.getinfo(fn,'S')
    if not info.source:gsub('\\','/'):find(suffix,1,true) then return end
    for index=1,128 do
      local name,value = debug.getupvalue(fn,index)
      if not name then break end
      if wanted[name] then
        assert(type(value)=='table', 'unexpected tire state '..name)
        refs[name] = refs[name] or {fn,index}
      end
      if type(value)=='function' then walk(value,depth+1) end
    end
  end
  for _,fn in ipairs(roots) do walk(fn,0) end
  for name in pairs(wanted) do assert(refs[name], 'missing tire state '..name) end
  return refs
end
local function get(refs,name)
  local ref = refs[name]
  local _,value = debug.getupvalue(ref[1],ref[2])
  assert(type(value)=='table', 'tire state binding changed')
  return value
end
local function gate(owner,key,resetHook,settleHook)
  local base = owner and owner[key]
  if type(base) ~= 'function' then return end
  local entry = {owner=owner,key=key,base=base,attached=true}
  entry.wrapper = function(...)
    local blocked = resetHook and active and ownReset or (not resetHook and (active or (settleHook and settleRemaining>0)))
    if not entry.attached or not blocked then return base(...) end
  end
  owner[key] = entry.wrapper
  hooks[#hooks+1] = entry
end
local function refreshHooks()
  if extensions and extensions.hookUpdate then
    extensions.hookUpdate('updateGFX'); extensions.hookUpdate('onReset'); extensions.hookUpdate('onVehicleResetted')
  end
end
local function detachHooks()
  for _,entry in ipairs(hooks) do
    entry.attached = false
    if entry.owner[entry.key] == entry.wrapper then entry.owner[entry.key] = entry.base end
  end
  hooks = {}
  refreshHooks()
end
local function discover()
  local d = extensions and rawget(extensions,'tireDebeadingDebug')
  local p = extensions and rawget(extensions,'selfPunctureGlobal')
  if d == seenDetach and p == seenPuncture then return end
  if d ~= seenDetach then delayedCollision=nil; settleRemaining=0 end
  detachHooks()
  seenDetach,seenPuncture,detachable,puncture,detachableRefs,punctureRefs = d,p,nil,nil,nil,nil
  if d then
    local ok,refs = pcall(function()
      assert(d._hubImpactDeflation and d._hubImpactDeflation.version=='0.5.3.0.41.81', 'unsupported Detachable Tires version')
      assert(d._meshSwapPolicy and d._visualLifecycle and d._pressureCoupling and d._beadStressIntegration, 'unknown Detachable Tires schema')
      return discoverRefs({d.updateGFX,d.onReset,d._handleVehicleReset,d.forceRestoreStockTireCollisionState,d.enableDetachedTireSelfCollision},privateNames,'tireDebeadingDebug.lua')
    end)
    if ok then
      detachable,detachableRefs = d,refs
      gate(d,'updateGFX',false,true); gate(d,'onReset',true); gate(d,'onVehicleResetted',true)
      gate(d._hubImpactDeflation,'observe',false,true); gate(d._hubImpactDeflation,'physicsStep',false,true)
      gate(d._detachedSpeedoIsolation,'preStockWheelVelocity'); gate(d._detachedSpeedoIsolation,'postStockWheelVelocity')
    else warn(tostring(refs)) end
  end
  if p then
    local ok,refs = pcall(function()
      local info = type(jsonReadFile)=='function' and jsonReadFile('mod_info/MQ3KW6G24/info.json')
      assert(info and info.resource_id==39354 and info.version_string=='1.4', 'unsupported Tire Impact Punctures version')
      return discoverRefs({p.updateGFX,p.onReset,p.dumpStatus},punctureNames,'selfPunctureGlobal.lua')
    end)
    if ok then
      puncture,punctureRefs = p,refs
      gate(p,'updateGFX'); gate(p,'onReset',true)
    else warn(tostring(refs)) end
  end
  refreshHooks()
end
local function runtimeWheel(raw)
  local wheel = wheels and wheels.wheelRotators and wheels.wheelRotators[raw.cid]
  if wheel and wheel.name==raw.name then return wheel end
  for _,candidate in pairs(wheels and wheels.wheels or {}) do
    if candidate.name==raw.name and candidate.node1==raw.node1 and candidate.node2==raw.node2 then return candidate end
  end
end
local function capture()
  discover()
  if not detachable and not puncture then return nil end
  local state = {wheels={},detached={},private={},public={},beamFlags={},puncture={}}
  for _,raw in pairs(v.data.wheels or {}) do
    local wheel = runtimeWheel(raw)
    if wheel and raw.name then
      local group = v.data.pressureGroups and v.data.pressureGroups[raw.pressureGroup]
      state.wheels[raw.name] = {deflated=wheel.isTireDeflated==true,punctured=wheel.isPunctured==true,
        punctureAngle=wheel.punctureAngle,pressure=group and obj:getGroupPressure(group) or nil}
    end
  end
  if detachable then
    for _,name in ipairs(privateNames) do state.private[name] = get(detachableRefs,name) end
    for name,fields in pairs(publicFields) do
      state.public[name] = {}
      for _,field in ipairs(fields) do state.public[name][field] = detachable[name][field] end
    end
    state.physical = detachable._physicalDetachActiveWheels or {}
    for name,raw in pairs(detachable._meshSwapPolicy.finalizedWheels or {}) do
      if type(raw)=='table' then state.detached[name] = true end
    end
    for cid in pairs(state.private.beamFlagOriginalByCid) do
      local beam = v.data.beams[cid]
      if beam then state.beamFlags[cid] = {mesh=beam.disableMeshBreaking,triangle=beam.disableTriangleBreaking} end
    end
    local impact = detachable._hubImpactDeflation.state
    if impact then
      state.impact = {clock=impact.clock,steps=impact.steps,phase=impact.phase,lastSupportAt=impact.lastSupportAt,
        landingAt=impact.landingAt,allSupportSince=impact.allSupportSince,issued=impact.issued,pending={},records={}}
      for key,event in pairs(impact.pending or {}) do
        local plain = {}
        for field,value in pairs(event) do if field~='raw' and field~='runtime' then plain[field]=value end end
        state.impact.pending[key] = plain
      end
      for key,record in pairs(impact.records or {}) do
        state.impact.records[key] = {lastSupportAt=record.lastSupportAt,lastDamaged=record.lastDamaged}
      end
    end
  end
  if puncture then for _,name in ipairs(punctureNames) do state.puncture[name] = get(punctureRefs,name) end end
  return copy(state)
end

function M.capture()
  local ok,state = pcall(capture)
  if ok then return state end
  warn(tostring(state))
end
function M.begin(state)
  discover()
  -- A missing/unsupported snapshot must never suppress the mod's normal reset.
  active = state~=nil and (detachable~=nil or puncture~=nil)
  ownReset = false
  previewVisibility = nil
end
function M.preview(state)
  if not active or not detachable or not state or not state.private.visualSwapDone then return end
  local changed, desired = false, {}
  for _,raw in pairs(v.data.wheels or {}) do
    local visible = state.detached[raw.name]==true or state.private.visualSwapDone[raw.name]==true
    desired[raw.name] = visible
    if not previewVisibility or previewVisibility[raw.name]~=visible then changed=true end
  end
  if not changed then return end
  local life = detachable._visualLifecycle
  local original = life.shouldReplacementBeVisible
  local selection = function(raw) return desired[raw.name]==true end
  life.shouldReplacementBeVisible = selection
  local ok,err = pcall(life.syncCurrentVisualState,'horizon-rewind-preview')
  if life.shouldReplacementBeVisible==selection then life.shouldReplacementBeVisible=original end
  if ok then previewVisibility=desired else warn(tostring(err)) end
end
function M.prepare(state)
  ownReset = active and state~=nil
  if not ownReset then active=false; return end
  if not detachable then return end
  -- Restore Lua-side mesh-break flags before native historical beam breaks.
  for cid,original in pairs(get(detachableRefs,'beamFlagOriginalByCid')) do
    local beam = v.data.beams[cid]
    if beam then beam.disableMeshBreaking,beam.disableTriangleBreaking = original.disableMeshBreaking,original.disableTriangleBreaking end
  end
  for cid,flags in pairs(state.beamFlags or {}) do
    local beam = v.data.beams[cid]
    if beam then beam.disableMeshBreaking,beam.disableTriangleBreaking = flags.mesh,flags.triangle end
  end
end

function M.restore(saved)
  if not saved then return false end
  local ok,state = pcall(copy,saved)
  if not ok then warn(tostring(state)); return false end
  local collisionStillPending = delayedCollision~=nil
  delayedCollision = nil
  for _,raw in pairs(v.data.wheels or {}) do
    local wheel,target = runtimeWheel(raw),state.wheels[raw.name]
    if wheel and target then
      if target.deflated and not wheel.isTireDeflated and beamstate and beamstate.deflateTire then beamstate.deflateTire(raw.cid) end
      wheel.isTireDeflated,wheel.isPunctured = target.deflated,target.punctured
      wheel.punctureAngle = target.punctureAngle or 0
      local group = v.data.pressureGroups and v.data.pressureGroups[raw.pressureGroup]
      if group and target.pressure then obj:setGroupPressure(group,target.pressure) end
    end
  end
  if detachable and state.private.autoDebeadingState then
    -- The installed mod normally suspends its observers during reset settle.
    -- Preserve that safety window without its later stock-state normalization.
    -- This also holds captured or newly completed bead-cascade collision queues.
    settleRemaining = 0.8
    local hadCollisionMutation = next(detachable._collisionMutationLedger or {})~=nil or detachable._collisionMutationAuthorityLatch==true
    for _,name in ipairs(privateNames) do replace(get(detachableRefs,name),state.private[name]) end
    for name,fields in pairs(publicFields) do for _,field in ipairs(fields) do detachable[name][field]=state.public[name][field] end end
    detachable._physicalDetachActiveWheels = state.physical or {}
    detachable._meshSwapPolicy.finalizedWheels = {}
    local registry = detachable._registeredTireByWheelID or {}
    for _,raw in pairs(v.data.wheels or {}) do
      local name = raw.name
      if state.detached[name] then detachable._meshSwapPolicy.finalizedWheels[name] = raw end
      local target = state.wheels[name]
      local record = registry[raw.wheelID]
      if record and target then record.deflationLatched=target.deflated end
    end
    -- Helper beam definitions expose both parked and released coefficients.
    -- Reapply only active helpers; a native reset already rebuilt parked ones.
    for _,fb in pairs(v.data.flexbodies or {}) do
      local name = fb._tireDebeadingWheel
      if state.private.dualCarcassActivated[name] then
        local pressure = state.public._pressureCoupling.applied[name]
        for _,entry in ipairs(fb._tireDebeadingHubDuplicateActivationEntries or {}) do
          if entry.cid and not obj:beamIsBroken(entry.cid) then
            local scale = pressure and (entry.family=='side-copy' and pressure.sideScale or entry.family=='reinf-copy' and pressure.reinfScale) or 1
            obj:setBeamSpringDamp(entry.cid,entry.spring*(scale or 1),entry.damp*(scale or 1),-1,-1)
          end
        end
      end
    end
    local impact = detachable._hubImpactDeflation.state
    if impact and state.impact then
      for _,field in ipairs({'clock','steps','phase','lastSupportAt','landingAt','allSupportSince','issued'}) do impact[field]=state.impact[field] end
      impact.pending = {}
      for key,event in pairs(state.impact.pending) do
        local record = impact.records[key]
        if record then event.raw,event.runtime=record.raw,record.rw; event.generation=impact.generation; impact.pending[key]=event end
      end
      for key,target in pairs(state.impact.records) do
        local record = impact.records[key]
        if record then record.lastSupportAt,record.lastDamaged=target.lastSupportAt,target.lastDamaged end
      end
    end
    detachable._visualLifecycle.syncCurrentVisualState('horizon-rewind')
    -- Detachable Tires documents native stock-node collision rebuilds as unsafe
    -- during reset. Use its own proven restoration after the 0.75 s settle.
    if collisionStillPending or hadCollisionMutation or next(state.private.detachedTireSelfCollisionApplied) then
      delayedCollision = {remaining=0.8,owner=detachable,applied=copy(state.private.detachedTireSelfCollisionApplied)}
    end
  end
  if puncture and next(state.puncture) then
    for _,name in ipairs(punctureNames) do replace(get(punctureRefs,name),state.puncture[name]) end
  end
  return true
end
function M.finish() active=false; ownReset=false end
function M.abort() active=false; ownReset=false end
function M.updateGFX(dt)
  if active or dt<=0 then return end
  settleRemaining = math.max(0,settleRemaining-dt)
  if not delayedCollision then return end
  delayedCollision.remaining = delayedCollision.remaining-dt
  if delayedCollision.remaining>0 then return end
  local pending=delayedCollision
  delayedCollision=nil
  if detachable and detachable==pending.owner and rawget(extensions,'tireDebeadingDebug')==pending.owner then
    local ok,err = pcall(function()
      detachable.forceRestoreStockTireCollisionState()
      local applied=get(detachableRefs,'detachedTireSelfCollisionApplied')
      for name,value in pairs(pending.applied) do
        if value then applied[name]=nil; detachable.enableDetachedTireSelfCollision(name) end
      end
    end)
    if not ok then warn(tostring(err)) end
  end
end
function M.onReset()
  if not ownReset then active=false; delayedCollision=nil; settleRemaining=0 end
end
function M.status() return {detachable=detachable~=nil,puncture=puncture~=nil,active=active,collisionPending=delayedCollision~=nil,settling=settleRemaining>0} end
function M.onExtensionUnloaded() active=false; ownReset=false; delayedCollision=nil; settleRemaining=0; detachHooks() end
return M
