-- UI/Compartment.lua — entry points only (brief section 6.3): the addon
-- compartment callback (the one allowed global besides the SavedVariables
-- table) and the /ccl slash. Slash routing requires the _G.SLASH_CCL1/2
-- registrations (client API mechanism, ledgered like the compartment
-- global). Zero idle cost: no timers, no frames created here.
local ADDON_NAME, ns = ...

-- Compartment click signature varies across clients; any args are ignored
-- and the click always toggles the window. Assumed correct; see VERIFY.md #23.
function CrowdCalmLab_OnAddonCompartmentClick()
  ns.ui.Toggle()
end

_G.SLASH_CCL1 = "/ccl"
_G.SLASH_CCL2 = "/crowdcalmlab"
SlashCmdList["CCL"] = function(msg)
  local command = (msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if command == "" then
    ns.ui.Toggle()
  elseif command == "restore" then
    ns.ui.RequestRestore()
  elseif command == "help" then
    ns.util.LogInfo("/ccl — open or close the window")
    ns.util.LogInfo("/ccl restore — restore settings from the baseline")
    ns.util.LogInfo("/ccl help — this list")
  else
    ns.util.LogInfo("Unknown command: " .. command .. " (try /ccl help)")
  end
end
