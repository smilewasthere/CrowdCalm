-- Core/Util.lua — shared helpers: pools, ring buffers, refcounted tickers,
-- small math/table utilities. Everything preallocated; no allocation inside
-- timer callbacks (brief section 6).
local ADDON_NAME, ns = ...

local Util = {}
ns.util = Util

-- ---------------------------------------------------------------- math ----

function Util.clamp(v, lo, hi)
  if v < lo then
    return lo
  end
  if v > hi then
    return hi
  end
  return v
end

function Util.round(v, digits)
  local mult = 10 ^ (digits or 0)
  if v >= 0 then
    return math.floor(v * mult + 0.5) / mult
  end
  return math.ceil(v * mult - 0.5) / mult
end

-- --------------------------------------------------------------- tables ---

function Util.deepCopy(v)
  if type(v) ~= "table" then
    return v
  end
  local out = {}
  for k, item in pairs(v) do
    out[k] = Util.deepCopy(item)
  end
  return out
end

function Util.deepMerge(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then
        dst[k] = Util.deepCopy(v)
      else
        dst[k] = v
      end
    elseif type(dst[k]) == "table" and type(v) == "table" then
      Util.deepMerge(dst[k], v)
    end
  end
  return dst
end

-- ---------------------------------------------------------------- pools ----
-- WoW never frees frames: acquire from the pool or create once, release back.

function Util.CreatePool(createFn)
  local pool = { free = {}, all = {} }
  function pool:Acquire()
    local n = #self.free
    local obj
    if n > 0 then
      obj = self.free[n]
      self.free[n] = nil
    else
      obj = createFn()
      self.all[#self.all + 1] = obj
    end
    if obj.Show then
      obj:Show()
    end
    return obj
  end
  function pool:Release(obj)
    if not obj then
      return
    end
    if obj.Hide then
      obj:Hide()
    end
    self.free[#self.free + 1] = obj
  end
  function pool:Counts()
    return #self.all, #self.free
  end
  function pool:Total()
    return #self.all
  end
  return pool
end

function Util.CreateFramePool(frameType, parent, template)
  return Util.CreatePool(function()
    return CreateFrame(frameType, parent, template)
  end)
end

function Util.CreateTexturePool(parent, layer, subLayer)
  return Util.CreatePool(function()
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    if subLayer then
      tex:SetDrawLayer(layer or "ARTWORK", subLayer)
    end
    return tex
  end)
end

-- -------------------------------------------------------- ring buffer -----

function Util.NewRing(cap)
  local buf = {}
  for i = 1, cap do
    buf[i] = false -- placeholder so the array shape exists; slots get replaced
  end
  local ring = { buf = buf, cap = cap, n = 0, pos = 0 }
  function ring:Push(item)
    self.pos = self.pos % self.cap + 1
    self.buf[self.pos] = item
    if self.n < self.cap then
      self.n = self.n + 1
    end
  end
  function ring:Count()
    return self.n
  end
  function ring:Clear()
    self.n = 0
    self.pos = 0
  end
  -- newest item first (pos), then backwards
  function ring:Get(i)
    -- i = 1 is oldest
    if i < 1 or i > self.n then
      return nil
    end
    local start = (self.pos - self.n) % self.cap + 1
    local idx = (start + i - 2) % self.cap + 1
    return self.buf[idx]
  end
  return ring
end

-- -------------------------------------------------------- refcounted ticker ----
-- One C_Timer ticker per key; consumers Acquire (start) and Release (stop).
-- The timer callback itself never allocates.

local activeTickers = {}

function Util.AcquireTicker(key, seconds, callback)
  local entry = activeTickers[key]
  if entry then
    entry.refs = entry.refs + 1
    return entry
  end
  entry = { refs = 1, seconds = seconds, callback = callback, ticker = nil }
  entry.ticker = C_Timer.NewTicker(seconds, callback)
  activeTickers[key] = entry
  return entry
end

function Util.ReleaseTicker(key)
  local entry = activeTickers[key]
  if not entry then
    return
  end
  entry.refs = entry.refs - 1
  if entry.refs <= 0 then
    if entry.ticker and entry.ticker.Cancel then
      entry.ticker:Cancel()
    end
    activeTickers[key] = nil
  end
end

function Util.HasTicker(key)
  return activeTickers[key] ~= nil
end

function Util.ActiveTickerCount()
  local n = 0
  for _ in pairs(activeTickers) do
    n = n + 1
  end
  return n
end

-- -------------------------------------------------------------- misc ------

function Util.SafeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    local label = (ns.name or "CrowdCalmLab") .. ": " .. tostring(err)
    print("|cffff5555" .. label .. "|r")
  end
  return ok
end

function Util.LogError(where, err)
  print("|cffff5555" .. (ns.name or "CrowdCalmLab") .. "|r " .. tostring(where) .. ": " .. tostring(err))
end

function Util.LogInfo(msg)
  print("|cffd9a441" .. (ns.name or "CrowdCalmLab") .. "|r " .. tostring(msg))
end
