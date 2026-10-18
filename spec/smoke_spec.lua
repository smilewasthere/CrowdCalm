describe("harness", function()
  it("stub GetCVar returns configured value", function()
    stub.reset()
    stub.state.cvars.maxFPS = "60"
    expect(GetCVar("maxFPS")):toBe("60")
  end)

  it("stub SetCVar records successful writes in callLog", function()
    stub.reset()
    expect(SetCVar("particleDensity", "25")):toBeTruthy()
    expect(#stub.state.callLog):toBe(1)
    expect(stub.state.callLog[1].name):toBe("particleDensity")
    expect(stub.state.callLog[1].value):toBe("25")
  end)

  it("stub SetCVar returns nil for failing cvars without recording", function()
    stub.reset()
    stub.state.setCvarFail.particleDensity = true
    expect(SetCVar("particleDensity", "25")):toBeFalsy()
    expect(#stub.state.callLog):toBe(0)
  end)
end)
