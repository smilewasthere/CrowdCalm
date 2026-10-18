local ADDON_NAME, ns = ...

local Dev = {}
Dev.__index = Dev
ns.Dev = Dev

local JOURNAL_CAP = 2000
local DELTA_CAP = 30000
local MEM_INTERVAL = 5
local REPORT_CAP = 60000
local TESTS_CAP = 5
local VERDICT_CLEAR = 5
local VERDICT_SLIGHT = 2
local FLIP_GRACE = 2
local DEFAULT_PHASE_SECONDS = 60
local PHASE_LENGTHS = { [30] = true, [60] = true, [120] = true }

function Dev.FrameStats(deltas, capped)
  local stats = {
    frames = 0,
    seconds = 0,
    avgFps = 0,
    avgMs = 0,
    maxMs = 0,
    minFps = 0,
    p1LowFps = 0,
    capped = capped == true,
  }
  local n = deltas and #deltas or 0
  if n == 0 then
    return stats
  end
  local sorted = {}
  local sum, max = 0, 0
  for i = 1, n do
    local delta = deltas[i]
    sorted[i] = delta
    sum = sum + delta
    if delta > max then
      max = delta
    end
  end
  table.sort(sorted, function(a, b)
    return a > b
  end)
  local index = math.max(1, math.ceil(n * 0.01))
  local p1 = sorted[index]
  stats.frames = n
  stats.seconds = sum / 1000
  stats.avgFps = stats.seconds > 0 and (n / stats.seconds) or 0
  stats.avgMs = sum / n
  stats.maxMs = max
  stats.minFps = max > 0 and (1000 / max) or 0
  stats.p1LowFps = p1 > 0 and (1000 / p1) or 0
  return stats
end

function Dev.CompareFrameStats(on, off)
  local onAvg = on.avgFps or 0
  local offAvg = off.avgFps or 0
  local avgDelta = onAvg - offAvg
  local avgPercent = 0
  if offAvg ~= 0 then
    avgPercent = avgDelta / offAvg * 100
  end
  local verdict = "none"
  local magnitude = math.abs(avgPercent)
  if magnitude >= VERDICT_CLEAR then
    verdict = "clear"
  elseif magnitude >= VERDICT_SLIGHT then
    verdict = "slight"
  end
  return {
    avgDelta = avgDelta,
    avgPercent = avgPercent,
    lowDelta = (on.p1LowFps or 0) - (off.p1LowFps or 0),
    verdict = verdict,
  }
end

function Dev.new(settings, deps)
  if type(settings) ~= "table" then
    settings = {}
  end
  if type(settings.enabled) ~= "boolean" then
    settings.enabled = settings.enabled == true
  end
  if type(settings.lastReport) ~= "string" then
    settings.lastReport = ""
  end
  if type(settings.tests) ~= "table" then
    settings.tests = {}
  end
  while #settings.tests > TESTS_CAP do
    table.remove(settings.tests)
  end
  local self = setmetatable({
    settings = settings,
    deps = deps,
    enabled = settings.enabled == true,
    forceCrowd = false,
    entries = {},
    dropped = 0,
    pendingCvars = {},
    lastWrite = {},
    lastApplied = nil,
    lastBaselines = {},
    lastMode = nil,
    test = nil,
    lastTest = nil,
    lastResult = nil,
    lastMem = nil,
  }, Dev)
  return self
end

