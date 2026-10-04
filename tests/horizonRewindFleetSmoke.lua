-- Isolated, real-engine vehicle lifecycle regression. This extension never
-- enables the mod: normal modScript autoload and native recovery input must work.
local M = {}
local cases = {
  {label = 'pickup baseline', action = 'initial', model = 'pickup'},
  {label = 'replace with ETK 800', action = 'replace', model = 'etk800'},
  {label = 'replace with Covet', action = 'replace', model = 'covet'},
  {label = 'Covet crash latches and resume', action = 'replace', model = 'covet', damage = true},
  {label = 'replace with Scintilla', action = 'replace', model = 'scintilla'},
  {label = 'replace with city bus', action = 'replace', model = 'citybus'},
  {label = 'replace with Wigeon', action = 'replace', model = 'wigeon'},
  {label = 'replace Wigeon with same model', action = 'replace', model = 'wigeon'},
  {label = 'reload Wigeon vehicle Lua', action = 'reload', model = 'wigeon'},
  {label = 'spawn and enter another Covet', action = 'spawn', model = 'covet'},
  {label = 'switch back to existing Wigeon', action = 'switch', model = 'wigeon'}
}
local timer, stage, stageTime, caseIndex = 0, 'boot', 0, 0
local results, events, current = {}, {}, nil
local hookedExtension, wrapper, savedExistingId
local cameraProbe
local reportPath = 'horizon-rewind-fleet.json'
local driveStart, rewindStart, previewPosition, resumeStart
local driveSimTime, resumedSimTime, holdStarted = 0, 0, 0

local function position(car) return vec3(car:getPosition()) end
local function modelOf(car) return car and car:getJBeamFilename() or nil end
local function speedOf(car) return vec3(car:getVelocity()):length() end

local function clearCameraProbe()
  if cameraProbe and cameraProbe.instance.reset == cameraProbe.wrapper then
    cameraProbe.instance.reset = cameraProbe.original
  end
  cameraProbe = nil
end

