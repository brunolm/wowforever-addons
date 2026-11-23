local ADDON, ns = ...

local HBDPins = LibStub("HereBeDragons-Pins-2.0")

-- Matched in order, so "Dark Iron" wins over "Iron" and "Truesilver" over "Silver".
local ORES = {
  { word = "Dark Iron", item = 11370 },
  { word = "Truesilver", item = 7911 },
  { word = "Copper", item = 2770 },
  { word = "Tin", item = 2771 },
  { word = "Silver", item = 2775 },
  { word = "Iron", item = 2772 },
  { word = "Gold", item = 2776 },
  { word = "Mithril", item = 3858 },
  { word = "Thorium", item = 10620 },
  { word = "Incendicite", item = 3340 },
  { word = "Bloodstone", item = 4278 },
  { word = "Indurium", item = 5833 },
}
-- Nodes whose metal isn't listed above (e.g. Starsilver, new in Forever) still show, with this icon.
local OTHER = { word = "Other", icon = "Interface\\Icons\\INV_Misc_QuestionMark" }

local PIN_SIZE = 14

local shownMapId, shownKey
local activePins, pinPool = {}, {}

local Show, Hide, Print, ParseFilter, CurrentZoneMap, OreFor, AddPin, CreatePin

SLASH_OREMAP1 = "/ore"
SlashCmdList.OREMAP = function(msg)
  local key = strtrim(msg or ""):lower()
  if shownMapId and key == shownKey then
    Hide()
    Print("off.")
    return
  end
  local filter = ParseFilter(key)
  if filter == false then return end
  Show(key, filter)
end

function Show(key, filter)
  local mapId, zoneName = CurrentZoneMap()
  if not mapId then
    Print("you're not in a zone with a map.")
    return
  end

  Hide()
  local counts, order = {}, {}
  for name, coords in pairs(ns.nodes[mapId] or {}) do
    local ore = OreFor(name)
    if not filter or filter[ore] then
      for i = 1, #coords, 2 do
        AddPin(name, ore, mapId, coords[i] / 100, coords[i + 1] / 100)
      end
      if not counts[ore] then order[#order + 1] = ore end
      counts[ore] = (counts[ore] or 0) + #coords / 2
    end
  end

  if #order == 0 then
    Print("no known ore nodes in " .. zoneName .. ".")
    return
  end
  shownMapId, shownKey = mapId, key
  local parts = {}
  for _, ore in ipairs(order) do parts[#parts + 1] = counts[ore] .. " " .. ore.word end
  Print(zoneName .. ": " .. table.concat(parts, ", ") .. ". Open the map (M); type /ore again to hide.")
end

function Hide()
  HBDPins:RemoveAllWorldMapIcons(ADDON)
  for i = #activePins, 1, -1 do
    pinPool[#pinPool + 1] = activePins[i]
    activePins[i] = nil
  end
  shownMapId, shownKey = nil, nil
end

function Print(text)
  print("|cffd4a017OreMap|r: " .. text)
end

-- Returns nil for "all ores", a set of ORES entries, or false after reporting a bad name.
function ParseFilter(key)
  if key == "" then return nil end
  local filter = {}
  for token in key:gmatch("%S+") do
    local match
    for _, ore in ipairs(ORES) do
      if ore.word:lower():gsub(" ", ""):find(token, 1, true) == 1 then match = ore break end
    end
    if not match then
      local names = {}
      for _, ore in ipairs(ORES) do names[#names + 1] = ore.word:lower() end
      Print("unknown ore '" .. token .. "'. Use /ore, or /ore followed by any of: " .. table.concat(names, ", "))
      return false
    end
    filter[match] = true
  end
  return filter
end

-- Walks up from sub-zone and cave maps to the zone map; nil in instances or on continents.
function CurrentZoneMap()
  local mapId = C_Map.GetBestMapForUnit("player")
  while mapId do
    local info = C_Map.GetMapInfo(mapId)
    if not info or info.mapType < Enum.UIMapType.Zone then return end
    if info.mapType == Enum.UIMapType.Zone then return mapId, info.name end
    mapId = info.parentMapID
  end
end

function OreFor(name)
  for _, ore in ipairs(ORES) do
    if name:find("%f[%a]" .. ore.word .. "%f[%A]") then return ore end
  end
  return OTHER
end

function AddPin(name, ore, mapId, x, y)
  ore.icon = ore.icon or C_Item.GetItemIconByID(ore.item) or OTHER.icon
  local pin = table.remove(pinPool) or CreatePin()
  pin.icon:SetTexture(ore.icon)
  pin.label = name
  activePins[#activePins + 1] = pin
  HBDPins:AddWorldMapIconMap(ADDON, pin, mapId, x, y, HBD_PINS_WORLDMAP_SHOW_CURRENT)
end

function CreatePin()
  local pin = CreateFrame("Frame")
  pin:SetSize(PIN_SIZE, PIN_SIZE)
  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetAllPoints()
  pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- Hover-only, so clicks still reach the map underneath.
  pin:EnableMouseMotion(true)
  pin:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.label)
    GameTooltip:Show()
  end)
  pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return pin
end

local events = CreateFrame("Frame")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
  if not shownMapId or CurrentZoneMap() == shownMapId then return end
  Hide()
  Print("off (you left the zone).")
end)
