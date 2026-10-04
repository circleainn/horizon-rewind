-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Automatic player-car history and a reversible bridge to stock recovery input.
local M = {}
M.dependencies = {'horizonRewindCamera', 'horizonRewindFluids', 'horizonRewindParticles'}
local enabled, vehicleId, session = false, nil, 0
local wanted = true
local vehicleBundle, failedVehicleId, failedBundle
local phase, message = 'disabled', 'Waiting for Freeroam.'
local availableSeconds, rewindSeconds, speed = 0, 0, 2
local held, ready, busy, finishing, cancelRequested = false, false, false, false, false
local pauseOwned, wasPaused, disableAfterRestore = false, false, false
local elapsed, heartbeat, sentSeconds = 0, 0, 0
local maxSeconds = 20
local recoveryHeld, recoveryTime, recoveryPending = false, 0, false
local recoveryDelay = 0.7 -- Stock recovery.lua uses this tap/hold threshold.
local pendingRestore
local visibleRestoreUpdates = 0
local settingsPath = '/settings/horizonRewind.json'
local speeds = {[0.25] = true, [0.5] = true, [1] = true, [2] = true, [4] = true, [8] = true}
local effectModules = {'horizonRewindFluids', 'horizonRewindParticles'}
local failedEffects = {}

local function effectsCall(method, ...)
  for _, name in ipairs(effectModules) do
    local effect = extensions and extensions[name]
    if effect and type(effect[method]) == 'function' and (not failedEffects[name] or method == 'abort') then
      local ok, err = pcall(effect[method], ...)
      if not ok then
        failedEffects[name] = true
        if effect.abort then pcall(effect.abort) end
        log('W', 'horizonRewind', name..' stopped: '..tostring(err))
      end
    end
  end
end

local function loadSettings()
  if type(jsonReadFile) ~= 'function' then return end
  local ok, data = pcall(jsonReadFile, settingsPath)
  if ok and type(data) == 'table' and speeds[tonumber(data.speed)] then
    speed = tonumber(data.speed)
  end
end

local function canRun()
  local replayState = core_replay and core_replay.state and core_replay.state.state
  if replayState == 'recording' or replayState == 'playback' then
    return false, 'Live rewind is suspended while a saved replay is active.'
  end
  if not core_gamestate or not core_gamestate.state or core_gamestate.state.state ~= 'freeroam'
    or (career_career and career_career.isActive and career_career.isActive())
    or (gameplay_missions_missionManager and gameplay_missions_missionManager.getForegroundMissionId
      and gameplay_missions_missionManager.getForegroundMissionId()) then
    return false, 'Live rewind is available in Freeroam.'
  end
  return true
end

local function publish()
  guihooks.trigger('HorizonRewindState', {enabled = enabled, phase = phase,
    availableSeconds = availableSeconds, rewindSeconds = rewindSeconds,
    maxSeconds = maxSeconds, speed = speed, message = message,
    damageMode = 'experimental'})
end

local function vehicle()
  return vehicleId and be:getObjectByID(vehicleId) or nil
end

local function cameraCall(method, id)
  local camera = extensions and extensions.horizonRewindCamera
  if camera and camera[method] then
    local ok, err = pcall(camera[method], id)
    if not ok then
      if camera.abort then pcall(camera.abort) end
      log('W', 'horizonRewind', 'Camera preservation failed: '..tostring(err))
    end
  end
end

local function publishGeometry(position)
  local car = vehicle()
  if car and position then
    car:setClusterPosRelRot(car:getRefNodeId(), position[1], position[2], position[3], 0, 0, 0, 1)
  end
end

local function bundleFor(id)
  return id and core_vehicle_manager and core_vehicle_manager.getVehicleData
    and core_vehicle_manager.getVehicleData(id) or nil
end

local function queue(method, args)
  local car = vehicle()
  if not car then return false end
  car:queueLuaCommand('if extensions.horizonRewindVehicle then extensions.horizonRewindVehicle.'
    ..method..'('..session..(args and ','..args or '')..') end')
  return true
