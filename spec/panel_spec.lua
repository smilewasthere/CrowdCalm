describe("Panel", function()
  local ns = stub.newNs()
  stub.loadAddon("Profiles.lua", ns)
  stub.loadAddon("Monitor.lua", ns)
  stub.loadAddon("Panel.lua", ns)

  local function fakeCore(settings)
    ns.Core = { sv = { settings = settings } }
  end

  local function printedContains(text)
    for _, line in ipairs(stub.state.printed) do
      if line:find(text, 1, true) then
        return true
      end
    end
    return false
  end

  it("creates the frame once and builds working controls", function()
    stub.reset()
    fakeCore({ enabled = false, categories = { particles = false } })
    local first = ns.Panel.Create()
    local second = ns.Panel.Create()
    expect(first):toBe(second)
    expect(stub.state.framesByName["CrowdCalmPanel"]):toBeTruthy()

    local enabled = stub.state.framesByName["CrowdCalmPanelEnabled"]
    enabled:Click()
    expect(ns.Core.sv.settings.enabled):toBe(true)

    local particles = stub.state.framesByName["CrowdCalmPanelCategoryparticles"]
    particles:Click()
    expect(ns.Core.sv.settings.categories.particles):toBe(true)
  end)

  it("clamps values edited through sliders and reports the correction", function()
    fakeCore({ high = 15, low = 10, enterDelay = 3, exitDelay = 5, framecapValue = 60 })
    ns.Panel.Create()
    local highSlider = stub.state.framesByName["CrowdCalmPanelHigh"]
    highSlider:SetValue(9)
    expect(ns.Core.sv.settings.high):toBe(9)
    expect(ns.Core.sv.settings.low):toBe(8)
    expect(printedContains("low")):toBe(true)
  end)

  it("clamps inconsistent thresholds and reports the correction", function()
    local sanitized, issues = ns.Panel.ValidateSettings({ high = 5, low = 9 })
    expect(sanitized.low < sanitized.high):toBe(true)
    expect(sanitized.low):toBe(4)
    expect(#issues >= 1):toBe(true)
    local mentionsLow = false
    for _, issue in ipairs(issues) do
      if issue:find("low", 1, true) then
        mentionsLow = true
      end
    end
    expect(mentionsLow):toBe(true)
  end)

  it("clamps delays and frame cap into range", function()
    local sanitized, issues = ns.Panel.ValidateSettings({ enterDelay = 61, exitDelay = -3, framecapValue = -10 })
    expect(sanitized.enterDelay):toBe(60)
    expect(sanitized.exitDelay):toBe(0)
    expect(sanitized.framecapValue):toBe(0)
    expect(#issues >= 3):toBe(true)
  end)

  it("clamps stutter settings", function()
    local sanitized, issues = ns.Panel.ValidateSettings({ stutter = { thresholdMs = 5, maxEntries = 0 } })
    expect(sanitized.stutter.thresholdMs):toBe(10)
    expect(sanitized.stutter.maxEntries):toBe(1)
    expect(#issues >= 2):toBe(true)
  end)

  it("leaves a valid settings table untouched", function()
    local input = {
      high = 15, low = 10, enterDelay = 3, exitDelay = 5, framecapValue = 60,
      stutter = { thresholdMs = 50, maxEntries = 100 },
    }
    local sanitized, issues = ns.Panel.ValidateSettings(input)
    expect(#issues):toBe(0)
    expect(sanitized.high):toBe(15)
    expect(sanitized.low):toBe(10)
    expect(sanitized.enterDelay):toBe(3)
    expect(sanitized.exitDelay):toBe(5)
    expect(sanitized.framecapValue):toBe(60)
    expect(sanitized.stutter.thresholdMs):toBe(50)
    expect(sanitized.stutter.maxEntries):toBe(100)
  end)

  it("prints a status line and warns about unknown commands", function()
    fakeCore({ enabled = true })
    ns.Panel.RunCommand("status")
    expect(printedContains("CrowdCalm")):toBe(true)
    local before = #stub.state.printed
    ns.Panel.RunCommand("bogus")
    expect(#stub.state.printed):toBe(before + 1)
    expect(stub.state.printed[#stub.state.printed]:find("unknown", 1, true) ~= nil):toBe(true)
  end)

  it("flips settings.enabled through on/off and the registered slash command", function()
    fakeCore({ enabled = false })
    ns.Panel.RunCommand("on")
    expect(ns.Core.sv.settings.enabled):toBe(true)
    ns.Panel.RunCommand("off")
    expect(ns.Core.sv.settings.enabled):toBe(false)
    expect(_G.SlashCmdList.CROWDCALM):toBeTruthy()
    _G.SlashCmdList.CROWDCALM("on")
    expect(ns.Core.sv.settings.enabled):toBe(true)
  end)

  it("toggles the stutter log from the panel and the slash command", function()
    fakeCore({ enabled = true, stutter = { enabled = false } })
    local synced = 0
    ns.Core._syncStutterHook = function()
      synced = synced + 1
    end
    ns.Panel.Create()
    local stutter = stub.state.framesByName["CrowdCalmPanelStutter"]
    expect(stutter):toBeTruthy()
    stutter:Click()
    expect(ns.Core.sv.settings.stutter.enabled):toBe(true)
    expect(synced):toBe(1)
    ns.Panel.RunCommand("stutter off")
    expect(ns.Core.sv.settings.stutter.enabled):toBe(false)
    expect(synced):toBe(2)
    local before = #stub.state.printed
    ns.Panel.RunCommand("stutter")
    expect(#stub.state.printed):toBe(before + 1)
  end)

  it("toggles the panel visibility on a bare command", function()
    fakeCore({ enabled = true })
    local frame = ns.Panel.Create()
    ns.Panel.RunCommand("")
    expect(frame:IsShown()):toBe(true)
    ns.Panel.RunCommand("")
    expect(frame:IsShown()):toBe(false)
  end)
end)
