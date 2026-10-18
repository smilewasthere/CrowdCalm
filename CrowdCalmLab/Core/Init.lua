-- Core/Init.lua — bootstrap: shared addon table, SavedVariables, init/login hooks.
-- Loaded first; every other file may call ns.addInit / ns.onLogin at file scope
-- because this file runs before them.
local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.version = "1.0.0"
ns.db = nil
ns.dbReady = false

local initializers = {}
local loginHandlers = {}

function ns.addInit(fn)
  initializers[#initializers + 1] = fn
end

function ns.onLogin(fn)
  loginHandlers[#loginHandlers + 1] = fn
end

local function runList(list, tag)
  for i = 1, #list do
    local ok, err = pcall(list[i], ns.db)
    if not ok then
      print("|cffff5555" .. ADDON_NAME .. "|r " .. tag .. " error: " .. tostring(err))
    end
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then
      return
    end
    frame:UnregisterEvent("ADDON_LOADED")
    if type(CrowdCalmLabDB) ~= "table" then
      CrowdCalmLabDB = {}
    end
    ns.db = CrowdCalmLabDB
    if ns.settings and ns.settings.initialize then
      local ok, err = pcall(ns.settings.initialize, ns.db)
      if not ok then
        print("|cffff5555" .. ADDON_NAME .. "|r settings error: " .. tostring(err))
      end
    end
    ns.dbReady = true
    runList(initializers, "init")
  elseif event == "PLAYER_LOGIN" then
    frame:UnregisterEvent("PLAYER_LOGIN")
    runList(loginHandlers, "login")
  end
end)
