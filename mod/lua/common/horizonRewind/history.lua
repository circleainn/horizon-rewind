-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Engine-independent, bounded snapshot history (Lua 5.1).
-- Samples are stored by reference. Treat each stored sample, including its time,
-- as immutable. All times use the same monotonically increasing clock.
local M = {}
local History = {}
History.__index = History

local function finite(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function requireTime(value)
  if not finite(value) then
    error("history time must be a finite number", 3)
  end
end

local function indexAt(self, offset)
  return ((self._head + offset - 2) % self._capacity) + 1
end

local function sampleAt(self, offset)
  return self._samples[indexAt(self, offset)]
end

local function discardOldest(self)
  self._samples[self._head] = nil
  self._head = (self._head % self._capacity) + 1
  self._count = self._count - 1
end

function M.new(maxSeconds, maxSamples)
  if maxSeconds == nil then maxSeconds = 20 end
  if maxSamples == nil then maxSamples = 600 end
  if not finite(maxSeconds) or maxSeconds < 0 then
    error("maxSeconds must be a finite nonnegative number", 2)
  end
  if not finite(maxSamples) or maxSamples < 1 or maxSamples % 1 ~= 0 then
    error("maxSamples must be a positive integer", 2)
  end
  return setmetatable({
    _maxSeconds = maxSeconds,
    _capacity = maxSamples,
    _samples = {},
    _head = 1,
    _count = 0
  }, History)
end

function History:push(sample)
  if type(sample) ~= "table" then
    error("history sample must be a table", 2)
  end
  requireTime(sample.time)
  local latest = self:latest()
  if latest and sample.time <= latest.time then
    error("history sample times must be strictly increasing", 2)
  end

  if self._count == self._capacity then discardOldest(self) end
  self._count = self._count + 1
  self._samples[indexAt(self, self._count)] = sample

  -- Retain the predecessor of the time window to interpolate its start.
  -- If a sample lies exactly on the cutoff, no predecessor is needed.
  local cutoff = sample.time - self._maxSeconds
  while self._count > 1 and sampleAt(self, 2).time <= cutoff do
    discardOldest(self)
  end
  return sample
end

function History:oldest()
  if self._count == 0 then return nil end
  return sampleAt(self, 1)
end

function History:latest()
  if self._count == 0 then return nil end
  return sampleAt(self, self._count)
end

function History:count()
  return self._count
end

function History:duration()
  if self._count < 2 then return 0 end
  return self:latest().time - self:oldest().time
end

-- Empty history: nil, nil, 0. Clamped endpoints and exact timestamps:
-- the same sample twice, alpha 0. Otherwise a.time < time < b.time.
function History:bracket(time)
  requireTime(time)
  if self._count == 0 then return nil, nil, 0 end
  local oldest, latest = self:oldest(), self:latest()
  if time <= oldest.time then return oldest, oldest, 0 end
  if time >= latest.time then return latest, latest, 0 end

  local lo, hi = 1, self._count
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    local sample = sampleAt(self, mid)
    if time == sample.time then return sample, sample, 0 end
    if sample.time < time then lo = mid else hi = mid end
  end
  local a, b = sampleAt(self, lo), sampleAt(self, hi)
  return a, b, (time - a.time) / (b.time - a.time)
end

-- Remove the abandoned future before recording a new branch. No interpolated
-- sample is inserted here: callers may push their restored state afterward.
function History:truncateAfter(time)
  requireTime(time)
  local lo, hi = 0, self._count
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if sampleAt(self, mid).time <= time then lo = mid else hi = mid - 1 end
  end
  local removed = self._count - lo
  for offset = self._count, lo + 1, -1 do
    self._samples[indexAt(self, offset)] = nil
  end
  self._count = lo
  if lo == 0 then self._head = 1 end
  return removed
end

function History:clear()
  self._samples = {}
  self._head = 1
  self._count = 0
end

return M