end

local function queueRecovery(method, args)
  local car = vehicle()
  if not car then return false end
  car:queueLuaCommand('if extensions.horizonRewindRecovery then extensions.horizonRewindRecovery.'
    ..method..'('..session..(args and ','..args or '')..') end')
  return true
end

local function restorePause()
  if pauseOwned then
    pauseOwned = false
    if simTimeAuthority.getPause() ~= wasPaused then simTimeAuthority.pause(wasPaused) end
  end
end

local function clearOperation()
  held, ready, busy, finishing, cancelRequested = false, false, false, false, false
  elapsed, rewindSeconds, sentSeconds = 0, 0, 0
  recoveryHeld, recoveryTime, recoveryPending = false, 0, false
  pendingRestore = nil
  visibleRestoreUpdates = 0
end

local function detach()
  queue('abort')
  queueRecovery('configure', 'false')
  cameraCall('abort')
  effectsCall('abort')
  restorePause()
  session = session + 1
  vehicleId, vehicleBundle, availableSeconds = nil, nil, 0
  disableAfterRestore = false
  clearOperation()
end

local function attach(car)
  if vehicleId then detach() end
  session, vehicleId = session + 1, car:getID()
  vehicleBundle = bundleFor(vehicleId)
  failedVehicleId, failedBundle = nil, nil
  failedEffects = {}
  effectsCall('configure', vehicleId, session)
  phase, message = 'recording', 'Hold your recovery control to rewind.'
  car:queueLuaCommand("extensions.load('horizonRewindEffects'); extensions.load('horizonRewindFluids'); extensions.load('horizonRewindTires'); extensions.load('horizonRewindVehicle'); extensions.horizonRewindVehicle.configure("..session..',true)')
  car:queueLuaCommand("extensions.load('horizonRewindRecovery'); extensions.horizonRewindRecovery.configure("..session..',true)')
  publish()
end

local function setActive(value)
  value = value == true
  if not value and (phase == 'rewinding' or phase == 'restoring') then
    disableAfterRestore, held, cancelRequested = true, false, true
    return
  end
  if value == enabled then
    if value then disableAfterRestore = false end
    publish(); return
  end
  enabled = value
  if enabled then
    local car = be:getPlayerVehicle(0)
    if car then attach(car) else phase, message = 'recording', 'Load Freeroam and select a vehicle.' end
  else
    detach()
    phase, message = 'disabled', 'Live rewind is off.'
  end
  publish()
end

local function setEnabled(value)
  wanted = value == true
  if wanted then failedVehicleId, failedBundle = nil, nil end
  local allowed, reason = canRun()
  setActive(wanted and allowed)
  if wanted and not allowed and phase == 'disabled' then message = reason; publish() end
end

local function beginRewind()
  if not enabled then setEnabled(true); return end
  if recoveryHeld or recoveryPending then return end
  if phase ~= 'recording' or not vehicle() then return end
  if core_replay and core_replay.state and core_replay.state.state ~= 'inactive' then
    -- Some versions use nil before their first replay. Only actual replay
    -- recording/playback conflicts; this mod never stops or replaces either.
    local replayState = core_replay.state.state
    if replayState == 'recording' or replayState == 'playback' then
      message = 'Stop the saved replay before using live rewind.'; publish(); return
    end
  end
  if availableSeconds < 0.1 then message = 'Drive for a moment to build rewind history.'; publish(); return end
  wasPaused = simTimeAuthority.getPause()
  if not wasPaused then simTimeAuthority.pause(true) end
  pauseOwned = true
  held, ready, busy, finishing, cancelRequested = true, false, true, false, false
  elapsed, rewindSeconds, sentSeconds = 0, 0, 0
  phase, message = 'rewinding', 'Release to drive from here. Cancel returns to where you started.'
  effectsCall('begin', vehicleId, session)
  queue('begin')
  publish()
end

local function endRewind() held = false end
local function cancelRewind()
  if phase == 'rewinding' then held, cancelRequested = false, true end
end

