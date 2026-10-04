-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Horizon Rewind: original player-vehicle recorder for BeamNG.drive 0.39.
local M = {}
local ffi = require('ffi')
local History = require('horizonRewind/history')
local WheelInterpolation = require('horizonRewind/wheelInterpolation')
local history = History.new(20, 401)
local session, enabled, phase = 0, false, 'disabled'
local clock, accumulator, reportClock = 0, 0, 0
local nodeIds, beamIds = {}, {}
local wheelGeometry = {}
local localCouplers = {}
local cursor, liveFrame, restoreFrame, impulseFrame
local restoreCancel, waitingForReset = false, false
local preparedForReset = false
local detachedRestore = false
local pendingConfiguration
local sampleInterval, maxSeconds = 0.05, 20
local trafficVehicle = false
local historySegment = 0
local scratch = vec3()
local completeRestore
local resetCallback
local drivingInputs = {steering=true, throttle=true, brake=true, clutch=true, parkingbrake=true}
local deviceFields = {'outputAV1','outputAV2','inputAV','virtualMassAV','gearIndex',
  'gearRatio','desiredGearRatio','gearRatioChangeRate','shiftLossCoef',
  'gearIndex1','gearIndex2','gearRatio1','gearRatio2','clutchAV1','clutchAV2',
  'clutchAngle1','clutchAngle2','clutchRatio1','clutchRatio2','clutchRatio'}

local function notify(event, data)
  obj:queueGameEngineLua(string.format(
    'if extensions.horizonRewind then extensions.horizonRewind.onVehicleMessage(%d,%d,%q,%s) end',
    obj:getId(), session, event, serialize(data or {})))
end

local function available()
  return math.min(maxSeconds, history:duration())
end

