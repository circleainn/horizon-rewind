-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Original rewind cue. This does not record or reverse the game's audio mix.
local M = {}
local emitter, playing, failed = nil, false, false
local level, pitch = 0, 1

local function dispose()
  if emitter then
    pcall(function() emitter:stop(); emitter:delete() end)
  end
  emitter, playing, level = nil, false, 0
end

local function update(active, speed, dt)
  if failed then return end
  if active and not emitter then
    emitter = createObject('SFXEmitter')
    assert(emitter, 'SFXEmitter unavailable')
    emitter:setField('fileName', 0, '/art/sound/horizonRewind/rewind.wav')
    emitter:setField('sourceGroup', 0, 'AudioGui')
    emitter:setField('is3D', 0, '0')
    emitter:setField('isLooping', 0, '1')
    emitter:setField('isStreaming', 0, '0')
    emitter:setField('playOnAdd', 0, '0')
    emitter:setField('volume', 0, '0')
    emitter.canSave = false
    emitter:registerObject('')
    if scenetree.MissionCleanup then scenetree.MissionCleanup:addObject(emitter) end
  end
  if not emitter then return end
  dt = math.max(0, math.min(0.1, dt or 0))
  local targetPitch = math.max(0.5, math.min(2, (speed or 2)^0.35))
  pitch = pitch + (targetPitch-pitch)*math.min(1, dt*18)
  level = level + ((active and 0.3 or 0)-level)*math.min(1, dt*25)
  if active and not playing then emitter:play(); playing = true end
  emitter:setVolumePitchCT(level, pitch, 0, 0)
  if not active and level < 0.002 then dispose() end
end

function M.update(...)
  local ok, err = pcall(update, ...)
  if not ok then
    dispose(); failed = true
    log('W', 'horizonRewindAudio', 'Rewind sound unavailable: '..tostring(err))
  end
end
M.stop = dispose
M.onClientEndMission = function() dispose(); failed = false end
M.onExtensionUnloaded = dispose
return M
