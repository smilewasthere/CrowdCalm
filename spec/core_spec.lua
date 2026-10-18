describe("Core", function()
  local ns = stub.newNs()
  stub.loadAddon("Crowd.lua", ns)
  stub.loadAddon("Profiles.lua", ns)
  stub.loadAddon("Restore.lua", ns)
  stub.loadAddon("Switch.lua", ns)
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

  local function login(except)
    stub.reset()
    _G.CrowdCalmDB = nil
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
    stub.reset()
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
    stub.reset()
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

  it("re-applies spell density after entering world while crowd persists", function()
    stub.reset()
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
    stub.reset()
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
end)
