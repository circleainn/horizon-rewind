-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Reversible bridge for BeamNG's existing repair/rewind actions.
local M = {}
local active, session, generation = false, 0, 0
local pressed, consumed, passedThrough = false, false, false
local recordUpdate, nativeRecoveryUpdate, gate
local originalStart, originalStop, wrappedStart, wrappedStop

local function notify(method)
  obj:queueGameEngineLua(string.format(
    'if extensions.horizonRewind then extensions.horizonRewind.%s(%d,%d) end',
    method, obj:getId(), session))
end

local function acknowledgeTakeover(token, accepted)
  obj:queueGameEngineLua(string.format(
    'if extensions.horizonRewind then extensions.horizonRewind.recoveryTakenOver(%d,%d,%s) end',
    obj:getId(), token, tostring(accepted)))
end

local function clearPress(restoreRecord)
  -- Another mod or a native reset may already have replaced our callback.
  if restoreRecord and gate and (recovery.updateGFX == gate
      or (passedThrough and recovery.updateGFX == nativeRecoveryUpdate)) then
    recovery.updateGFX = recordUpdate
  end
  pressed, consumed, passedThrough = false, false, false
  recordUpdate, nativeRecoveryUpdate, gate = nil, nil, nil
end

local function uninstall()
  active = false
  clearPress(true)
  generation = generation + 1
  if wrappedStart and recovery.startRecovering == wrappedStart then recovery.startRecovering = originalStart end
  if wrappedStop and recovery.stopRecovering == wrappedStop then recovery.stopRecovering = originalStop end
  wrappedStart, wrappedStop = nil, nil
end

local function install()
  if wrappedStart then return end
  generation = generation + 1
  local installedGeneration = generation
  local start, stop = recovery.startRecovering, recovery.stopRecovering
  assert(type(start) == 'function' and type(stop) == 'function', 'Native recovery API unavailable')
  originalStart, originalStop = start, stop

  wrappedStart = function(useAltMode)
    -- Old wrappers may remain inside another mod's wrapper chain.
    if not active or installedGeneration ~= generation then return start(useAltMode) end
    if pressed then return end
    pressed, consumed, passedThrough = true, false, false
    recordUpdate = recovery.updateGFX
    -- Queue ownership before another recovery wrapper queues its own effects
    -- cleanup. GE can then defer that cleanup for this specific held press.
    notify('recoveryDown')
    -- Native start captures the exact press position and smart-recovery mode.
    -- It does not reset or move the vehicle.
    start(useAltMode)
    nativeRecoveryUpdate = recovery.updateGFX
    gate = function() end
    recovery.updateGFX = gate
  end

  wrappedStop = function(player)
    if not active or installedGeneration ~= generation then return stop(player) end
    if not pressed then return end
    local wasConsumed = consumed
    -- Keep the gate installed for a tap: native stop sees an active recovery
    -- and restores its captured press position using the original alt mode.
    clearPress(false)
    if not wasConsumed then
      local result = stop(player)
      notify('recoveryUp')
      return result
    end
    notify('recoveryUp')
  end
  recovery.startRecovering, recovery.stopRecovering = wrappedStart, wrappedStop
end

local function configure(token, enabled)
  assert(type(token) == 'number' and token == token and token ~= math.huge and token ~= -math.huge and token % 1 == 0,
    'Recovery session must be an integer')
  if token ~= session or enabled ~= true then uninstall() end
  session, active = token, enabled == true
  if active then install() end
end

local function takeOver(token)
  if not active or token ~= session or not pressed or consumed or passedThrough or recovery.updateGFX ~= gate then
    acknowledgeTakeover(token, false)
    return false
  end
  recovery.updateGFX = recordUpdate
  consumed = true
  acknowledgeTakeover(token, true)
  return true
end

local function passthrough(token)
  if not active or token ~= session or not pressed or consumed or passedThrough then return false end
  if recovery.updateGFX ~= gate then return false end
  recovery.updateGFX = nativeRecoveryUpdate
  passedThrough = true
  return true
end

M.configure, M.takeOver, M.passthrough = configure, takeOver, passthrough
M.onReset = function() clearPress(true) end
M.onExtensionUnloaded = uninstall
M.onSerialize = function() uninstall(); return {} end
M.onDeserialized = uninstall
return M
