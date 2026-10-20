-- Engine/LabRunner.lua — the A-B-A heart of the lab (brief section 5.3,
-- reworked in pre.5 for measurement stability, pre.7 for the engine update).
-- Every phase is the same shape: [apply or restore action] -> settle (6 s)
-- -> warm-up (4 s, ignored by Stats) -> measured sample (sampleSeconds, the
-- slider value). Quick plans A-B-A (3 phases); Thorough plans A-B-A-B-A-B-A
-- (7 phases): 4 shared baselines and 3 tests, each test compared against the
-- average of its two neighbouring baselines, reported as the median gain plus
-- the min-max spread. Baselines diverging more than Stats.UNRELIABLE_PCT
-- percent mark the row "Not reliable" with the actual difference for the
-- card. Pre.7: a 15 s warm-up runs before the first baseline, the job order
-- is shuffled (combine last), Big step mode steps each setting to its lowest
-- value (Body Quota at half), every final restore is verified by read-back
-- (mismatch -> Not testable + Restore warning), and the Max FPS cap warning
-- is decided after the run — measured FPS within 10% of the cap. A movement
-- watchdog (GetUnitSpeed/GetPlayerFacing, probed once) warns when the
-- player moves or turns during a run; a read-only caps preflight reads
-- Max FPS/VSync before the run and never writes them. Records the
-- apply-moment hitch (worst sample within 1 s after each set). Cancel,
-- combat, foreign CVar changes and read-back mismatches all restore through
-- CVarGuard.
local ADDON_NAME, ns = ...

local Lab = {}
ns.lab = Lab

Lab.state = "idle" -- "idle" | "running"
Lab.activeRunId = 0
Lab.lastError = nil -- { key = "combat"|"instance"|"noselect"|"cancelled"|"foreign"|"noapi", ... }
Lab.lastRun = nil
Lab.completedAt = nil
Lab.caps = nil -- read-only Max FPS/VSync preflight of the last run (pre.5)
Lab.moved = false -- movement watchdog fired during the last run (pre.5)
local mode = "quick"

Lab.progress = {
  phase = "", -- "prewarm" | "sample" | "settle" | "warmup" | "applying" | "restoring" | ""
  cand = nil,
  labelKey = nil,
  pass = 1, -- current phase within the plan (pre.5); 0 = pre-roll (pre.7)
  passes = 1, -- phase count: Quick 3, Thorough 7 (pre.5)
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
local plan = {} -- phase plan for the current mode (see buildPlan)
local snaps = {} -- ordered per-phase snapshots for the current job
local phaseIdx = 1
local rows = {}
local runSeq = 0
local hitchWorst = nil
local hitchWindow = 0

local hitchApply = nil -- worst FPS in the 1 s window after the apply (review I4)
local anyHitch = false
local worstHitchFps = nil

local bigStep = false -- pre.7: Big step mode for the current run (db toggle)
local runOrder = {} -- pre.7: shuffled job ids for the report ("run.order")

-- pre.5: movement watchdog state (ticked from Lab.OnSample, 4 Hz)
local moveAccum = 0 -- seconds of real movement (0.25 per moving sample)
local turnAccum = 0 -- radians of camera yaw change
local lastFacing = nil
local jobMoved = false -- player moved/turned during the current job
local runMoved = false -- any movement during this run (banner + run record)
local speedFn = nil
local facingFn = (type(GetPlayerFacing) == "function") and GetPlayerFacing or nil

-- probe once at load: the watchdog degrades to FPS-only when the client
-- lacks GetUnitSpeed (never errors, never blocks a run)
if type(GetUnitSpeed) == "function" then
  local ok = pcall(GetUnitSpeed, "player")
  if ok then
    speedFn = GetUnitSpeed
  end
end

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
  return { sampleSeconds = 8, settleSeconds = 6, ignoreSeconds = 4, defaultMode = "quick" }
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

-- step down by exactly one; unknown ranges stay within [0, current].
-- Pre.7 Big step: the lowest value per setting (Body Quota at half, since
-- "lowest" for an experimental count means fewer bodies, not necessarily 0).
local function computeLower(cand, num, big)
  if type(num) ~= "number" then
    return nil
  end
  local lower
  if big then
    if cand.key == "bodyQuota" then
      lower = math.floor(num / 2)
      if cand.min ~= nil and lower < cand.min then
        lower = cand.min
      end
    elseif cand.min ~= nil then
      lower = cand.min
    else
      lower = 0
    end
    if lower >= num then
      return nil -- already at (or below) the big-step target
    end
    return lower
  end
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
    -- p5/long fills come from the aggregate path; not-testable rows keep 0
    p5Before = 0,
    p5After = 0,
    longBefore = 0,
    longAfter = 0,
    noisy = noisyFlag, -- pre.5: "Not reliable" (baselines over the limit)
    confidence = ns.stats.confidence(mode, noisyFlag),
    hitch = hitchFlag,
    hitchFps = hitchFps,
    notTestable = notTestable,
    reason = reason,
    cost = cost,
    valueFrom = j.baseValue,
    valueTo = j.lowers and j.lowers[1] or nil,
    bigStep = bigStep, -- pre.7: Results shows "Big step: A -> B -> A" per card
    changed = jobMoved, -- pre.5: movement watchdog flag for this job
    changes = changes,
  }
