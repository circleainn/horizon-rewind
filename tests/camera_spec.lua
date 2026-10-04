-- Camera lifecycle tests with mocked GE objects and BeamNG vector primitives.
-- An embedded runner can provide HORIZON_REWIND_CAMERA_SOURCE for the game VFS.
local scriptPath = debug.getinfo(1, 'S').source:gsub('^@', ''):gsub('\\', '/')
local scriptDirectory = scriptPath:match('^(.*)/') or '.'
local modulePath = scriptDirectory .. '/../mod/lua/ge/extensions/horizonRewindCamera.lua'
local passed = 0

local function eq(actual, expected, label)
  assert(actual == expected, (label or 'value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end

local function near(a, b)
  assert(math.abs(a - b) < 1e-8, 'expected ' .. tostring(b) .. ', got ' .. tostring(a))
end

local function point(a, x, y, z)
  near(a.x, x); near(a.y, y); near(a.z, z)
end

local function test(name, run)
  local ok, err = pcall(run)
  if not ok then error(name .. ': ' .. tostring(err), 0) end
  passed = passed + 1
  print('PASS camera ' .. name)
end

local function harness(mode)
  local h = {mode = mode or 'orbit', playerId = 1, cars = {}, cameras = {}, sets = 0}
  function h.addCar(id)
    local car = {id = id, pos = vec3(100, 5, 2), velocity = vec3(7, 0, 0)}
    function car:getID() return self.id end
    function car:getPositionXYZ() return self.pos.x, self.pos.y, self.pos.z end
    function car:getRefNodeAbsPositionXYZ() return self.pos.x, self.pos.y, self.pos.z end
    function car:getVelocity() return self.velocity end
    h.cars[id] = car
    local cams = {}
    for _, name in ipairs({'orbit', 'chase', 'driver', 'onboard.hood', 'relative'}) do
      local proto = {}
      function proto:update(data)
        self.updates = self.updates + 1
        self.seenPrevPos, self.seenVel = vec3(data.prevPos), vec3(data.vel)
        self.seenTeleport = data.teleported
        data.res.pos:set(data.pos)
        return true
      end
      local cam = setmetatable({updates = 0, resets = 0,
        camRot = vec3(73, -26, 0), camDist = 9.25,
        camLastTargetPos = vec3(100, 5, 2), camLastTargetPos2 = vec3(101, 5, 2),
        camLastPos = vec3(98, -2, 5), camLastPos2 = vec3(98, 5, 2),
        camLastPosPerp = vec3(100, 8, 2), camVel = vec3(-5, 0, 0),
        lastDataPos = vec3(100, 5, 2), prevCarPos = vec3(100, 5, 2),
        relativeYaw = .65, relativePitch = -.2, relYaw = .75, relPitch = .1,
        manualzoom = {fov = 47}, collision = {lastNearClipCenter = vec3(99, 5, 2), useRaycast = false},
        fwdVeloSmoother = {set = function(self, value) self.value = value end}}, {__index = proto})
      function cam:reset()
        self.resets = self.resets + 1
        self.camRot:set(0, -17, 0)
        self.camDist = 5
        self.relativeYaw, self.relativePitch, self.relYaw, self.relPitch = 0, 0, 0, 0
        self.manualzoom.fov = 65
      end
      if name == 'relative' then cam.resetCameraOnVehicleReset = false end
      cams[name] = cam
    end
    h.cameras[id] = cams
    return car
  end
  h.addCar(1); h.addCar(2)
  h.core = {
    getCameraDataById = function(id) return h.cameras[id] end,
    getActiveCamName = function() return h.global or h.mode end,
    getActiveGlobalCameraName = function() return h.global end,
    getPosition = function() return vec3(98, -2, 5) end,
    getQuat = function() return quat(0, 0, 0, 1) end,
    getFovDeg = function() return 47 end,
    setByName = function() h.sets = h.sets + 1 end
  }
  function h.core.onVehicleResetted(id)
    local cam = h.cameras[id] and h.cameras[id][h.mode]
    if cam and cam.resetCameraOnVehicleReset ~= false and not h.global then cam:reset() end
  end
  h.resetHook = h.core.onVehicleResetted
  h.env = setmetatable({
    core_camera = h.core,
    be = {getObjectByID = function(_, id) return h.cars[id] end,
      getPlayerVehicle = function() return h.cars[h.playerId] end},
    commands = {isFreeCamera = function() return h.oldFree == true end},
    extensions = {}
  }, {__index = _G})
  local chunk = HORIZON_REWIND_CAMERA_SOURCE
    and assert(loadstring(HORIZON_REWIND_CAMERA_SOURCE, '@' .. modulePath))
    or assert(loadfile(modulePath))
  setfenv(chunk, h.env)
  h.mod = chunk()
  function h.data()
    local car = h.cars[h.playerId]
    return {veh = car, vid = car.id, pos = vec3(car.pos), vehPos = vec3(car.pos),
      prevPos = vec3(999, 999, 999), prevVehPos = vec3(999, 999, 999),
      vel = vec3(9000, 0, 0), prevVel = vec3(9000, 0, 0), teleported = true,
      res = {pos = vec3(), rot = quat(), targetPos = vec3(), fov = 60}}
  end
  return h
end

test('reset guard is scoped to one vehicle and preserves inherited flags', function()
  local h = harness()
  local orbit = h.cameras[1].orbit
  eq(rawget(orbit, 'resetCameraOnVehicleReset'), nil)
  eq(h.mod.beforeRestore(1), true)
  for _, cam in pairs(h.cameras[1]) do eq(cam.resetCameraOnVehicleReset, false) end
  h.core.onVehicleResetted(1); eq(orbit.resets, 0)
  h.core.onVehicleResetted(2); eq(h.cameras[2].orbit.resets, 1)
  eq(h.core.onVehicleResetted, h.resetHook)
  h.mod.abort()
  eq(rawget(orbit, 'resetCameraOnVehicleReset'), nil)
  eq(h.cameras[1].relative.resetCameraOnVehicleReset, false)
end)

test('reset geometry never enters the camera integrator', function()
  local h = harness()
  local orbit = h.cameras[1].orbit
  h.mod.beforeRestore(1)
  h.cars[1].pos:set(500, 500, 50) -- temporary reset baseline
  local data = h.data()
  orbit:update(data)
  eq(orbit.updates, 0)
  point(data.res.pos, 98, -2, 5)
  point(data.res.targetPos, 100, 5, 2)
  near(data.res.fov, 47)
  point(orbit.camRot, 73, -26, 0); near(orbit.camDist, 9.25)
  h.mod.abort()
end)

test('resume rebases smoothing at the restored car and allows delayed reset hook', function()
  local h = harness()
  local orbit = h.cameras[1].orbit
  local inheritedUpdate = orbit.update
  h.mod.beforeRestore(1)
  h.cars[1].pos:set(60, 9, 3)
  eq(h.mod.afterRestore(1), true)
  point(orbit.camLastTargetPos, 60, 9, 3)
  point(orbit.camLastTargetPos2, 61, 9, 3)
  point(orbit.camLastPos, 58, 2, 6)
  point(orbit.camLastPos2, 58, 9, 3)
  point(orbit.camLastPosPerp, 60, 12, 3)
  point(orbit.lastDataPos, 60, 9, 3)
  point(orbit.prevCarPos, 60, 9, 3)
  point(orbit.camVel, 0, 0, 0)
  point(orbit.collision.lastNearClipCenter, 59, 9, 3)
  eq(orbit.collision.useRaycast, true)
  h.mod.onUpdate(.016)
  h.core.onVehicleResetted(1); eq(orbit.resets, 0)
  orbit:update(h.data())
  eq(orbit.updates, 1)
  point(orbit.seenPrevPos, 60, 9, 3); point(orbit.seenVel, 7, 0, 0)
  eq(orbit.seenTeleport, false)
  point(orbit.camRot, 73, -26, 0); near(orbit.camDist, 9.25)
  h.mod.onUpdate(.016)
  eq(orbit.update, inheritedUpdate); eq(rawget(orbit, 'update'), nil)
  h.core.onVehicleResetted(1); eq(orbit.resets, 1)
  eq(h.sets, 0)
end)

test('chase and cockpit modes retain look and zoom without selecting a mode', function()
  for _, mode in ipairs({'chase', 'driver', 'onboard.hood'}) do
    local h = harness(mode)
    local cam = h.cameras[1][mode]
    h.mod.beforeRestore(1)
    h.core.onVehicleResetted(1)
    h.cars[1].pos:set(-40, 6, 2)
    h.mod.afterRestore(1)
    near(cam.relativeYaw, .65); near(cam.relativePitch, -.2)
    near(cam.relYaw, .75); near(cam.relPitch, .1); near(cam.manualzoom.fov, 47)
    eq(cam.fwdVeloSmoother.value, 0)
    eq(cam.resets, 0); eq(h.mode, mode); eq(h.sets, 0)
    h.mod.abort()
  end
end)

test('global and legacy free cameras are untouched', function()
  for _, legacy in ipairs({false, true}) do
    local h = harness()
    if legacy then h.oldFree = true else h.global = 'free' end
    local originalUpdate = h.cameras[1].orbit.update
    eq(h.mod.beforeRestore(1), false)
    eq(h.mod.afterRestore(1), false)
    eq(h.cameras[1].orbit.update, originalUpdate)
    eq(rawget(h.cameras[1].orbit, 'resetCameraOnVehicleReset'), nil)
    eq(h.sets, 0)
  end
end)

test('changing camera during restore never forces the previous mode back', function()
  local h = harness()
  h.mod.beforeRestore(1)
  h.mode = 'driver'
  h.core.onVehicleResetted(1); eq(h.cameras[1].driver.resets, 0)
  h.cameras[1].driver:update(h.data()); eq(h.cameras[1].driver.updates, 1)
  eq(h.mod.afterRestore(1), true)
  h.mod.onUpdate(.016); h.mod.onUpdate(.016)
  eq(h.mode, 'driver'); eq(h.sets, 0)
  eq(rawget(h.cameras[1].driver, 'resetCameraOnVehicleReset'), nil)
end)

test('switching to free camera releases the guard without moving free camera', function()
  local h = harness()
  h.mod.beforeRestore(1)
  h.global = 'free'
  eq(h.mod.afterRestore(1), false)
  eq(rawget(h.cameras[1].orbit, 'resetCameraOnVehicleReset'), nil)
  eq(h.global, 'free'); eq(h.sets, 0)
end)

test('replacement using the same vehicle id does not inherit guarded camera state', function()
  local h = harness()
  local old = h.cameras[1].orbit
  h.mod.beforeRestore(1)
  h.addCar(1)
  h.mod.onUpdate(.01)
  eq(rawget(old, 'resetCameraOnVehicleReset'), nil)
  eq(rawget(old, 'update'), nil)
  eq(rawget(h.cameras[1].orbit, 'resetCameraOnVehicleReset'), nil)
  eq(h.mod.afterRestore(1), false)
end)

test('timeout unload serialization and explicit abort all restore owned state', function()
  for _, finish in ipairs({'timeout', 'onExtensionUnloaded', 'onClientEndMission', 'onSerialize', 'abort'}) do
    local h = harness()
    local orbit = h.cameras[1].orbit
    h.mod.beforeRestore(1)
    if finish == 'timeout' then h.mod.onUpdate(8.1) else h.mod[finish]() end
    eq(rawget(orbit, 'resetCameraOnVehicleReset'), nil)
    eq(rawget(orbit, 'update'), nil)
    h.mod.abort()
  end
end)

test('cleanup does not overwrite another mod changes and old wrappers become transparent', function()
  local h = harness()
  local cam = h.cameras[1].orbit
  h.mod.beforeRestore(1)
  local wrapped = cam.update
  local later = function(self, data) return wrapped(self, data) end
  cam.update, cam.resetCameraOnVehicleReset = later, true
  h.mod.abort()
  eq(cam.update, later); eq(cam.resetCameraOnVehicleReset, true)
  cam:update(h.data()); eq(cam.updates, 1)
end)

test('unrelated ids and stale completion cannot finish the active guard', function()
  local h = harness()
  eq(h.mod.beforeRestore(2), false)
  h.mod.beforeRestore(1)
  eq(h.mod.afterRestore(2), false)
  eq(h.cameras[1].orbit.resetCameraOnVehicleReset, false)
  h.mod.abort()
end)

print('CAMERA_SPECS_PASSED ' .. passed)
