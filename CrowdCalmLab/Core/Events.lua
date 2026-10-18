-- Core/Events.lua — one event frame, pcall-guarded dispatch, lazy registration.
-- Registers only events the addon actually needs (brief section 6).
local ADDON_NAME, ns = ...

local frame = CreateFrame("Frame")
local handlers = {}
local registered = {}

local function dispatch(_, event, ...)
  local list = handlers[event]
  if not list then
    return
  end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then
      print("|cffff5555" .. ADDON_NAME .. "|r event error (" .. event .. "): " .. tostring(err))
    end
  end
end
frame:SetScript("OnEvent", dispatch)

local events = {}
ns.events = events

function events.Register(event, fn)
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
  end
  list[#list + 1] = fn
  if not registered[event] then
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if ok then
      registered[event] = true
    else
      print("|cffff5555" .. ADDON_NAME .. "|r cannot register event " .. tostring(event) .. ": " .. tostring(err))
    end
  end
end

function events.Unregister(event, fn)
  local list = handlers[event]
  if not list then
    return
  end
  for i = #list, 1, -1 do
    if list[i] == fn then
      table.remove(list, i)
    end
  end
  if #list == 0 then
    handlers[event] = nil
    if registered[event] then
      registered[event] = nil
      pcall(frame.UnregisterEvent, frame, event)
    end
  end
end

function events.Count(event)
  local list = handlers[event]
  if list then
    return #list
  end
  return 0
end
