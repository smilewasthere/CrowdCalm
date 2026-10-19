-- luacheck configuration for CrowdCalm Lab (WoW retail + Forever).
-- luacheck itself is optional (not installed on every machine); the static
-- gate is scripts/check-lua.js. Keep this file in sync with the globals the
-- addon actually uses.

std = "lua51"

-- Globals this addon defines (nothing else may leak into _G).
globals = {
  "CrowdCalmLabDB",
  "CrowdCalmLab_OnAddonCompartmentClick",
  "SLASH_CCL1",
  "SLASH_CCL2",
}

-- Read-only WoW API surface used by the addon.
read_globals = {
  -- frames / UI
  "CreateFrame",
  "UIParent",
  "UISpecialFrames",
  "GameTooltip",
  "STANDARD_TEXT_FONT",
  "DEFAULT_FONT",
  "NORMAL_FONT",
  "InCombatLockdown",
  "GetTime",
  "GetFramerate",
  "GetBuildInfo",
  "IsResting",
  "GetZoneText",
  "GetSubZoneText",
  "GetInstanceInfo",
  "GetNumGroupMembers",
  "SlashCmdList",
  "PlaySound",
  "date",
  "SOUNDKIT",
  "YES",
  "NO",
  "StaticPopupDialogs",
  "StaticPopup_Show",
  "StaticPopup_Hide",
  "GetAddOnMetadata",
  "GetAddOnEnableState",
  "GetNumAddOns",
  "GetAddOnInfo",
  "UpdateAddOnMemoryUsage",
  "GetAddOnMemoryUsage",
  "SetItemRef",
  -- movement watchdog (Engine/LabRunner.lua, probed at load)
  "GetUnitSpeed",
  "GetPlayerFacing",
  -- minimap button (UI/MinimapButton.lua)
  "Minimap",
  "GetCursorPosition",
  -- static popup confirmation buttons
  "OKAY",
  -- namespaced namespaces (fields are validated in game, not by luacheck)
  "C_Timer",
  "C_CVar",
  "C_NamePlate",
  "C_AddOnProfiler",
  "C_AddOns",
  "C_Texture",
  "C_Var",
  "C_UI",
  "C_DateAndTime",
}

ignore = {
  "631", -- max line length is not enforced
  "212", -- unused trailing arguments (client callbacks)
  "213", -- unused loop variables
  "211", -- unused local: the shared-namespace idiom leaves ADDON_NAME unused in some files
}