end

-- ------------------------------------------------------------ phases ------
-- pre.5: one shared pipeline for both modes (see the header comment). The
-- plan decides how many phases a job runs; everything after it is identical
-- for Quick and Thorough.

local runPhase, completeJob

local function buildPlan()
  if mode == "thorough" then
    return {
      { kind = "A", action = "none" },
      { kind = "B", action = "apply" },
      { kind = "A", action = "restore" },
      { kind = "B", action = "apply" },
      { kind = "A", action = "restore" },
      { kind = "B", action = "apply" },
      { kind = "A", action = "restore" },
    }
  end
  return {
    { kind = "A", action = "none" },
    { kind = "B", action = "apply" },
    { kind = "A", action = "restore" },
  }
end

local function advanceJob()
  jobIndex = jobIndex + 1
  phaseIdx = 1
  snaps = {}
  if jobIndex > #jobs then
    ns.lab.FinishRun()
  else
    ns.lab.StartJob()
  end
end

local beginWarmup, beginSample, phaseDone

beginSample = function()
  Lab.progress.phase = "sample"
  setPhase(labSettings().sampleSeconds, phaseDone)
end

beginWarmup = function()
  local ph = plan[phaseIdx]
  if ph and ph.action == "apply" then
    hitchApply = hitchWorst -- keep the apply-moment hitch (review I4)
    local ref = snaps[1]
    if hitchApply and ref and ref.avg > 0 then
      if ((ref.avg - hitchApply) / ref.avg) > 0.20 then
        anyHitch = true
      end
      if not worstHitchFps or hitchApply < worstHitchFps then
        worstHitchFps = hitchApply
      end
    end
  end
  local s = labSettings()
  ns.stats.Begin(s.ignoreSeconds)
  Lab.progress.phase = "warmup"
  setPhase(math.max(1, tonumber(s.ignoreSeconds) or 4), beginSample)
end

phaseDone = function()
  snaps[phaseIdx] = snapshotCopy()
  phaseIdx = phaseIdx + 1
  if phaseIdx <= #plan then
    runPhase()
  else
    completeJob()
  end
end

