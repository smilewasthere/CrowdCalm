-- Engine/LabRunner.lua — the A-B-A heart of the lab (brief section 5.3).
-- For each selected setting: sample A1 (8 s), lower it, settle (3 s), sample
-- B (8 s), restore, settle (3 s), sample A2 (8 s). Gain = B - avg(A1,A2);
-- A1/A2 diverging by more than 10% marks the row "Noisy, rerun". Quick runs
-- once; Thorough repeats 3x and takes the median. Records the apply-moment
-- hitch (worst sample within 1 s after each set). Cancel, combat, foreign
-- CVar changes and read-back mismatches all restore through CVarGuard.
local ADDON_NAME, ns = ...

local Lab = {}
ns.lab = Lab

Lab.state = "idle" -- "idle" | "running"
Lab.activeRunId = 0
Lab.lastError = nil -- { key = "combat"|"instance"|"noselect"|"cancelled"|"foreign"|"noapi", ... }
Lab.lastRun = nil
Lab.completedAt = nil
local mode = "quick"

Lab.progress = {
  phase = "", -- "sample" | "settle" | "applying" | "restoring" | ""
  cand = nil,
  labelKey = nil,
  pass = 1,
  passes = 1,
  stepFrom = nil,
  stepTo = nil,
  gain = nil,
  jobIndex = 0,
  jobCount = 0,
  noisy = false,
  hitch = false,
}

local phaseTimer = nil
local jobs = {}
local jobIndex = 1
local pass = 1
local passes = 1
local rows = {}
local runSeq = 0
local hitchWorst = nil
local hitchWindow = 0

local snapA1, snapB, snapA2 = nil, nil, nil
local hitchApply = nil -- worst FPS in the 1 s window after the apply (review I4)

local function cancelTimer()
  if phaseTimer then
    if phaseTimer.Cancel then
      phaseTimer:Cancel()
    end
    phaseTimer = nil
  end
end

local function setPhase(seconds, fn)
  cancelTimer()
  phaseTimer = C_Timer.NewTicker(seconds, fn, 1)
end

local function labSettings()
  if ns.db and ns.db.settings and ns.db.settings.lab then
    return ns.db.settings.lab
  end
  return { sampleSeconds = 8, settleSeconds = 3, defaultMode = "quick" }
end

local function snapshotCopy()
  local s = ns.stats.Snapshot()
  return {
    avg = s.avg,
    median = s.median,
    p5 = s.p5,
    count = s.count,
    d50 = s.d50,
    d100 = s.d100,
    d500 = s.d500,
    d1000 = s.d1000,
  }
end

local function longTotal(snap)
  return snap.d50 + snap.d100 + snap.d500 + snap.d1000
end

-- step down by exactly one; unknown ranges stay within [0, current]
local function computeLower(cand, num)
  if type(num) ~= "number" then
    return nil
  end
  local lower
  if cand.min ~= nil then
    lower = math.max(cand.min, num - 1)
  else
    lower = num - 1
    if lower < 0 then
      lower = 0
    end
  end
  if lower >= num then
    return nil
  end
  return lower
end

local function currentJob()
  return jobs[jobIndex]
end

local function buildRow(j, before, after, gain, noisyFlag, hitchFlag, hitchFps, notTestable, reason)
  local cost = "Unknown"
  if j.cands[1] and j.cands[1].key then
    cost = ns.settings.costOf(j.cands[1].key)
  end
  -- tested values (pre.3): what was actually changed, so Results can say
  -- "set it to X (it is Y now)" instead of only reporting FPS movement.
  local changes
  if j.fromValues and j.lowers and not notTestable then
    for i = 1, #j.keys do
      local from = j.fromValues[i]
      local to = j.lowers[i]
      if from ~= nil and to ~= nil then
        if not changes then
          changes = {}
        end
        changes[#changes + 1] = {
          key = j.keys[i],
          labelKey = j.cands[i] and j.cands[i].label or nil,
          from = from,
          to = to,
        }
      end
    end
  end
  return {
    id = j.id,
    key = j.key,
    labelKey = j.labelKey,
    before = before,
    after = after,
    gain = gain,
    medBefore = before,
    medAfter = after,
    p5Before = snapA1 and snapA1.p5 or 0,
    p5After = snapB and snapB.p5 or 0,
    longBefore = snapA1 and longTotal(snapA1) or 0,
    longAfter = snapB and longTotal(snapB) or 0,
    noisy = noisyFlag,
    confidence = ns.stats.confidence(mode, noisyFlag),
    hitch = hitchFlag,
    hitchFps = hitchFps,
    notTestable = notTestable,
    reason = reason,
    cost = cost,
    valueFrom = j.baseValue,
    valueTo = j.lowers and j.lowers[1] or nil,
    changes = changes,
  }