local function recoveryDown(id, token)
  if not enabled or id ~= vehicleId or token ~= session then return end
  if phase ~= 'recording' then
    -- A second input must not run native recovery over a pending restore.
    queueRecovery('takeOver')
    return
  end
  if recoveryHeld or recoveryPending then return end
  recoveryHeld, recoveryTime = true, 0
  effectsCall('arm', vehicleId, session)
end

local function recoveryUp(id, token)
  if not enabled or id ~= vehicleId or token ~= session then return end
  recoveryHeld, recoveryTime, recoveryPending = false, 0, false
  if phase == 'recording' then effectsCall('releaseNative') end
  if phase == 'rewinding' then endRewind() end
end

local function recoveryTakenOver(id, token, accepted)
  if not enabled or id ~= vehicleId or token ~= session or not recoveryPending then return end
  recoveryPending, recoveryTime = false, 0
  -- The release can reach VLua before the queued takeover. Only a positive
  -- acknowledgment guarantees native recovery has not already reset the car.
  if accepted and canRun() then beginRewind() else effectsCall('releaseNative') end
end

local function setSpeed(value)
  value = tonumber(value)
  if not speeds[value] then return end
  speed = value
  if type(jsonWriteFile) == 'function' then
    local ok, result = pcall(jsonWriteFile, settingsPath, {speed = speed}, true)
    if not ok or result == false then log('W', 'horizonRewind', 'Could not save rewind speed.') end
  end
  publish()
end

local function commitRestore(data)
  -- Seed translation directly before physics resumes. Applying the entire
  -- restored road speed as a force looks like a crash to acceleration sensors.
  -- The vehicle-side impulse then supplies only remaining per-node motion.
  local car = vehicle()
  if car and data.velocity and type(car.applyClusterVelocityScaleAdd)=='function' then
    local v = data.velocity
    car:applyClusterVelocityScaleAdd(car:getRefNodeId(), 0, v[1], v[2], v[3])
  end
  effectsCall('finish', data.actualSelectedSeconds or data.rewindSeconds or sentSeconds, data.cancelled == true)
  cameraCall('afterRestore', vehicleId)
  restorePause(); clearOperation()
  phase, message = 'recording', data.cancelled and 'Returned to the start of rewind.' or 'Hold your recovery control to rewind.'
  if disableAfterRestore then disableAfterRestore = false; setActive(false) end
  publish()
end

local function restoredGeometryVisible(data)
  if not data.position then return true end
  local car = vehicle()
  if not car then return false end
  local pos = car:getPosition()
  local dx, dy, dz = pos.x-data.position[1], pos.y-data.position[2], pos.z-data.position[3]
  return dx*dx + dy*dy + dz*dz < 0.0025
end

