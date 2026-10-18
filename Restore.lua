local ADDON_NAME, ns = ...

local Restore = {}
ns.Restore = Restore

function Restore.Plan(persisted, current)
  local plan = { restore = {}, adopt = {}, clear = {}, restoreAny = false }
  if not persisted or not persisted.sessionActive then
    return plan
  end

  local applied = persisted.applied or {}
  local baselines = persisted.baselines or {}
  current = current or {}

  for cvar, appliedValue in pairs(applied) do
    local now = current[cvar]
    local baseline = baselines[cvar]
    if now == nil then
      plan.clear[cvar] = true
    elseif now == appliedValue then
      if baseline ~= nil then
        plan.restore[cvar] = baseline
        plan.restoreAny = true
      else
        plan.clear[cvar] = true
      end
    elseif now == baseline then
      plan.clear[cvar] = true
    else
      plan.adopt[cvar] = now
    end
  end

  return plan
end
