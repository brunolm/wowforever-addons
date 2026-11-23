local VISIBILITY = "[combat][vehicleui][overridebar][possessbar][petbattle] show; hide"

-- Bar 2 must be set to "Always" in Edit Mode; its own "In Combat" setting would hide it again out of combat.
local BARS = { MainActionBar, MultiBarBottomLeft }

local enabled = true

local function hideOutOfCombat()
  for _, bar in ipairs(BARS) do
    RegisterStateDriver(bar, "visibility", VISIBILITY)
  end
end

local function showAlways()
  for _, bar in ipairs(BARS) do
    UnregisterStateDriver(bar, "visibility")
    bar:Show()
  end
end

-- While a spell, item or macro is on the cursor the bars are shown so it can be dropped on.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ACTIONBAR_SHOWGRID")
frame:RegisterEvent("ACTIONBAR_HIDEGRID")
frame:SetScript("OnEvent", function(_, event)
  if InCombatLockdown() or not enabled then return end
  if event == "ACTIONBAR_SHOWGRID" then
    showAlways()
    return
  end
  hideOutOfCombat()
end)

SLASH_COMBATBARS1 = "/combatbars"
SlashCmdList.COMBATBARS = function(msg)
  if InCombatLockdown() then return end
  if msg == "off" or msg == "on" then
    enabled = msg == "on"
  else
    enabled = not enabled
  end
  if not enabled then
    showAlways()
    print("CombatBars: bars 1 and 2 always shown until /combatbars or /reload")
    return
  end
  hideOutOfCombat()
  print("CombatBars: bars 1 and 2 shown only in combat")
end