completeJob = function()
  local j = currentJob()
  local aList, bList = {}, {}
  for i = 1, #plan do
    if plan[i].kind == "A" then
      aList[#aList + 1] = snaps[i]
    else
      bList[#bList + 1] = snaps[i]
    end
  end
  if #aList == 0 or #bList == 0 then
    -- defensive: a truncated plan must not produce a fabricated result
    rows[#rows + 1] = buildRow(j, nil, nil, nil, false, false, nil, true, "truncated")
    advanceJob()
    return
  end
  local baselines, tests = {}, {}
  local aSum, bSum, aP5, bP5, aLong, bLong = 0, 0, 0, 0, 0, 0
  for i, s in ipairs(aList) do
    baselines[i] = s.avg
    aSum = aSum + s.avg
    aP5 = aP5 + s.p5
    aLong = aLong + longTotal(s)
  end
  for i, s in ipairs(bList) do
    tests[i] = s.avg
    bSum = bSum + s.avg
    bP5 = bP5 + s.p5
    bLong = bLong + longTotal(s)
  end
  -- per-test gains against the average of the two neighbouring baselines
  local gains = {}
  for i = 1, #bList do
    gains[i] = tests[i] - ((baselines[i] + baselines[i + 1]) / 2)
  end
  local sorted = {}
  for i = 1, #gains do
    sorted[i] = gains[i]
  end
  table.sort(sorted)
  local gain = sorted[math.floor((#sorted + 1) / 2)]
  local baselinePct = ns.stats.baselineDivergence(baselines)
  local unreliable = baselinePct > ns.stats.UNRELIABLE_PCT

  local before = aSum / #aList
  local after = bSum / #bList
  local row = buildRow(j, before, after, gain, unreliable, anyHitch, worstHitchFps, false, nil)
  row.p5Before = aP5 / #aList
  row.p5After = bP5 / #bList
  row.longBefore = aLong / #aList
  row.longAfter = bLong / #bList
  -- pre.5 display triples: entry baseline, mean test, exit baseline, plus
  -- the per-test gains and their min..max spread for Thorough (the gain
  -- itself is the median — labeled as such in Results)
  row.fpsBefore = baselines[1]
  row.fpsTest = after
  row.fpsAfter = baselines[#baselines]
  row.baselines = baselines
  row.tests = tests
  row.gains = gains
  row.spreadMin = sorted[1]
  row.spreadMax = sorted[#sorted]
  row.baselinePct = baselinePct
  row.unreliable = unreliable
  -- pre.7: baseline stats the Results threshold uses (mean for the 5% bar,
  -- max-min gap for "bigger than the baselines wandered anyway")
  row.baselineMean = before
  local bMin, bMax = baselines[1], baselines[1]
  for i = 2, #baselines do
    if baselines[i] < bMin then
      bMin = baselines[i]
    end
    if baselines[i] > bMax then
      bMax = baselines[i]
    end
  end
  row.baselineSpread = bMax - bMin
  -- values triple: from -> to -> read back after the final restore
  row.valueAfter = tonumber(ns.cvarGuard.Read(j.keys[1]))
  if row.changes then
    for i = 1, #row.changes do
      local ch = row.changes[i]
      ch.after = tonumber(ns.cvarGuard.Read(ch.key))
    end
  end
  -- pre.7 A1: verify the final restore by reading back. A value that did not
  -- come back makes the row untrustworthy and the settings wrong: mark it
  -- Not testable so Results tells the owner to use Restore.
  local restoredOk = true
  local function stillHere(key, expect)
    local now = tonumber(ns.cvarGuard.Read(key))
    if expect == nil or now == nil then
      return true -- nothing to compare: keep the row (guard restore already warned)
    end
    return math.abs(now - expect) <= 0.0005
  end
  if not stillHere(j.keys[1], row.valueFrom) then
    restoredOk = false
  end
  if restoredOk and row.changes then
    for i = 1, #row.changes do
      local ch = row.changes[i]
      if not stillHere(ch.key, ch.from) then
        restoredOk = false
        break
      end
    end
  end
  if not restoredOk then
    row.notTestable = true
    row.reason = "restore-mismatch"
    row.restoreFailed = true
  end
  Lab.progress.gain = gain
  Lab.progress.noisy = unreliable
  Lab.progress.hitch = anyHitch
  rows[#rows + 1] = row
  advanceJob()
end

runPhase = function()
  local j = currentJob()
  local ph = plan[phaseIdx]
  if not j then
    ns.lab.FinishRun()
    return
  end
  if not ph then
    advanceJob()
    return
  end
  Lab.progress.cand = j.cands[1]
  Lab.progress.labelKey = j.labelKey
  Lab.progress.pass = phaseIdx
  Lab.progress.passes = #plan
  Lab.progress.jobIndex = jobIndex
  Lab.progress.jobCount = #jobs
  Lab.progress.stepFrom = j.baseValue
  Lab.progress.stepTo = j.lower
  Lab.progress.gain = nil
  Lab.progress.noisy = false
  Lab.progress.hitch = false

  if ph.action == "apply" then
    Lab.progress.phase = "applying"
    hitchWorst = nil
    hitchWindow = 1.0
    local failed = false
    for i = 1, #j.keys do
      local ok, err = ns.cvarGuard.Apply(j.keys[i], j.lowers[i])
      if not ok then
        failed = true
        j.failReason = tostring(err)
        break
      end
    end
    if failed then
      ns.cvarGuard.EndTest()
      rows[#rows + 1] = buildRow(j, nil, nil, nil, false, false, nil, true, j.failReason)
      advanceJob()
      return
    end
    ns.context.Update(true)
  elseif ph.action == "restore" then
    Lab.progress.phase = "restoring"
    hitchWorst = nil
    hitchWindow = 1.0
    for i = 1, #j.keys do
      ns.cvarGuard.Restore(j.keys[i])
    end
  end

  ns.stats.Reset()
  Lab.progress.phase = "settle"
  setPhase(labSettings().settleSeconds, beginWarmup)
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
  j.failReason = nil
  anyHitch, worstHitchFps = false, nil
  moveAccum, turnAccum, lastFacing = 0, 0, nil
  jobMoved = false
  local baseValue = nil
  for i = 1, #j.keys do
    local v = ns.cvarGuard.Read(j.keys[i])
    local num = tonumber(v)
    if num == nil then
      rows[#rows + 1] = buildRow(j, nil, nil, nil, false, false, nil, true, "unreadable")
      advanceJob()
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
    local lower = computeLower(cand, num, bigStep)
    if lower == nil then
      rows[#rows + 1] = buildRow(j, nil, nil, nil, false, false, nil, true, "already-lowest")
      advanceJob()
      return
    end
    lowers[i] = lower
  end
  j.fromValues = fromValues
  j.lowers = lowers
  j.lower = lowers[1] -- progress.stepTo (was never set before pre.3)
  snaps = {}
  phaseIdx = 1
  ns.stats.Reset()
  runPhase()
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
  -- pre.7: the cap warning only means something after measurement — flag it
  -- when the run's own FPS came within 10% of the Max FPS cap it read pre-run
  if type(Lab.caps) == "table" then
    local maxFps = 0
    for _, r in ipairs(rows) do
      if not r.notTestable then
        local vals = { r.fpsBefore, r.fpsTest, r.fpsAfter, r.before, r.after }
        for i = 1, 5 do
          local n = tonumber(vals[i])
          if n and n > maxFps then
            maxFps = n
          end
        end
      end
    end
    Lab.caps.measuredFps = maxFps
    Lab.caps.limited = (Lab.caps.maxfps and Lab.caps.maxfps > 0 and maxFps >= Lab.caps.maxfps * 0.9) or nil
  end
  local restoreFailed = false
  for _, r in ipairs(rows) do
    if r.restoreFailed then
      restoreFailed = true
      break
    end
  end
  local run = {
    id = runSeq,
    t = GetTime(),
    zone = snap.zone,
    subzone = snap.sub,
    crowd = ns.context.Label(),
    mode = mode,
    client = (ns.compat and ns.compat.chip) or "",
    moved = runMoved, -- pre.5: movement watchdog fired during this run
    caps = Lab.caps, -- pre.5/7: preflight + post-run "was it capped" for the report
    bigStep = bigStep, -- pre.7: Big step mode used for this run
    order = runOrder, -- pre.7: shuffled test order for the report
    restoreFailed = restoreFailed, -- pre.7 A1: a value did not read back after restore
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

-- pre.5/7: read-only caps preflight. A Max FPS cap or VSync can limit what a
-- run can measure, so the values are recorded up front for the report; the
-- actual "capped" warning is decided after the run against the measured FPS
-- (pre.7: only within 10% of the cap). Candidate names are probed, never
-- written — this file must not contain a single SetCVar for these keys
-- (owner: "check, never set").
local CAP_CANDIDATES = { "maxfps", "renderFrameRateCap" }

local function readCaps()
  local caps = { maxfps = nil, capName = nil, vsync = false, limited = nil, measuredFps = nil }
  if not (C_CVar and C_CVar.GetCVar) then
    return caps -- no CVar API at all: Lab.Run already gates on the cvar feature
  end
  for _, name in ipairs(CAP_CANDIDATES) do
    local ok, v = pcall(C_CVar.GetCVar, name)
    if ok and v ~= nil and v ~= "" then
      local num = tonumber(v)
      if num ~= nil then
        caps.maxfps = num
        caps.capName = name
        break
      end
    end
  end
  local okV, vs = pcall(C_CVar.GetCVar, "gxVSync")
  if okV and (vs == "1" or vs == 1 or vs == true) then
    caps.vsync = true
  end
  return caps
end

-- pre.7: Fisher-Yates shuffle of the test order so measurement drift (cold
-- cache, long-frame bursts) cannot systematically favour one setting. The
-- combine-confirmation job is appended after the shuffle so it always runs
-- last (it needs this run's results to be meaningful anyway).
local function shuffleJobs(list)
  -- WoW seeds math.random per session; no explicit seed needed here.
  for i = #list, 2, -1 do
    local j = math.random(i)
    list[i], list[j] = list[j], list[i]
  end
end

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
  bigStep = (ns.db and ns.db.settings and ns.db.settings.lab and ns.db.settings.lab.bigStep) and true or false
  plan = buildPlan()
  jobs = {}
  jobIndex = 1
  rows = {}
  snaps = {}
  phaseIdx = 1
  runOrder = {}
  anyHitch, worstHitchFps = false, nil
  moveAccum, turnAccum, lastFacing = 0, 0, nil
  jobMoved, runMoved = false, false
  Lab.moved = false
  Lab.caps = readCaps()
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
  shuffleJobs(jobs)
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
  for i = 1, #jobs do
    runOrder[i] = jobs[i].id
  end
  Lab.state = "running"
  Lab.lastError = nil
  Lab.activeRunId = runSeq + 1
  ns.meter.Acquire()
  -- pre.7: 15 s warm-up before the first baseline — the crowd needs to
  -- settle before anything is measured (owner item 4)
  Lab.progress.phase = "prewarm"
  Lab.progress.cand = nil
  Lab.progress.labelKey = nil
  Lab.progress.pass = 0
  Lab.progress.passes = 0
  Lab.progress.stepFrom = nil
  Lab.progress.stepTo = nil
  Lab.progress.gain = nil
  Lab.progress.noisy = false
  Lab.progress.hitch = false
  Lab.progress.jobIndex = 0
  Lab.progress.jobCount = #jobs
  setPhase(15, ns.lab.StartJob)
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
  snaps = {}
  phaseIdx = 1
end

function Lab.IsRunning()
  return Lab.state == "running"
end

-- estimated wall-clock seconds for the Run button (pre.5: every phase costs
-- settle + warm-up + measured sample + ~1 s of actions; pre.7 adds the 15 s
-- pre-roll before the first baseline)
function Lab.EstimateSeconds(runMode, jobCount)
  local s = labSettings()
  local phases = (runMode == "thorough") and 7 or 3
  local perPhase = (tonumber(s.settleSeconds) or 6)
    + (tonumber(s.ignoreSeconds) or 4)
    + (tonumber(s.sampleSeconds) or 8)
    + 1
  return 15 + (jobCount * phases * perPhase)
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
  if Lab.state ~= "running" then
    return
  end
  -- pre.5 movement watchdog: warn-only, never aborts the run. Movement is
  -- counted in the 0.25 s sample quanta; camera yaw accumulates wrapped
  -- absolute deltas. Crossing a limit flags the row and (once per run)
  -- shows a banner.
  if speedFn then
    local okSp, sp = pcall(speedFn, "player")
    if okSp and type(sp) == "number" and sp > 0.1 then
      moveAccum = moveAccum + 0.25
    end
  end
  if facingFn then
    local okF, f = pcall(facingFn)
    if okF and type(f) == "number" then
      if lastFacing then
        local d = math.abs(f - lastFacing)
        if d > math.pi then
          d = (2 * math.pi) - d
        end
        turnAccum = turnAccum + d
      end
      lastFacing = f
    end
  end
  if not jobMoved and (moveAccum > 2.5 or math.deg(turnAccum) > 120) then
    jobMoved = true
    runMoved = true
    if not Lab.moved then
      Lab.moved = true
      if ns.ui and ns.ui.ShowBanner and ns.L then
        pcall(ns.ui.ShowBanner, ns.L("moved_warn"), "danger", 6)
      end
    end
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
