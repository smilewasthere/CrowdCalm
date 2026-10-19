-- Core/Sound.lua — the tiny UI sound layer (pre.5 owner request). There were
-- no sounds at all before, so the "Mute UI sounds" checkbox had nothing to
-- mute; every playback goes through Sound.Play, which checks that flag in
-- one place. Candidates resolve through the SOUNDKIT table first and fall
-- back to the classic SoundKit IDs (verified in SoundKitConstants.lua);
-- anything that fails stays silent instead of erroring.
local ADDON_NAME, ns = ...

local Sound = {}
ns.sound = Sound

-- kind -> { SOUNDKIT key, classic numeric id }
local KINDS = {
  click = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
  toggleOn = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
  toggleOff = { "IG_MAINMENU_OPTION_CHECKBOX_OFF", 857 },
  done = { "GS_TITLE_OPTION_OK", 798 },
  error = { "GS_TITLE_OPTION_EXIT", 799 },
}

local function isMuted()
  local db = ns.db
  return db ~= nil and db.settings ~= nil and db.settings.ui ~= nil and db.settings.ui.muted == true
end

function Sound.IsMuted()
  return isMuted()
end

-- ignores the mute flag (used by the Mute checkbox itself so unmuting gives
-- audible confirmation)
function Sound.PlayRaw(kind)
  local spec = KINDS[kind]
  if not spec then
    return
  end
  local key, id = spec[1], spec[2]
  if SOUNDKIT and SOUNDKIT[key] then
    pcall(PlaySound, SOUNDKIT[key])
    return
  end
  pcall(PlaySound, id)
end

function Sound.Play(kind)
  if isMuted() then
    return
  end
  Sound.PlayRaw(kind)
end

return Sound
