describe("Core", function()
  local ns = stub.newNs()
  stub.loadAddon("Crowd.lua", ns)
  stub.loadAddon("Profiles.lua", ns)
  stub.loadAddon("Restore.lua", ns)
  stub.loadAddon("Switch.lua", ns)
  stub.loadAddon("Stutter.lua", ns)
  stub.loadAddon("Monitor.lua", ns)
  stub.loadAddon("Panel.lua", ns)
  stub.loadAddon("Dev.lua", ns)
  stub.loadAddon("Core.lua", ns)

  local BASELINES = {
    particleDensity = "100",
    particleMTDensity = "100",
    groundEffectDensity = "100",
    groundEffectDist = "100",
    graphicsShadowQuality = "3",
    spellVisualDensityFilterSetting = "4",
  }

  local function primeKnown(except)
    for name, value in pairs(BASELINES) do
      if name ~= except then
        stub.known(name, value)
      end
    end
  end

  local function resetSession()
    stub.reset()
    _G.CrowdCalmDB = nil
    ns.Core.frame = nil
  end

  local function login(except)
    resetSession()
    primeKnown(except)
    ns.Core._handleEvent("ADDON_LOADED", "CrowdCalm")
  end

  local function plates(count)
    stub.state.nameplates = {}
    stub.state.playerUnits = {}
    for i = 1, count do
      local token = "nameplate" .. i
      stub.state.nameplates[#stub.state.nameplates + 1] = token
      stub.state.playerUnits[token] = true
    end
  end

  local function printedContains(text)
    for _, line in ipairs(stub.state.printed) do
      if line:find(text, 1, true) then
        return true
      end
    end
    return false
  end

  local function journalHas(dev, kind, fields)
    for _, entry in ipairs(dev:GetJournal()) do
      if entry.kind == kind then
        local match = true
        for key, value in pairs(fields) do
          if entry[key] ~= value then
            match = false
            break
          end
        end
        if match then
          return true
        end
      end
    end
    return false
  end

  it("initializes SavedVariables with defaults on first login", function()
    login()
    expect(_G.CrowdCalmDB.schemaVersion):toBe(1)
    expect(_G.CrowdCalmDB.settings.enabled):toBe(true)
    expect(_G.CrowdCalmDB.settings.high):toBe(15)
    expect(_G.CrowdCalmDB.settings.low):toBe(10)
    expect(_G.CrowdCalmDB.settings.enterDelay):toBe(3)
    expect(_G.CrowdCalmDB.settings.exitDelay):toBe(5)
    expect(_G.CrowdCalmDB.settings.categories.particles):toBe(true)
    expect(_G.CrowdCalmDB.settings.categories.spelldensity):toBe(false)
    expect(_G.CrowdCalmDB.settings.stutter.thresholdMs):toBe(50)
    expect(_G.CrowdCalmDB.restore.sessionActive):toBe(false)
    expect(#stub.state.callLog):toBe(0)
  end)

  it("applies the crowd profile, then restores when the crowd clears", function()
    login()
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#stub.state.callLog):toBe(5)
    expect(_G.CrowdCalmDB.restore.sessionActive):toBe(true)
    expect(C_CVar.GetCVar("particleDensity")):toBe("25")
    plates(0)
    ns.Core._tick(20)
    expect(_G.CrowdCalmDB.restore.sessionActive):toBe(true)
    ns.Core._tick(25.1)
    expect(#stub.state.callLog):toBe(10)
    expect(_G.CrowdCalmDB.restore.sessionActive):toBe(false)
    expect(C_CVar.GetCVar("particleDensity")):toBe("100")
    expect(C_CVar.GetCVar("graphicsShadowQuality")):toBe("3")
  end)

  it("defers applies during combat until PLAYER_REGEN_ENABLED", function()
    login()
    stub.state.inCombat = true
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#stub.state.callLog):toBe(0)
    stub.state.inCombat = false
    ns.Core._handleEvent("PLAYER_REGEN_ENABLED")
    expect(#stub.state.callLog):toBe(5)
    expect(_G.CrowdCalmDB.restore.sessionActive):toBe(true)
  end)

  it("restores everything on logout mid-crowd", function()
    login()
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#stub.state.callLog):toBe(5)
    ns.Core._handleEvent("PLAYER_LOGOUT")
    expect(#stub.state.callLog):toBe(10)
    expect(C_CVar.GetCVar("particleDensity")):toBe("100")
    expect(_G.CrowdCalmDB.restore.sessionActive):toBe(false)
  end)

  it("restores persisted applied values at the next login after a crash", function()
    resetSession()
    primeKnown()
    stub.state.cvars.particleDensity = "25"
    _G.CrowdCalmDB = {
      schemaVersion = 1,
      restore = {
        sessionActive = true,
        baselines = { particleDensity = "100" },
        applied = { particleDensity = "25" },
      },
    }
    ns.Core._handleEvent("ADDON_LOADED", "CrowdCalm")
    expect(#stub.state.callLog):toBe(1)
    expect(stub.state.callLog[1].name):toBe("particleDensity")
    expect(stub.state.callLog[1].value):toBe("100")
    expect(C_CVar.GetCVar("particleDensity")):toBe("100")
    expect(_G.CrowdCalmDB.restore.sessionActive):toBe(false)
  end)

  it("adopts hand-edited values at the next login instead of overwriting", function()
    resetSession()
    primeKnown()
    stub.state.cvars.particleDensity = "50"
    _G.CrowdCalmDB = {
      schemaVersion = 1,
      restore = {
        sessionActive = true,
        baselines = { particleDensity = "100" },
        applied = { particleDensity = "25" },
      },
    }
    ns.Core._handleEvent("ADDON_LOADED", "CrowdCalm")
    expect(#stub.state.callLog):toBe(0)
    expect(C_CVar.GetCVar("particleDensity")):toBe("50")
    expect(_G.CrowdCalmDB.restore.sessionActive):toBe(false)
  end)

  it("skips cvars the client does not know and logs them", function()
    login("particleDensity")
    expect(printedContains("particleDensity")):toBe(true)
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#stub.state.callLog):toBe(4)
    for _, entry in ipairs(stub.state.callLog) do
      expect(entry.name == "particleDensity"):toBe(false)
    end
  end)

  it("skips cvars the client reports as nil, not just ones that error", function()
    resetSession()
    stub.state.getInfoNilMode = true
    primeKnown("particleDensity")
    ns.Core._handleEvent("ADDON_LOADED", "CrowdCalm")
    expect(printedContains("particleDensity")):toBe(true)
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#stub.state.callLog):toBe(4)
  end)

  it("re-applies spell density after entering world while crowd persists", function()
    resetSession()
    primeKnown()
    _G.CrowdCalmDB = {
      schemaVersion = 1,
      settings = { categories = { spelldensity = true } },
    }
    ns.Core._handleEvent("ADDON_LOADED", "CrowdCalm")
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    local before = #stub.state.callLog
    expect(before):toBe(6)
    stub.state.time = 13.1
    ns.Core._handleEvent("PLAYER_ENTERING_WORLD")
    stub.state.time = 15.2
    stub.runTimers()
    expect(#stub.state.callLog):toBe(7)
    local last = stub.state.callLog[#stub.state.callLog]
    expect(last.name):toBe("spellVisualDensityFilterSetting")
    expect(last.value):toBe("1")
  end)

  it("does not re-apply spell density when no crowd is engaged", function()
    resetSession()
    primeKnown()
    _G.CrowdCalmDB = {
      schemaVersion = 1,
      settings = { categories = { spelldensity = true } },
    }
    ns.Core._handleEvent("ADDON_LOADED", "CrowdCalm")
    ns.Core._tick(0)
    stub.state.time = 1
    ns.Core._handleEvent("PLAYER_ENTERING_WORLD")
    stub.state.time = 3.2
    stub.runTimers()
    expect(#stub.state.callLog):toBe(0)
  end)

  it("does not re-apply spell density while in combat", function()
    resetSession()
    primeKnown()
    _G.CrowdCalmDB = {
      schemaVersion = 1,
      settings = { categories = { spelldensity = true } },
    }
    ns.Core._handleEvent("ADDON_LOADED", "CrowdCalm")
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#stub.state.callLog):toBe(6)
    stub.state.time = 13.1
    ns.Core._handleEvent("PLAYER_ENTERING_WORLD")
    stub.state.inCombat = true
    stub.state.time = 15.2
    stub.runTimers()
    expect(#stub.state.callLog):toBe(6)
  end)

  it("fires the friendly-nameplates hint once after 30s resting with no plates", function()
    login()
    expect(ns.Core._checkHint(0, 0, false)):toBe(false)
    expect(ns.Core._checkHint(1, 3, true)):toBe(false)
    expect(ns.Core._checkHint(2, 0, true)):toBe(false)
    expect(ns.Core._checkHint(10, 0, true)):toBe(false)
    expect(ns.Core._checkHint(32.1, 0, true)):toBe(true)
    expect(ns.Core._checkHint(60, 0, true)):toBe(false)
    expect(_G.CrowdCalmDB.settings.hintShown):toBe(true)
    expect(printedContains("friendly nameplates")):toBe(true)
  end)

  it("preserves crowd state across a switch rebuild", function()
    login()
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#stub.state.callLog):toBe(5)
    ns.Core.RebuildSwitch()
    ns.Core._tick(13.5)
    expect(#stub.state.callLog):toBe(5)
    expect(_G.CrowdCalmDB.restore.sessionActive):toBe(true)
    plates(0)
    ns.Core._tick(20)
    ns.Core._tick(25.1)
    expect(#stub.state.callLog):toBe(10)
    expect(C_CVar.GetCVar("particleDensity")):toBe("100")
  end)

  it("keeps a partially applied switch recoverable across rebuilds", function()
    login()
    stub.state.setCvarFail.graphicsShadowQuality = true
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#stub.state.callLog):toBe(4)
    expect(_G.CrowdCalmDB.restore.sessionActive):toBe(true)
    ns.Core.RebuildSwitch()
    ns.Core._tick(13.5)
    expect(#stub.state.callLog):toBe(4)
    plates(0)
    ns.Core._tick(20)
    ns.Core._tick(25.1)
    expect(#stub.state.callLog):toBe(8)
    expect(C_CVar.GetCVar("particleDensity")):toBe("100")
    expect(C_CVar.GetCVar("groundEffectDist")):toBe("100")
  end)

  it("tops up newly enabled categories while a crowd stays active", function()
    login()
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#stub.state.callLog):toBe(5)
    _G.CrowdCalmDB.settings.categories.spelldensity = true
    ns.Core.RebuildSwitch()
    ns.Core._tick(13.5)
    expect(#stub.state.callLog):toBe(6)
    local last = stub.state.callLog[#stub.state.callLog]
    expect(last.name):toBe("spellVisualDensityFilterSetting")
  end)

  it("sanitizes corrupt saved settings before using them", function()
    resetSession()
    primeKnown()
    _G.CrowdCalmDB = {
      schemaVersion = 1,
      settings = { high = "15", low = "banana", stutter = { thresholdMs = "x" } },
    }
    ns.Core._handleEvent("ADDON_LOADED", "CrowdCalm")
    expect(_G.CrowdCalmDB.settings.high):toBe(15)
    expect(_G.CrowdCalmDB.settings.low):toBe(10)
    expect(_G.CrowdCalmDB.settings.stutter.thresholdMs):toBe(50)
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#stub.state.callLog):toBe(5)
  end)

  it("attaches a stutter OnUpdate hook when enabled and logs slow frames", function()
    resetSession()
    primeKnown()
    _G.CrowdCalmDB = { schemaVersion = 1, settings = { stutter = { enabled = true } } }
    ns.Core._handleEvent("ADDON_LOADED", "CrowdCalm")
    local frame = stub.state.framesByName["CrowdCalmFrame"]
    expect(frame):toBeTruthy()
    local onUpdate = frame:GetScript("OnUpdate")
    expect(onUpdate):toBeTruthy()
    stub.state.time = 10
    onUpdate(frame, 0.016)
    stub.state.time = 10.08
    onUpdate(frame, 0.08)
    stub.state.time = 10.2
    onUpdate(frame, 0.12)
    local entries = ns.Core.stutter:GetEntries()
    expect(#entries):toBe(1)
    expect(entries[1].deltaMs > 50):toBe(true)
    expect(entries[1].context.zone):toBe("Test Zone")
    expect(entries[1].context.mode):toBe("normal")
  end)

  it("leaves the frame without an OnUpdate hook when stutter logging is disabled", function()
    login()
    local frame = stub.state.framesByName["CrowdCalmFrame"]
    expect(frame):toBeTruthy()
    expect(frame:GetScript("OnUpdate")):toBeNil()
  end)

  it("force crowd applies and restores the profile without any plates", function()
    login()
    plates(0)
    ns.Core.dev:SetEnabled(true)
    ns.Core.dev:SetForceCrowd(true)
    ns.Core._tick(10)
    expect(#stub.state.callLog):toBe(5)
    expect(C_CVar.GetCVar("particleDensity")):toBe("25")
    ns.Core.dev:SetForceCrowd(false)
    ns.Core._tick(11)
    expect(#stub.state.callLog):toBe(10)
    expect(C_CVar.GetCVar("particleDensity")):toBe("100")
    ns.Core._tick(12)
    expect(#stub.state.callLog):toBe(10)
  end)

  it("slash command registers and persists dev mode", function()
    login()
    _G.SlashCmdList.CROWDCALMDEV("on")
    expect(_G.CrowdCalmDB.settings.dev.enabled):toBe(true)
    _G.SlashCmdList.CROWDCALMDEV("off")
    expect(_G.CrowdCalmDB.settings.dev.enabled):toBe(false)
    _G.SlashCmdList.CROWDCALMDEV("bogus")
    expect(printedContains("usage")):toBe(true)
  end)

  it("normalizes corrupt dev settings at init", function()
    resetSession()
    primeKnown()
    _G.CrowdCalmDB = {
      schemaVersion = 1,
      settings = { dev = { enabled = "yes", lastReport = 5, tests = "x" } },
    }
    ns.Core._handleEvent("ADDON_LOADED", "CrowdCalm")
    expect(_G.CrowdCalmDB.settings.dev.enabled):toBe(false)
    expect(_G.CrowdCalmDB.settings.dev.lastReport):toBe("")
    expect(type(_G.CrowdCalmDB.settings.dev.tests)):toBe("table")
  end)

  it("player path stays silent while dev mode is off", function()
    login()
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(#ns.Core.dev:GetJournal()):toBe(0)
    local frame = stub.state.framesByName["CrowdCalmDevFrame"]
    expect(frame):toBeTruthy()
    expect(frame:GetScript("OnUpdate")):toBeNil()
  end)

  it("dev enabled journals crowd transitions and applies", function()
    login()
    ns.Core.dev:SetEnabled(true)
    plates(16)
    ns.Core._tick(10)
    ns.Core._tick(13.1)
    expect(journalHas(ns.Core.dev, "mode", { to = "crowd" })):toBe(true)
    expect(journalHas(ns.Core.dev, "apply", { cvar = "particleDensity", value = "25", baseline = "100" })):toBe(true)
    plates(0)
    ns.Core._tick(20)
    ns.Core._tick(25.1)
    expect(journalHas(ns.Core.dev, "restore", { cvar = "particleDensity", value = "100" })):toBe(true)
  end)

  it("full auto AB test drives the real switch", function()
    login()
    ns.Core.dev:SetEnabled(true)
    stub.state.time = 10
    ns.Core.dev:StartTest("auto", { phaseSeconds = 30, rounds = "AB" })
    local frame = stub.state.framesByName["CrowdCalmDevFrame"]
    local hook = frame:GetScript("OnUpdate")
    expect(hook):toBeTruthy()
    for i = 1, 20 do
      stub.state.time = 10 + i * 0.025
      hook(frame)
    end
    ns.Core._tick(11)
    stub.state.time = 41
    ns.Core._tick(41)
    expect(ns.Core.dev.forceCrowd):toBe(false)
    for i = 1, 10 do
      stub.state.time = 41 + i * 0.025
      hook(frame)
    end
    stub.state.time = 71.5
    ns.Core._tick(71.5)

    expect(#stub.state.callLog):toBe(10)
    local applied, restored = {}, {}
    for i = 1, 5 do
      applied[stub.state.callLog[i].name] = stub.state.callLog[i].value
    end
    for i = 6, 10 do
      restored[stub.state.callLog[i].name] = stub.state.callLog[i].value
    end
    expect(applied.particleDensity):toBe("25")
    expect(restored.particleDensity):toBe("100")
    expect(restored.graphicsShadowQuality):toBe("3")
    expect(ns.Core.dev.forceCrowd):toBe(false)
    expect(ns.Core.dev:GetStatus().mode):toBe("idle")
    expect(_G.CrowdCalmDB.settings.dev.lastReport:find("PHASE COMPARISON", 1, true) ~= nil):toBe(true)
    expect(_G.CrowdCalmDB.settings.dev.lastReport:find("frames /", 1, true) ~= nil):toBe(true)
    expect(#_G.CrowdCalmDB.settings.dev.tests):toBe(1)
  end)

  it("logout mid-test aborts and persists a partial report", function()
    login()
    ns.Core.dev:SetEnabled(true)
    ns.Core.dev:StartTest("passive")
    ns.Core._handleEvent("PLAYER_LOGOUT")
    expect(ns.Core.dev:GetStatus().recording):toBe(false)
    expect(_G.CrowdCalmDB.settings.dev.lastReport ~= ""):toBe(true)
  end)

  it("installs the DEV frame hook only while recording", function()
    login()
    local frame = stub.state.framesByName["CrowdCalmDevFrame"]
    expect(frame):toBeTruthy()
    expect(frame:GetScript("OnUpdate")):toBeNil()
    ns.Core.dev:SetEnabled(true)
    expect(frame:GetScript("OnUpdate")):toBeNil()
    ns.Core.dev:StartTest("passive")
    expect(frame:GetScript("OnUpdate")):toBeTruthy()
    ns.Core.dev:StopTest("manual")
    expect(frame:GetScript("OnUpdate")):toBeNil()
  end)
end)
