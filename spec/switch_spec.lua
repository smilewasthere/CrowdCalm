describe("Switch", function()
  local ns = stub.newNs()
  stub.loadAddon("Switch.lua", ns)

  local function baseEntries()
    return {
      { cvar = "a", value = "1", category = "particles", secure = false },
      { cvar = "b", value = "2", category = "particles", secure = false },
    }
  end

  local function newSwitch()
    return ns.Switch.new(stub.deps(), baseEntries())
  end

  local function primeCvars()
    stub.state.cvars.a = "10"
    stub.state.cvars.b = "20"
  end

  it("applies crowd entries in order and captures baselines", function()
    stub.reset()
    primeCvars()
    local s = newSwitch()
    s:Request("crowd")
    s:TryApply()
    local state = s:GetState()
    expect(state.mode):toBe("crowd")
    expect(state.pendingReason):toBeNil()
    expect(state.applied.a):toBe("1")
    expect(state.applied.b):toBe("2")
    expect(state.baselines.a):toBe("10")
    expect(state.baselines.b):toBe("20")
    expect(#stub.state.callLog):toBe(2)
    expect(stub.state.callLog[1].name):toBe("a")
    expect(stub.state.callLog[1].value):toBe("1")
    expect(stub.state.callLog[2].name):toBe("b")
    expect(stub.state.callLog[2].value):toBe("2")
  end)

  it("restores baselines and clears applied", function()
    stub.reset()
    primeCvars()
    local s = newSwitch()
    s:Request("crowd")
    s:TryApply()
    s:Request("normal")
    s:TryApply()
    local state = s:GetState()
    expect(state.mode):toBe("normal")
    expect(state.applied.a):toBeNil()
    expect(state.applied.b):toBeNil()
    expect(state.baselines.a):toBeNil()
    expect(state.baselines.b):toBeNil()
    expect(#stub.state.callLog):toBe(4)
    local restored = {}
    for i = 3, 4 do
      restored[stub.state.callLog[i].name] = stub.state.callLog[i].value
    end
    expect(restored.a):toBe("10")
    expect(restored.b):toBe("20")
  end)

  it("defers while in combat and flushes on combat end", function()
    stub.reset()
    primeCvars()
    stub.state.inCombat = true
    local s = newSwitch()
    s:Request("crowd")
    s:TryApply()
    expect(#stub.state.callLog):toBe(0)
    expect(s:GetState().pendingReason):toBe("combat")
    expect(s:GetState().mode):toBe("normal")
    stub.state.inCombat = false
    s:OnCombatEnd()
    expect(s:GetState().mode):toBe("crowd")
    expect(#stub.state.callLog):toBe(2)
  end)

  it("defers during the post-loading debounce window", function()
    stub.reset()
    primeCvars()
    stub.state.time = 10
    local s = newSwitch()
    s:Request("crowd")
    s:OnEnteringWorld()
    stub.state.time = 11
    s:TryApply()
    expect(#stub.state.callLog):toBe(0)
    expect(s:GetState().pendingReason):toBe("loading")
    stub.state.time = 12.1
    s:TryApply()
    expect(#stub.state.callLog):toBe(2)
    expect(s:GetState().mode):toBe("crowd")
  end)

  it("retries failed entries without rewriting applied ones", function()
    stub.reset()
    primeCvars()
    stub.state.setCvarFail.b = true
    local s = newSwitch()
    s:Request("crowd")
    s:TryApply()
    local state = s:GetState()
    expect(state.applied.a):toBe("1")
    expect(state.applied.b):toBeNil()
    expect(state.pendingReason):toBe("failed")
    expect(state.mode):toBe("normal")
    expect(#stub.state.callLog):toBe(1)
    stub.state.setCvarFail.b = nil
    s:TryApply()
    state = s:GetState()
    expect(state.applied.b):toBe("2")
    expect(state.mode):toBe("crowd")
    expect(state.pendingReason):toBeNil()
    expect(#stub.state.callLog):toBe(2)
    expect(stub.state.callLog[2].name):toBe("b")
  end)

  it("ignores echoes and adopts user changes", function()
    stub.reset()
    primeCvars()
    local s = newSwitch()
    s:Request("crowd")
    s:TryApply()
    s:OnCvarChange("a", "1")
    expect(s:GetState().baselines.a):toBe("10")
    s:OnCvarChange("b", "9")
    expect(s:GetState().baselines.b):toBe("9")
    s:Request("normal")
    s:TryApply()
    local restored = {}
    for _, entry in ipairs(stub.state.callLog) do
      restored[entry.name] = entry.value
    end
    expect(restored.a):toBe("10")
    expect(restored.b):toBe("9")
  end)

  it("force-restores on logout even inside the loading window", function()
    stub.reset()
    primeCvars()
    stub.state.time = 10
    local s = newSwitch()
    s:Request("crowd")
    s:TryApply()
    s:OnEnteringWorld()
    stub.state.time = 10.5
    s:OnLogout()
    local state = s:GetState()
    expect(state.mode):toBe("normal")
    expect(state.applied.a):toBeNil()
    expect(state.baselines.a):toBeNil()
    expect(#stub.state.callLog):toBe(4)
  end)

  it("does not rewrite when already in the desired state", function()
    stub.reset()
    primeCvars()
    local s = newSwitch()
    s:Request("crowd")
    s:TryApply()
    s:TryApply()
    expect(#stub.state.callLog):toBe(2)
    s:Request("normal")
    s:TryApply()
    s:TryApply()
    expect(#stub.state.callLog):toBe(4)
  end)

  it("applies a persisted restore plan", function()
    stub.reset()
    stub.state.cvars.a = "1"
    local s = newSwitch()
    s:GetState().baselines.c = "77"
    s:RestorePersisted({ restore = { a = "10" }, adopt = { b = "50" }, clear = { c = true } })
    expect(stub.state.callLog[1].name):toBe("a")
    expect(stub.state.callLog[1].value):toBe("10")
    local state = s:GetState()
    expect(state.mode):toBe("normal")
    expect(state.baselines.b):toBe("50")
    expect(state.baselines.c):toBeNil()
  end)
end)
