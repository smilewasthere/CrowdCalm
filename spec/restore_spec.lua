describe("Restore", function()
  local ns = stub.newNs()
  stub.loadAddon("Restore.lua", ns)

  local function persisted(overrides)
    local data = { sessionActive = true, baselines = { a = "10" }, applied = { a = "1" } }
    for key, value in pairs(overrides or {}) do
      data[key] = value
    end
    return data
  end

  it("restores the baseline when the cvar still holds our applied value", function()
    local plan = ns.Restore.Plan(persisted(), { a = "1" })
    expect(plan.restore.a):toBe("10")
    expect(plan.restoreAny):toBe(true)
  end)

  it("clears when the cvar already holds the baseline", function()
    local plan = ns.Restore.Plan(persisted(), { a = "10" })
    expect(plan.restore.a):toBeNil()
    expect(plan.clear.a):toBe(true)
    expect(plan.restoreAny):toBe(false)
  end)

  it("adopts user changes as the new baseline", function()
    local plan = ns.Restore.Plan(persisted(), { a = "50" })
    expect(plan.adopt.a):toBe("50")
    expect(plan.restore.a):toBeNil()
    expect(plan.clear.a):toBeNil()
    expect(plan.restoreAny):toBe(false)
  end)

  it("clears cvars that no longer exist", function()
    local plan = ns.Restore.Plan(persisted(), {})
    expect(plan.clear.a):toBe(true)
    expect(plan.restore.a):toBeNil()
    expect(plan.restoreAny):toBe(false)
  end)

  it("does nothing when no session was active", function()
    local inactive = ns.Restore.Plan(persisted({ sessionActive = false }), { a = "1" })
    expect(inactive.restoreAny):toBe(false)
    expect(inactive.restore.a):toBeNil()
    expect(inactive.adopt.a):toBeNil()
    expect(inactive.clear.a):toBeNil()

    local noData = ns.Restore.Plan(nil, { a = "1" })
    expect(noData.restoreAny):toBe(false)
    expect(noData.restore.a):toBeNil()
  end)

  it("clears when the applied value has no recorded baseline", function()
    local plan = ns.Restore.Plan(persisted({ baselines = {} }), { a = "1" })
    expect(plan.restore.a):toBeNil()
    expect(plan.clear.a):toBe(true)
    expect(plan.restoreAny):toBe(false)
  end)
end)