local function selectCamera()
  if not core_camera or not core_camera.setByName or not core_camera.getCameraDataById then
    current.cameraCheck = 'Camera APIs unavailable'
    return
  end
  local names = {'orbit', 'chase', 'driver'}
  local name = names[((caseIndex - 1) % #names) + 1]
  local modes = core_camera.getCameraDataById(current.vehicleId)
  local cam = modes and modes[name]
  if not cam then
    current.cameraCheck = 'Requested camera unavailable: '..name
    return
  end
  core_camera.setByName(0, name, false)
  current.cameraMode = name
  current.cameraResetCount = 0
  if name == 'orbit' then
    cam.camRot:set(43, -24, 0)
    cam.camLastRot:set(math.rad(43), math.rad(-24), 0)
    cam.camDist, cam.camLastDist = 9.25, 9.25
    current.cameraOrbitRotation, current.cameraOrbitDistance = {43, -24, 0}, 9.25
  end
  if type(cam.reset) == 'function' then
    local testCase, original = current, cam.reset
    local resetWrapper = function(self, ...)
      if current == testCase then testCase.cameraResetCount = testCase.cameraResetCount + 1 end
      return original(self, ...)
    end
    cameraProbe = {instance = cam, original = original, wrapper = resetWrapper}
    cam.reset = resetWrapper
  end
end

local function cameraError(checkpoint)
  if not current.cameraMode then return nil end
  local active = core_camera.getActiveCamName(0)
  current['cameraMode'..checkpoint] = active
  if active ~= current.cameraMode then return 'camera changed from '..current.cameraMode..' to '..tostring(active)..' at '..checkpoint end
  if current.cameraResetCount ~= 0 then return 'active camera reset '..current.cameraResetCount..' times during rewind' end
  if current.cameraMode == 'orbit' then
    local cam = core_camera.getCameraDataById(current.vehicleId).orbit
    local rotationError = vec3(cam.camRot):distance(vec3(current.cameraOrbitRotation))
    local distanceError = math.abs(cam.camDist - current.cameraOrbitDistance)
    current['cameraRotationError'..checkpoint], current['cameraDistanceError'..checkpoint] = rotationError, distanceError
    if rotationError > 0.05 or distanceError > 0.05 then return 'orbit view or zoom changed at '..checkpoint end
  end
  return nil
end

local function report(ok, detail)
  jsonWriteFile(reportPath, {
    ok = ok, detail = detail, stage = stage, elapsedSeconds = timer,
    completedCases = #results, expectedCases = #cases,
    cases = results, currentCase = current, events = events
  }, true)
end

local function finish(ok, detail)
  if stage == 'done' then return end
  clearCameraProbe()
  stage = 'done'
  report(ok, detail)
  log(ok and 'I' or 'E', 'HR_FLEET', detail)
  shutdown(ok and 0 or 1)
end

local function setStage(value)
  stage, stageTime = value, 0
  if current then current.stage = value end
  log('I', 'HR_FLEET', 'Case '..caseIndex..' '..(current and current.label or '')..' -> '..value)
  report(nil, 'Running')
end

local function eventReceived(id, token, event, data)
  data = data or {}
  if event ~= 'recording' and event ~= 'previewed' then
    events[#events + 1] = {time = timer, caseIndex = caseIndex, id = id,
      token = token, event = event, data = data}
  end
  if not current then return end
  local car = be:getPlayerVehicle(0)
  if not car or car:getID() ~= id or modelOf(car) ~= current.model then return end
  if current.vehicleId and current.vehicleId ~= id then return end
  if current.token and token < current.token then return end
  -- A newly loaded vehicle VM must produce fresh telemetry. No manual
  -- configure/enable calls are used to mask the same-ID replacement regression.
  if event == 'configured' or event == 'recording' then
    current.vehicleId, current.token = id, token
    current.availableSeconds = data.availableSeconds or 0
    current.telemetryTime = timer
    current.recordingMessages = (current.recordingMessages or 0) + (event == 'recording' and 1 or 0)
    if event == 'configured' then
      current.configuredTime = timer
      current.nodeCount, current.beamCount = data.nodeCount, data.beamCount
    end
  elseif event == 'began' then
    current.beganTime = timer
    current.holdDelaySeconds = timer - holdStarted
    current.beganCount = (current.beganCount or 0) + 1
    if current.holdDelaySeconds < 0.69 then finish(false, current.label..': rewind began before hold threshold') end
  elseif event == 'previewed' then
    current.previewCount = (current.previewCount or 0) + 1
    current.previewTime = timer
    current.previewPosition = data.position
  elseif event == 'restored' then
    current.restoredTime, current.cancelled = timer, data.cancelled
    if not data.position then finish(false, current.label..': restored acknowledgment omitted position'); return end
    current.restorePosition = data.position
    current.atomicRestore = data.resetFlexMesh == true
  elseif event == 'error' then
    finish(false, current.label..': vehicle error: '..tostring(data.message))
  end
end

local function installHook()
  local extension = extensions.horizonRewind
  if not extension then return false end
  if extension ~= hookedExtension or extension.onVehicleMessage ~= wrapper then
    local original = extension.onVehicleMessage
    wrapper = function(id, token, event, data)
      original(id, token, event, data)
      eventReceived(id, token, event, data)
    end
    extension.onVehicleMessage, hookedExtension = wrapper, extension
  end
  return true
end

local function beginCase()
  clearCameraProbe()
  caseIndex = caseIndex + 1
  local spec = cases[caseIndex]
  if not spec then
    finish(true, 'All '..#results..' vehicle lifecycle cases rewound through native recovery and resumed motion.')
    return
  end
  local car = be:getPlayerVehicle(0)
  current = {label = spec.label, action = spec.action, model = spec.model,
    damage = spec.damage, previousVehicleId = car and car:getID(), startedTime = timer}
  driveStart, rewindStart, previewPosition, resumeStart = nil, nil, nil, nil
  driveSimTime, resumedSimTime = 0, 0
  setStage('waiting-for-recorder')
  if spec.action == 'initial' then
    if modelOf(car) ~= spec.model then core_vehicles.replaceVehicle(spec.model, {}) end
  elseif spec.action == 'replace' then
    core_vehicles.replaceVehicle(spec.model, {})
  elseif spec.action == 'reload' then
    core_vehicle_manager.reloadVehicle(0)
  elseif spec.action == 'spawn' then
    savedExistingId = car:getID()
    -- Keep the parked car away from the next trajectory. The spawn API has
    -- its own safe placement and creates a genuinely different vehicle ID.
    local p = position(car) + vec3(0, 30, 0)
    core_vehicles.spawnNewVehicle(spec.model, {autoEnterVehicle = true,
      canSpawnAnotherVehicleCheck = false, pos = p})
  elseif spec.action == 'switch' then
    local existing = savedExistingId and be:getObjectByID(savedExistingId)
    if not existing then finish(false, 'Previously spawned Wigeon disappeared before switch test'); return end
    be:enterVehicle(0, existing)
  end
end

local function update(dtReal, dtSim)
  if stage == 'done' then return end
  dtReal, dtSim = dtReal or 0, dtSim or 0
  timer, stageTime = timer + dtReal, stageTime + dtReal
  if timer > 420 then finish(false, 'Fleet test timed out at '..stage); return end
  local car = be:getPlayerVehicle(0)
  if stage == 'boot' then
    if not car or not getCurrentLevelIdentifier() then return end
    if not installHook() then
      if stageTime > 10 then finish(false, 'Horizon Rewind did not autoload') end
      return
    end
    if not core_gamestate or not core_gamestate.state or core_gamestate.state.state ~= 'freeroam' then return end
    beginCase()
    return
  end
  if not installHook() then finish(false, 'Coordinator disappeared during '..stage); return end
  if stageTime > 45 then finish(false, current.label..': timeout at '..stage); return end

  if stage == 'waiting-for-recorder' then
    if not car or modelOf(car) ~= current.model or not current.telemetryTime then return end
    if not current.recordingMessages or current.recordingMessages < 1 then return end
    current.vehicleId = car:getID()
    current.sameVehicleId = current.vehicleId == current.previousVehicleId
    current.recorderReadySeconds = timer - current.startedTime
    if current.action == 'spawn' and current.sameVehicleId then
      finish(false, 'spawnNewVehicle reused the previous vehicle ID'); return
    end
    if current.action == 'switch' and current.vehicleId ~= savedExistingId then return end
    car:queueLuaCommand('input.event("parkingbrake",0,1); input.event("brake",0,1); input.event("throttle",0.25,1)')
    driveStart = position(car)
    local direction = car:getDirectionVector()
    direction.z = 0
    direction:normalize()
    car:applyClusterVelocityScaleAdd(car:getRefNodeId(), 0, direction.x * 12, direction.y * 12, 0)
    setStage('driving')
  elseif stage == 'driving' then
    if not car or car:getID() ~= current.vehicleId then finish(false, 'Unexpected vehicle switch while driving'); return end
    driveSimTime = driveSimTime + dtSim
    if driveSimTime < 2 or (current.availableSeconds or 0) < 1.5 then return end
    rewindStart = position(car)
    current.driveSeconds = driveSimTime
    current.driveDistance = driveStart:distance(rewindStart)
    current.historyAtHold = current.availableSeconds
    current.speedBeforeHold = speedOf(car)
    if current.driveDistance < 1 then finish(false, current.label..': controlled vehicle failed to move'); return end
    selectCamera()
    if current.damage then
      car:queueLuaCommand('beamstate.breakBreakGroup("doorL_latch"); beamstate.breakBreakGroup("hood_latch"); beamstate.breakBreakGroup("tailgate_latch")')
    end
    holdStarted = timer
    car:queueLuaCommand('recovery.startRecovering()')
    setStage('holding-recovery')
  elseif stage == 'holding-recovery' then
    if not car or car:getID() ~= current.vehicleId then finish(false, 'Vehicle changed during recovery'); return end
    -- Native input runs for the 0.7 second threshold, then at least 0.5 seconds
    -- of actual acknowledged rewind. Require movement before releasing.
    if not current.beganTime then
      if stageTime > 8 then finish(false, current.label..': recovery hold never began detailed rewind (native fallback?)') end
      return
    end
    if timer - current.beganTime < 0.55 or not current.previewPosition then return end
    previewPosition = position(car)
    current.publishError = previewPosition:distance(vec3(current.previewPosition))
    current.rewindDistance = rewindStart:distance(previewPosition)
    current.previewHoldSeconds = timer - current.beganTime
    if current.publishError > 0.1 then finish(false, current.label..': display transform did not publish the rewound position'); return end
    if current.rewindDistance < 0.25 then finish(false, current.label..': held rewind did not visibly move the car'); return end
    car:queueLuaCommand('recovery.stopRecovering(0)')
    current.releaseTime = timer
    setStage('waiting-for-restore')
  elseif stage == 'waiting-for-restore' then
    local releaseDistance = position(car):distance(previewPosition)
    current.maximumReleaseDisplacement = math.max(current.maximumReleaseDisplacement or 0, releaseDistance)
    -- Catch even a single cached spawn/reset pose between release and resume.
    -- A small allowance covers the final queued preview at the hold boundary.
    local releaseBound = math.max(1, current.speedBeforeHold * 0.12)
    if releaseDistance > releaseBound then
      finish(false, current.label..': temporary position jump during release: '..releaseDistance)
      return
    end
    if not current.restoredTime then return end
    -- The vehicle reply precedes asynchronous cluster publication. The
    -- coordinator must keep pause/camera ownership until that handshake ends.
    if simTimeAuthority.getPause() then return end
    current.geometryHandshakeSeconds = timer - current.restoredTime
    current.positionAtRestore = position(car):toTable()
    current.speedAtRestore = speedOf(car)
    current.restorePositionError = position(car):distance(vec3(current.restorePosition))
    if current.restorePositionError > 0.1 then
      finish(false, current.label..': restored position was not published before unpause; error='..current.restorePositionError)
      return
    end
    local err = cameraError('AtRestore')
    if err then finish(false, current.label..': '..err); return end
    if current.cancelled then finish(false, current.label..': ordinary release cancelled instead of committing rewind'); return end
    current.restoreSeconds = current.restoredTime - current.releaseTime
    -- Anchor to the restored physics snapshot, not a potentially stale cached
    -- spawn/reset transform, so a large teleport cannot masquerade as motion.
    resumeStart = vec3(current.restorePosition)
    current.resumeStart = resumeStart:toTable()
    setStage('resumed')
  elseif stage == 'resumed' then
    resumedSimTime = resumedSimTime + dtSim
    local displacement = resumeStart:distance(position(car))
    local maximumMovement = math.max(5, current.speedBeforeHold * resumedSimTime * 2 + 2)
    current.resumeMovementBound = maximumMovement
    current.resumeMaximumDistance = math.max(current.resumeMaximumDistance or 0, displacement)
    if displacement > maximumMovement then
      current.resumedDistance, current.resumedSeconds = displacement, resumedSimTime
      current.resumeFailurePosition, current.resumeFailureSpeed = position(car):toTable(), speedOf(car)
      finish(false, current.label..': position jumped '..displacement..' metres in '..resumedSimTime
        ..' simulated seconds after restore (bound '..maximumMovement..')')
      return
    end
    if resumedSimTime >= 0.1 and not current.positionAfterTenth then
      current.positionAfterTenth = position(car):toTable()
      current.distanceAfterTenth, current.speedAfterTenth = displacement, speedOf(car)
      current.sampleAfterTenthSeconds = resumedSimTime
    end
    if resumedSimTime < 0.5 then return end
    current.resumedDistance = displacement
    current.resumedSeconds = resumedSimTime
    if current.resumedDistance < 0.1 then finish(false, current.label..': vehicle did not move after release'); return end
    if current.beganCount ~= 1 then finish(false, current.label..': expected one detailed rewind per recovery hold'); return end
    if simTimeAuthority.getPause() then finish(false, current.label..': simulation unexpectedly paused after release'); return end
    local err = cameraError('AtFinish')
    if err then finish(false, current.label..': '..err); return end
    current.completedTime, current.ok = timer, true
    results[#results + 1] = current
    log('I', 'HR_FLEET', current.label..' PASS id='..current.vehicleId..' sameID='..tostring(current.sameVehicleId)
      ..' history='..current.historyAtHold..' rewindMetres='..current.rewindDistance..' resumedMetres='..current.resumedDistance)
    report(nil, 'Completed '..#results..' of '..#cases)
    beginCase()
  end
end

M.onUpdate = function(dtReal, dtSim)
  local ok, err = pcall(update, dtReal, dtSim)
  if not ok then finish(false, tostring(err)) end
end
M.onExtensionLoaded = function()
  setExtensionUnloadMode(M, 'manual')
  installHook()
  log('I', 'HR_FLEET', 'Loaded isolated fleet regression; waiting for Freeroam')
end
return M
