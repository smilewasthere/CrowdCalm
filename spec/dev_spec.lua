describe("Dev", function()
  local ns = stub.newNs()
  stub.loadAddon("Dev.lua", ns)

  local SNAP = { mode = "normal", plates = 0, applied = {}, baselines = {}, pendingReason = nil }

  local function fakeDeps(overrides)
    local deps = {}
    deps.snapshot = SNAP
    deps.getTime = function()
      return stub.state.time
    end
    deps.setFrameHook = function(fn)
      deps.hook = fn
    end
    deps.log = function(msg)
      stub.state.logged[#stub.state.logged + 1] = tostring(msg)
    end
    deps.getSnapshot = function()
      return deps.snapshot or SNAP
    end
    for key, value in pairs(overrides or {}) do
      deps[key] = value
    end
    return deps
  end

  local function newDev(settings, overrides)
    local deps = fakeDeps(overrides)
    local dev = ns.Dev.new(settings or {}, deps)
    return dev, deps
  end

  local function contains(list, needle)
    for _, item in ipairs(list) do
      if tostring(item):find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  local function countKind(entries, kind, field, value)
    local n = 0
    for _, entry in ipairs(entries) do
      if entry.kind == kind and (field == nil or entry[field] == value) then
        n = n + 1
      end
    end
    return n
  end

  it("FrameStats computes avg, min, 1% low and worst", function()
    local deltas = {}
    for i = 1, 80 do
      deltas[i] = 12.5
    end
    local stats = ns.Dev.FrameStats(deltas)
    expect(stats.frames):toBe(80)
    expect(stats.seconds):toBe(1)
    expect(stats.avgFps):toBe(80)
    expect(stats.avgMs):toBe(12.5)
    expect(stats.maxMs):toBe(12.5)
    expect(stats.minFps):toBe(80)
    expect(stats.p1LowFps):toBe(80)
    expect(stats.capped):toBe(false)

    stats = ns.Dev.FrameStats({ 100, 12.5, 12.5, 12.5, 12.5 })
    expect(stats.frames):toBe(5)
    expect(stats.avgMs):toBe(30)
    expect(stats.maxMs):toBe(100)
    expect(stats.minFps):toBe(10)
    expect(stats.p1LowFps):toBe(10)
  end)

  it("FrameStats handles empty and capped input", function()
    local stats = ns.Dev.FrameStats({})
    expect(stats.frames):toBe(0)
    expect(stats.seconds):toBe(0)
    expect(stats.avgFps):toBe(0)
    expect(stats.avgMs):toBe(0)
    expect(stats.maxMs):toBe(0)
    expect(stats.minFps):toBe(0)
    expect(stats.p1LowFps):toBe(0)
    expect(stats.capped):toBe(false)
    expect(ns.Dev.FrameStats({}, true).capped):toBe(true)

    stub.reset()
    local dev = newDev()
    dev:SetEnabled(true)
    dev:StartTest("passive")
    for i = 1, 30005 do
      dev:OnFrame(i * 0.001, 1.0)
    end
    dev:StopTest("manual")
    local report = dev:GetReport()
    expect(report:find("30000 frames", 1, true) ~= nil):toBe(true)
    expect(report:find("(capped)", 1, true) ~= nil):toBe(true)
  end)

  it("CompareFrameStats verdicts", function()
    local cmp = ns.Dev.CompareFrameStats(
      { avgFps = 120, p1LowFps = 100 },
      { avgFps = 100, p1LowFps = 90 }
    )
    expect(cmp.avgDelta):toBe(20)
    expect(cmp.avgPercent):toBe(20)
    expect(cmp.lowDelta):toBe(10)
    expect(cmp.verdict):toBe("clear")

    cmp = ns.Dev.CompareFrameStats({ avgFps = 101 }, { avgFps = 100 })
    expect(cmp.verdict):toBe("none")

    cmp = ns.Dev.CompareFrameStats({ avgFps = 103 }, { avgFps = 100 })
    expect(cmp.verdict):toBe("slight")

    cmp = ns.Dev.CompareFrameStats({ avgFps = 96 }, { avgFps = 100 })
    expect(cmp.avgDelta):toBe(-4)
    expect(cmp.verdict):toBe("slight")

    cmp = ns.Dev.CompareFrameStats({ avgFps = 50 }, { avgFps = 0 })
    expect(cmp.avgPercent):toBe(0)
    expect(cmp.verdict):toBe("none")
  end)

  it("normalizes corrupt dev settings in place", function()
    local settings = { enabled = "yes", lastReport = 5, tests = "x" }
    local dev = newDev(settings)
    expect(settings.enabled):toBe(false)
    expect(settings.lastReport):toBe("")
    expect(type(settings.tests)):toBe("table")
    expect(dev.forceCrowd):toBe(false)
    expect(dev.enabled):toBe(false)

    local over = { enabled = true, lastReport = "old", tests = {} }
    for i = 1, 9 do
      over.tests[i] = { when = "t" .. i, summary = "s" .. i }
    end
    newDev(over)
    expect(#over.tests):toBe(5)
    expect(over.tests[1].summary):toBe("s1")
  end)

  it("journals mode, apply and restore diffs", function()
    stub.reset()
    local dev, deps = newDev()
    dev:SetEnabled(true)

    deps.snapshot = { mode = "normal", plates = 0, applied = {}, baselines = {} }
    dev:OnTick(1)

    deps.snapshot = { mode = "crowd", plates = 16, applied = { particleDensity = "25" }, baselines = { particleDensity = "100" } }
    dev:OnTick(2)

    deps.snapshot = { mode = "normal", plates = 0, applied = {}, baselines = {} }
    dev:OnTick(3)

    local journal = dev:GetJournal()
    expect(#journal):toBe(4)
    expect(journal[1].kind):toBe("mode")
    expect(journal[1].from):toBe("normal")
    expect(journal[1].to):toBe("crowd")
    expect(journal[1].plates):toBe(16)
    expect(journal[2].kind):toBe("apply")
    expect(journal[2].cvar):toBe("particleDensity")
    expect(journal[2].value):toBe("25")
    expect(journal[2].baseline):toBe("100")
    expect(journal[3].kind):toBe("mode")
    expect(journal[3].to):toBe("normal")
    expect(journal[4].kind):toBe("restore")
    expect(journal[4].cvar):toBe("particleDensity")
    expect(journal[4].value):toBe("100")
  end)

  it("caps the journal at 2000 entries and counts drops", function()
    stub.reset()
    local dev, deps = newDev()
    dev:SetEnabled(true)
    for i = 1, 2101 do
      deps.snapshot = { mode = (i % 2 == 0) and "crowd" or "normal", plates = 0, applied = {}, baselines = {} }
      dev:OnTick(i)
    end
    expect(#dev:GetJournal()):toBe(2000)
    expect(dev:GetStatus().dropped):toBe(100)
  end)

  it("OnCvar tags managed writes as echo and real edits as user", function()
    stub.reset()
    local dev, deps = newDev()
    dev:SetEnabled(true)

    dev:OnTick(1)
    deps.snapshot = { mode = "normal", plates = 0, applied = { a = "1" }, baselines = { a = "10" } }
    dev:OnTick(2)

    dev:OnCvar("a", "1")
    dev:OnTick(3)

    dev:OnCvar("a", "2")
    dev:OnTick(4)

    local journal = dev:GetJournal()
    expect(#journal):toBe(3)
    expect(journal[1].kind):toBe("apply")
    expect(journal[2].kind):toBe("cvar")
    expect(journal[2].cvar):toBe("a")
    expect(journal[2].value):toBe("1")
    expect(journal[2].tag):toBe("echo")
    expect(journal[3].kind):toBe("cvar")
    expect(journal[3].value):toBe("2")
    expect(journal[3].tag):toBe("user")

    dev:OnCvar("neverManaged", "5")
    dev:OnTick(5)
    expect(#dev:GetJournal()):toBe(3)
  end)

  it("passive recording captures frames and stops cleanly", function()
    stub.reset()
    local settings = {}
    local dev, deps = newDev(settings)
    dev:SetEnabled(true)
    dev:StartTest("passive")
    expect(deps.hook ~= nil):toBe(true)
    for i = 1, 10 do
      dev:OnFrame(2 + i * 0.01, 10)
    end
    dev:StopTest("manual")
    expect(deps.hook):toBe(nil)
    expect(dev:GetStatus().mode):toBe("idle")
    expect(settings.lastReport:find("CrowdCalm Dev Report", 1, true) ~= nil):toBe(true)
    expect(settings.lastReport:find("comparison unavailable", 1, true) ~= nil):toBe(true)
  end)

  it("auto AB test flips force crowd and produces a comparison", function()
    stub.reset()
    local settings = {}
    local dev, deps = newDev(settings)
    dev:SetEnabled(true)
    stub.state.time = 100
    dev:StartTest("auto", { phaseSeconds = 30, rounds = "AB" })
    expect(dev.forceCrowd):toBe(true)

    deps.snapshot = { mode = "crowd", plates = 16, applied = { a = "1" }, baselines = { a = "10" } }
    for i = 1, 10 do
      dev:OnFrame(100 + i * 0.01, 10)
    end
    dev:OnTick(110)

    stub.state.time = 131
    deps.snapshot = { mode = "normal", plates = 0, applied = {}, baselines = {} }
    dev:OnTick(131)
    expect(dev.forceCrowd):toBe(false)

    for i = 1, 10 do
      dev:OnFrame(131 + i * 0.02, 20)
    end
    stub.state.time = 162
    dev:OnTick(162)

    expect(dev:GetStatus().mode):toBe("idle")
    expect(dev.forceCrowd):toBe(false)
    expect(deps.hook):toBe(nil)
    local result = dev:GetLastResult()
    expect(result:find("A", 1, true) ~= nil):toBe(true)
    expect(result:find("faster", 1, true) ~= nil):toBe(true)
    expect(settings.lastReport:find("PHASE COMPARISON", 1, true) ~= nil):toBe(true)
    expect(settings.lastReport:find("verdict:", 1, true) ~= nil):toBe(true)
    expect(#settings.tests):toBe(1)
  end)

  it("ABAB merges both rounds per group", function()
    stub.reset()
    local dev, deps = newDev()
    dev:SetEnabled(true)
    stub.state.time = 100
    dev:StartTest("auto", { phaseSeconds = 30, rounds = "ABAB" })

    deps.snapshot = { mode = "crowd", plates = 16, applied = { a = "1" }, baselines = { a = "10" } }
    for i = 1, 5 do
      dev:OnFrame(100 + i * 0.01, 10)
    end
    stub.state.time = 131
    dev:OnTick(131)
    expect(dev.forceCrowd):toBe(false)

    deps.snapshot = { mode = "normal", plates = 0, applied = {}, baselines = {} }
    for i = 1, 5 do
      dev:OnFrame(131 + i * 0.02, 20)
    end
    stub.state.time = 162
    dev:OnTick(162)
    expect(dev.forceCrowd):toBe(true)

    deps.snapshot = { mode = "crowd", plates = 16, applied = { a = "1" }, baselines = { a = "10" } }
    for i = 1, 5 do
      dev:OnFrame(162 + i * 0.01, 10)
    end
    stub.state.time = 193
    dev:OnTick(193)
    expect(dev.forceCrowd):toBe(false)

    deps.snapshot = { mode = "normal", plates = 0, applied = {}, baselines = {} }
    for i = 1, 5 do
      dev:OnFrame(193 + i * 0.02, 20)
    end
    stub.state.time = 224
    dev:OnTick(224)

    expect(dev:GetStatus().mode):toBe("idle")
    expect(countKind(dev:GetJournal(), "phase", "event", "flip")):toBe(3)
    local result = dev:GetLastResult()
    expect(result:find("A 10 frames", 1, true) ~= nil):toBe(true)
    expect(result:find("B 10 frames", 1, true) ~= nil):toBe(true)
    expect(result:find("faster", 1, true) ~= nil):toBe(true)
  end)

  it("auto aborts when combat blocks the flip", function()
    stub.reset()
    local settings = {}
    local dev, deps = newDev(settings)
    dev:SetEnabled(true)
    stub.state.time = 100
    dev:StartTest("auto", { phaseSeconds = 30, rounds = "AB" })

    deps.snapshot = { mode = "crowd", plates = 16, applied = { a = "1" }, baselines = { a = "10" } }
    stub.state.time = 131
    dev:OnTick(131)
    expect(dev.forceCrowd):toBe(false)

    deps.snapshot = { mode = "normal", plates = 0, applied = {}, baselines = {}, pendingReason = "combat" }
    stub.state.time = 133.5
    dev:OnTick(133.5)

    local status = dev:GetStatus()
    expect(status.mode):toBe("idle")
    expect(status.recording):toBe(false)
    expect(dev.forceCrowd):toBe(false)
    expect(deps.hook):toBe(nil)
    expect(settings.lastReport:find("aborted", 1, true) ~= nil):toBe(true)
    expect(settings.lastReport:find("combat", 1, true) ~= nil):toBe(true)
    expect(countKind(dev:GetJournal(), "test", "state", "aborted")):toBe(1)
  end)

  it("auto aborts when the apply never takes effect", function()
    stub.reset()
    local settings = {}
    local dev, deps = newDev(settings)
    dev:SetEnabled(true)
    stub.state.time = 100
    dev:StartTest("auto", { phaseSeconds = 30, rounds = "AB" })

    stub.state.time = 102.5
    dev:OnTick(102.5)

    expect(dev:GetStatus().mode):toBe("idle")
    expect(dev.forceCrowd):toBe(false)
    expect(deps.hook):toBe(nil)
    expect(settings.lastReport:find("apply did not take effect", 1, true) ~= nil):toBe(true)
    expect(countKind(dev:GetJournal(), "test", "state", "aborted")):toBe(1)
  end)

  it("guided recording alternates phases on demand", function()
    stub.reset()
    local dev, deps = newDev()
    dev:SetEnabled(true)
    dev:StartTest("guided")
    expect(dev.forceCrowd):toBe(true)
    expect(deps.hook ~= nil):toBe(true)

    dev:NextPhase()
    expect(dev.forceCrowd):toBe(false)
    expect(dev:GetStatus().phase):toBe("B")

    dev:NextPhase()
    expect(dev.forceCrowd):toBe(true)
    expect(dev:GetStatus().phase):toBe("A")

    local stopsBefore = countKind(dev:GetJournal(), "phase", "event", "stop")
    dev:StopTest("manual")
    expect(dev:GetStatus().mode):toBe("idle")
    expect(deps.hook):toBe(nil)
    expect(countKind(dev:GetJournal(), "phase", "event", "stop")):toBe(stopsBefore + 1)

    dev:NextPhase()
    expect(dev:GetStatus().mode):toBe("idle")
  end)

  it("disabling dev mid-test aborts and persists", function()
    stub.reset()
    local settings = {}
    local dev, deps = newDev(settings)
    dev:SetEnabled(true)
    dev:StartTest("passive")

    dev:SetEnabled(false)
    expect(dev:GetStatus().mode):toBe("off")
    expect(dev:GetStatus().recording):toBe(false)
    expect(settings.enabled):toBe(false)
    expect(settings.lastReport ~= ""):toBe(true)
    expect(deps.hook):toBe(nil)
    expect(countKind(dev:GetJournal(), "test", "state", "aborted")):toBe(1)
  end)

  it("OnLogout mid-test aborts with a logout reason", function()
    stub.reset()
    local settings = {}
    local dev = newDev(settings)
    dev:SetEnabled(true)
    dev:StartTest("passive")

    dev:OnLogout(5)
    expect(dev:GetStatus().recording):toBe(false)
    expect(settings.lastReport ~= ""):toBe(true)
    local journal = dev:GetJournal()
    local found = false
    for _, entry in ipairs(journal) do
      if entry.kind == "test" and entry.state == "aborted" and tostring(entry.reason):find("logout", 1, true) then
        found = true
      end
    end
    expect(found):toBe(true)

    dev:OnLogout(6)
    expect(dev:GetStatus().recording):toBe(false)
  end)

  it("memory is sampled every 5s while recording only", function()
    stub.reset()
    stub.state.gcKB = 2048
    local dev = newDev()
    dev:SetEnabled(true)
    dev:StartTest("passive")

    dev:OnTick(10)
    dev:OnTick(12)
    dev:OnTick(15)
    dev:OnTick(20)
    local journal = dev:GetJournal()
    expect(countKind(journal, "mem")):toBe(3)
    for _, entry in ipairs(journal) do
      if entry.kind == "mem" then
        expect(entry.mb):toBe(2)
      end
    end

    dev:StopTest("manual")
    dev:OnTick(30)
    expect(countKind(dev:GetJournal(), "mem")):toBe(3)
  end)

  it("report renders all sections", function()
    stub.reset()
    stub.state.gcKB = 3072
    local dev, deps = newDev()
    dev:SetEnabled(true)
    stub.state.time = 100
    dev:StartTest("auto", { phaseSeconds = 30, rounds = "AB" })

    deps.snapshot = { mode = "crowd", plates = 16, applied = { a = "1" }, baselines = { a = "10" } }
    for i = 1, 10 do
      dev:OnFrame(100 + i * 0.01, 10)
    end
    dev:OnTick(110)
    stub.state.time = 131
    deps.snapshot = { mode = "normal", plates = 0, applied = {}, baselines = {} }
    dev:OnTick(131)
    for i = 1, 10 do
      dev:OnFrame(131 + i * 0.02, 20)
    end
    stub.state.time = 162
    dev:OnTick(162)
    dev:OnTick(165)

    local report = dev:GetReport()
    expect(report:find("== CrowdCalm Dev Report ==", 1, true) ~= nil):toBe(true)
    expect(report:find("generated:", 1, true) ~= nil):toBe(true)
    expect(report:find("features:", 1, true) ~= nil):toBe(true)
    expect(report:find("-- PHASE COMPARISON --", 1, true) ~= nil):toBe(true)
    expect(report:find("-- MEMORY --", 1, true) ~= nil):toBe(true)
    expect(report:find("-- SWITCH TIMELINE --", 1, true) ~= nil):toBe(true)
    expect(report:find("-- USER CVAR CHANGES --", 1, true) ~= nil):toBe(true)
    expect(report:find("-- FAILURES & NOTES --", 1, true) ~= nil):toBe(true)
    expect(report:find("-- SLOW FRAMES --", 1, true) ~= nil):toBe(true)
    expect(report:find("verdict:", 1, true) ~= nil):toBe(true)
  end)

  it("PersistReport caps the report and the tests list", function()
    stub.reset()
    local settings = {}
    local dev = newDev(settings)
    for i = 1, 7 do
      dev.lastResult = "summary " .. i
      dev:PersistReport("report " .. i)
    end
    expect(#settings.tests):toBe(5)
    expect(settings.tests[1].summary):toBe("summary 7")
    expect(settings.tests[5].summary):toBe("summary 3")

    dev:PersistReport(string.rep("x", 69999) .. "END")
    expect(#settings.lastReport):toBe(60000)
    expect(settings.lastReport:sub(-3)):toBe("END")
  end)

  it("RunCommand handles on/off/status/window/usage", function()
    stub.reset()
    local dev = newDev()
    local toggled = 0
    ns.Core = { dev = dev }
    ns.DevWindow = {
      Toggle = function()
        toggled = toggled + 1
      end,
    }

    ns.Dev.RunCommand("on")
    expect(dev.enabled):toBe(true)
    expect(contains(stub.state.logged, "dev mode on")):toBe(true)

    ns.Dev.RunCommand("status")
    ns.Dev.RunCommand("report")
    ns.Dev.RunCommand("")
    expect(toggled):toBe(1)
    ns.Dev.RunCommand("window")
    expect(toggled):toBe(2)

    ns.Dev.RunCommand("off")
    expect(dev.enabled):toBe(false)
    expect(contains(stub.state.logged, "dev mode off")):toBe(true)

    ns.Dev.RunCommand("")
    expect(toggled):toBe(2)
    expect(contains(stub.state.printed, "/ccdev on")):toBe(true)

    ns.Dev.RunCommand("bogus")
    expect(contains(stub.state.printed, "usage")):toBe(true)

    expect(type(_G.SlashCmdList.CROWDCALMDEV)):toBe("function")
  end)
end)