local function onVehicleMessage(id, token, event, data)
  if not enabled or id ~= vehicleId or token ~= session then return end
  data = data or {}
  -- Acks are asynchronous. Ignore events for a different operation phase and
  -- do not let ordinary recording messages keep a stuck command alive.
  if event == 'configured' or event == 'recording' then
    if phase ~= 'recording' then return end
  elseif event == 'began' then
    if phase ~= 'rewinding' or ready then return end
    ready, busy, elapsed = true, false, 0
  elseif event == 'previewed' then
    if phase ~= 'rewinding' or not ready or not busy then return end
    -- Vehicle-Lua changes alone leave the GE/display transform cached while
    -- simulation is paused. This no-reset native placement publishes the
    -- changed cluster to GE without advancing the rest of the world.
    publishGeometry(data.position)
    effectsCall('seek', data.rewindSeconds or sentSeconds)
    busy, elapsed = false, 0
  elseif event == 'empty' then
    if phase ~= 'rewinding' or ready then return end
    effectsCall('abort')
    effectsCall('configure', vehicleId, session)
    restorePause(); clearOperation(); phase, message = 'recording', data.message
    if disableAfterRestore then disableAfterRestore = false; setActive(false) end
  elseif event == 'restorePrepared' then
    if phase ~= 'restoring' or not busy then return end
    elapsed = 0
    local car = vehicle()
    -- The native reset publishes its own baseline before new geometry reaches
    -- GE. Place that baseline at the chosen rewind pose first, as ordinary
    -- recovery does when it establishes the recovered vehicle transform.
    if car and data.position and data.rotation and type(car.setOriginalTransform) == 'function' then
      local p, r = data.position, data.rotation
      car:setOriginalTransform(p[1], p[2], p[3], r[1], r[2], r[3], r[4])
    end
    queue('executeRestore')
  elseif event == 'resetReady' then
    if phase ~= 'restoring' or not busy then return end
    elapsed = 0
    local car = vehicle()
    if car then car:resetBrokenFlexMesh() end
    queue('completeRestore')
  elseif event == 'restored' then
    if phase ~= 'restoring' then return end
    -- The native reset baseline now matches the selected pose. Repair mesh
    -- links after final geometry is ready; older callbacks keep resetReady.
    if data.resetFlexMesh then
      local car = vehicle()
      if car then car:resetBrokenFlexMesh() end
    end
    publishGeometry(data.position)
    -- Native publication is asynchronous. Keep the camera frozen and physics
    -- paused until GE has the selected pose, rather than exposing the reset
    -- baseline for a frame and interpreting that teleport as vehicle speed.
    pendingRestore, busy, elapsed, visibleRestoreUpdates = data, true, 0, 0
  elseif event == 'reset' then
    cameraCall('abort')
    effectsCall('reset')
    restorePause(); clearOperation(); phase, message = 'recording', 'Vehicle reset. Building a fresh history.'
    if disableAfterRestore then disableAfterRestore = false; setActive(false) end
  elseif event == 'error' then
    failedVehicleId, failedBundle = vehicleId, vehicleBundle
    detach(); enabled = false
    phase, message = 'error', 'Rewind stopped for this vehicle: '..tostring(data.message)..' Reset or replace it to retry.'
  else
    return
  end
  if enabled and data.availableSeconds then availableSeconds = data.availableSeconds end
  publish()
end

local function invalidateVehicle(id)
  if id == failedVehicleId then failedVehicleId, failedBundle = nil, nil end
  if id ~= vehicleId then return end
  -- Vehicle Selector and part changes can rebuild the VLua VM while retaining
  -- the GE object ID. The old token belongs to that destroyed VM: do not send
  -- abort/restore commands to the replacement's unrelated node structure.
  cameraCall('abort')
  effectsCall('abort')
  restorePause()
  session = session + 1
  vehicleId, vehicleBundle, availableSeconds = nil, nil, 0
  disableAfterRestore = false
  clearOperation()
  phase, message = 'recording', 'Preparing rewind for the replacement vehicle.'
  publish()
end