function Dev:_journal(kind, data)
  data = data or {}
  data.kind = kind
  if data.t == nil then
    data.t = self.deps.getTime()
  end
  self.entries[#self.entries + 1] = data
  if #self.entries > JOURNAL_CAP then
    table.remove(self.entries, 1)
    self.dropped = self.dropped + 1
  end
  return data
end

function Dev:SetEnabled(on)
  on = on == true
  if self.enabled == on then
    return
  end
  if not on then
    if self.test then
      self:StopTest("dev disabled")
    end
    if self.forceCrowd then
      self:SetForceCrowd(false)
    end
  end
  self.enabled = on
  self.settings.enabled = on
  if self.deps.log then
    self.deps.log(on and "dev mode on" or "dev mode off")
  end
end

function Dev:SetForceCrowd(on)
  on = on == true
  if on and not self.enabled then
    return
  end
  if self.forceCrowd == on then
    return
  end
  self.forceCrowd = on
  self:_journal("note", { text = on and "force crowd on" or "force crowd off" })
end

function Dev:StartTest(mode, opts)
  if not self.enabled then
    return
  end
  if self.test then
    self:StopTest("restart")
  end
  opts = opts or {}
  local now = self.deps.getTime()
  local test = {
    mode = mode,
    startedAt = now,
    phaseStartedAt = now,
    groups = {},
  }
  if mode == "auto" then
    local length = tonumber(opts.phaseSeconds)
    if not PHASE_LENGTHS[length] then
      length = DEFAULT_PHASE_SECONDS
    end
    local rounds = opts.rounds == "ABAB" and "ABAB" or "AB"
    test.phaseSeconds = length
    test.rounds = rounds
    test.phaseIndex = 1
    test.phase = rounds:sub(1, 1)
    test.phaseEndsAt = now + length
    test.flipCheckAt = now + FLIP_GRACE
    test.groups.A = { deltas = {}, capped = false }
    test.groups.B = { deltas = {}, capped = false }
  elseif mode == "guided" then
    test.phase = "A"
    test.groups.A = { deltas = {}, capped = false }
    test.groups.B = { deltas = {}, capped = false }
  else
    test.mode = "passive"
    test.phase = "S"
    test.groups.S = { deltas = {}, capped = false }
  end
  self.test = test
  self.lastMem = nil
  self:_journal("test", { mode = test.mode, state = "started" })
  if test.mode == "auto" then
    self:_journal("phase", { name = test.phase, event = "start" })
    self:SetForceCrowd(test.phase == "A")
  elseif test.mode == "guided" then
    self:_journal("phase", { name = "A", event = "start" })
    self:SetForceCrowd(true)
  end
  if self.deps.setFrameHook then
    local last = now
    self.deps.setFrameHook(function()
      local t = self.deps.getTime()
      local delta = (t - last) * 1000
      last = t
      self:OnFrame(t, delta)
    end)
  end
end

function Dev:NextPhase()
  local test = self.test
  if not test or test.mode ~= "guided" then
    return
  end
  self:_journal("phase", { name = test.phase, event = "stop" })
  test.phase = test.phase == "A" and "B" or "A"
  test.interferenceNoted = nil
  test.phaseStartedAt = self.deps.getTime()
  self:_journal("phase", { name = test.phase, event = "start" })
  self:SetForceCrowd(test.phase == "A")
end

function Dev:_buildResult(test)
  local a = test.groups.A
  local b = test.groups.B
  if a and b and #a.deltas > 0 and #b.deltas > 0 then
    local on = Dev.FrameStats(a.deltas, a.capped)
    local off = Dev.FrameStats(b.deltas, b.capped)
    local cmp = Dev.CompareFrameStats(on, off)
    local verb = cmp.avgDelta >= 0 and "is faster by" or "costs"
    return string.format(
      "A %d frames %.1f avg / B %d frames %.1f avg - profile %s %.1f fps (%+.1f%%)",
      on.frames, on.avgFps, off.frames, off.avgFps, verb, math.abs(cmp.avgDelta), cmp.avgPercent
    )
  end
  local s = test.groups.S
  if s and #s.deltas > 0 then
    local stats = Dev.FrameStats(s.deltas, s.capped)
    return string.format("passive %d frames %.1f avg", stats.frames, stats.avgFps)
  end
  if a or b then
    local countA = a and #a.deltas or 0
    local countB = b and #b.deltas or 0
    return string.format("incomplete: A %d frames / B %d frames", countA, countB)
  end
  return "no frames captured"
end

function Dev:StopTest(reason)
  local test = self.test
  if not test then
    return
  end
  reason = reason or "manual"
  test.stoppedAt = self.deps.getTime()
  local state = (reason == "manual" or reason == "complete") and "stopped" or "aborted"
  test.state = state
  test.reason = reason
  if test.mode ~= "passive" then
    self:_journal("phase", { name = test.phase, event = "stop" })
  end
  self:_journal("test", { mode = test.mode, state = state, reason = reason })
  self.lastTest = test
  self.test = nil
  self.lastMem = nil
  self.lastResult = self:_buildResult(test)
  if self.deps.setFrameHook then
    self.deps.setFrameHook(nil)
  end
  if self.forceCrowd then
    self:SetForceCrowd(false)
  end
  self:PersistReport(self:GetReport())
end

function Dev:OnFrame(now, deltaMs)
  local test = self.test
  if not test then
    return
  end
  local group = test.groups[test.phase]
  if not group then
    return
  end
  if #group.deltas >= DELTA_CAP then
    group.capped = true
    return
  end
  group.deltas[#group.deltas + 1] = deltaMs
end

function Dev:_diffSnapshot(snap)
  local mode = snap.mode or "normal"
  if self.lastMode == nil then
    self.lastMode = mode
  elseif mode ~= self.lastMode then
    self:_journal("mode", { from = self.lastMode, to = mode, plates = snap.plates or 0 })
    self.lastMode = mode
  end
  local applied = snap.applied or {}
  local baselines = snap.baselines or {}
  if self.lastApplied == nil then
    self.lastApplied = {}
    for cvar, value in pairs(applied) do
      self.lastApplied[cvar] = value
    end
  else
    for cvar, value in pairs(applied) do
      if self.lastApplied[cvar] == nil then
        self:_journal("apply", { cvar = cvar, value = value, baseline = baselines[cvar] })
        self.lastWrite[cvar] = value
      end
    end
    for cvar in pairs(self.lastApplied) do
      if applied[cvar] == nil then
        local baseline = self.lastBaselines[cvar]
        self:_journal("restore", { cvar = cvar, value = baseline })
        if baseline ~= nil then
          self.lastWrite[cvar] = baseline
        end
      end
    end
  end
  self.lastApplied = {}
  for cvar, value in pairs(applied) do
    self.lastApplied[cvar] = value
  end
  self.lastBaselines = {}
  for cvar, value in pairs(baselines) do
    self.lastBaselines[cvar] = value
  end
end

function Dev:_flushCvars()
  if #self.pendingCvars == 0 then
    return
  end
  for _, item in ipairs(self.pendingCvars) do
    local last = self.lastWrite[item.cvar]
    if last ~= nil then
      local tag = item.value == last and "echo" or "user"
      self:_journal("cvar", { cvar = item.cvar, value = item.value, tag = tag })
    end
  end
  self.pendingCvars = {}
end

function Dev:OnCvar(cvar, value)
  if not self.enabled or cvar == nil or value == nil then
    return
  end
  self.pendingCvars[#self.pendingCvars + 1] = { cvar = tostring(cvar), value = tostring(value) }
end

function Dev:OnTick(now)
  if not self.enabled then
    return
  end
  local snap = nil
  if self.deps.getSnapshot then
    snap = self.deps.getSnapshot()
  end
  if snap then
    self:_diffSnapshot(snap)
  end
  self:_flushCvars()

  local test = self.test
  if test and test.mode == "guided" and test.phase == "B" and snap and (snap.mode or "normal") == "crowd"
    and not test.interferenceNoted then
    test.interferenceNoted = true
    self:_journal("note", { text = "interference: real crowd kept the profile active during phase B" })
  end
  if test and (self.lastMem == nil or now - self.lastMem >= MEM_INTERVAL) then
    self.lastMem = now
    self:_journal("mem", { mb = collectgarbage("count") / 1024, phase = test.phase })
  end

  test = self.test
  if test and test.mode == "auto" then
    if test.flipCheckAt and now >= test.flipCheckAt then
      test.flipCheckAt = nil
      snap = snap or {}
      if snap.pendingReason == "combat" then
        self:StopTest("combat interfered")
      elseif snap.pendingReason == "failed" then
        self:StopTest("apply failed")
      else
        local applied = snap.applied or {}
        local expectedOn = test.phase == "A"
        local hasApplied = next(applied) ~= nil
        if expectedOn ~= hasApplied then
          if snap.pendingReason == "loading" then
            test.flipCheckAt = now + 1
          else
            self:StopTest("apply did not take effect")
          end
        end
      end
    end
    test = self.test
    if test and test.phaseEndsAt and now >= test.phaseEndsAt then
      local nextIndex = test.phaseIndex + 1
      if nextIndex > #test.rounds then
        self:StopTest("complete")
      else
        test.phaseIndex = nextIndex
        test.phase = test.rounds:sub(nextIndex, nextIndex)
        test.phaseEndsAt = test.phaseEndsAt + test.phaseSeconds
        test.phaseStartedAt = now
        test.flipCheckAt = now + FLIP_GRACE
        self:_journal("phase", { name = test.phase, event = "flip" })
        self:SetForceCrowd(test.phase == "A")
      end
    end
  end
end

function Dev:OnLogout(now)
  if not self.enabled then
    return
  end
  if self.test then
    if self.deps.getSnapshot then
      local snap = self.deps.getSnapshot()
      if snap then
        self:_diffSnapshot(snap)
      end
    end
    self:StopTest("logout")
  end
end

function Dev:GetStatus()
  local test = self.test
  return {
    mode = test and test.mode or (self.enabled and "idle" or "off"),
    phase = test and test.phase or nil,
    phaseEndsAt = test and test.phaseEndsAt or nil,
    phaseStartedAt = test and test.phaseStartedAt or nil,
    recording = test ~= nil,
    forceCrowd = self.forceCrowd == true,
    result = self.lastResult,
    dropped = self.dropped,
  }
end

function Dev:GetJournal()
  return self.entries
end

function Dev:GetLastResult()
  return self.lastResult
end

function Dev:_featuresLine()
  local settings = self.settings
  local parts = { "enabled=" .. tostring(settings.enabled == true) }
  if type(settings.categories) == "table" then
    for key, value in pairs(settings.categories) do
      parts[#parts + 1] = string.format("%s=%s", key, tostring(value == true))
    end
  end
  if type(settings.stutter) == "table" then
    parts[#parts + 1] = "stutter=" .. tostring(settings.stutter.enabled == true)
  end
  return table.concat(parts, " ")
end

function Dev:_entriesInWindow(test)
  local out = {}
  if not test then
    return out
  end
  local startedAt = test.startedAt or 0
  local stoppedAt = test.stoppedAt
  for _, entry in ipairs(self.entries) do
    local t = entry.t
    if t and t >= startedAt and (stoppedAt == nil or t <= stoppedAt) then
      out[#out + 1] = entry
    end
  end
  return out
end

local function formatStamp(t, startedAt)
  local rel = math.max(0, t - startedAt)
  return string.format("[%d:%02d]", math.floor(rel / 60), math.floor(rel % 60))
end

function Dev:_comparisonLines(test, add)
  if test and test.groups.A and test.groups.B and #test.groups.A.deltas > 0 and #test.groups.B.deltas > 0 then
    local on = Dev.FrameStats(test.groups.A.deltas, test.groups.A.capped)
    local off = Dev.FrameStats(test.groups.B.deltas, test.groups.B.capped)
    add(string.format("A (profile ON) : %d frames%s / %.1fs | avg %.1f | 1%% low %.1f | worst %.1f",
      on.frames, on.capped and " (capped)" or "", on.seconds, on.avgFps, on.p1LowFps, on.maxMs))
    add(string.format("B (profile OFF): %d frames%s / %.1fs | avg %.1f | 1%% low %.1f | worst %.1f",
      off.frames, off.capped and " (capped)" or "", off.seconds, off.avgFps, off.p1LowFps, off.maxMs))
    local cmp = Dev.CompareFrameStats(on, off)
    local verb = cmp.avgDelta >= 0 and "is faster by" or "costs"
    local word = "no significant difference"
    if cmp.verdict == "clear" then
      word = "clear difference"
    elseif cmp.verdict == "slight" then
      word = "slight difference"
    end
    add(string.format("verdict: profile %s %.1f fps (%+.1f%%) - %s", verb, math.abs(cmp.avgDelta), cmp.avgPercent, word))
    for _, entry in ipairs(self:_entriesInWindow(test)) do
      if entry.kind == "note" and type(entry.text) == "string" and entry.text:find("^interference") then
        add("interference: real crowd kept the profile active during a phase - comparison may be biased")
        break
      end
    end
  elseif test then
    local why = test.mode == "passive" and "passive recording" or "incomplete phases"
    add("comparison unavailable: " .. why)
    local s = test.groups.S
    if s and #s.deltas > 0 then
      local stats = Dev.FrameStats(s.deltas, s.capped)
      add(string.format("S: %d frames%s / %.1fs | avg %.1f", stats.frames, stats.capped and " (capped)" or "", stats.seconds, stats.avgFps))
    end
  else
    add("comparison unavailable: no test recorded")
  end
end

function Dev:_memoryLines(test, add)
  local window = self:_entriesInWindow(test)
  local memEntries = {}
  for _, entry in ipairs(window) do
    if entry.kind == "mem" then
      memEntries[#memEntries + 1] = entry
    end
  end
  if #memEntries == 0 then
    add("no samples")
  else
    local first = memEntries[1].mb
    local last = memEntries[#memEntries].mb
    local peak = first
    for _, entry in ipairs(memEntries) do
      if entry.mb > peak then
        peak = entry.mb
      end
    end
    local seconds = math.max(0.001, memEntries[#memEntries].t - memEntries[1].t)
    local delta = last - first
    add(string.format("lua MB: start %.1f / end %.1f / peak %.1f - %+.1f MB (%+.1f MB/h over %.0fs)",
      first, last, peak, delta, delta / seconds * 3600, seconds))
    local order, perPhase = {}, {}
    for _, entry in ipairs(memEntries) do
      local phase = entry.phase or "-"
      if not perPhase[phase] then
        perPhase[phase] = { first = entry.mb, last = entry.mb }
        order[#order + 1] = phase
      else
        perPhase[phase].last = entry.mb
      end
    end
    for _, phase in ipairs(order) do
      local info = perPhase[phase]
      add(string.format("phase %s: %.1f -> %.1f MB (%+.1f)", phase, info.first, info.last, info.last - info.first))
    end
    add(string.format("samples: %d", #memEntries))
  end
  local stutterCount = "-"
  if ns.Core and ns.Core.stutter and type(ns.Core.stutter.GetEntries) == "function" then
    stutterCount = tostring(#ns.Core.stutter:GetEntries())
  end
  local monitorCount = "-"
  if ns.Monitor and type(ns.Monitor.GetSamples) == "function" then
    monitorCount = tostring(#ns.Monitor.GetSamples())
  end
  add(string.format("buffers: journal %d (dropped %d), tests %d, stutter %s, monitor %s",
    #self.entries, self.dropped, #self.settings.tests, stutterCount, monitorCount))
end

function Dev:_timelineLines(test, add)
  local window = self:_entriesInWindow(test)
  local any = false
  for _, entry in ipairs(window) do
    local stamp = formatStamp(entry.t, test.startedAt)
    if entry.kind == "mode" then
      add(string.format("%s mode %s -> %s (plates %s)", stamp, tostring(entry.from), tostring(entry.to), tostring(entry.plates)))
      any = true
    elseif entry.kind == "apply" then
      add(string.format("%s apply %s = %s (was %s)", stamp, tostring(entry.cvar), tostring(entry.value), tostring(entry.baseline)))
      any = true
    elseif entry.kind == "restore" then
      add(string.format("%s restore %s = %s", stamp, tostring(entry.cvar), tostring(entry.value)))
      any = true
    elseif entry.kind == "phase" then
      add(string.format("%s phase %s %s", stamp, tostring(entry.name), tostring(entry.event)))
      any = true
    elseif entry.kind == "test" then
      add(string.format("%s test %s (%s)", stamp, tostring(entry.state), tostring(entry.reason)))
      any = true
    end
  end
  if not any then
    add("(no events)")
  end
end

function Dev:_userCvarLines(test, add)
  local window = self:_entriesInWindow(test)
  local any = false
  for _, entry in ipairs(window) do
    if entry.kind == "cvar" and entry.tag == "user" then
      add(string.format("%s %s = %s", formatStamp(entry.t, test.startedAt), tostring(entry.cvar), tostring(entry.value)))
      any = true
    end
  end
  if not any then
    add("(none)")
  end
end

function Dev:_failureLines(test, add)
  local window = self:_entriesInWindow(test)
  local any = false
  for _, entry in ipairs(window) do
    if entry.kind == "test" and entry.state == "aborted" then
      add("aborted: " .. tostring(entry.reason))
      any = true
    elseif entry.kind == "error" then
      add("error: " .. tostring(entry.text))
      any = true
    elseif entry.kind == "note" then
      add("note: " .. tostring(entry.text))
      any = true
    end
  end
  if not any then
    add("(none)")
  end
end

function Dev:_slowFrameLines(test, add)
  if not test then
    add("(no test recorded)")
    return
  end
  local slow = {}
  for label, group in pairs(test.groups) do
    for _, delta in ipairs(group.deltas) do
      slow[#slow + 1] = { ms = delta, phase = label }
    end
  end
  if #slow == 0 then
    add("(no frames captured)")
    return
  end
  table.sort(slow, function(a, b)
    return a.ms > b.ms
  end)
  for i = 1, math.min(5, #slow) do
    add(string.format("%d. %.1f ms (%s)", i, slow[i].ms, slow[i].phase))
  end
end

function Dev:GetReport()
  local test = self.test or self.lastTest
  local lines = {}
  local function add(line)
    lines[#lines + 1] = line
  end

  add("== CrowdCalm Dev Report ==")
  local dateStr = "?"
  if type(date) == "function" then
    dateStr = date("%Y-%m-%d %H:%M:%S")
  end
  local version = "?"
  if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then
    local ok, value = pcall(_G.C_AddOns.GetAddOnMetadata, ADDON_NAME or "CrowdCalm", "Version")
    if ok and value ~= nil then
      version = tostring(value)
    end
  end
  local charName = "?"
  if type(UnitName) == "function" then
    charName = tostring(UnitName("player") or "?")
  end
  local zone = "?"
  if type(GetZoneText) == "function" then
    zone = tostring(GetZoneText() or "?")
  end
  add(string.format("generated: %s | addon %s | char %s | zone %s", dateStr, version, charName, zone))
  if test then
    local desc = test.mode
    if test.mode == "auto" then
      desc = string.format("auto %s %ds", test.rounds or "AB", test.phaseSeconds or DEFAULT_PHASE_SECONDS)
    end
    add(string.format("test: %s | state: %s", desc, tostring(test.reason or test.state or "running")))
  else
    add("test: none | state: -")
  end
  add("features: " .. self:_featuresLine())

  add("-- PHASE COMPARISON --")
  self:_comparisonLines(test, add)
  add("-- MEMORY --")
  self:_memoryLines(test, add)
  add("-- SWITCH TIMELINE --")
  self:_timelineLines(test, add)
  add("-- USER CVAR CHANGES --")
  self:_userCvarLines(test, add)
  add("-- FAILURES & NOTES --")
  self:_failureLines(test, add)
  add("-- SLOW FRAMES --")
  self:_slowFrameLines(test, add)
  return table.concat(lines, "\n")
end

function Dev:PersistReport(report)
  report = tostring(report or "")
  if #report > REPORT_CAP then
    report = report:sub(#report - REPORT_CAP + 1)
  end
  self.settings.lastReport = report
  local summary = self.lastResult
  if type(summary) == "string" then
    summary = summary:match("^[^\n]*")
  end
  if type(summary) ~= "string" or summary == "" then
    summary = "no test result"
  end
  local when = "?"
  if type(date) == "function" then
    when = date("%Y-%m-%d %H:%M:%S")
  end
  table.insert(self.settings.tests, 1, { when = when, summary = summary })
  while #self.settings.tests > TESTS_CAP do
    table.remove(self.settings.tests)
  end
end

local function statusLine(dev)
  local status = dev:GetStatus()
  local line = "dev " .. status.mode
  if status.recording then
    line = line .. " - phase " .. tostring(status.phase or "?")
  end
  if status.forceCrowd then
    line = line .. " - force-crowd ON"
  end
  if type(status.result) == "string" then
    line = line .. " - " .. status.result
  end
  return "CrowdCalm: " .. line
end

function Dev.RunCommand(input)
  input = tostring(input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local core = ns.Core
  local dev = core and core.dev
  if input == "on" or input == "off" then
    if not dev then
      print("CrowdCalm: dev mode unavailable")
      return
    end
    dev:SetEnabled(input == "on")
    if input == "off" and ns.DevWindow and ns.DevWindow.Hide then
      ns.DevWindow.Hide()
    end
  elseif input == "status" then
    if not dev then
      print("CrowdCalm: dev mode unavailable")
      return
    end
    print(statusLine(dev))
  elseif input == "report" then
    print("CrowdCalm: use the dev window's 'Copy report' button, or read CrowdCalmDB.settings.dev.lastReport in the SavedVariables file")
  elseif input == "" or input == "window" then
    if not dev then
      print("CrowdCalm: dev mode unavailable")
      return
    end
    if not dev.enabled then
      print("CrowdCalm: dev mode is off - use /ccdev on")
      return
    end
    if ns.DevWindow then
      ns.DevWindow.Toggle()
    else
      print("CrowdCalm: dev window unavailable")
    end
  else
    print("CrowdCalm: usage - /ccdev on | off | status | report | window")
  end
end

SLASH_CROWDCALMDEV1 = "/ccdev"
SlashCmdList["CROWDCALMDEV"] = function(input)
  Dev.RunCommand(input)
end
