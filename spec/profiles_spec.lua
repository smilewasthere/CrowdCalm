describe("Profiles", function()
  local ns = stub.newNs()
  stub.loadAddon("Profiles.lua", ns)

  local function fullEnv(overrides)
    local env = {
      isKnown = function()
        return true
      end,
      isSecure = function()
        return false
      end,
      isReadOnly = function()
        return false
      end,
      findCvar = function()
        return nil
      end,
    }
    for key, value in pairs(overrides or {}) do
      env[key] = value
    end
    return env
  end

  local function map(entries)
    local out = {}
    for _, entry in ipairs(entries) do
      out[entry.cvar] = entry
    end
    return out
  end

  local function valueOf(byName, cvar)
    return byName[cvar] and byName[cvar].value
  end

  it("selects only default-enabled categories by default", function()
    local entries = ns.Profiles.Select({}, fullEnv())
    local byName = map(entries)
    expect(valueOf(byName, "particleDensity")):toBe("25")
    expect(valueOf(byName, "particleMTDensity")):toBe("30")
    expect(valueOf(byName, "groundEffectDensity")):toBe("16")
    expect(valueOf(byName, "groundEffectDist")):toBe("70")
    expect(valueOf(byName, "graphicsShadowQuality")):toBe("1")
    expect(byName.graphicsViewDistance):toBeNil()
    expect(byName.maxFPS):toBeNil()
    expect(byName.maxFPSBk):toBeNil()
    expect(byName.spellVisualDensityFilterSetting):toBeNil()
  end)

  it("adds framecap cvars when the category is enabled", function()
    local entries = ns.Profiles.Select({ categories = { framecap = true } }, fullEnv())
    local byName = map(entries)
    expect(valueOf(byName, "maxFPS")):toBe("60")
    expect(valueOf(byName, "maxFPSBk")):toBe("60")
  end)

  it("uses the configured frame cap value for the framecap category", function()
    local entries = ns.Profiles.Select({ categories = { framecap = true }, framecapValue = 120 }, fullEnv())
    local byName = map(entries)
    expect(valueOf(byName, "maxFPS")):toBe("120")
    expect(valueOf(byName, "maxFPSBk")):toBe("120")
  end)

  it("falls back to the default frame cap value when unset", function()
    local entries = ns.Profiles.Select({ categories = { framecap = true } }, fullEnv())
    local byName = map(entries)
    expect(valueOf(byName, "maxFPS")):toBe("60")
  end)

  it("skips unknown cvars with an unknown reason", function()
    local entries, skipped = ns.Profiles.Select({}, fullEnv({
      isKnown = function(cvar)
        return cvar ~= "particleDensity"
      end,
    }))
    expect(skipped.particleDensity):toBe("unknown")
    expect(map(entries).particleDensity):toBeNil()
    expect(valueOf(map(entries), "graphicsShadowQuality")):toBe("1")
  end)

  it("skips read-only cvars", function()
    local entries, skipped = ns.Profiles.Select({}, fullEnv({
      isReadOnly = function(cvar)
        return cvar == "groundEffectDensity"
      end,
    }))
    expect(skipped.groundEffectDensity):toBe("read-only")
    expect(map(entries).groundEffectDensity):toBeNil()
  end)

  it("includes secure cvars and flags them", function()
    local entries = ns.Profiles.Select({}, fullEnv({
      isSecure = function(cvar)
        return cvar == "graphicsShadowQuality"
      end,
    }))
    local entry = map(entries).graphicsShadowQuality
    expect(entry):toBeTruthy()
    expect(entry.secure):toBe(true)
  end)

  it("skips the discovered cvar when absent", function()
    local entries, skipped = ns.Profiles.Select({ categories = { targetfps = true } }, fullEnv())
    expect(skipped.targetfps):toBe("not-found")
    local targetfpsEntries = 0
    for _, entry in ipairs(entries) do
      if entry.category == "targetfps" then
        targetfpsEntries = targetfpsEntries + 1
      end
    end
    expect(targetfpsEntries):toBe(0)
  end)

  it("includes the discovered cvar under its discovered name", function()
    local entries = ns.Profiles.Select({ categories = { targetfps = true } }, fullEnv({
      findCvar = function(name)
        if name == "targetfps" then
          return "discoveredTargetCvar"
        end
        return nil
      end,
    }))
    local found
    for _, entry in ipairs(entries) do
      if entry.category == "targetfps" then
        found = entry
      end
    end
    expect(found):toBeTruthy()
    expect(found.cvar):toBe("discoveredTargetCvar")
    expect(found.value):toBe("60")
  end)

  it("never defines forbidden cvar patterns", function()
    local forbidden = { "texture", "scale", "resolution", "msaa", "gxapi", "uiscale" }
    for _, definition in ipairs(ns.Profiles.Definitions) do
      local name = string.lower(definition.cvar or definition.discover or "")
      for _, pattern in ipairs(forbidden) do
        expect(name:find(pattern, 1, true)):toBeNil()
      end
    end
  end)
end)
