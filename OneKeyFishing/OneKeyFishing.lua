local KEY = "F"
local FISHING = "Fishing"

local frame = CreateFrame("Frame")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:SetScript("OnEvent", function(self, event, _, _, spellID)
  -- Override bindings are protected in combat, so leave them alone there.
  if InCombatLockdown() then return end
  if event == "UNIT_SPELLCAST_CHANNEL_START" and C_Spell.GetSpellName(spellID) == FISHING then
    SetOverrideBinding(self, true, KEY, "INTERACTTARGET")
    return
  end
  ClearOverrideBindings(self)
end)
