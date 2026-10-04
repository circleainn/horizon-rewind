-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Keep the current vehicle camera through our short structural reset.
-- BeamNG 0.39 checks resetCameraOnVehicleReset on the actual camera instance.
-- Use that opt-out instead of replacing core_camera hooks or selecting a mode.
local M = {}
local guard
local timeoutSeconds = 8

local function cameraCore()
  return core_camera or (extensions and extensions.core_camera)
end

local function getVehicle(id)
  return be and be:getObjectByID(id) or nil
end

local function position(car, reference)
  if reference and car.getRefNodeAbsPositionXYZ then
    return vec3(car:getRefNodeAbsPositionXYZ())
  end
  if car.getPositionXYZ then return vec3(car:getPositionXYZ()) end
  if car.getPosition then return vec3(car:getPosition()) end
end

local function activeVehicleCamera(id)
  local camera = cameraCore()
  if not camera or not camera.getCameraDataById or not camera.getActiveCamName then return end
  if camera.getActiveGlobalCameraName and camera.getActiveGlobalCameraName(0) then return end
  if commands and commands.isFreeCamera and commands.isFreeCamera() then return end
  local player = be and be:getPlayerVehicle(0)
  if not player or player:getID() ~= id then return end
  local cameras = camera.getCameraDataById(id)
  local name = camera.getActiveCamName(0)
  return cameras and cameras[name], cameras, name, camera
end

local function restoreOwnedValues(g)
  g.active = false
  for _, entry in ipairs(g.flags) do
    if rawget(entry.camera, 'resetCameraOnVehicleReset') == false then
      rawset(entry.camera, 'resetCameraOnVehicleReset', entry.value)
    end
  end
  if g.wrapper and rawget(g.camera, 'update') == g.wrapper then
    rawset(g.camera, 'update', g.rawUpdate)
  end
end

local function abort()
  local g = guard
  guard = nil
  if g then restoreOwnedValues(g) end
end

local function setVector(target, source)
  if target and source and type(target.set) == 'function' then target:set(source) end
end

-- Only world-space history is translated. Orbit angles/distances, cockpit
-- look/seat/FOV, and smoothing objects remain the same live instances.
local worldHistory = {
  'camLastTargetPos', 'camLastTargetPos2', 'camLastPos',
  'camLastPos2', 'camLastPosPerp'
}

local function rebaseHistory(g)
  local car = getVehicle(g.vehicleId)
  if not car or car ~= g.vehicle then return end
  local newAnchor = position(car, true)
  local newPosition = position(car)
  local delta = newAnchor and g.anchor and (newAnchor - g.anchor)
  local camera = g.camera
  if delta then
    for _, key in ipairs(worldHistory) do
      local value = camera[key]
      if value and type(value.setAdd) == 'function' then value:setAdd(delta) end
    end
    local collision = camera.collision
    if collision then
      if collision.lastNearClipCenter then
        collision.lastNearClipCenter:setAdd(delta)
      end
      -- Recheck the destination's walls without throwing away zoom smoothing.
      collision.useRaycast = true
    end
  end
  setVector(camera.lastDataPos, newPosition) -- chase movement/velocity history
  setVector(camera.prevCarPos, newPosition) -- driver movement/autocenter history
  if camera.camVel then camera.camVel:set(0, 0, 0) end
  if camera.fwdVeloSmoother and camera.fwdVeloSmoother.set then
    camera.fwdVeloSmoother:set(0) -- do not interpret a restore jump as reversing
  end
end

local function seedFrame(data)
  -- core_camera computes velocity before the mode runs. Its previous frame
  -- may contain the temporary reset baseline; discard that false teleport.
  setVector(data.prevPos, data.pos)
  setVector(data.prevVehPos, data.vehPos)
  if data.veh and data.veh.getVelocity then
    local velocity = data.veh:getVelocity()
    setVector(data.vel, velocity)
    setVector(data.prevVel, velocity)
  end
  data.teleported = false
