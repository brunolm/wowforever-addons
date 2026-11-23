local ROW_HEIGHT = 46
local FRAME_WIDTH = 660
local MAX_ROWS = 12

local QuestieDB, ZoneDB
local frame, rows = nil, {}
local mapPin
local PIN_REF = "QuestItemGuide"

local RefreshIfShown, ShowGuide, LoadQuestie, ScanBags, ItemsForActiveQuests, AddQuestItems, EntryForItem
local OpenRelatedQuest, FindTarget, StarterTarget, BlizzardPoint, FinisherPoints, StarterPoints, SpecificPoints, ObjectivePoints, AddNpc, AddObject, AddSpawns, ClosestPoint
local FirstInBusiestZone, GetFrame, Render, CreateRow, FillRow, DetailText, Track, ShowOnMap, GetMapPin, IsUsable, IsQuestClass

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:SetScript("OnEvent", function() RefreshIfShown() end)

SLASH_QUESTITEMGUIDE1 = "/qig"
SlashCmdList.QUESTITEMGUIDE = function()
  if not LoadQuestie() then
    print("QuestItemGuide: Questie is still loading, try again in a few seconds.")
    return
  end
  ShowGuide()
end

function RefreshIfShown()
  if not (frame and frame:IsShown()) or not LoadQuestie() then return end
  Render(ScanBags())
end

function ShowGuide()
  local f = GetFrame()
  Render(ScanBags())
  f:Show()
end

function LoadQuestie()
  if QuestieDB and QuestieDB.QueryNPCSingle then return true end
  if not QuestieLoader then return false end
  QuestieDB = QuestieLoader:ImportModule("QuestieDB")
  ZoneDB = QuestieLoader:ImportModule("ZoneDB")
  return QuestieDB and QuestieDB.QueryNPCSingle and QuestieDB.GetQuest and true or false
end

