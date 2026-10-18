describe("Monitor", function()
  local ns = stub.newNs()
  stub.loadAddon("Monitor.lua", ns)

  it("reports own memory in MB from collectgarbage", function()
    stub.reset()
    stub.state.gcKB = 2048
    expect(ns.Monitor.GetOwnMB()):toBe(2)
    stub.state.gcKB = 1536
    expect(ns.Monitor.GetOwnMB()):toBe(1.5)
  end)

  it("keeps only the last 12 samples", function()
    stub.reset()
    expect(ns.Monitor.GetLast()):toBeNil()
    for i = 1, 13 do
      ns.Monitor.Push(i, i)
    end
    local samples = ns.Monitor.GetSamples()
    expect(#samples):toBe(12)
    expect(samples[1].t):toBe(2)
    expect(samples[1].mb):toBe(2)
    expect(samples[#samples].t):toBe(13)
    expect(ns.Monitor.GetLast()):toBe(13)
  end)
end)
