-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Original rewind cue. This does not record or reverse the game's audio mix.
local M = {}
local sourceId, playing, failed = nil, false, false
local level, cue = 0, nil
local cues = {[0.25]='rewind_025.wav',[0.5]='rewind_050.wav',[1]='rewind.wav',
  [2]='rewind_200.wav',[4]='rewind_400.wav',[8]='rewind_800.wav'}

local function dispose()
  if sourceId then
    pcall(function() Engine.Audio.deleteSource(sourceId) end)
  end
  sourceId, playing, level, cue = nil, false, 0, nil
end

local function update(active, speed, dt)
  if failed then return end
  local wanted=cues[speed] or cues[2]
  if active and sourceId and cue~=wanted then dispose() end
  if active and not sourceId then
    -- File sources expose setVolume but no native setPitch in BeamNG 0.39.
    -- Use resampled copies of our own cue for the six supported speeds.
    sourceId = Engine.Audio.createSource('AudioGui','/art/sound/horizonRewind/'..wanted)
    assert(sourceId and sourceId~=0,'Could not create rewind audio source')
    cue=wanted
  end
  if not sourceId then return end
  local source=scenetree.findObjectById(sourceId)
  assert(source,'Rewind audio source disappeared')
  dt = math.max(0, math.min(0.1, dt or 0))
  level = level + ((active and 0.65 or 0)-level)*math.min(1, dt*25)
  -- Control the file source directly. The old emitter started with zero
  -- volume and used an event-parameter helper; a WAV is not an FMOD event.
  source:setVolume(level)
  if active and (not playing or not source:isPlaying()) then source:play(-1); playing=true end
  if not active and level < 0.002 then dispose() end
end
M.getStatus=function()
  return {sourceId=sourceId,playing=playing,failed=failed,volume=level,cue=cue}
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