end

-- ------------------------------------------------------------ phases ------

local phaseA1Done, phasePreB, phaseBDone, phasePreA2, phaseA2Done

local function startPass()
  local j = currentJob()
  Lab.progress.phase = "sample"
  Lab.progress.cand = j.cands[1]
  Lab.progress.labelKey = j.labelKey
  Lab.progress.pass = pass
  Lab.progress.passes = passes
  Lab.progress.jobIndex = jobIndex
  Lab.progress.jobCount = #jobs
  Lab.progress.stepFrom = j.baseValue
  Lab.progress.stepTo = j.lower
  Lab.progress.gain = nil
  Lab.progress.noisy = false
  Lab.progress.hitch = false
  snapA1, snapB, snapA2 = nil, nil, nil
  ns.stats.Reset()
  setPhase(labSettings().sampleSeconds, phaseA1Done)
end

phaseA1Done = function()
  snapA1 = snapshotCopy()
  local j = currentJob()
  Lab.progress.phase = "applying"
  ns.context.Update(true)
  -- apply every CVar of this job
  local failed = false
  for i = 1, #j.keys do
    local key = j.keys[i]
    local ok, err = ns.cvarGuard.Apply(key, j.lowers[i])
    if not ok then
      failed = true
      j.failReason = tostring(err)
      break
    end
  end
  if failed then
    ns.cvarGuard.EndTest()
    rows[#rows + 1] = buildRow(j, nil, nil, nil, false, false, nil, true, j.failReason)
    jobIndex = jobIndex + 1
    pass = 1
    if jobIndex > #jobs then
      ns.lab.FinishRun()
    else
      ns.lab.StartJob()
    end
    return
  end
  hitchWorst = nil
  hitchWindow = 1.0
  hitchApply = nil
  setPhase(labSettings().settleSeconds, phasePreB)
end

phasePreB = function()
  Lab.progress.phase = "sample"
  hitchApply = hitchWorst -- keep the apply-moment hitch (review I4)
  ns.stats.Reset()
  setPhase(labSettings().sampleSeconds, phaseBDone)
end

phaseBDone = function()
  snapB = snapshotCopy()
  local j = currentJob()
  Lab.progress.phase = "restoring"
  for i = 1, #j.keys do
    ns.cvarGuard.Restore(j.keys[i])
  end
  hitchWorst = nil
  hitchWindow = 1.0
  setPhase(labSettings().settleSeconds, phasePreA2)
end

phasePreA2 = function()
  Lab.progress.phase = "sample"
  ns.stats.Reset()
  setPhase(labSettings().sampleSeconds, phaseA2Done)
end

phaseA2Done = function()
  snapA2 = snapshotCopy()
  local j = currentJob()
  local gain = snapB.avg - ((snapA1.avg + snapA2.avg) / 2)
  local noisyFlag = ns.stats.noisy(snapA1.avg, snapA2.avg)
  local hitchFlag = false
  local hitchFps = nil
  if hitchApply and snapA1.avg > 0 then
    hitchFps = hitchApply
    if ((snapA1.avg - hitchApply) / snapA1.avg) > 0.20 then
      hitchFlag = true
    end
  end
  -- per-pass record for Thorough aggregation
  j.results[pass] = {
    gain = gain,
    before = snapA1.avg,
    after = snapB.avg,
    noisy = noisyFlag,
    hitch = hitchFlag,
    hitchFps = hitchFps,
    p5Before = snapA1.p5,
    p5After = snapB.p5,
    longBefore = longTotal(snapA1),
    longAfter = longTotal(snapB),
  }
  Lab.progress.gain = gain
  Lab.progress.noisy = noisyFlag
  Lab.progress.hitch = hitchFlag
  pass = pass + 1
  if pass <= passes then
    startPass()
  else
    -- aggregate passes (median gain for Thorough)
    local results = j.results
    local gains = {}
    for i = 1, #results do
      gains[i] = results[i].gain
    end
    table.sort(gains)
    local medianGain = gains[math.floor((#gains + 1) / 2)]
    local anyNoisy, anyHitch, worstHitch = false, false, nil
    local before, after, p5b, p5a, lb, la = 0, 0, 0, 0, 0, 0
    for i = 1, #results do
      local r = results[i]
      if r.noisy then
        anyNoisy = true
      end
      if r.hitch then
        anyHitch = true
        if not worstHitch or (r.hitchFps and r.hitchFps < worstHitch) then
          worstHitch = r.hitchFps
        end
      end
      before = before + r.before
      after = after + r.after
      p5b = p5b + r.p5Before
      p5a = p5a + r.p5After
      lb = lb + r.longBefore
      la = la + r.longAfter
    end
    local n = #results
    local row = buildRow(j, before / n, after / n, medianGain, anyNoisy, anyHitch, worstHitch, false, nil)
    row.p5Before = p5b / n
    row.p5After = p5a / n
    row.longBefore = lb / n
    row.longAfter = la / n
    rows[#rows + 1] = row
    jobIndex = jobIndex + 1
    pass = 1
    if jobIndex > #jobs then
      ns.lab.FinishRun()
    else
      ns.lab.StartJob()
    end
  end
end

-- --------------------------------------------------------- job control ----

function ns.lab.StartJob()
  local j = currentJob()
  if not j then
    ns.lab.FinishRun()
    return
  end
  -- re-check the instance rule at every job boundary (review M13): zoning
  -- into a dungeon mid-run must abort like the combat rule does.
  local okInst, _, instType = pcall(GetInstanceInfo)
  if okInst and instType and instType ~= "none" then
    cancelTimer()
    ns.meter.Release()
    ns.cvarGuard.EndTest()
    Lab.state = "idle"
    Lab.progress.phase = ""
    Lab.lastError = { key = "instance", value = instType }
    rows = {}
    jobs = {}
    jobIndex = 1
    return
  end
  j.results = {}
  j.failReason = nil
  local baseValue = nil
  for i = 1, #j.keys do
    local v = ns.cvarGuard.Read(j.keys[i])
    local num = tonumber(v)
    if num == nil then
      rows[#rows + 1] = buildRow(j, nil, nil, nil, false, false, nil, true, "unreadable")
      jobIndex = jobIndex + 1
      pass = 1
      if jobIndex > #jobs then
        ns.lab.FinishRun()
      else
        ns.lab.StartJob()
      end
      return
    end
    if i == 1 then
      baseValue = num
    end
  end
  j.baseValue = baseValue
  local lowers = {}
  local fromValues = {}
  for i = 1, #j.keys do
    local cand = j.cands[i]
    local num = tonumber(ns.cvarGuard.Read(j.keys[i]))
    fromValues[i] = num
    local lower = computeLower(cand, num)
    if lower == nil then
      rows[#rows + 1] = buildRow(j, nil, nil, nil, false, false, nil, true, "already-lowest")
      jobIndex = jobIndex + 1
      pass = 1
      if jobIndex > #jobs then
        ns.lab.FinishRun()
      else
        ns.lab.StartJob()
      end
      return
    end
    lowers[i] = lower
  end
  j.fromValues = fromValues
  j.lowers = lowers
  j.lower = lowers[1] -- progress.stepTo (was never set before pre.3)
  startPass()
end

function ns.lab.FinishRun()
  cancelTimer()
  ns.context.Update(true)
  runSeq = runSeq + 1
  if ns.db then
    ns.db.lastRunId = runSeq
  end
  Lab.activeRunId = runSeq
  local snap = ns.context.Snapshot()
  local run = {
    id = runSeq,
    t = GetTime(),
    zone = snap.zone,
    subzone = snap.sub,
    crowd = ns.context.Label(),
    mode = mode,
    client = (ns.compat and ns.compat.chip) or "",
    rows = rows,
  }
  Lab.lastRun = run
  if ns.db then
    local results = ns.db.results
    results[#results + 1] = run
    while #results > 20 do
      table.remove(results, 1)
    end
  end
  Lab.state = "idle"
  Lab.progress.phase = ""
  ns.meter.Release()
  ns.cvarGuard.EndTest()
  Lab.completedAt = GetTime()
  rows = {}
  jobs = {}
  jobIndex = 1
end

-- ------------------------------------------------------------- public -----

function Lab.Run(runMode, selectedIds)
  if Lab.state == "running" then
    return false, "running"
  end
  if InCombatLockdown() then
    Lab.lastError = { key = "combat" }
    return false, "combat"
  end
  if not (ns.compat and ns.compat.features and ns.compat.features.cvar) then
    Lab.lastError = { key = "noapi" }
    return false, "noapi"
  end
  local okInst, _, instType = pcall(GetInstanceInfo)
  if okInst and instType and instType ~= "none" then
    Lab.lastError = { key = "instance", value = instType }
    return false, "instance"
  end
  mode = (runMode == "thorough") and "thorough" or "quick"
  passes = (mode == "thorough") and 3 or 1
  jobs = {}
  jobIndex = 1
  pass = 1
  rows = {}
  for _, cand in ipairs(ns.settings.testable()) do
    if cand.key and selectedIds[cand.id] then
      jobs[#jobs + 1] = {
        id = cand.id,
        key = cand.key,
        labelKey = cand.label,
        cands = { cand },
        keys = { cand.key },
      }
    end
  end
  -- optional final confirmation: combine the settings that gained the most
  if selectedIds["__combine__"] then
    local top = {}
    if Lab.lastRun then
      for _, row in ipairs(Lab.lastRun.rows) do
        if not row.notTestable and row.gain and row.gain > 1 then
          top[#top + 1] = row
        end
      end
      table.sort(top, function(a, b)
        return a.gain > b.gain
      end)
    end
    local combineCands = {}
    local combineKeys = {}
    for i = 1, math.min(3, #top) do
      local cand = ns.settings.byKey(top[i].key)
      if cand then
        combineCands[#combineCands + 1] = cand
        combineKeys[#combineKeys + 1] = cand.key
      end
    end
    if #combineCands > 0 then
      jobs[#jobs + 1] = {
        id = "__combine__",
        key = "combined",
        labelKey = nil,
        cands = combineCands,
        keys = combineKeys,
      }
    end
  end
  if #jobs == 0 then
    Lab.lastError = { key = "noselect" }
    return false, "noselect"
  end
  Lab.state = "running"
  Lab.lastError = nil
  Lab.activeRunId = runSeq + 1
  ns.meter.Acquire()
  ns.lab.StartJob()
  return true
end

function Lab.Cancel()
  if Lab.state ~= "running" then
    return
  end
  cancelTimer()
  ns.meter.Release()
  ns.cvarGuard.EndTest()
  Lab.state = "idle"
  Lab.progress.phase = ""
  Lab.lastError = { key = "cancelled" }
  rows = {}
  jobs = {}
  jobIndex = 1
end

function Lab.IsRunning()
  return Lab.state == "running"
end

-- estimated wall-clock seconds for the Run button
function Lab.EstimateSeconds(runMode, jobCount)
  local s = labSettings()
  local p = (runMode == "thorough") and 3 or 1
  return jobCount * p * ((s.sampleSeconds * 3) + (s.settleSeconds * 2) + 1)
end

function Lab.Progress()
  return Lab.progress
end

-- meter hook (no allocation: called 4 times per second while running)
function Lab.OnSample(fps)
  if hitchWindow > 0 then
    if not hitchWorst or fps < hitchWorst then
      hitchWorst = fps
    end
    hitchWindow = hitchWindow - 0.25
  end
end

ns.cvarGuard.onCombatAbort = function()
  if Lab.state == "running" then
    cancelTimer()
    ns.meter.Release()
    Lab.state = "idle"
    Lab.progress.phase = ""
    Lab.lastError = { key = "combat" }
    rows = {}
    jobs = {}
    jobIndex = 1
  end
end

ns.cvarGuard.onForeignChange = function(changedName)
  if Lab.state == "running" then
    cancelTimer()
    ns.meter.Release()
    ns.cvarGuard.EndTest()
    Lab.state = "idle"
    Lab.progress.phase = ""
    Lab.lastError = { key = "foreign", cvar = changedName }
    rows = {}
    jobs = {}
    jobIndex = 1
  end
end
