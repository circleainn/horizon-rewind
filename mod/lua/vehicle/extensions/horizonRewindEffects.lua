-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Optional Dynamic Damage Particles 2.0 compatibility. No third-party code,
-- configuration, or files are replaced. This guard lives only in this vehicle.
local M = {}
local guards = {}
local active = false
local hooks = {'onBeamBroke', 'onBeamDeformed', 'updateGFX'}

local function refreshHooks()
  if extensions and extensions.hookUpdate then
    for _, name in ipairs(hooks) do extensions.hookUpdate(name) end
  end
end

local function finish()
  active = false
  for _, entry in ipairs(guards) do
    entry.active = false
    if entry.target[entry.name] == entry.wrapper then
      entry.target[entry.name] = entry.original
    end
  end
  guards = {}
  refreshHooks()
end

local function block(target, name)
  if type(target[name]) ~= 'function' then return end
  local entry = {target = target, name = name, original = target[name], active = true}
  entry.wrapper = function(...)
    if entry.active then return end
    return entry.original(...)
  end
  target[name] = entry.wrapper
  guards[#guards + 1] = entry
end

local function begin()
  if active then return true end
  local particles = rawget(_G, 'crashParticles') or (extensions and rawget(extensions, 'crashParticles'))
  if type(particles) ~= 'table' or type(particles.applyConfig) ~= 'function'
    or type(particles.sendNodeMaterials) ~= 'function'
    or type(particles.sendWheelNodes) ~= 'function' then return false end
  active = true
  for _, name in ipairs(hooks) do block(particles, name) end
  -- Paused historical positions must not generate fresh grip loss or tire cuts.
  block(particles, 'debrisSlip')
  block(particles, 'setGlassPoints')
  if type(particlefilter) == 'table' and type(particlefilter.setConfig) == 'function' then
    block(particlefilter, 'nodeCollision')
  end
  refreshHooks()
  return true
end

M.begin, M.finish, M.abort = begin, finish, finish
M.isActive = function() return active end
M.onExtensionUnloaded = finish
return M
