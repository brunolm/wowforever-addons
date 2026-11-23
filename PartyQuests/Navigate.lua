local _, ns = ...

-- Track (TomTom arrow) and Show on map. Quests in your log go through Questie's tracker helpers, which
-- pick the nearest objective, or the turn-in once the quest is complete. Other quests point to the
-- nearest quest giver from QuestieDB. The game's own quest map marker is the last resort.

local PIN_REF = "PartyQuests"
local GIVER_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local QUEST_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"

local waypoint, mapPin
local Target, QuestieHelper, GiverPoint, AddSpawns, GameMapPoint, Nearest, MapPin

function ns.CanTrack()
  return TomTom ~= nil and TomTom.AddWaypoint ~= nil
end

function ns.TrackQuest(questID)
  if not ns.CanTrack() then
    print("PartyQuests: Track needs the TomTom addon.")
    return
  end
  if QuestieHelper("SetQuestTomTomTarget", questID) then return end
  local point = Target(questID)
  if not point then
    print("PartyQuests: no location is known for " .. ns.QuestTitle(questID) .. ".")
    return
  end
  if waypoint and TomTom.RemoveWaypoint then TomTom:RemoveWaypoint(waypoint) end
  waypoint = TomTom:AddWaypoint(point.mapID, point.x, point.y,
    { title = ns.QuestTitle(questID) .. ": " .. point.name, crazy = true, from = "PartyQuests" })
end

--- Opens the world map on the quest; a temporary pin marks the spot unless Questie's own icons do.
function ns.ShowQuestOnMap(questID)
  if QuestieHelper("ShowQuestOnMap", questID) then return end
  local point = Target(questID)
  if not point then
    print("PartyQuests: no location is known for " .. ns.QuestTitle(questID) .. ".")
    return
  end
  if not WorldMapFrame:IsShown() then ToggleWorldMap() end
  WorldMapFrame:SetMapID(point.mapID)
  local pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
  if not pins then return end
  local pin = MapPin()
  pin.texture:SetTexture(point.icon)
  pin.label = ns.QuestTitle(questID) .. "|n|cffffffff" .. point.name .. "|r"
  pins:RemoveAllWorldMapIcons(PIN_REF)
  pins:AddWorldMapIconMap(PIN_REF, pin, point.mapID, point.x, point.y, HBD_PINS_WORLDMAP_SHOW_PARENT)
  if not WorldMapFrame.partyQuestsHooked then
    WorldMapFrame.partyQuestsHooked = true
    WorldMapFrame:HookScript("OnHide", function() pins:RemoveAllWorldMapIcons(PIN_REF) end)
  end
end

-- Questie's helpers only handle quests in your log that Questie knows; they return false otherwise.
function QuestieHelper(name, questID)
  if not ns.OwnLog().active[questID] then return false end
  local tracker = ns.QuestieModule("TrackerUtils")
  return tracker and ns.Call(tracker[name], questID) == true
end

--- { mapID, x, y (0-1), name, icon } for a quest: the game's marker for your own quests, else the quest giver.
function Target(questID)
  if ns.OwnLog().active[questID] then return GameMapPoint(questID) or GiverPoint(questID) end
  return GiverPoint(questID) or GameMapPoint(questID)
end

function GiverPoint(questID)
  local db = _G.QuestDB
  local starters = db and ns.Call(db.Get, questID, "startedBy")
  if type(starters) ~= "table" then return nil end
  local points = {}
  for _, id in ipairs(starters[1] or {}) do AddSpawns(points, _G.NpcDB, id) end
  for _, id in ipairs(starters[2] or {}) do AddSpawns(points, _G.ObjectDB, id) end
  return Nearest(points)
end

-- QuestieDB spawns are { [areaId] = { {x, y}, ... } } on a 0-100 scale; instance spawns use negative coordinates.
function AddSpawns(points, db, id)
  local zones = ns.QuestieModule("ZoneDB")
  if not (db and zones) then return end
  local name = ns.Call(db.Get, id, "name") or "Quest giver"
  for areaID, coords in pairs(ns.Call(db.Get, id, "spawns") or {}) do
    local mapID = ns.Call(zones.GetUiMapIdByAreaId, zones, areaID)
    for _, c in ipairs(mapID and coords or {}) do
      if c[1] and c[1] >= 0 then
        points[#points + 1] = { mapID = mapID, x = c[1] / 100, y = c[2] / 100, name = "Quest giver: " .. name, icon = GIVER_ICON }
      end
    end
  end
end

-- The game's quest marker only exists for quests on the map it's asked about.
function GameMapPoint(questID)
  local mapID = GetQuestUiMapID and ns.Call(GetQuestUiMapID, questID)
  if not mapID or mapID == 0 or not C_QuestLog.GetQuestsOnMap then return nil end
  for _, q in ipairs(ns.Call(C_QuestLog.GetQuestsOnMap, mapID) or {}) do
    if q.questID == questID then return { mapID = mapID, x = q.x, y = q.y, name = "Quest area", icon = QUEST_ICON } end
  end
  return nil
end

-- Nearest point on the player's map; otherwise the first point listed.
function Nearest(points)
  if #points == 0 then return nil end
  local playerMap = C_Map.GetBestMapForUnit("player")
  local pos = playerMap and C_Map.GetPlayerMapPosition(playerMap, "player")
  if not pos then return points[1] end
  local px, py = pos:GetXY()
  local best, bestDist
  for _, p in ipairs(points) do
    local dist = p.mapID == playerMap and (p.x - px) ^ 2 + (p.y - py) ^ 2
    if dist and (not bestDist or dist < bestDist) then best, bestDist = p, dist end
  end
  return best or points[1]
end

function MapPin()
  if mapPin then return mapPin end
  mapPin = CreateFrame("Frame")
  mapPin:SetSize(22, 22)
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