end

local function beforeRestore(vehicleId)
  if guard and guard.vehicleId == vehicleId and guard.phase == 'resetting' then return true end
  abort()
  local camera, cameras, name, core = activeVehicleCamera(vehicleId)
  local car = getVehicle(vehicleId)
  if type(camera) ~= 'table' or not car then return false end
  local g = {vehicleId = vehicleId, vehicle = car, camera = camera,
    name = name, flags = {}, active = true, phase = 'resetting', elapsed = 0,
    anchor = position(car, true), rawUpdate = rawget(camera, 'update'),
    update = camera.update}

  -- Guard every camera of this vehicle so a user-selected mode during the
  -- reset also retains its settings. Other vehicles and free cameras are untouched.
  for _, instance in pairs(cameras) do
    if type(instance) == 'table' then
      g.flags[#g.flags + 1] = {camera = instance, value = rawget(instance, 'resetCameraOnVehicleReset')}
      instance.resetCameraOnVehicleReset = false
    end
  end
  guard = g

  if core.getPosition and core.getQuat and core.getFovDeg and type(g.update) == 'function' then
    local fov = core.getFovDeg()
    if type(fov) == 'number' and fov > 0 then
      g.pose = {pos = vec3(core.getPosition()), rot = quat(core.getQuat()),
        fov = fov, target = vec3(camera.camLastTargetPos or g.anchor)}
      g.wrapper = function(self, data)
        -- An intervening mod may wrap this function, or the player may switch
        -- away. Once released this closure is just a transparent pass-through.
        local current = g.active and activeVehicleCamera(g.vehicleId)
        if not g.active or current ~= self or data.vid ~= g.vehicleId then
          return g.update(self, data)
        end
        if g.phase == 'resetting' then
          -- Do not let any camera integrator see the reset's temporary body.
          setVector(data.res.pos, g.pose.pos)
          setVector(data.res.rot, g.pose.rot)
          setVector(data.res.targetPos, g.pose.target)
          data.res.fov = g.pose.fov
          return true
        end
        if g.seedPending then
          g.seedPending = false
          seedFrame(data)
        end
        return g.update(self, data)
      end
      camera.update = g.wrapper
    end
  end
  return true
end

local function afterRestore(vehicleId)
  local g = guard
  if not g or g.vehicleId ~= vehicleId or g.phase ~= 'resetting' then return false end
  local current, cameras = activeVehicleCamera(vehicleId)
  if getVehicle(vehicleId) ~= g.vehicle or not cameras or cameras[g.name] ~= g.camera then
    abort()
    return false
  end
  -- The coordinator must publish the restored geometry to GE BEFORE this call.
  -- No setByName/deserialize: those would trigger another camera transition.
  rebaseHistory(g)
  g.phase, g.seedPending, g.graceUpdates = 'resuming', current == g.camera, 2
  return true
end

local function onUpdate(dtReal)
  local g = guard
  if not g then return end
  g.elapsed = g.elapsed + math.max(tonumber(dtReal) or 0, 0)
  if getVehicle(g.vehicleId) ~= g.vehicle or g.elapsed > timeoutSeconds then abort(); return end
  local core = cameraCore()
  local cameras = core and core.getCameraDataById and core.getCameraDataById(g.vehicleId)
  if not cameras or cameras[g.name] ~= g.camera then abort(); return end
  if g.phase == 'resuming' then
    -- The reset hook can arrive after the physics acknowledgment. Keep its
    -- opt-out through a full update boundary without delaying normal camera input.
    g.graceUpdates = g.graceUpdates - 1
    if g.graceUpdates <= 0 then abort() end
  end
end

M.beforeRestore, M.afterRestore, M.abort = beforeRestore, afterRestore, abort
M.onUpdate = onUpdate
M.onExtensionUnloaded, M.onClientEndMission = abort, abort
M.onSerialize = function() abort(); return {} end
return M
