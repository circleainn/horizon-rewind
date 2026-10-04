-- Pure-Lua coordinator tests. Engine objects and async command delivery are
-- mocked; these verify lifecycle behavior, not BeamNG physics restoration.
local scriptPath = debug.getinfo(1, 'S').source:gsub('^@', ''):gsub('\\', '/')
local scriptDirectory = scriptPath:match('^(.*)/') or '.'
local modulePath = scriptDirectory .. '/../mod/lua/ge/extensions/horizonRewind.lua'
local passed = 0

local function eq(actual, expected, label)
  assert(actual == expected, (label or 'value') .. ': expected '
    .. tostring(expected) .. ', got ' .. tostring(actual))
end

local function near(actual, expected)
  assert(math.abs(actual - expected) < 1e-8,
    'expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then error(name .. ': ' .. tostring(err), 0) end
  passed = passed + 1
  print('PASS ' .. name)
end

local function harness(initialPause, initialMode, savedSettings)
  local h = {paused = initialPause == true, currentId = 1, cars = {}, bundles = {},
    commands = {}, recoveryCommands = {}, states = {}, tokens = {}, pauses = {},
    careerActive = false, foregroundMissionId = nil, cameraCalls = {}, writes = {}, effectCalls = {}}
  function h.addCar(id)
    local car = {id = id, flexResets = 0}
    function car:getID() return self.id end
    function car:queueLuaCommand(command)
      local matched = false
      for module, method, token, args in command:gmatch('(horizonRewind%w*)%.(%w+)%((%-?%d+)(.-)%)') do
        matched = true
        token = tonumber(token)
        local commands = module == 'horizonRewindRecovery' and h.recoveryCommands or h.commands
        eq(module == 'horizonRewindRecovery' or module == 'horizonRewindVehicle', true)
        commands[#commands + 1] = {id = self.id, method = method, token = token, args = args}
        if module == 'horizonRewindVehicle' and method == 'configure' then h.tokens[self.id] = token end
      end
      assert(matched, 'unrecognized command: ' .. command)
    end
    function car:resetBrokenFlexMesh() self.flexResets = self.flexResets + 1 end
    function car:getRefNodeId() return 42 end
    function car:getPosition()
      local p = self.placement
      return {x = p and p[2] or 0, y = p and p[3] or 0, z = p and p[4] or 0}
    end
    function car:setClusterPosRelRot(ref, x, y, z, qx, qy, qz, qw)
      self.placement = {ref, x, y, z, qx, qy, qz, qw}
    end
    function car:setOriginalTransform(x, y, z, qx, qy, qz, qw)
      self.resetBaseline = {x, y, z, qx, qy, qz, qw}
    end
    function car:applyClusterVelocityScaleAdd(ref, scale, x, y, z)
      self.velocitySeeds=(self.velocitySeeds or 0)+1
      self.velocitySeed={ref,scale,x,y,z,paused=h.paused,placement=self.placement}
    end
    h.cars[id] = car
    h.bundles[id] = {}
    return car
  end
  h.addCar(1)
  local env = setmetatable({
    be = {
      getPlayerVehicle = function() return h.cars[h.currentId] end,
      getObjectByID = function(_, id) return h.cars[id] end
    },
    guihooks = {trigger = function(event, data)
      eq(event, 'HorizonRewindState'); h.states[#h.states + 1] = data
    end},
    simTimeAuthority = {
      getPause = function() return h.paused end,
      pause = function(value) h.paused = value; h.pauses[#h.pauses + 1] = value end
    },
    core_replay = {state = {state = 'inactive'}},
    core_gamestate = {state = {state = initialMode or 'freeroam'}},
    core_vehicle_manager = {getVehicleData = function(id) return h.bundles[id] end},
    extensions = {horizonRewindCamera = {
      beforeRestore = function(id) h.cameraCalls[#h.cameraCalls + 1] = {event = 'before', id = id, paused = h.paused} end,
      afterRestore = function(id) h.cameraCalls[#h.cameraCalls + 1] = {event = 'after', id = id, paused = h.paused, placement = h.cars[id].placement} end,
      abort = function() h.cameraCalls[#h.cameraCalls + 1] = {event = 'abort'} end
    }},
    career_career = {isActive = function() return h.careerActive end},
    gameplay_missions_missionManager = {
      getForegroundMissionId = function() return h.foregroundMissionId end
    },
    setExtensionUnloadMode = function() end,
    jsonReadFile = function(path)
      eq(path, '/settings/horizonRewind.json')
      return savedSettings
    end,
    jsonWriteFile = function(path, data)
      eq(path, '/settings/horizonRewind.json')
      h.writes[#h.writes + 1] = data
      return true
    end
  }, {__index = _G})
  for _, name in ipairs({'horizonRewindFluids', 'horizonRewindParticles'}) do
    local effectName = name
    env.extensions[name] = {}
    for _, method in ipairs({'configure', 'record', 'arm', 'begin', 'seek', 'finish', 'releaseNative', 'abort', 'reset'}) do
      local methodName = method
      env.extensions[name][method] = function(...)
        h.effectCalls[#h.effectCalls + 1] = {name = effectName, method = methodName, args = {...}, paused = h.paused}
      end
    end
  end
  -- An embedded runner can supply source when the game's dofile uses its VFS.
  local chunk = HORIZON_REWIND_COORDINATOR_SOURCE
    and assert(loadstring(HORIZON_REWIND_COORDINATOR_SOURCE, '@' .. modulePath))
    or assert(loadfile(modulePath))
  setfenv(chunk, env)
  h.mod, h.env = chunk(), env
  h.mod.onExtensionLoaded()
  function h.state() return h.states[#h.states] end
  function h.lastCommand() return h.commands[#h.commands] end
  function h.lastRecoveryCommand() return h.recoveryCommands[#h.recoveryCommands] end
  function h.send(event, data, id, token)
    id = id or 1
    h.mod.onVehicleMessage(id, token or h.tokens[id], event, data)
  end
  function h.tick(dt) h.mod.onUpdate(dt or 0.01, h.paused and 0 or (dt or 0.01)) end
  function h.recoveryDown(id, token)
    id = id or 1
    h.mod.recoveryDown(id, token or h.tokens[id])
  end
  function h.recoveryUp(id, token)
    id = id or 1
    h.mod.recoveryUp(id, token or h.tokens[id])
  end
  function h.recoveryTakenOver(accepted, id, token)
    id = id or 1
    h.mod.recoveryTakenOver(id, token or h.tokens[id], accepted)
  end
  function h.record(seconds)
    h.mod.setEnabled(true)
    h.send('configured', {availableSeconds = 0})
    h.send('recording', {availableSeconds = seconds or 10})
  end
  function h.begin()
    h.mod.beginRewind()
    eq(h.lastCommand().method, 'begin')
    h.send('began', {availableSeconds = 10})
  end
  function h.restore(cancelled, id)
    h.send('resetReady', {}, id)
    eq(h.lastCommand().method, 'completeRestore')
    h.send('restored', {availableSeconds = 8, cancelled = cancelled}, id)
    h.tick(); h.tick()
  end
  return h
end

test('eligible extension load starts recorder and recovery bridge without UI', function()
  local h = harness()
  eq(h.state().enabled, true); eq(h.state().phase, 'recording')
  eq(h.lastCommand().method, 'configure'); eq(h.lastCommand().args, ',true,20')
  eq(h.lastRecoveryCommand().method, 'configure'); eq(h.lastRecoveryCommand().args, ',true')
  eq(h.lastRecoveryCommand().token, h.tokens[1])
  h.send('recording', {availableSeconds = 4})
  eq(h.state().availableSeconds, 4)
end)

test('short recovery tap keeps native behavior and never begins rewind', function()
  local h = harness()
  h.send('recording', {availableSeconds = 5})
  local before = #h.commands
  local recoveryBefore = #h.recoveryCommands
  h.recoveryDown(); h.tick(0.3); h.recoveryUp(); h.tick(1)
  eq(#h.commands, before); eq(#h.recoveryCommands, recoveryBefore)
  eq(h.state().phase, 'recording'); eq(h.paused, false)
end)

test('holding stock recovery takes over once after the threshold', function()
  local h = harness()
  h.send('recording', {availableSeconds = 5})
  h.recoveryDown(); h.tick(0.69)
  eq(h.lastCommand().method, 'configure'); eq(h.paused, false)
  h.tick(0.02)
  eq(h.lastRecoveryCommand().method, 'takeOver')
  eq(h.lastCommand().method, 'configure'); eq(h.state().phase, 'recording'); eq(h.paused, false)
  h.recoveryTakenOver(true)
  eq(h.lastCommand().method, 'begin'); eq(h.state().phase, 'rewinding'); eq(h.paused, true)
  local recoveryCount = #h.recoveryCommands
  h.tick(0.1); eq(#h.recoveryCommands, recoveryCount)
  h.recoveryUp(); h.send('began'); h.tick()
  if h.lastCommand().method == 'seek' then h.send('previewed'); h.tick() end
  eq(h.lastCommand().method, 'finish'); eq(h.lastCommand().args, ',false')
  h.restore(false); eq(h.paused, false)
end)

test('no history passes a held recovery press back to native recovery', function()
  local h = harness()
  local before = #h.commands
  h.recoveryDown(); h.tick(0.71)
  eq(h.lastRecoveryCommand().method, 'passthrough')
  eq(#h.commands, before); eq(h.paused, false); eq(h.state().phase, 'recording')
  local recoveryCount = #h.recoveryCommands
  h.tick(1); eq(#h.recoveryCommands, recoveryCount)
  h.recoveryUp(); h.tick(); eq(#h.commands, before)
end)

test('recovery callbacks require current player and session', function()
  local h = harness()
  h.addCar(2)
  h.send('recording', {availableSeconds = 5})
  local before = #h.commands
  h.recoveryDown(2, h.tokens[1]); h.tick(1)
  h.recoveryDown(1, h.tokens[1] + 99); h.tick(1)
  eq(#h.commands, before); eq(h.paused, false)
  h.recoveryDown()
  h.recoveryUp(2, h.tokens[1]); h.recoveryUp(1, h.tokens[1] + 99)
  h.tick(0.71)
  h.recoveryTakenOver(true)
  eq(h.lastCommand().method, 'begin'); eq(h.lastRecoveryCommand().method, 'takeOver')
end)

test('release before takeover acknowledgment cannot begin a stale rewind', function()
  local h = harness()
  h.send('recording', {availableSeconds = 5})
  local before = #h.commands
  h.recoveryDown(); h.tick(0.71)
  eq(h.lastRecoveryCommand().method, 'takeOver'); eq(h.paused, false)
  h.recoveryUp(); h.recoveryTakenOver(true); h.tick()
  eq(#h.commands, before); eq(h.state().phase, 'recording'); eq(h.paused, false)
  -- A fresh hold can still use the recorder after the aborted handshake.
  h.recoveryDown(); h.tick(0.71); h.recoveryTakenOver(true)
  eq(h.lastCommand().method, 'begin'); eq(h.paused, true)
end)

test('rejected takeover acknowledgment preserves recording without pausing', function()
  local h = harness()
  h.send('recording', {availableSeconds = 5})
  local before = #h.commands
  h.recoveryDown(); h.tick(0.71); h.recoveryTakenOver(false); h.tick()
  eq(#h.commands, before); eq(h.state().phase, 'recording'); eq(h.paused, false)
  local recoveryCount = #h.recoveryCommands
  h.tick(6); eq(#h.recoveryCommands, recoveryCount)
  h.recoveryTakenOver(true); eq(#h.commands, before)
end)

test('unsolicited and stale takeover acknowledgments cannot consume a current request', function()
  local h = harness()
  h.addCar(2)
  h.send('recording', {availableSeconds = 5})
  local before = #h.commands
  h.recoveryTakenOver(true); eq(#h.commands, before)
  h.recoveryDown(); h.tick(0.71)
  h.recoveryTakenOver(true, 2, h.tokens[1])
  h.recoveryTakenOver(true, 1, h.tokens[1] + 99)
  eq(#h.commands, before); eq(h.paused, false)
  h.recoveryTakenOver(true)
  eq(h.lastCommand().method, 'begin'); eq(h.paused, true)
  before = #h.commands
  h.recoveryTakenOver(true); eq(#h.commands, before)
end)

test('takeover acknowledgment from a previous recording session is ignored', function()
  local h = harness()
  h.send('recording', {availableSeconds = 5})
  h.recoveryDown(); h.tick(0.71)
  local oldToken = h.tokens[1]
  h.mod.setEnabled(false); h.mod.setEnabled(true)
  h.send('recording', {availableSeconds = 5})
  h.recoveryDown(); h.tick(0.71)
  local before = #h.commands
  h.recoveryTakenOver(true, 1, oldToken)
  eq(#h.commands, before); eq(h.paused, false)
  h.recoveryTakenOver(true)
  eq(h.lastCommand().method, 'begin'); eq(h.paused, true)
end)

test('unanswered takeover times out to native recovery and ignores late acceptance', function()
  local h = harness()
  h.send('recording', {availableSeconds = 5})
  local before = #h.commands
  h.recoveryDown(); h.tick(0.71)
  eq(h.lastRecoveryCommand().method, 'takeOver')
  h.tick(6)
  eq(h.lastRecoveryCommand().method, 'passthrough')
  eq(#h.commands, before); eq(h.state().phase, 'recording'); eq(h.paused, false)
  local recoveryCount = #h.recoveryCommands
  h.tick(1); h.recoveryTakenOver(true)
  eq(#h.recoveryCommands, recoveryCount); eq(#h.commands, before); eq(h.paused, false)
end)

test('pending recovery press cannot transfer across a vehicle switch', function()
  local h = harness()
  h.send('recording', {availableSeconds = 5}); h.recoveryDown(); h.tick(0.3)
  local oldToken = h.tokens[1]
  h.addCar(2); h.currentId = 2; h.tick()
  h.send('recording', {availableSeconds = 5}, 2)
  local before = #h.commands
  h.recoveryDown(1, oldToken); h.recoveryUp(1, oldToken); h.tick(1)
  eq(#h.commands, before); eq(h.paused, false); eq(h.state().phase, 'recording')
  eq(h.lastRecoveryCommand().id, 2)
end)

test('saved replay temporarily suspends automatic history and bridge', function()
  for _, state in ipairs({'recording', 'playback'}) do
    local h = harness()
    local oldToken = h.tokens[1]
    h.env.core_replay.state.state = state; h.tick()
    eq(h.state().enabled, false); eq(h.lastCommand().method, 'abort')
    eq(h.lastRecoveryCommand().method, 'configure'); eq(h.lastRecoveryCommand().args, ',false')
    h.tick(); eq(h.state().enabled, false)
    h.env.core_replay.state.state = 'inactive'; h.tick()
    eq(h.state().enabled, true); eq(h.state().phase, 'recording')
    eq(h.lastCommand().method, 'configure'); eq(h.lastCommand().args, ',true,20')
    eq(h.lastRecoveryCommand().args, ',true')
    assert(h.tokens[1] ~= oldToken, 'resumption must create a new recording session')
    eq(h.state().availableSeconds, 0)
  end
end)

test('non-freeroam load waits then starts automatically in freeroam', function()
  local h = harness(false, 'menu')
  eq(h.state().enabled, false); eq(#h.commands, 0); eq(#h.recoveryCommands, 0)
  h.env.core_gamestate.state.state = 'freeroam'; h.tick()
  eq(h.state().enabled, true); eq(h.lastCommand().method, 'configure')
end)

test('gamemode career and foreground mission suspend and resume history', function()
  for _, restriction in ipairs({'gamemode', 'career', 'mission'}) do
    local h = harness()
    if restriction == 'gamemode' then h.env.core_gamestate.state.state = 'scenario'
    elseif restriction == 'career' then h.careerActive = true
    else h.foregroundMissionId = 'test-mission' end
    h.tick(); eq(h.state().enabled, false); eq(h.paused, false)
    eq(h.lastRecoveryCommand().args, ',false')
    h.env.core_gamestate.state.state = 'freeroam'
    h.careerActive, h.foregroundMissionId = false, nil
    h.tick(); eq(h.state().enabled, true); eq(h.state().phase, 'recording')
    eq(h.lastRecoveryCommand().args, ',true')
  end
end)

test('manual disable persists across eligibility changes', function()
  local h = harness()
  h.mod.setEnabled(false); eq(h.state().enabled, false)
  h.env.core_replay.state.state = 'playback'; h.tick()
  h.env.core_replay.state.state = 'inactive'; h.tick()
  eq(h.state().enabled, false)
  h.mod.setEnabled(true); eq(h.state().enabled, true)
end)

test('normal release restores both original pause states', function()
  for _, paused in ipairs({false, true}) do
    local h = harness(paused)
    h.record(); h.begin()
    eq(h.paused, true)
    h.mod.endRewind(); h.tick()
    eq(h.state().phase, 'restoring')
    eq(h.lastCommand().method, 'finish'); eq(h.lastCommand().args, ',false')
    h.restore(false)
    eq(h.paused, paused); eq(h.state().phase, 'recording')
    eq(h.cars[1].flexResets, 1)
  end
end)

test('cancel waits for pending preview then restores the starting state', function()
  local h = harness()
  h.record(); h.begin(); h.tick(0.25)
  eq(h.lastCommand().method, 'seek')
  h.mod.cancelRewind(); h.tick(0.1)
  eq(h.lastCommand().method, 'seek')
  h.send('previewed'); h.tick()
  eq(h.lastCommand().method, 'finish'); eq(h.lastCommand().args, ',true')
  h.restore(true)
  eq(h.paused, false); eq(h.state().phase, 'recording')
end)

test('paused preview publishes position through the native no-reset path', function()
  local h = harness()
  h.record(); h.begin(); h.tick(0.25)
  h.send('previewed', {position={10,20,30}})
  local p = h.cars[1].placement
  eq(p[1],42); eq(p[2],10); eq(p[3],20); eq(p[4],30); eq(p[8],1)
  eq(h.cars[1].flexResets,0); eq(h.paused,true)
end)

test('release before begin acknowledgment still completes', function()
  local h = harness()
  h.record(); h.mod.beginRewind(); h.mod.endRewind(); h.tick(0.1)
  eq(h.lastCommand().method, 'begin'); eq(h.paused, true)
  h.send('began'); h.tick()
  eq(h.lastCommand().method, 'finish'); eq(h.lastCommand().args, ',false')
  h.restore(false); eq(h.paused, false)
end)

test('empty and insufficient history never leave a pause owned', function()
  local h = harness()
  h.record(0)
  local before = #h.commands
  h.mod.beginRewind()
  eq(#h.commands, before); eq(h.paused, false); eq(h.state().phase, 'recording')
  h.send('recording', {availableSeconds = 1})
  h.mod.beginRewind(); eq(h.paused, true)
  h.send('empty', {message = 'No history remains.'})
  eq(h.paused, false); eq(h.state().phase, 'recording')
end)

test('replay conflict blocks begin and cancels an existing rewind', function()
  for _, replayState in ipairs({'recording', 'playback'}) do
    local h = harness()
    h.record(); h.env.core_replay.state.state = replayState
    local before = #h.commands
    h.mod.beginRewind(); eq(#h.commands, before); eq(h.paused, false)
    h.tick(); eq(h.state().enabled, false)

    h = harness()
    h.record(); h.begin()
    h.env.core_replay.state.state = replayState
    h.tick()
    eq(h.lastCommand().method, 'finish'); eq(h.lastCommand().args, ',true')
    h.restore(true)
    eq(h.paused, false); eq(h.state().enabled, false); eq(h.state().phase, 'disabled')
  end
end)

test('watchdog releases pause and ignores late acknowledgments', function()
  local h = harness()
  h.record(); h.mod.beginRewind()
  local oldToken = h.tokens[1]
  h.mod.setEnabled(false)
  -- Ordinary telemetry cannot keep an unanswered begin alive.
  h.tick(3); h.send('recording', {availableSeconds = 12}); h.tick(3)
  eq(h.paused, false); eq(h.state().enabled, false); eq(h.state().phase, 'error')
  h.send('began', {}, 1, oldToken); h.send('restored', {}, 1, oldToken)
  eq(h.state().phase, 'error')
  -- Pending disable from the failed session must not affect the next session.
  h.record(); h.begin(); h.mod.endRewind(); h.tick(); h.restore(false)
  eq(h.state().enabled, true); eq(h.state().phase, 'recording')
end)

test('replay startup does not bypass an outstanding watchdog', function()
  local h = harness()
  h.record(); h.mod.beginRewind()
  h.env.core_replay.state.state = 'playback'
  h.tick(6)
  eq(h.paused, false); eq(h.state().phase, 'error')
end)

test('vehicle switch cancels old car before attaching replacement', function()
  local h = harness()
  h.record(); h.begin(); h.tick(0.25)
  local oldToken = h.tokens[1]
  h.addCar(2); h.currentId = 2; h.tick()
  eq(h.lastCommand().method, 'seek'); eq(h.tokens[2], nil)
  h.send('previewed'); h.tick()
  eq(h.lastCommand().id, 1); eq(h.lastCommand().method, 'finish')
  eq(h.lastCommand().args, ',true')
  h.restore(true); eq(h.paused, false)
  h.tick()
  eq(h.lastCommand().id, 2); eq(h.lastCommand().method, 'configure')
  eq(h.state().phase, 'recording'); eq(h.state().availableSeconds, 0)
  h.send('error', {message = 'late error'}, 1, oldToken)
  eq(h.state().enabled, true); eq(h.state().phase, 'recording')
end)

test('deleted vehicle and mission shutdown release the owned pause', function()
  local h = harness()
  h.record(); h.begin(); h.cars[1] = nil; h.currentId = nil; h.tick()
  eq(h.paused, false); eq(h.state().phase, 'recording')
  h = harness()
  h.record(); h.begin(); h.mod.onClientEndMission()
  eq(h.paused, false); eq(h.state().enabled, false)
end)

test('reset and error terminate an operation and reject phase-stale acks', function()
  local h = harness()
  h.record(); h.begin(); h.tick()
  h.send('reset', {availableSeconds = 0})
  eq(h.paused, false); eq(h.state().phase, 'recording')
  h.send('previewed'); h.send('resetReady'); h.send('restored')
  eq(h.state().phase, 'recording'); eq(h.cars[1].flexResets, 0)
  h.send('recording', {availableSeconds = 5}); h.mod.beginRewind()
  h.send('error', {message = 'synthetic failure'})
  eq(h.paused, false); eq(h.state().enabled, false); eq(h.state().phase, 'error')
  h.send('began'); eq(h.state().phase, 'error')
  h.tick(); eq(h.state().enabled, false); eq(h.state().phase, 'error')
end)

test('rewind wall-clock speed survives acknowledgment latency and final release', function()
  local h = harness()
  h.record(); h.begin(); h.tick(0.25)
  eq(h.lastCommand().method, 'seek'); near(tonumber(h.lastCommand().args:sub(2)), 0.5)
  h.tick(0.25); h.tick(0.25)
  h.send('previewed'); h.tick(0.25)
  near(tonumber(h.lastCommand().args:sub(2)), 2)
  h.tick(0.25); h.mod.endRewind(); h.send('previewed'); h.tick()
  eq(h.lastCommand().method, 'seek'); near(tonumber(h.lastCommand().args:sub(2)), 2.5)
  h.send('previewed'); h.tick()
  eq(h.lastCommand().method, 'finish'); eq(h.lastCommand().args, ',false')
  h.restore(false); eq(h.paused, false)
end)

test('holding oldest point does not trip an idle watchdog', function()
  local h = harness()
  h.record(); h.begin(); h.tick(1); h.send('previewed')
  h.tick(1); h.send('previewed'); h.tick(1); h.send('previewed')
  h.tick(1); h.send('previewed'); h.tick(1); h.send('previewed')
  h.tick(6)
  eq(h.state().phase, 'rewinding'); eq(h.state().enabled, true)
  h.mod.endRewind(); h.tick(); h.restore(false); eq(h.paused, false)
end)

test('disable during begin handles an empty reply and preserves initial pause', function()
  local h = harness(true)
  h.record(); h.mod.beginRewind(); h.mod.setEnabled(false)
  h.send('empty', {message = 'No history'})
  eq(h.state().enabled, false); eq(h.state().phase, 'disabled'); eq(h.paused, true)
end)

test('unload and serialization abort before releasing pause', function()
  local h = harness()
  h.record(); h.begin(); h.mod.onExtensionUnloaded()
  eq(h.lastCommand().method, 'abort'); eq(h.paused, false)
  h = harness()
  h.record(); h.begin()
  local token = h.tokens[1]
  h.mod.onSerialize()
  eq(h.lastCommand().method, 'abort'); eq(h.paused, false)
  eq(h.state().enabled, false); eq(h.state().phase, 'disabled')
  h.send('restored', {}, 1, token); eq(h.state().phase, 'disabled')
  h.tick(); eq(h.state().enabled, true); eq(h.state().phase, 'recording')
end)

test('selector replacement reattaches both extensions when object ID is reused', function()
  local h = harness()
  h.record(10)
  local oldToken, before = h.tokens[1], #h.commands
  h.addCar(1)
  h.mod.onVehicleSpawned(1)
  eq(h.state().availableSeconds, 0)
  h.tick()
  eq(h.lastCommand().method, 'configure')
  eq(#h.commands, before + 1, 'must not send old abort into replacement VM')
  assert(h.tokens[1] > oldToken)
  eq(h.recoveryCommands[#h.recoveryCommands].method, 'configure')
  eq(h.recoveryCommands[#h.recoveryCommands].args, ',true')
  h.send('recording', {availableSeconds = 15}, 1, oldToken)
  eq(h.state().availableSeconds, 0, 'old VM messages rejected')
  h.send('configured', {availableSeconds = 0})
  h.send('recording', {availableSeconds = 2})
  h.mod.recoveryDown(1, h.tokens[1]); h.tick(0.71)
  h.mod.recoveryTakenOver(1, h.tokens[1], true)
  eq(h.lastCommand().method, 'begin')
end)

test('changed vehicle bundle detects same-ID rebuild without spawn hook', function()
  local h = harness()
  h.record()
  local token = h.tokens[1]
  h.bundles[1] = {}
  h.tick()
  assert(h.tokens[1] > token)
  eq(h.lastCommand().method, 'configure'); eq(h.state().availableSeconds, 0)
end)

test('replacement during rewind releases pause without restoring old geometry into new car', function()
  local h = harness()
  h.record(); h.begin()
  local count = #h.commands
  h.addCar(1); h.mod.onVehicleSpawned(1)
  eq(h.paused, false); eq(#h.commands, count)
  h.tick(); eq(h.lastCommand().method, 'configure')
end)

test('failure is isolated to vehicle incarnation and retries on user reset or replacement', function()
  local h = harness()
  h.record(); h.send('error', {message = 'broken optional system'})
  h.tick(); eq(h.state().enabled, false)
  h.mod.onVehicleResetted(1); h.tick()
  eq(h.state().enabled, true); eq(h.lastCommand().method, 'configure')
  h.send('error', {message = 'still broken'})
  h.addCar(2); h.currentId = 2; h.tick()
  eq(h.state().enabled, true); eq(h.lastCommand().id, 2)
  h.send('error', {message = 'failed'}, 2)
  h.addCar(2); h.mod.onVehicleSpawned(2); h.tick()
  eq(h.state().enabled, true); eq(h.lastCommand().id, 2)
end)

test('unrelated spawns do not clear history and replacement respects manual off', function()
  local h = harness()
  h.record()
  local token = h.tokens[1]
  h.addCar(2); h.mod.onVehicleSpawned(2); h.tick()
  eq(h.tokens[1], token); eq(h.state().availableSeconds, 10)
  h.mod.setEnabled(false)
  h.addCar(1); h.mod.onVehicleSpawned(1); h.tick()
  eq(h.state().enabled, false)
end)

test('camera guard spans reset and receives published geometry before unpausing', function()
  local h = harness()
  h.record(); h.begin(); h.mod.endRewind(); h.tick()
  local before = h.cameraCalls[#h.cameraCalls]
  eq(before.event, 'before'); eq(before.id, 1); eq(before.paused, true)
  h.send('resetReady')
  h.send('restored', {position = {4, 5, 6}, availableSeconds = 8})
  eq(h.paused, true)
  h.tick(); eq(h.paused, true); h.tick()
  local after = h.cameraCalls[#h.cameraCalls]
  eq(after.event, 'after'); eq(after.paused, true)
  eq(after.placement[2], 4); eq(after.placement[3], 5); eq(after.placement[4], 6)
  eq(h.paused, false)
  h.mod.onExtensionUnloaded()
  eq(h.cameraCalls[#h.cameraCalls].event, 'abort')
end)

test('release waits through stale and transient published poses before unpausing', function()
  local h = harness()
  h.record(); h.begin(); h.mod.endRewind(); h.tick(); h.send('resetReady')
  local pos = {x = 0, y = 0, z = 0}
  h.cars[1].getPosition = function() return pos end
  h.send('restored', {position = {4, 5, 6}})
  h.tick(); h.tick(); eq(h.paused, true); eq(h.state().phase, 'restoring')
  pos = {x = 4, y = 5, z = 6}; h.tick(); eq(h.paused, true)
  pos = {x = 0, y = 0, z = 0}; h.tick(); eq(h.paused, true)
  pos = {x = 4, y = 5, z = 6}; h.tick(); h.tick()
  eq(h.paused, false); eq(h.state().phase, 'recording')
end)

test('effects follow acknowledged previews and commit before physics resumes', function()
  local h = harness()
  h.record(); h.begin(); h.tick(0.5)
  h.send('previewed', {rewindSeconds = 0.75})
  local call = h.effectCalls[#h.effectCalls]
  eq(call.method, 'seek'); near(call.args[1], 0.75); eq(call.paused, true)
  h.mod.endRewind(); h.tick()
  h.send('restored', {actualSelectedSeconds = 0.73, resetFlexMesh = true, position = {4, 5, 6}})
  eq(h.cars[1].flexResets, 1)
  eq(h.paused, true)
  h.tick(); h.tick()
  call = h.effectCalls[#h.effectCalls]
  eq(call.method, 'finish'); near(call.args[1], 0.73); eq(call.args[2], false); eq(call.paused, true)
  eq(h.paused, false)
end)

test('native reset starts only after its display baseline matches the chosen pose', function()
  local h = harness()
  h.record(); h.begin(); h.mod.endRewind(); h.tick()
  h.send('restorePrepared', {position = {4, 5, 6}, rotation = {0, 0, 0, 1}})
  eq(h.lastCommand().method, 'executeRestore')
  near(h.cars[1].resetBaseline[2], 5)
  eq(h.paused, true)
  h.send('restored', {resetFlexMesh = true, position = {4, 5, 6}})
  h.tick(); h.tick()
  eq(h.paused, false); eq(h.state().phase, 'recording')
end)

test('effect cancellation and disable restore owned state', function()
  local h = harness()
  h.record(); h.begin(); h.mod.cancelRewind(); h.tick(); h.restore(true)
  local call = h.effectCalls[#h.effectCalls]
  eq(call.method, 'finish'); eq(call.args[2], true)
  h.mod.setEnabled(false)
  eq(h.effectCalls[#h.effectCalls].method, 'abort')
end)

test('native recovery press arms effects and taps release deferred cleanup', function()
  local h = harness()
  h.recoveryDown()
  eq(h.effectCalls[#h.effectCalls].method, 'arm')
  h.recoveryUp()
  eq(h.effectCalls[#h.effectCalls].method, 'releaseNative')
end)

test('an optional effect failure cannot strand the car or pause', function()
  local h = harness()
  h.env.extensions.horizonRewindFluids.seek = function() error('unsupported effect state') end
  h.env.log = function() end
  h.record(); h.begin(); h.tick(0.5); h.send('previewed')
  h.mod.endRewind(); h.tick(); h.restore(false)
  eq(h.state().phase, 'recording'); eq(h.paused, false)
end)

test('saved slow rewind speed controls keyboard hold and persists changes', function()
  local h = harness(false, 'freeroam', {speed = 0.25})
  near(h.state().speed, 0.25)
  h.record(); h.recoveryDown(); h.tick(0.71); h.recoveryTakenOver(true)
  h.send('began'); h.tick(1)
  near(tonumber(h.lastCommand().args:sub(2)), 0.25)
  h.mod.setSpeed(8)
  near(h.state().speed, 8); near(h.writes[1].speed, 8)
  h.send('previewed'); h.tick(1)
  near(tonumber(h.lastCommand().args:sub(2)), 8.25)
end)

test('invalid speed settings keep the default and invalid writes are ignored', function()
  for _, value in ipairs({0, -1, 3, 99, 'invalid', math.huge}) do
    local h = harness(false, 'freeroam', {speed = value})
    near(h.state().speed, 2)
    h.mod.setSpeed(value); near(h.state().speed, 2); eq(#h.writes, 0)
  end
  local h = harness(false, 'freeroam', 'malformed')
  h.mod.setSpeed(nil); near(h.state().speed, 2); eq(#h.writes, 0)
end)

test('a failed settings write leaves the selected runtime speed usable', function()
  local h = harness()
  h.env.jsonWriteFile = function() error('test disk failure') end
  h.env.log = function() end
  h.mod.setSpeed(0.5)
  near(h.state().speed, 0.5)
  h.record(); h.begin(); h.tick(1)
  near(tonumber(h.lastCommand().args:sub(2)), 0.5)
end)

test('momentum is seeded once at the published pose before releasing pause',function()
  for _,cancelled in ipairs({false,true}) do
    local h=harness(cancelled)
    h.record();h.begin()
    if cancelled then h.mod.cancelRewind() else h.mod.endRewind() end
    h.tick()
    local data={position={4,5,6},velocity={12,-3,2},cancelled=cancelled}
    h.send('restored',data)
    eq(h.cars[1].velocitySeeds,nil)
    h.tick();h.tick()
    local seed=h.cars[1].velocitySeed
    eq(seed.paused,true);near(seed[3],12);near(seed[4],-3);near(seed[5],2)
    near(seed.placement[2],4);eq(h.paused,cancelled)
    h.send('restored',data);h.tick()
    eq(h.cars[1].velocitySeeds,1)
  end
end)
test('history and traffic settings persist together and reject mid-rewind changes', function()
  local h = harness(false, 'freeroam', {maxSeconds=60, trafficEnabled=true, speed=4})
  eq(h.state().maxSeconds,60);eq(h.state().trafficEnabled,true)
  eq(h.lastCommand().args,',true,60')
  h.mod.setSpeed(2);eq(h.writes[1].maxSeconds,60);eq(h.writes[1].trafficEnabled,true)
  h.mod.setHistorySeconds(40);eq(h.state().maxSeconds,40);eq(h.lastCommand().args,',true,40')
  h.mod.setHistorySeconds(50);eq(h.state().maxSeconds,40)
  h.record();h.begin()
  h.mod.setHistorySeconds(20);h.mod.setTrafficEnabled(false)
  eq(h.state().maxSeconds,40);eq(h.state().trafficEnabled,true)
end)

test('slow traffic does not gate player preview but still gates release', function()
  local h=harness()
  local ready=false
  h.env.extensions.horizonRewindTraffic={ready=function() return ready end, status=function(n) return n,2 end}
  h.record();h.begin();h.tick()
  eq(h.lastCommand().method,'seek');h.send('previewed')
  h.tick();eq(h.lastCommand().method,'seek');h.send('previewed')
  ready=true
  h.mod.endRewind();h.tick()
  ready=false
  h.send('restored',{position={1,2,3}});h.tick();h.tick()
  eq(h.paused,true)
  ready=true;h.tick();eq(h.paused,false)
end)
test('reapplying the current traffic setting leaves recorded history attached',function()
  local h=harness(false,'freeroam',{trafficEnabled=true})
  local configured=0
  h.env.extensions.horizonRewindTraffic={configure=function() configured=configured+1 end}
  h.record();h.mod.setTrafficEnabled(true)
  eq(configured,0)
  h.mod.setTrafficEnabled(false);eq(configured,1)
end)
print('coordinator_spec: ' .. passed .. ' tests passed')
