local _, ns = ...

local GOLD = "|cffffd200"
local GREY = "|cffaaaaaa"
local shown -- { owner, questID, member, hint } of the tooltip on screen, refreshed when quest data loads
local reported -- the first tooltip error is printed to chat; Lua errors are hidden by default

local Call, Questie = ns.Call, ns.QuestieModule
local Section, AddHeader, AddObjectives, AddRewards, RewardItems, ItemText, Money, Number, Reputation, FactionName, QuestXP

local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, _, questID)
  if shown and shown.questID == questID and GameTooltip:IsOwned(shown.owner) then
    ns.QuestTooltip(shown.owner, shown.questID, shown.member, shown.hint)
  end
end)

--- Shows a quest's status for `member`, its objectives and rewards. The game loads data for quests
--- outside your log on request, so the tooltip fills in when QUEST_DATA_LOAD_RESULT arrives.
function ns.QuestTooltip(owner, questID, member, hint)
  shown = { owner = owner, questID = questID, member = member, hint = hint }
  if not HaveQuestData(questID) and C_QuestLog.RequestLoadQuestByID then C_QuestLog.RequestLoadQuestByID(questID) end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  -- SetText already shows the tooltip, so the closing Show must always run to size it for the later lines.
  GameTooltip:SetText(ns.QuestTitle(questID), 1, 1, 1, 1, true)
  Section(AddHeader, questID, member)
  Section(AddObjectives, questID)
  Section(AddRewards, questID)
  if hint then GameTooltip:AddLine(hint, 0.5, 0.5, 0.5, true) end
  GameTooltip:Show()
end

--- Runs one part of the tooltip; an error there skips only that part.
function Section(fn, ...)
  local ok, err = pcall(fn, ...)
  if ok or reported then return end
  reported = true
  print("|cffff8080PartyQuests:|r part of a quest tooltip failed (shown once): " .. tostring(err))
end

function AddHeader(questID, member)
  local sharable = ns.IsSharable(questID)
  GameTooltip:AddLine(("%s · level %s · #%d%s"):format(ns.QuestZone(questID), ns.LevelText(questID), questID,
    sharable == nil and "" or sharable and " · |cff1eff00sharable|r" or " · not sharable"), 0.67, 0.67, 0.67, true)
  if not member then return end
  local status = ns.Status(questID, member)
  GameTooltip:AddLine(("|c%s%s|r: %s%s"):format(ns.ClassColor(member), member.name, ns.Colorize(status),
    status.tip and (GREY .. " (" .. status.tip .. ")|r") or ""), 1, 1, 1, true)
end

-- Your own log gives objectives with your progress; otherwise QuestieDB's summary, then the game's objective list.
function AddObjectives(questID)
  local lines = {}
  local mine = ns.OwnLog().active[questID]
  if mine or HaveQuestData(questID) then
    for _, objective in ipairs(Call(C_QuestLog.GetQuestObjectives, questID) or {}) do
      if type(objective) == "table" and type(objective.text) == "string" and objective.text ~= "" then
        local color = (mine and objective.finished) and "|cff8fd18f" or "|cffffffff"
        lines[#lines + 1] = color .. objective.text .. "|r"
      end
    end
  end
  local q = ns.QuestData(questID)
  local summary = q and q.objectivesText
  if not mine and type(summary) == "table" and #summary > 0 then lines = { "|cffffffff" .. table.concat(summary, " ") .. "|r" } end
  if #lines == 0 then return end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(GOLD .. (mine and "Objectives (your progress)" or "Objectives") .. "|r")
  for _, line in ipairs(lines) do GameTooltip:AddLine(" - " .. line, 1, 1, 1, true) end
end

function AddRewards(questID)
  local lines = {}
  local xp = QuestXP(questID)
  local money = Call(GetQuestLogRewardMoney, questID) or 0
  local summary = {}
  if xp and xp > 0 then summary[#summary + 1] = Number(xp) .. " XP" end
  if money > 0 then summary[#summary + 1] = Money(money) end
  if #summary > 0 then lines[#lines + 1] = table.concat(summary, "   ") end
  local items, choices = RewardItems(questID)
  for _, item in ipairs(items) do lines[#lines + 1] = ItemText(item) end
  if #choices > 0 then
    lines[#lines + 1] = GREY .. "Choose one:|r"
    for _, item in ipairs(choices) do lines[#lines + 1] = "   " .. ItemText(item) end
  end
  for _, rep in ipairs(Reputation(questID)) do
    local name = FactionName(rep[1])
    if name and rep[2] then lines[#lines + 1] = ("%s%+d|r %s"):format(rep[2] >= 0 and "|cff8fd18f" or "|cffff8080", rep[2], name) end
  end
  if #lines == 0 then return end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(GOLD .. "Rewards|r")
  for _, line in ipairs(lines) do GameTooltip:AddLine(line, 1, 1, 1, true) end
end

-- The reward functions take the quest ID on this client; they fill in for quests outside the log once loaded.
function RewardItems(questID)
  local items, choices = {}, {}
  for i = 1, Call(GetNumQuestLogRewards, questID) or 0 do
    local name, texture, count, quality = Call(GetQuestLogRewardInfo, i, questID)
    if name and name ~= "" then items[#items + 1] = { name = name, texture = texture, count = count, quality = quality } end
  end
  for i = 1, Call(GetNumQuestLogChoices, questID, true) or 0 do
    local name, texture, count, quality = Call(GetQuestLogChoiceInfo, i, questID)
    if name and name ~= "" then choices[#choices + 1] = { name = name, texture = texture, count = count, quality = quality } end
  end
  return items, choices
end

-- The coin and number helpers moved between client versions; use whichever this one has.
function Money(copper)
  local format = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  local text = format and Call(format, copper)
  if text then return text end
  local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
  return (gold > 0 and gold .. "g " or "") .. ((gold > 0 or silver > 0) and silver .. "s " or "") .. copper % 100 .. "c"
end

function Number(n)
  return BreakUpLargeNumbers and Call(BreakUpLargeNumbers, n) or tostring(n)
end

function ItemText(item)
  local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality or 1]
  local icon = item.texture and ("|T%s:14:14|t "):format(item.texture) or ""
  local count = item.count and item.count > 1 and (" x" .. item.count) or ""
  return icon .. (color and color.hex or "|cffffffff") .. item.name .. "|r" .. count
end

-- Questie's version applies its reputation multipliers; QuestieDB's raw values are the fallback.
function Reputation(questID)
  local module = Questie("QuestieReputation")
  local rewards = module and Call(module.GetReputationReward, questID)
  if type(rewards) == "table" and #rewards > 0 then return rewards end
  local q = ns.QuestData(questID)
  return q and type(q.reputation) == "table" and q.reputation or {}
end

function FactionName(factionID)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local data = Call(C_Reputation.GetFactionDataByID, factionID)
    if data and data.name then return data.name end
  end
  return GetFactionInfoByID and Call(GetFactionInfoByID, factionID) or nil
end

-- Questie's XP table (adjusted for your level) covers any quest; the game's own value only covers your log.
function QuestXP(questID)
  local module = Questie("QuestXP")
  local xp = module and module.GetQuestLogRewardXP and Call(module.GetQuestLogRewardXP, module, questID)
  if xp and xp > 0 then return xp end
  if ns.OwnLog().active[questID] then return Call(GetQuestLogRewardXP, questID) end
  return nil
end