-- Returns one entry per distinct quest item in the bags.
function ScanBags()
  local itemQuests = ItemsForActiveQuests()
  local entries, added = {}, {}
  for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local entry = info and not added[info.itemID] and EntryForItem(bag, slot, info, itemQuests)
      if entry then
        added[info.itemID] = true
        entries[#entries + 1] = entry
      end
    end
  end
  return entries
end

function ItemsForActiveQuests()
  local itemQuests = {}
  for logIndex = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(logIndex)
    if info and not info.isHeader and info.questID then
      AddQuestItems(itemQuests, info.questID, logIndex)
    end
  end
  return itemQuests
end

function AddQuestItems(itemQuests, questID, logIndex)
  local quest = QuestieDB.GetQuest(questID)
  if quest then
    if quest.sourceItemId then itemQuests[quest.sourceItemId] = questID end
    if quest.SpellItemId then itemQuests[quest.SpellItemId] = questID end
    for _, itemID in ipairs(quest.requiredSourceItems or {}) do itemQuests[itemID] = questID end
    for _, objective in ipairs(quest.ObjectiveData or {}) do
      if objective.Type == "item" then itemQuests[objective.Id] = questID end
    end
  end
  local link = GetQuestLogSpecialItemInfo and GetQuestLogSpecialItemInfo(logIndex)
  local specialID = link and (C_Item.GetItemInfoInstant or GetItemInfoInstant)(link)
  if specialID then itemQuests[specialID] = questID end
end

-- Quest-flagged items are always listed; other items only when a quest in the log needs you to use them.
-- Items you use point to where to use them; items you hand in point to the turn-in.
-- A quest item whose quest isn't in the log points to the giver of its next open quest.
function EntryForItem(bag, slot, info, itemQuests)
  local entry = { itemID = info.itemID, icon = info.iconFileID, link = info.hyperlink }
  local questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
  if questInfo and questInfo.questID and not questInfo.isActive then
    entry.questID, entry.startsQuest = questInfo.questID, true
    return entry
  end
  local isQuestItem = (questInfo and questInfo.isQuestItem) or IsQuestClass(info.itemID)
  local usable = IsUsable(info.itemID)
  local questID = itemQuests[info.itemID]
  if questID and (isQuestItem or usable) then
    entry.questID, entry.target = questID, FindTarget(questID, not usable)
    return entry
  end
  if not isQuestItem then return nil end
  local openQuest = OpenRelatedQuest(info.itemID)
  if openQuest then
    entry.questID, entry.notInLog, entry.target = openQuest, true, StarterTarget(openQuest)
  end
  return entry
end

function OpenRelatedQuest(itemID)
  for _, questID in ipairs(QuestieDB.QueryItemSingle(itemID, "relatedQuests") or {}) do
    if not C_QuestLog.IsQuestFlaggedCompleted(questID) then return questID end
  end
  return nil
end

-- Picks the waypoint for a quest in the log: the turn-in when delivering or once it's complete, otherwise
-- the spot to use the item (event or custom Questie points first, then the objective mobs and objects).
-- Questie lacks many Forever-only quests, so the game's own quest map marker is the fallback.
function FindTarget(questID, deliver)
  local quest = QuestieDB.GetQuest(questID)
  if not quest then return BlizzardPoint(questID) end
  local points
  if deliver or C_QuestLog.IsComplete(questID) then
    points = FinisherPoints(quest)
  else
    points = SpecificPoints(quest)
    if #points == 0 then points = ObjectivePoints(quest) end
  end
  return ClosestPoint(points) or BlizzardPoint(questID)
end

function StarterTarget(questID)
  local quest = QuestieDB.GetQuest(questID)
  return quest and ClosestPoint(StarterPoints(quest))
end

function BlizzardPoint(questID)
  local mapID = GetQuestUiMapID and GetQuestUiMapID(questID)
  if not mapID or mapID == 0 or not C_QuestLog.GetQuestsOnMap then return nil end
  for _, q in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
    if q.questID == questID then return { mapID = mapID, x = q.x * 100, y = q.y * 100, name = "Quest area (game map)" } end
  end
  return nil
end

function FinisherPoints(quest)
  local points = {}
  for _, id in ipairs(quest.Finisher.NPC or {}) do AddNpc(points, id, "Turn in: ") end
  for _, id in ipairs(quest.Finisher.GameObject or {}) do AddObject(points, id, "Turn in: ") end
  return points
end

function StarterPoints(quest)
  local points = {}
  for _, id in ipairs(quest.Starts.NPC or {}) do AddNpc(points, id, "Quest giver: ") end
  for _, id in ipairs(quest.Starts.GameObject or {}) do AddObject(points, id, "Quest giver: ") end
  return points
end

function SpecificPoints(quest)
  local points = {}
  for _, objective in ipairs(quest.ObjectiveData or {}) do
    if objective.Type == "event" then AddSpawns(points, objective.Coordinates, objective.Text) end
  end
  for _, extra in ipairs(quest.extraObjectives or {}) do
    AddSpawns(points, extra[1], extra[3])
    for _, ref in ipairs(extra[5] or {}) do
      if ref[1] == "monster" then AddNpc(points, ref[2]) else AddObject(points, ref[2]) end
    end
  end
  return points
end

function ObjectivePoints(quest)
  local points = {}
  for _, objective in ipairs(quest.ObjectiveData or {}) do
    if objective.Type == "monster" then AddNpc(points, objective.Id) end
    if objective.Type == "object" then AddObject(points, objective.Id) end
    if objective.Type == "killcredit" then
      for _, id in ipairs(objective.IdList or {}) do AddNpc(points, id) end
    end
  end
  return points
end

function AddNpc(points, id, prefix)
  AddSpawns(points, QuestieDB.QueryNPCSingle(id, "spawns"), (prefix or "") .. (QuestieDB.QueryNPCSingle(id, "name") or "?"))
end

function AddObject(points, id, prefix)
  AddSpawns(points, QuestieDB.QueryObjectSingle(id, "spawns"), (prefix or "") .. (QuestieDB.QueryObjectSingle(id, "name") or "?"))
end

-- Questie spawns are { [areaId] = { {x, y}, ... } } on a 0-100 scale; instance spawns use negative coordinates.
function AddSpawns(points, spawns, name)
  for areaId, coords in pairs(spawns or {}) do
    local mapID = ZoneDB:GetUiMapIdByAreaId(areaId)
    for _, c in ipairs(mapID and coords or {}) do
      if c[1] and c[1] >= 0 then
        points[#points + 1] = { mapID = mapID, x = c[1], y = c[2], name = name }
      end
    end
  end
end

-- Nearest point in the player's zone; otherwise the first point in the zone with the most points.
function ClosestPoint(points)
  if #points == 0 then return nil end
  local playerMap = C_Map.GetBestMapForUnit("player")
  local pos = playerMap and C_Map.GetPlayerMapPosition(playerMap, "player")
  local best, bestDist
  if pos then
    local px, py = pos:GetXY()
    for _, p in ipairs(points) do
      local dist = p.mapID == playerMap and (p.x / 100 - px) ^ 2 + (p.y / 100 - py) ^ 2
      if dist and (not bestDist or dist < bestDist) then best, bestDist = p, dist end
    end
  end
  return best or FirstInBusiestZone(points)
end

function FirstInBusiestZone(points)
  local counts, first = {}, {}
  for _, p in ipairs(points) do
    counts[p.mapID] = (counts[p.mapID] or 0) + 1
    first[p.mapID] = first[p.mapID] or p
  end
  local bestMap
  for mapID, n in pairs(counts) do
    if not bestMap or n > counts[bestMap] then bestMap = mapID end
  end
  return first[bestMap]
end

function GetFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", "QuestItemGuideFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(FRAME_WIDTH, 120)
  frame:SetPoint("CENTER", 0, 150)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOP", 0, -5)
  frame.title:SetText("Quest items")
  frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.empty:SetPoint("TOP", 0, -45)
  frame.empty:SetText("No usable quest items in your bags.")
  tinsert(UISpecialFrames, "QuestItemGuideFrame")
  return frame
end

function Render(entries)
  local shown = math.min(#entries, MAX_ROWS)
  for i = 1, shown do
    local row = rows[i] or CreateRow(i)
    rows[i] = row
    FillRow(row, entries[i])
    row:Show()
  end
  for i = shown + 1, #rows do rows[i]:Hide() end
  frame.empty:SetShown(shown == 0)
  frame:SetHeight(40 + math.max(shown, 1) * ROW_HEIGHT)
end

function CreateRow(i)
  local row = CreateFrame("Frame", nil, frame)
  row:SetSize(FRAME_WIDTH - 24, ROW_HEIGHT - 4)
  row:SetPoint("TOPLEFT", 12, -30 - (i - 1) * ROW_HEIGHT)

  row.icon = CreateFrame("Button", nil, row)
  row.icon:SetSize(36, 36)
  row.icon:SetPoint("LEFT")
  row.icon.texture = row.icon:CreateTexture(nil, "ARTWORK")
  row.icon.texture:SetAllPoints()
  row.icon:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
  end)
  row.icon:SetScript("OnLeave", GameTooltip_Hide)

  row.track = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.track:SetSize(90, 24)
  row.track:SetPoint("RIGHT")
  row.track:SetText("Track")

  row.map = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.map:SetSize(100, 24)
  row.map:SetPoint("RIGHT", row.track, "LEFT", -4, 0)
  row.map:SetText("Show on map")

  row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
  row.title:SetPoint("RIGHT", row.map, "LEFT", -8, 0)
  row.title:SetJustifyH("LEFT")
  row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
  row.detail:SetPoint("RIGHT", row.map, "LEFT", -8, 0)
  row.detail:SetJustifyH("LEFT")
  return row
end

function FillRow(row, entry)
  row.icon.texture:SetTexture(entry.icon)
  row.icon.link = entry.link
  local questName = entry.questID and (C_QuestLog.GetTitleForQuestID(entry.questID) or QuestieDB.QueryQuestSingle(entry.questID, "name") or ("Quest " .. entry.questID))
  row.title:SetText(entry.link .. (questName and ("  |cffffd200" .. questName .. "|r") or ""))
  row.detail:SetText(DetailText(entry))
  row.track:SetEnabled(entry.target ~= nil)
  row.track:SetScript("OnClick", function() Track(entry, questName) end)
  row.map:SetEnabled(entry.target ~= nil)
  row.map:SetScript("OnClick", function() ShowOnMap(entry, questName) end)
end

function DetailText(entry)
  if entry.startsQuest then return "Starts a quest: right-click the item to accept it." end
  if not entry.questID then return "|cff999999No open quest uses this item (already done?).|r" end
  local prefix = entry.notInLog and "|cffff8040Not in your log.|r " or ""
  local t = entry.target
  if not t then return prefix .. "|cff999999No location found for this quest.|r" end
  local zone = C_Map.GetMapInfo(t.mapID)
  return string.format("%s%s  |cffaaaaaa%s %.1f, %.1f|r", prefix, t.name or "", zone and zone.name or "?", t.x, t.y)
end

function Track(entry, questName)
  local t = entry.target
  TomTom:AddWaypoint(t.mapID, t.x / 100, t.y / 100, { title = questName .. ": " .. (t.name or ""), crazy = true, from = "QuestItemGuide" })
end

-- Opens the world map on the target's zone with a temporary pin; the pin is removed when the map closes.
function ShowOnMap(entry, questName)
  local pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
  if not pins then return end
  local t = entry.target
  local pin = GetMapPin()
  pin.texture:SetTexture(entry.icon)
  pin.label = questName .. "|n|cffffffff" .. (t.name or "") .. "|r"
  pins:RemoveAllWorldMapIcons(PIN_REF)
  pins:AddWorldMapIconMap(PIN_REF, pin, t.mapID, t.x / 100, t.y / 100, HBD_PINS_WORLDMAP_SHOW_PARENT)
  frame:Hide()
  if not WorldMapFrame:IsShown() then ToggleWorldMap() end
  WorldMapFrame:SetMapID(t.mapID)
  if not WorldMapFrame.questItemGuideHooked then
    WorldMapFrame.questItemGuideHooked = true
    WorldMapFrame:HookScript("OnHide", function() pins:RemoveAllWorldMapIcons(PIN_REF) end)
  end
end

function GetMapPin()
  if mapPin then return mapPin end
  mapPin = CreateFrame("Frame")
  mapPin:SetSize(24, 24)
  mapPin.texture = mapPin:CreateTexture(nil, "ARTWORK")
  mapPin.texture:SetAllPoints()
  mapPin:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.label)
    GameTooltip:Show()
  end)
  mapPin:SetScript("OnLeave", GameTooltip_Hide)
  -- Questie fixes its world map pins at frame level 2016 and up; stay above them.
  mapPin:SetFrameLevel(3000)
  mapPin:SetFixedFrameLevel(true)
  return mapPin
end

function IsUsable(itemID)
  local getItemSpell = C_Item.GetItemSpell or GetItemSpell
  return getItemSpell(itemID) ~= nil
end

function IsQuestClass(itemID)
  local classID = select(6, (C_Item.GetItemInfoInstant or GetItemInfoInstant)(itemID))
  return classID == Enum.ItemClass.Questitem
end
