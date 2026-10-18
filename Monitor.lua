local ADDON_NAME, ns = ...

local Monitor = {}
ns.Monitor = Monitor

local MAX_SAMPLES = 12

Monitor.samples = {}

function Monitor.GetOwnMB()
  return collectgarbage("count") / 1024
end

function Monitor.Push(now, mb)
  local samples = Monitor.samples
  samples[#samples + 1] = { t = now, mb = mb }
  while #samples > MAX_SAMPLES do
    table.remove(samples, 1)
  end
end

function Monitor.GetSamples()
  return Monitor.samples
end

function Monitor.GetLast()
  local last = Monitor.samples[#Monitor.samples]
  if last then
    return last.mb
  end
  return nil
end