local function indexVehicle()
  nodeIds, beamIds = {}, {}
  local nodeNames = {}
  for _, node in pairs(v.data.nodes) do
    nodeIds[#nodeIds + 1] = node.cid
    if node.name then nodeNames[node.name] = node.cid end
  end
  for _, beam in pairs(v.data.beams) do beamIds[#beamIds + 1] = beam.cid end
  table.sort(nodeIds)
  table.sort(beamIds)
  wheelGeometry = WheelInterpolation.index(v.data.wheels, nodeIds, v.data.flexbodies, v.data.nodes)
  localCouplers = {}
  -- Local latches have precise node pairs in the stock controller definition.
  -- Trailer/external couplers are deliberately outside the player-car scope.
  for _, definition in pairs(v.data.controller or {}) do
    if definition.fileName == 'advancedCouplerControl' and type(definition.couplerNodes) == 'table' then
      local header = definition.couplerNodes[1]
      if type(header) == 'table' then
        for i=2,#definition.couplerNodes do
          local row, values = definition.couplerNodes[i], {}
          if type(row) == 'table' then
            for column,key in ipairs(header) do values[key] = row[column] end
            local cid = nodeNames[values.cid1]
            if cid then
              localCouplers[#localCouplers+1] = {cid = cid, name = definition.name,
                otherCid = nodeNames[type(values.cid2) == 'table' and values.cid2[1] or values.cid2],
                strength = values.autoCouplingStrength or 40000,
                radius = math.max(values.autoCouplingRadius or 0.01, values.couplingStartRadius or 0),
                speed = values.autoCouplingSpeed or 0.2}
            end
          end
        end
      end
    end
  end
end

-- Third-party vehicles and props may have no engine or incomplete state
-- callbacks. Optional systems must not disable the structural recorder.
local function optionalCall(fn, ...)
  if type(fn) ~= 'function' then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
end

local function fluids(method, ...)
  local extension = type(extensions) == 'table' and rawget(extensions, 'horizonRewindFluids')
  return type(extension) == 'table' and optionalCall(extension[method], ...) or nil
end

local function effects(method)
  local extension = type(extensions) == 'table' and rawget(extensions, 'horizonRewindEffects')
  if type(extension) == 'table' then optionalCall(extension[method]) end
end

local function tires(method, ...)
  local extension = type(extensions) == 'table' and rawget(extensions, 'horizonRewindTires')
  return type(extension) == 'table' and optionalCall(extension[method], ...) or nil
end

local function materials(method, ...)
  local extension = type(extensions) == 'table' and rawget(extensions, 'horizonRewindMaterials')
  return type(extension) == 'table' and optionalCall(extension[method], ...) or nil
end

local function transmission(method, ...)
  local extension = type(extensions) == 'table' and rawget(extensions, 'horizonRewindTransmission')
  return type(extension) == 'table' and optionalCall(extension[method], ...) or nil
end

local function dirt(method, ...)
  local extension = type(extensions)=='table' and rawget(extensions,'horizonRewindDirt')
  return type(extension)=='table' and optionalCall(extension[method],...) or nil
end

local function removeResetCallback()
  if not resetCallback then return end
  local callback = resetCallback
  resetCallback = nil
  callback.armed = false
  if onVehicleReset == callback.wrapper then onVehicleReset = callback.original end
end

local function captureInputSmoothing()
  local result = {}
  for name, state in pairs(type(input) == 'table' and input.state or {}) do
    if type(state) == 'table' then
      local entry = {state = state, value = state.val, eventTime = state.osClockHP,
        filter=state.filter, angle=state.angle, lockType=state.lockType, source=state.source}
      for _, key in ipairs({'smootherKBD', 'smootherPAD'}) do
        local smoother = state[key]
        if smoother then entry[key] = optionalCall(smoother.value, smoother) end
      end
      result[name] = entry
    end
  end
  return result
end

local function restoreInputSmoothing(saved)
  for name, entry in pairs(saved) do
    local state = type(input) == 'table' and input.state and input.state[name]
    -- Spawn/reset controllers inject untimestamped parking-brake commands.
    -- Retain the driver's current controls across our synchronous reset, while
    -- allowing a genuinely newer timestamped input to take precedence.
    if drivingInputs[name] and state == entry.state
      and (state.osClockHP == nil or state.osClockHP == entry.eventTime) then
      state.val, state.filter, state.osClockHP = entry.value, entry.filter, entry.eventTime
      state.angle, state.lockType, state.source = entry.angle, entry.lockType, entry.source
    end
    if state == entry.state and state.val == entry.value and state.osClockHP == entry.eventTime then
      for _, key in ipairs({'smootherKBD', 'smootherPAD'}) do
        local smoother = state[key]
        if smoother and entry[key] ~= nil then optionalCall(smoother.set, smoother, entry[key]) end
      end
    end
  end
end

local function captureLocalCouplers()
  local result = {}
  local attached = type(beamstate) == 'table' and beamstate.attachedCouplers or {}
  for _, pair in ipairs(localCouplers) do
    local connection = attached[pair.cid]
    result[pair.cid] = connection and connection.obj2id == obj:getId() and connection.obj2nodeId or false
  end
  return result
end

local function restoreLocalCouplers(frame)
  if not frame.localCouplers or type(obj.attachLocalCoupler) ~= 'function' then return end
  for _, pair in ipairs(localCouplers) do
    local target = frame.localCouplers[pair.cid]
    local group = frame.controllers and frame.controllers[(pair.name or '')..'_groupState']
    -- Cancels spawn-time latch searches even when the recorded panel was open.
    obj:detachCoupler(pair.cid, group == 'broken' and math.huge or 0)
    if type(target) == 'number' then
      -- Nodes already occupy their recorded attached positions. Lock at the
      -- spawn radius instead of starting the controller's slow close impulse.
      obj:attachLocalCoupler(pair.cid, target, pair.strength, pair.radius, pair.radius, pair.speed, true)
    elseif group == 'broken' and type(controller) == 'table' then
      -- A reset starts an unattached latch search. Cancelling that search has
      -- no native detach event, so restore the controller's broken metadata.
      local control = optionalCall(controller.getController, pair.name)
      if control then optionalCall(control.onCouplerDetached, pair.cid, obj:getId(), pair.otherCid, math.huge) end
    end
  end
end

local function optionalState(system)
  local state = type(system) == 'table' and optionalCall(system.getState)
  return state and optionalCall(deepcopy, state) or nil
end

local function devices()
  local data = type(powertrain) == 'table' and optionalCall(powertrain.getDevices)
  return type(data) == 'table' and data or {}
end

local function storages()
  local data = type(energyStorage) == 'table' and optionalCall(energyStorage.getStorages)
  return type(data) == 'table' and data or {}
end

local function hydraulicStates()
  return type(hydros) == 'table' and type(hydros.hydros) == 'table' and hydros.hydros or {}
end

local function restoreOptionalState(system, state)
  if type(system) ~= 'table' or not state then return end
  local copy = optionalCall(deepcopy, state)
  if copy then optionalCall(system.setState, copy) end
end

local function captureRotation()
  -- This is the native recovery path's raw vehicle rotation convention.
  local ok, rotation = pcall(function()
    return quatFromDir(-obj:getDirectionVector(), obj:getDirectionVectorUp())
  end)
  if ok and rotation then return {rotation.x, rotation.y, rotation.z, rotation.w} end
  if type(obj.getInitialQuaternion) == 'function' then
    local valid, x, y, z, w = pcall(obj.getInitialQuaternion, obj)
    if valid and type(x) == 'number' and type(w) == 'number' then return {x,y,z,w} end
  end
  return {0,0,0,1}
end

local function interpolateRotation(a, b, alpha)
  local dot = 0
  for i=1,4 do dot = dot + a[i]*b[i] end
  local sign = dot < 0 and -1 or 1
  dot = math.min(1, math.abs(dot))
  local wa, wb = 1-alpha, alpha
  if dot < 0.9995 then
    local angle = math.acos(dot)
    local denominator = math.sin(angle)
    wa, wb = math.sin((1-alpha)*angle)/denominator, math.sin(alpha*angle)/denominator
  end
  local result, length = {}, 0
  for i=1,4 do result[i] = a[i]*wa + b[i]*wb*sign; length = length + result[i]*result[i] end
  length = math.sqrt(length)
  if length < 1e-12 then return {0,0,0,1} end
  for i=1,4 do result[i] = result[i]/length end
  return result
end

local function snapshot()
  local pos = obj:getPosition()
  local velocity = optionalCall(obj.getVelocity, obj)
  local f = {time = clock, segment = historySegment, origin = {pos.x, pos.y, pos.z}, rotation = captureRotation(),
    velocity = velocity and {velocity.x, velocity.y, velocity.z} or nil,
    nodes = ffi.new('float[?]', #nodeIds * 7),
    beams = ffi.new('float[?]', #beamIds * 2),
    broken = ffi.new('uint8_t[?]', #beamIds),
    hydros = {}, devices = {}, storage = {},
    controllers = optionalState(controller),
    powertrain = optionalState(powertrain), fluidState = fluids('capture'), tireState = tires('capture'),
    localCouplers = captureLocalCouplers(), materialState = materials('capture'), transmissionState = transmission('capture'), dirtState = dirt('capture')}
  for i, cid in ipairs(nodeIds) do
    local p, velocity = obj:getNodePosition(cid), obj:getNodeVelocityVector(cid)
    local k = (i - 1) * 7
    f.nodes[k], f.nodes[k+1], f.nodes[k+2] = p.x, p.y, p.z
    f.nodes[k+3], f.nodes[k+4], f.nodes[k+5] = velocity.x, velocity.y, velocity.z
    f.nodes[k+6] = obj:getNodeMass(cid)
  end
  for i, cid in ipairs(beamIds) do
    f.beams[(i-1)*2] = obj:getBeamRestLength(cid)
    f.beams[(i-1)*2+1] = obj:getBeamDeformation(cid)
    f.broken[i-1] = obj:beamIsBroken(cid) and 1 or 0
  end
  for k, h in pairs(hydraulicStates()) do
    if type(h) == 'table' then f.hydros[k] = h.state end
  end
  -- These scalars supplement public controller state for RPM/gear continuity.
  -- They do not constitute a complete thermal/mechanical simulation snapshot.
  for name, device in pairs(devices()) do
    local state = {}
    if type(device) == 'table' then
      for _, key in ipairs(deviceFields) do
        if type(device[key]) == 'number' then state[key] = device[key] end
      end
    end
    f.devices[name] = state
  end
  for name, storage in pairs(storages()) do
    if type(storage) == 'table' and type(storage.storedEnergy) == 'number' then f.storage[name] = storage.storedEnergy end
  end
  f.topology = ffi.string(f.broken, #beamIds)
  if trafficVehicle and type(ai) == 'table' then
    -- getState returns the whole AI module, including functions. Only copy the
    -- public driving options; route planning restarts at the restored pose.
    f.ai = {}
    for _, key in ipairs({'mode','speedMode','routeSpeed','extAggression','cutOffDrivability',
      'driveInLaneFlag','extAvoidCars','targetObjectID'}) do
      local value = ai[key]
      if type(value) == 'number' or type(value) == 'string' or type(value) == 'boolean' then f.ai[key] = value end
    end
  end
  return f
end

local function applyGeometry(a, b, alpha)
  b, alpha = b or a, alpha or 0
  -- Node positions are world-oriented offsets from obj:getPosition(). Capture
  -- the origin once: moving the reference node changes it during commitLoad.
  local origin = obj:getPosition()
  local wheelPlans = WheelInterpolation.plans(wheelGeometry, a, b, alpha)
  for i, cid in ipairs(nodeIds) do
    local k = (i - 1) * 7
    local plan = wheelPlans[k]
    if plan then
      local x,y,z = WheelInterpolation.position(plan,k)
      scratch:set(x-origin.x,y-origin.y,z-origin.z)
    else
      scratch:set(
        a.origin[1] + a.nodes[k] + (b.origin[1] - a.origin[1] + b.nodes[k] - a.nodes[k]) * alpha - origin.x,
        a.origin[2] + a.nodes[k+1] + (b.origin[2] - a.origin[2] + b.nodes[k+1] - a.nodes[k+1]) * alpha - origin.y,
        a.origin[3] + a.nodes[k+2] + (b.origin[3] - a.origin[3] + b.nodes[k+2] - a.nodes[k+2]) * alpha - origin.z)
    end
    obj:setNodePosition(cid, scratch)
  end
  obj:commitLoad()
end

local function fail(err)
  log('E', 'horizonRewind', tostring(err))
  enabled, phase = false, 'error'
  effects('abort')
  tires('abort')
  dirt('abort')
  notify('error', {message = tostring(err)})
end

local function protected(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then fail(err) end
end

local function configure(token, active, seconds, isTraffic)
  if detachedRestore then
    pendingConfiguration = {token, active, seconds, isTraffic}
    return
  end
  removeResetCallback()
  fluids('setRewinding', false)
  effects('abort')
  tires('abort')
  dirt('abort')
  session = token
  enabled, phase = active == true, active and 'recording' or 'disabled'
  if seconds == 20 or seconds == 40 or seconds == 60 then maxSeconds = seconds end
  trafficVehicle = isTraffic == true
  history = History.new(maxSeconds, math.ceil(maxSeconds / sampleInterval) + 2)
  cursor, liveFrame, restoreFrame, impulseFrame = nil, nil, nil, nil
  waitingForReset, preparedForReset = false, false
  detachedRestore = false
  clock, accumulator, reportClock = 0, 0, 0
  indexVehicle()
  if enabled then
    assert(#nodeIds > 0 and #beamIds > 0, 'This vehicle has no rewindable structure.')
    assert(type(obj.applyForceVector) == 'function', 'Node momentum API unavailable in this version.')
    enablePhysicsStepHook()
    history:push(snapshot())
  end
  notify('configured', {availableSeconds = 0, nodeCount = #nodeIds, beamCount = #beamIds})
end

local function begin(token)
  if token ~= session or not enabled or phase ~= 'recording' then return end
  if history:count() < 2 or available() < 0.1 then
    notify('empty', {message = 'Drive for a moment to build rewind history.'})
    return
  end
  liveFrame = snapshot()
  if liveFrame.time > history:latest().time then history:push(liveFrame) end
  cursor, phase = history:latest().time, 'rewinding'
  fluids('setRewinding', true)
  effects('begin')
  tires('begin', liveFrame.tireState)
  dirt('begin')
  notify('began', {availableSeconds = available()})
end

local function bracket(time)
  local a,b,alpha=history:bracket(time)
  if a==b or alpha==0 then return a,b,alpha end
  local discontinuous=a.segment~=b.segment or a.topology~=b.topology
  local distance,speed2=0,0
  for axis=1,3 do
    distance=distance+(b.origin[axis]-a.origin[axis])^2
    speed2=speed2+((a.velocity and a.velocity[axis]) or 0)^2
  end
  -- Never blend a teleport/reset or a change in broken-beam topology into an
  -- invented physical car. The earlier intact frame remains intact.
  local maxTravel=2+math.sqrt(speed2)*math.max(0,b.time-a.time)*2
  if discontinuous or distance>maxTravel*maxTravel then return a,a,0 end
  return a,b,alpha
end

local function seek(token, secondsAgo)
  if token ~= session or phase ~= 'rewinding' then return end
  local amount = math.max(0, math.min(available(), tonumber(secondsAgo) or 0))
  cursor = history:latest().time - amount
  local a, b, alpha = bracket(cursor)
  applyGeometry(a, b, alpha)
  tires('preview', a.tireState)
  materials('apply', a.materialState)
  dirt('preview', a.dirtState)
  local pos = obj:getPosition()
  notify('previewed', {rewindSeconds = amount, position = {pos.x, pos.y, pos.z}})
end

-- The release pose must be exactly the pose that was shown, rather than the
-- preceding 20 Hz sample. Discrete controller/topology state uses that sample.
local function frameAt(time)
  local a, b, alpha = bracket(time)
  if a == b or alpha == 0 then return a end
  local f = {}
  for key, value in pairs(a) do f[key] = value end
  f.time, f.origin = time, {}
  if a.velocity and b.velocity then
    f.velocity = {}
    for axis=1,3 do f.velocity[axis]=a.velocity[axis]+(b.velocity[axis]-a.velocity[axis])*alpha end
  end
  f.rotation = interpolateRotation(a.rotation, b.rotation, alpha)
  f.nodes = ffi.new('float[?]', #nodeIds * 7)
  f.beams = ffi.new('float[?]', #beamIds * 2)
  for axis=1,3 do f.origin[axis] = a.origin[axis] + (b.origin[axis]-a.origin[axis])*alpha end
  local plans = WheelInterpolation.plans(wheelGeometry, a, b, alpha)
  for i=1,#nodeIds do
    local k = (i-1)*7
    for component=0,6 do f.nodes[k+component] = a.nodes[k+component] + (b.nodes[k+component]-a.nodes[k+component])*alpha end
    if plans[k] then
      local x,y,z = WheelInterpolation.position(plans[k],k)
      f.nodes[k],f.nodes[k+1],f.nodes[k+2] = x-f.origin[1],y-f.origin[2],z-f.origin[3]
    end
  end
  for k=0,#beamIds*2-1 do f.beams[k] = a.beams[k] + (b.beams[k]-a.beams[k])*alpha end
  return f
end

local function queueDetachedExecute()
  -- A disabled/unloaded GE manager cannot prepare the live cancellation pose.
  -- Keep this handoff independent, including its native reset baseline.
  local p, r = restoreFrame.origin, restoreFrame.rotation
  obj:queueGameEngineLua(string.format(
    'local car=be:getObjectByID(%d); if car then if type(car.setOriginalTransform)=="function" then car:setOriginalTransform(%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g) end; car:queueLuaCommand(%q) end',
    obj:getId(), p[1], p[2], p[3], r[1], r[2], r[3], r[4],
    'if extensions.horizonRewindVehicle then extensions.horizonRewindVehicle.executeRestore('..session..',true) end'))
end

local function finish(token, cancel)
  if token ~= session or phase ~= 'rewinding' then return end
  restoreCancel = cancel == true
  restoreFrame = restoreCancel and liveFrame or frameAt(cursor)
  phase, waitingForReset, preparedForReset = 'restoring', false, true
  if detachedRestore then queueDetachedExecute()
  else notify('restorePrepared', {position = restoreFrame.origin, rotation = restoreFrame.rotation}) end
end

local function executeRestore(token, detachedPrepared)
  if token ~= session or phase ~= 'restoring' or not restoreFrame or not preparedForReset then return end
  -- Ignore an old manager acknowledgement after abort replaced the target.
  if detachedRestore and not detachedPrepared then return end
  preparedForReset, waitingForReset = false, true
  tires('prepare', restoreFrame.tireState)
  -- onReset runs before the native Lua subsystems reset. Restore only after
  -- the complete callback returns. GE has already aligned the native reset
  -- baseline with this pose. Leave other mods' later wrappers intact if chained.
  if type(onVehicleReset) == 'function' then
    local callback = {original = onVehicleReset, armed = true}
    callback.wrapper = function(...)
      if not callback.armed then return callback.original(...) end
      local smoothing = captureInputSmoothing()
      local ok, err = pcall(callback.original, ...)
      if resetCallback == callback then removeResetCallback() end
      if not ok then fail(err); return end
      protected(completeRestore, token, true)
      restoreInputSmoothing(smoothing)
    end
    resetCallback, onVehicleReset = callback, callback.wrapper
  end
  obj:requestReset(RESET_PHYSICS)
end

completeRestore = function(token, atomicReset)
  if token ~= session or phase ~= 'restoring' or not restoreFrame or preparedForReset then return end
  local f = restoreFrame
  local selectedSeconds = restoreCancel and 0 or math.max(0, (liveFrame and liveFrame.time or history:latest().time)-f.time)
  applyGeometry(f)
  for i, cid in ipairs(nodeIds) do obj:setNodeMass(cid, f.nodes[(i-1)*7+6]) end
  for i, cid in ipairs(beamIds) do
    obj:setBeamLength(cid, f.beams[(i-1)*2])
    if f.broken[i-1] == 1 then obj:breakBeam(cid) end
    local deformation = f.beams[(i-1)*2+1]
    if deformation > 0 then beamstate.onBeamDeformed(cid, deformation) end
  end
  local currentHydros = hydraulicStates()
  for k, value in pairs(f.hydros) do
    if type(currentHydros[k]) == 'table' then currentHydros[k].state = value end
  end
  restoreOptionalState(controller, f.controllers)
  restoreOptionalState(powertrain, f.powertrain)
  local currentDevices = devices()
  for name, state in pairs(f.devices) do
    local device = currentDevices[name]
    if type(device) == 'table' then
      if state.gearIndex then optionalCall(device.setGearIndex, device, state.gearIndex) end
      for key, value in pairs(state) do
        if key ~= 'gearIndex' then device[key] = value end
      end
      if state.outputAV1 and type(device.lastOutputAV1) == 'number' then device.lastOutputAV1 = state.outputAV1 end
    end
  end
  optionalCall(type(powertrain)=='table' and powertrain.calculateTreeInertia)
  transmission('restore', f.transmissionState)
  if trafficVehicle and f.ai then restoreOptionalState(ai, f.ai) end
  local currentStorages = storages()
  for name, value in pairs(f.storage) do
    local storage = currentStorages[name]
    if type(storage) == 'table' and type(storage.setStoredEnergy) == 'function' then
      optionalCall(storage.setStoredEnergy, storage, value)
    elseif type(storage) == 'table' and type(storage.setRemainingRatio) == 'function' and type(storage.energyCapacity) == 'number' and storage.energyCapacity > 0 then
      optionalCall(storage.setRemainingRatio, storage, value / storage.energyCapacity)
    end
  end
  obj:commitLoad()
  restoreLocalCouplers(f)
  fluids('restore', f.fluidState)
  tires('restore', f.tireState)
  materials('apply', f.materialState)
  dirt('restore', f.dirtState)
  fluids('setRewinding', false)
  effects('finish')
  tires('finish')
  dirt('finish')
  impulseFrame = f
  if not restoreCancel then
    history:truncateAfter(f.time)
    clock = f.time
  end
  accumulator = 0
  cursor, liveFrame, restoreFrame = nil, nil, nil
  phase = enabled and 'recording' or 'disabled'
  local position = obj:getPosition()
  if detachedRestore and atomicReset then
    -- The manager may already be gone; finish visual repair independently.
    obj:queueGameEngineLua(string.format(
      'local car=be:getObjectByID(%d); if car then car:resetBrokenFlexMesh() end', obj:getId()))
  end
  notify('restored', {availableSeconds = available(), cancelled = restoreCancel,
    position = {position.x, position.y, position.z}, velocity = f.velocity, resetFlexMesh = atomicReset == true,
    actualSelectedSeconds = selectedSeconds, rewindSeconds = selectedSeconds})
  if detachedRestore then
    detachedRestore = false
    history:clear()
    if pendingConfiguration then
      local pending = pendingConfiguration
      pendingConfiguration = nil
      configure(pending[1], pending[2], pending[3], pending[4])
      impulseFrame = f
      if enabled then
        local initial = {}
        for key, value in pairs(f) do initial[key] = value end
        initial.time = 0
        history:clear()
        history:push(initial)
      end
    end
  end
end

local function queueDetachedRestore()
  -- Independent of the GE extension, which may already be unloading.
  obj:queueGameEngineLua(string.format(
    'local car=be:getObjectByID(%d); if car then car:resetBrokenFlexMesh(); car:queueLuaCommand(%q) end',
    obj:getId(), 'if extensions.horizonRewindVehicle then extensions.horizonRewindVehicle.completeRestore('..session..') end'))
end

local function abort(token)
  if token ~= session then return end
  if phase == 'rewinding' or phase == 'restoring' or liveFrame then
    enabled, detachedRestore = false, true
    if phase ~= 'restoring' then
      phase = 'rewinding'
      finish(token, true)
    else
      restoreFrame, restoreCancel = liveFrame or restoreFrame, true
      if preparedForReset then queueDetachedExecute()
      elseif not waitingForReset then queueDetachedRestore() end
    end
  else
    configure(token, false)
  end
end

local function onPhysicsStep(dt)
  if not impulseFrame or dt <= 0 then return end
  local f = impulseFrame
  impulseFrame = nil
  -- One impulse per node restores translation, rotation, wheel spin and
  -- separate fragments together. Verified using the game's physics console.
  for i, cid in ipairs(nodeIds) do
    local k = (i-1)*7
    local velocity = obj:getNodeVelocityVector(cid)
    local massOverDt = obj:getNodeMass(cid) / dt
    scratch:set((f.nodes[k+3]-velocity.x)*massOverDt,
      (f.nodes[k+4]-velocity.y)*massOverDt, (f.nodes[k+5]-velocity.z)*massOverDt)
    obj:applyForceVector(cid, scratch)
  end
end

local function updateGFX(dt)
  if not enabled or phase ~= 'recording' or dt <= 0 or impulseFrame then return end
  clock, accumulator, reportClock = clock + dt, accumulator + dt, reportClock + dt
  if accumulator >= sampleInterval then
    accumulator = accumulator % sampleInterval
    -- Only capture the actual state; never fabricate missed samples after a hitch.
    history:push(snapshot())
  end
  if reportClock >= 0.2 then
    reportClock = 0
    notify('recording', {availableSeconds = available()})
  end
end

local function onReset()
  if waitingForReset then
    waitingForReset = false
    if resetCallback and resetCallback.armed then return end
    if detachedRestore then queueDetachedRestore() else notify('resetReady') end
    return
  end
  -- Traffic can reset itself after a collision without changing its VM or
  -- node layout. Keep its pre-impact frames; otherwise one AI repair cuts the
  -- entire group's shared history to zero. Player recovery still starts fresh.
  local retain = trafficVehicle and enabled and phase == 'recording'
  historySegment=historySegment+1
  if not retain then history:clear(); clock = 0 end
  preparedForReset = false
  tires('abort')
  dirt(retain and 'finish' or 'abort')
  accumulator = 0
  cursor, liveFrame, restoreFrame, impulseFrame = nil, nil, nil, nil
  phase = enabled and 'recording' or 'disabled'
  notify(retain and 'recording' or 'reset', {availableSeconds = available()})
end

M.configure = function(...) protected(configure, ...) end
M.begin = function(...) protected(begin, ...) end
M.seek = function(...) protected(seek, ...) end
M.finish = function(...) protected(finish, ...) end
M.executeRestore = function(...) protected(executeRestore, ...) end
M.completeRestore = function(...) protected(completeRestore, ...) end
M.abort = function(...) protected(abort, ...) end
M.updateGFX = function(...) protected(updateGFX, ...) end
M.onPhysicsStep = function(...) protected(onPhysicsStep, ...) end
M.onReset = onReset
M.onSerialize = function() return {} end -- Never serialize the live FFI buffer.
M.onDeserialized = function() removeResetCallback(); fluids('setRewinding', false); effects('abort'); tires('abort'); dirt('abort'); enabled, phase = false, 'disabled'; history:clear() end
M.onExtensionUnloaded = function() removeResetCallback(); fluids('setRewinding', false); effects('abort'); tires('abort'); dirt('abort'); enabled = false; history:clear() end
return M
