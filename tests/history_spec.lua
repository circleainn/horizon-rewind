-- Run with a standard Lua 5.1+ interpreter, or BeamNG's console Lua runner.
-- Resolve the module relative to this script so the working directory is free.
local scriptPath = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local scriptDirectory = scriptPath:match("^(.*)/") or "."
local history = package.loaded['horizonRewind/history']
  or dofile(scriptDirectory .. "/../mod/lua/common/horizonRewind/history.lua")
local passed = 0

local function eq(actual, expected, label)
  assert(actual == expected, (label or "value") .. ": expected "
    .. tostring(expected) .. ", got " .. tostring(actual))
end

local function near(actual, expected)
  assert(math.abs(actual - expected) < 1e-10,
    "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function fails(fn)
  local ok = pcall(fn)
  assert(not ok, "expected an error")
end

local function sample(time)
  return {time = time, value = time * 3}
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then error(name .. ": " .. tostring(err), 0) end
  passed = passed + 1
  print("PASS " .. name)
end

test("empty and single sample boundaries", function()
  local h = history.new()
  eq(h:count(), 0)
  eq(h:duration(), 0)
  eq(h:oldest(), nil)
  eq(h:latest(), nil)
  local a, b, alpha = h:bracket(0)
  eq(a, nil); eq(b, nil); eq(alpha, 0)
  local s = sample(7)
  eq(h:push(s), s)
  eq(h:oldest(), s); eq(h:latest(), s); eq(h:duration(), 0)
  for _, time in ipairs({-100, 7, 100}) do
    a, b, alpha = h:bracket(time)
    eq(a, s); eq(b, s); eq(alpha, 0)
  end
end)

test("count cap and repeated ring wraps", function()
  local h = history.new(1000, 4)
  for time = 1, 100 do
    h:push(sample(time))
    eq(h:count(), math.min(time, 4))
    eq(h:oldest().time, math.max(1, time - 3))
    eq(h:latest().time, time)
    eq(h:duration(), math.min(time - 1, 3))
    if time > 1 then
      local a, b, alpha = h:bracket(time - 0.25)
      eq(a.time, time - 1); eq(b.time, time); near(alpha, 0.75)
    end
  end
end)

test("time cap retains only required predecessor", function()
  local h = history.new(5, 100)
  for _, time in ipairs({0, 2, 4, 6, 8}) do h:push(sample(time)) end
  -- Cutoff is 3: time 2 is needed to interpolate with time 4.
  eq(h:count(), 4); eq(h:oldest().time, 2); eq(h:duration(), 6)
  local a, b, alpha = h:bracket(3)
  eq(a.time, 2); eq(b.time, 4); near(alpha, 0.5)
  h:push(sample(9))
  -- Cutoff is exactly 4: time 2 is no longer needed.
  eq(h:oldest().time, 4); eq(h:count(), 4); eq(h:duration(), 5)
  h:push(sample(100))
  eq(h:count(), 2); eq(h:oldest().time, 9); eq(h:latest().time, 100)
end)

test("time trimming and capacity interact across wraps", function()
  local h = history.new(1, 5)
  for time = 1, 40 do h:push(sample(time * 0.5)) end
  eq(h:count(), 3); eq(h:oldest().time, 19); eq(h:latest().time, 20)
  local a, b, alpha = h:bracket(19.75)
  eq(a.time, 19.5); eq(b.time, 20); near(alpha, 0.5)
end)

test("irregular timestep interpolation and clamping", function()
  local h = history.new(100, 10)
  for _, time in ipairs({-4, 0, 0.2, 2, 11}) do h:push(sample(time)) end
  local a, b, alpha = h:bracket(0.65)
  eq(a.time, 0.2); eq(b.time, 2); near(alpha, 0.25)
  near(a.value + (b.value - a.value) * alpha, 0.65 * 3)
  a, b, alpha = h:bracket(-10)
  eq(a.time, -4); eq(b, a); eq(alpha, 0)
  a, b, alpha = h:bracket(99)
  eq(a.time, 11); eq(b, a); eq(alpha, 0)
  for _, time in ipairs({-4, 0, 0.2, 2, 11}) do
    a, b, alpha = h:bracket(time)
    eq(a.time, time); eq(b, a); eq(alpha, 0)
  end
end)

test("branching discards future and permits a new clock branch", function()
  local h = history.new(100, 4)
  for time = 1, 7 do h:push(sample(time)) end
  eq(h:truncateAfter(5.5), 2)
  eq(h:count(), 2); eq(h:oldest().time, 4); eq(h:latest().time, 5)
  h:push(sample(5.5)); h:push(sample(6.25)); h:push(sample(8))
  eq(h:count(), 4); eq(h:oldest().time, 5); eq(h:latest().time, 8)
  local a, b, alpha = h:bracket(6)
  eq(a.time, 5.5); eq(b.time, 6.25); near(alpha, 2 / 3)
  eq(h:truncateAfter(6.25), 1)
  eq(h:latest().time, 6.25)
  eq(h:truncateAfter(99), 0)
  eq(h:truncateAfter(-1), 3)
  eq(h:count(), 0); eq(h:oldest(), nil)
  h:push(sample(-2)); eq(h:latest().time, -2)
end)

test("clear resets wrapped history and timestamp constraints", function()
  local h = history.new(20, 3)
  for time = 1, 10 do h:push(sample(time)) end
  h:clear()
  eq(h:count(), 0); eq(h:duration(), 0)
  eq(h:latest(), nil); eq(h:oldest(), nil)
  eq(h:truncateAfter(0), 0)
  h:push(sample(0)); h:push(sample(1))
  eq(h:oldest().time, 0); eq(h:latest().time, 1)
  h:clear(); h:clear(); eq(h:count(), 0)
end)

test("duplicate, backward and invalid samples leave history intact", function()
  local h = history.new(20, 3)
  local first = sample(5)
  h:push(first)
  fails(function() h:push(sample(5)) end)
  fails(function() h:push(sample(4)) end)
  fails(function() h:push(nil) end)
  fails(function() h:push({}) end)
  fails(function() h:push("sample") end)
  for _, time in ipairs({0 / 0, math.huge, -math.huge, "6", false}) do
    fails(function() h:push({time = time}) end)
    fails(function() h:bracket(time) end)
    fails(function() h:truncateAfter(time) end)
  end
  fails(function() h:bracket(nil) end)
  fails(function() h:truncateAfter(nil) end)
  eq(h:count(), 1); eq(h:oldest(), first); eq(h:latest(), first)
  h:push(sample(6)); eq(h:count(), 2)
end)

test("constructor validation and smallest capacities", function()
  for _, seconds in ipairs({-1, 0 / 0, math.huge, -math.huge, "20", false}) do
    fails(function() history.new(seconds, 3) end)
  end
  for _, count in ipairs({0, -1, 1.5, 0 / 0, math.huge, -math.huge, "3", false}) do
    fails(function() history.new(20, count) end)
  end
  local one = history.new(20, 1)
  one:push(sample(1)); one:push(sample(2))
  eq(one:count(), 1); eq(one:oldest().time, 2); eq(one:duration(), 0)
  local zero = history.new(0, 10)
  zero:push(sample(1)); zero:push(sample(2))
  eq(zero:count(), 1); eq(zero:latest().time, 2)
end)

test("defaults enforce both limits", function()
  local h = history.new()
  for index = 0, 999 do h:push(sample(index / 100)) end
  eq(h:count(), 600); near(h:oldest().time, 4)
  h:clear()
  for time = 0, 40 do h:push(sample(time)) end
  eq(h:count(), 21); eq(h:oldest().time, 20); eq(h:latest().time, 40)
end)

print("history_spec: " .. passed .. " tests passed")
