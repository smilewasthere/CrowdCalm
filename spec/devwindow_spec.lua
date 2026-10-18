describe("DevWindow", function()
  local ns = stub.newNs()
  stub.loadAddon("Profiles.lua", ns)
  stub.loadAddon("Dev.lua", ns)
  stub.loadAddon("DevWindow.lua", ns)

  local function fakeCore(settings, devOverrides)
    local calls = { rebuild = 0, syncStutter = 0 }
    local dev = {
      enabled = false,
      forceCrowd = false,
      startCalls = {},
      stopCalls = {},
      result = nil,
      report = "REPORT BODY",
      SetForceCrowd = function(self, on)
        self.forceCrowd = on
      end,
      StartTest = function(self, mode, opts)
        self.startCalls[#self.startCalls + 1] = { mode = mode, opts = opts }
      end,
      StopTest = function(self, reason)
        self.stopCalls[#self.stopCalls + 1] = reason
      end,
      NextPhase = function(self)
        self.nextCalls = (self.nextCalls or 0) + 1
      end,
      GetStatus = function(self)
        return {
          mode = self.testMode or "idle",
          phase = self.phase,
          phaseEndsAt = self.phaseEndsAt,
          recording = self.recording == true,
          forceCrowd = self.forceCrowd,
          result = self.result,
        }
      end,
      GetLastResult = function(self)
        return self.result
      end,
      GetReport = function(self)
        return self.report
      end,
    }
    for key, value in pairs(devOverrides or {}) do
      dev[key] = value
    end
    ns.Core = {
      sv = { settings = settings },
      dev = dev,
      RebuildSwitch = function()
        calls.rebuild = calls.rebuild + 1
      end,
      _syncStutterHook = function()
        calls.syncStutter = calls.syncStutter + 1
      end,
    }
    return calls
  end

  local function widget(name)
    return stub.state.framesByName[name]
  end

  local function printedSince(mark, text)
    for i = mark + 1, #stub.state.printed do
      if stub.state.printed[i]:find(text, 1, true) then
        return true
      end
    end
    return false
  end

  it("Toggle refuses while dev mode is off or Core missing", function()
    stub.reset()
    ns.Core = nil
    ns.DevWindow.Toggle()
    expect(printedSince(0, "/ccdev on")):toBe(true)
    fakeCore({ enabled = true })
    ns.DevWindow.Toggle()
    expect(printedSince(1, "/ccdev on")):toBe(true)
    expect(widget("CrowdCalmDevPanel")):toBeNil()
    ns.Core.dev.enabled = true
    ns.DevWindow.Toggle()
    local panel = widget("CrowdCalmDevPanel")
    expect(panel):toBeTruthy()
    expect(panel:IsShown()):toBe(true)
    ns.DevWindow.Toggle()
    expect(panel:IsShown()):toBe(false)
  end)

  it("master and category checkboxes write settings", function()
    local settings = { enabled = true, categories = { particles = true }, stutter = { enabled = false } }
    local calls = fakeCore(settings)
    ns.Core.dev.enabled = true
    ns.DevWindow.Create()

    widget("CrowdCalmDevMaster"):Click()
    expect(settings.enabled):toBe(false)
    expect(calls.rebuild):toBe(0)

    widget("CrowdCalmDevCategoryparticles"):Click()
    expect(settings.categories.particles):toBe(false)
    expect(calls.rebuild):toBe(1)

    widget("CrowdCalmDevStutter"):Click()
    expect(settings.stutter.enabled):toBe(true)
    expect(calls.syncStutter):toBe(1)
  end)

  it("All OFF and All ON buttons", function()
    local settings = { enabled = true, categories = { particles = true, framecap = false } }
    local calls = fakeCore(settings)
    ns.Core.dev.enabled = true
    ns.DevWindow.Create()

    widget("CrowdCalmDevAllOff"):Click()
    expect(settings.enabled):toBe(false)

    widget("CrowdCalmDevAllOn"):Click()
    expect(settings.enabled):toBe(true)
    expect(settings.categories.particles):toBe(true)
    expect(settings.categories.framecap):toBe(true)
    expect(calls.rebuild >= 1):toBe(true)
  end)

  it("force crowd checkbox drives the dev engine", function()
    fakeCore({ enabled = true, categories = {} })
    ns.Core.dev.enabled = true
    ns.DevWindow.Create()

    widget("CrowdCalmDevForceCrowd"):Click()
    expect(ns.Core.dev.forceCrowd):toBe(true)

    ns.Core.dev.forceCrowd = false
    ns.DevWindow.Refresh()
    expect(widget("CrowdCalmDevForceCrowd"):GetChecked()):toBe(false)

    ns.Core.dev.forceCrowd = true
    ns.DevWindow.Refresh()
    expect(widget("CrowdCalmDevForceCrowd"):GetChecked()):toBe(true)
  end)

  it("mode radios are exclusive and defaults are sane", function()
    fakeCore({ enabled = true, categories = {} })
    ns.Core.dev.enabled = true
    ns.DevWindow.Create()

    expect(widget("CrowdCalmDevModeAuto"):GetChecked()):toBe(true)
    widget("CrowdCalmDevModeGuided"):Click()
    expect(widget("CrowdCalmDevModeGuided"):GetChecked()):toBe(true)
    expect(widget("CrowdCalmDevModeAuto"):GetChecked()):toBe(false)
    expect(widget("CrowdCalmDevLen60"):GetText():find("60", 1, true) ~= nil):toBe(true)
  end)

  it("START and STOP drive the engine with chosen options", function()
    fakeCore({ enabled = true, categories = {} })
    ns.Core.dev.enabled = true
    ns.DevWindow.Create()

    widget("CrowdCalmDevModeAuto"):Click()
    widget("CrowdCalmDevLen30"):Click()
    widget("CrowdCalmDevRounds"):Click()
    widget("CrowdCalmDevStart"):Click()
    local first = ns.Core.dev.startCalls[1]
    expect(first.mode):toBe("auto")
    expect(first.opts.phaseSeconds):toBe(30)
    expect(first.opts.rounds):toBe("ABAB")

    widget("CrowdCalmDevModePassive"):Click()
    widget("CrowdCalmDevStart"):Click()
    expect(ns.Core.dev.startCalls[2].mode):toBe("passive")

    widget("CrowdCalmDevStop"):Click()
    expect(ns.Core.dev.stopCalls[1]):toBe("manual")
  end)

  it("Next phase drives the guided engine", function()
    fakeCore({ enabled = true, categories = {} })
    ns.Core.dev.enabled = true
    ns.DevWindow.Create()
    widget("CrowdCalmDevNextPhase"):Click()
    expect(ns.Core.dev.nextCalls):toBe(1)
  end)

  it("Copy report fills the edit box and highlights it", function()
    local mark = #stub.state.printed
    widget("CrowdCalmDevCopyReport"):Click()
    expect(widget("CrowdCalmDevReport"):GetText()):toBe("REPORT BODY")
    expect(widget("CrowdCalmDevReport").__highlighted):toBe(true)
    expect(printedSince(mark, "copied")):toBe(true)
  end)

  it("Copy last test without a result prints a hint", function()
    ns.Core.dev.result = nil
    local mark = #stub.state.printed
    widget("CrowdCalmDevCopyTest"):Click()
    expect(printedSince(mark, "no test")):toBe(true)

    ns.Core.dev.result = "A 10 frames 100.0 avg / B 10 frames 50.0 avg"
    widget("CrowdCalmDevCopyTest"):Click()
    expect(widget("CrowdCalmDevReport"):GetText():find("A ", 1, true) ~= nil):toBe(true)
  end)

  it("Refresh renders live status", function()
    fakeCore({ enabled = true, categories = {} })
    ns.Core.dev.enabled = true
    ns.Core.dev.recording = true
    ns.Core.dev.phase = "A"
    ns.Core.dev.testMode = "auto"
    ns.DevWindow.Create()

    stub.state.fps = 77
    ns.DevWindow.Refresh()
    expect(widget("CrowdCalmDevStatus"):GetText():find("77", 1, true) ~= nil):toBe(true)
    expect(widget("CrowdCalmDevPhase"):GetText():find("A", 1, true) ~= nil):toBe(true)
  end)
end)
