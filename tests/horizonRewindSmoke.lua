-- Real GE + vehicle VM smoke test. Only installed in the isolated test user folder.
local M = {}
local timer, stage, stageTime = 0, 'waiting', 0
local events, latest = {}, {}
local startPos, previewPos, launchPos
local launched = false
local geometry
local beganCount, holdStarted, tapResets = 0, 0, 0
local function done(ok, detail)
  jsonWriteFile('horizon-rewind-smoke.json', {ok=ok, detail=detail, events=events}, true)
  log(ok and 'I' or 'E', 'HR_SMOKE', tostring(detail))
  stage = 'done'
  shutdown(ok and 0 or 1)
end
local function update(dt)
  timer, stageTime = timer + dt, stageTime + dt
  if stage == 'done' then return end
  if timer > 75 then done(false, 'Timeout at '..stage); return end
  local car = be:getPlayerVehicle(0)
  if stage == 'waiting' and car and getCurrentLevelIdentifier() then
    if not extensions.horizonRewind then done(false, 'Mod did not autoload'); return end
    log('I','HR_SMOKE','Autoloaded; game state '..dumps(core_gamestate.state))
    local callback = extensions.horizonRewind.onVehicleMessage
    extensions.horizonRewind.onVehicleMessage = function(id, token, event, data)
      if event ~= 'previewed' then events[#events+1] = {event=event, time=timer, data=data} end
      latest[event] = data or {}
      if event ~= 'previewed' then log('I','HR_SMOKE', event..' '..dumps(data)) end
      callback(id, token, event, data)
      if event == 'began' then
        beganCount = beganCount + 1
        if timer - holdStarted < 0.69 then done(false, 'Rewind began before the recovery hold threshold') end
        log('I','HR_SMOKE','Hold detected after '..tostring(timer-holdStarted)..' seconds')
      end
      if event == 'reset' and stage == 'tap-released' then tapResets = tapResets + 1 end
    end
    car:queueLuaCommand('input.event("parkingbrake",0,1); input.event("throttle",0.6,1)')
    stage, stageTime = 'recording', 0
  elseif stage == 'recording' and latest.recording and not launched then
    launched = true
    launchPos = vec3(car:getPosition())
    car:applyClusterVelocityScaleAdd(car:getRefNodeId(), 0, 20, 0, 0)
    car:queueLuaCommand([[
      local rewind = extensions.horizonRewindVehicle
      local originalSeek = rewind.seek
      rewind.seek = function(...)
        originalSeek(...)
        local origin = obj:getPosition()
        local probe = {front=obj:getDirectionVector():toTable(), nodes={}}
        for _, cid in ipairs({0, 10, 20}) do
          probe.nodes[#probe.nodes+1] = {cid, (origin+obj:getNodePosition(cid)):toTable()}
        end
        obj:queueGameEngineLua('extensions.horizonRewindSmoke.onGeometry('..serialize(probe)..')')
      end
      input.event('steering',0.65,1)
    ]])
  elseif stage == 'recording' and latest.recording and latest.recording.availableSeconds > 2 then
    startPos = vec3(car:getPosition())
    log('I','HR_SMOKE','Moved before rewind: '..launchPos:distance(startPos))
    if launchPos:distance(startPos) < 1 then done(false,'Test vehicle failed to move'); return end
    holdStarted = timer
    -- These are the exact stock recover_vehicle action callbacks; no UI app
    -- or custom input action enables history or initiates this test.
    car:queueLuaCommand('recovery.startRecovering()')
    stage, stageTime = 'rewinding', 0
  elseif stage == 'rewinding' and stageTime > 1.5 and latest.previewed then
    previewPos = vec3(car:getPosition())
    local expected = vec3(latest.previewed.position)
    if previewPos:distance(expected) > 0.02 then done(false,'Published position did not match physics snapshot'); return end
    if geometry then
      local directionError = vec3(car:getDirectionVector()):distance(vec3(geometry.front))
      local nodeError = 0
      for _, entry in ipairs(geometry.nodes) do
        nodeError = math.max(nodeError, (previewPos+car:getNodePosition(entry[1])):distance(vec3(entry[2])))
      end
      log('I','HR_SMOKE','Published geometry error: nodes='..nodeError..' direction='..directionError)
      if nodeError > 0.1 or directionError > 0.02 then done(false,'Published geometry differs from recorded physics'); return end
    end
    car:queueLuaCommand('recovery.stopRecovering(0)')
    stage, stageTime = 'restoring', 0
  elseif stage == 'restoring' and latest.restored then
    -- The physics acknowledgment precedes asynchronous GE publication. The
    -- coordinator deliberately remains paused until that handoff completes.
    if simTimeAuthority.getPause() then return end
    local displacement = startPos:distance(previewPos)
    if displacement < 0.1 then done(false, 'Preview did not move the actual car: '..displacement); return end
    stage, stageTime = 'resumed', 0
  elseif stage == 'resumed' and stageTime > 0.5 then
    if beganCount ~= 1 then done(false, 'Expected exactly one hold rewind'); return end
    car:queueLuaCommand('recovery.startRecovering(true)')
    stage, stageTime = 'tap-held', 0
  elseif stage == 'tap-held' and stageTime > 0.15 then
    car:queueLuaCommand('recovery.stopRecovering(0)')
    stage, stageTime = 'tap-released', 0
  elseif stage == 'tap-released' and stageTime > 1 then
    if tapResets < 1 then done(false, 'Tap did not perform native recovery'); return end
    if beganCount ~= 1 then done(false, 'Tap incorrectly started a rewind'); return end
    if simTimeAuthority.getPause() then done(false, 'Tap left simulation paused'); return end
    done(true, 'Automatic history and stock recovery hold rewound the car '..startPos:distance(previewPos)..' metres; release resumed physics; alternate tap performed native recovery with no second rewind.')
  end
  if latest.error then done(false, 'Vehicle error: '..tostring(latest.error.message)) end
end
M.onUpdate = function(dt) local ok, err=pcall(update,dt); if not ok then done(false,err) end end
M.onGeometry = function(value) geometry = value end
M.onExtensionLoaded = function() setExtensionUnloadMode(M,'manual'); log('I','HR_SMOKE','Loaded') end
return M