local function onUpdate(dtReal, dtSim)
  local allowed, reason = canRun()
  local car = be:getPlayerVehicle(0)
  local currentId = car and car:getID()
  local currentBundle = bundleFor(currentId)
  if wanted and allowed and not enabled and (not failedVehicleId
      or (currentId and (currentId ~= failedVehicleId or currentBundle ~= failedBundle))) then
    setActive(true)
  end
  if not enabled then return end
  if currentId == vehicleId and currentBundle and vehicleBundle and currentBundle ~= vehicleBundle then
    invalidateVehicle(vehicleId)
  end
  if not car or car:getID() ~= vehicleId then
    if (phase == 'rewinding' or phase == 'restoring') and vehicle() then
      -- Keep the old car and session until its cancellation restores the
      -- original state; discarding its history here would strand the preview.
      held, cancelRequested = false, true
    else
      detach()
      if car then attach(car) else phase, message = 'recording', 'Waiting for a player vehicle.' end
      publish()
      return
    end
  end
  if not allowed then
    if phase == 'recording' then
      setActive(false); message = reason; publish()
      return
    end
    -- A replay starting during an outstanding rewind must still allow its
    -- cancellation and watchdog to run, or the simulation can stay paused.
    held, cancelRequested, disableAfterRestore = false, true, true
  end
  if phase == 'recording' then effectsCall('record', dtSim) end
  if recoveryHeld and phase == 'recording' then
    recoveryTime = recoveryTime + dtReal
    if recoveryTime >= recoveryDelay then
      recoveryHeld = false
      if availableSeconds >= 0.1 then
        -- VLua receives this before begin: stop the stock preview without
        -- invoking its reset/teleport, then use the recorded physical car.
        recoveryPending, recoveryTime = true, 0
        queueRecovery('takeOver')
      else
        -- No usable detailed history yet; preserve native recovery instead.
        queueRecovery('passthrough')
        effectsCall('releaseNative')
      end
    end
  end
  if recoveryPending then
    recoveryTime = recoveryTime + dtReal
    if recoveryTime > 5 then
      recoveryPending, recoveryTime = false, 0
      queueRecovery('passthrough')
      effectsCall('releaseNative')
      message = 'Rewind input did not respond; using normal recovery.'
      publish()
    end
  end
  if phase == 'rewinding' or phase == 'restoring' then
    if not simTimeAuthority.getPause() then simTimeAuthority.pause(true) end
    if pendingRestore then
      visibleRestoreUpdates = restoredGeometryVisible(pendingRestore) and visibleRestoreUpdates + 1 or 0
      if visibleRestoreUpdates >= 2 then
        commitRestore(pendingRestore)
        return
      end
    end
    if busy then elapsed = elapsed + dtReal end
    if busy and elapsed > 5 then
      failedVehicleId, failedBundle = vehicleId, vehicleBundle
      detach(); enabled = false; phase, message = 'error', 'The vehicle did not respond. Reset or replace it to retry.'; publish(); return
    end
    -- Accumulate wall time while a preview is in flight. Acknowledgment delay
    -- changes display cadence, not the requested rewind speed.
    if phase == 'rewinding' and held then
      rewindSeconds = math.min(availableSeconds, rewindSeconds + dtReal * speed)
    end
    if phase == 'rewinding' and ready and not busy then
      if not cancelRequested and rewindSeconds > sentSeconds then
        busy = queue('seek', string.format('%.9g', rewindSeconds))
        sentSeconds, elapsed = rewindSeconds, 0
      elseif not held and not finishing then
        finishing, busy, phase = true, true, 'restoring'
        elapsed = 0
        message = 'Restoring the car and its momentum...'
        cameraCall('beforeRestore', vehicleId)
        queue('finish', tostring(cancelRequested))
        publish()
      end
    end
    heartbeat = heartbeat + dtReal
    if heartbeat >= 0.1 then heartbeat = 0; publish() end
  end
end

local function onClientEndMission()
  detach()
  failedVehicleId, failedBundle = nil, nil
  enabled, phase, message = false, 'disabled', 'Waiting for Freeroam.'
  publish()
end

M.setEnabled, M.beginRewind, M.endRewind = setEnabled, beginRewind, endRewind
M.cancelRewind, M.setSpeed, M.requestState = cancelRewind, setSpeed, publish
M.recoveryDown, M.recoveryUp = recoveryDown, recoveryUp
M.recoveryTakenOver = recoveryTakenOver
M.onVehicleMessage, M.onUpdate = onVehicleMessage, onUpdate
M.onClientEndMission = onClientEndMission
M.onVehicleSpawned = invalidateVehicle
M.onVehicleDestroyed = invalidateVehicle
M.onVehicleResetted = function(id)
  -- Ordinary physics resets keep the VLua module; its onReset clears history.
  -- Retry a failed vehicle only after the user has explicitly reset it.
  if id == failedVehicleId then failedVehicleId, failedBundle = nil, nil end
end
M.onExtensionLoaded = function() loadSettings(); setExtensionUnloadMode(M, 'manual'); setEnabled(true) end
M.onExtensionUnloaded = detach
M.onSerialize = function()
  detach()
  enabled, phase, message = false, 'disabled', 'Rebuilding history after saving state.'
  publish()
  return {}
end
return M
