local ADDON, ns = ...

-- Order is priority: a unit gets the color of the first enabled type it matches.
ns.CATEGORIES = {
  { key = "target",         label = "Your current target",    color = { 1, 1, 1 },       enabled = false },
  { key = "party",          label = "Party members",          color = { 1, 0.3, 0.9 },   enabled = true },
  { key = "raid",           label = "Raid members",           color = { 1, 0.6, 0.1 },   enabled = true },
  { key = "guild",          label = "Guild members",          color = { 0.3, 1, 0.6 },   enabled = false },
  { key = "friendlyPlayer", label = "Other friendly players", color = { 0.3, 0.6, 1 },   enabled = false },
  { key = "enemyPlayer",    label = "Enemy players",          color = { 1, 0.1, 0.1 },   enabled = false },
  { key = "friendlyNpc",    label = "Friendly NPCs",          color = { 0.2, 0.9, 0.2 }, enabled = false },
  { key = "neutralNpc",     label = "Neutral NPCs",           color = { 1, 0.9, 0.1 },   enabled = false },
  { key = "hostileNpc",     label = "Hostile NPCs",           color = { 0.9, 0.1, 0.1 }, enabled = false },
}

local REACTION_NEUTRAL = 4
ns.SIZE_MIN, ns.SIZE_MAX, ns.SIZE_STEP = 0.5, 2, 0.05

local MATCHES = {
  target = function(unit) return UnitIsUnit(unit, "target") end,
  party = function(unit) return ns.PartySlot(unit) ~= nil end,
  raid = function(unit) return IsInRaid() and UnitInRaid(unit) ~= nil end,
  guild = function(unit) return UnitIsInMyGuild ~= nil and UnitIsInMyGuild(unit) end,
  friendlyPlayer = function(unit, isPlayer) return isPlayer and UnitIsFriend("player", unit) end,
  enemyPlayer = function(unit, isPlayer) return isPlayer and UnitCanAttack("player", unit) end,
  friendlyNpc = function(_, isPlayer, reaction) return not isPlayer and reaction > REACTION_NEUTRAL end,
  neutralNpc = function(_, isPlayer, reaction) return not isPlayer and reaction == REACTION_NEUTRAL end,
  hostileNpc = function(_, isPlayer, reaction) return not isPlayer and reaction < REACTION_NEUTRAL end,
}

local defaultsByKey = {}
for _, cat in ipairs(ns.CATEGORIES) do defaultsByKey[cat.key] = cat end

-- Bars are recycled between units, so these are keyed by the bar, weak so they never pin a frame.
local gameColor = setmetatable({}, { __mode = "k" })
local ourColor = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
-- Unit frames are pooled and reused by other plates; every plate gets its size set when added,
-- so a reused frame is reset there.
local resized = setmetatable({}, { __mode = "k" })
local painting = false

local Passes, UpdatePlate, HealthBar, Paint, OnGameColor, Resize, Unresize, Pack

function ns.CategoryFor(unit)
  if not unit or UnitIsUnit(unit, "player") then return end
  local isPlayer = UnitIsPlayer(unit)
  local reaction = UnitReaction(unit, "player") or REACTION_NEUTRAL
  for _, cat in ipairs(ns.CATEGORIES) do
    if ns.db.enabled[cat.key] and MATCHES[cat.key](unit, isPlayer, reaction) then
      return cat.key
    end
  end
end

local PARTY_CHECKS = {
  { "plate", function(unit, member)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    return plate ~= nil and plate == C_NamePlate.GetNamePlateForUnit(member)
  end },
  { "UnitIsUnit", function(unit, member) return UnitIsUnit(unit, member) end },
  { "GUID", function(unit, member)
    local guid = UnitGUID(unit)
    return guid ~= nil and guid == UnitGUID(member)
  end },
}

-- Returns the party token and the name of the check that matched.
function ns.PartySlot(unit)
  if not IsInGroup() then return end
  for i = 1, 4 do
    local member = "party" .. i
    if UnitExists(member) then
      for _, check in ipairs(PARTY_CHECKS) do
        if Passes(check[2], unit, member) == true then return member, check[1] end
      end
    end
  end
end

-- The result is tested inside the pcall, so a check that errors or returns a secret value gives
-- nil ("couldn't tell") instead of aborting the caller.
function Passes(fn, ...)
  local args = { n = select("#", ...), ... }
  local ok, result = pcall(function() return fn(unpack(args, 1, args.n)) and true or false end)
  if ok then return result end
end

function ns.RefreshAll()
  for _, plate in ipairs(C_NamePlate.GetNamePlates()) do UpdatePlate(plate) end
end

function ns.Debug()
  local plates = C_NamePlate.GetNamePlates()
  print("PlateColors debug:", #plates, "plates")
  for _, plate in ipairs(plates) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    local okName, name = pcall(UnitName, unit)
    local okParty, inParty = pcall(UnitInParty, unit)
    local okKey, key = pcall(ns.CategoryFor, unit)
    local verdict = okKey and (key or "no match") or ("error: " .. tostring(key))
    print(tostring(unit), okName and tostring(name) or "name hidden", "forbidden:", tostring(plate:IsForbidden()),
      "bar:", tostring(HealthBar(plate) ~= nil), "UnitInParty:", okParty and tostring(inParty) or "hidden", verdict)
    local frame = plate.UnitFrame
    if frame then
      local size = okKey and key and ns.db.sizes[key]
      print("  size setting:", tostring(size), "frame scale:", frame:GetScale(), "frame:", math.floor(frame:GetWidth()),
        "x", math.floor(frame:GetHeight()), "plate:", math.floor(plate:GetWidth()), "x", math.floor(plate:GetHeight()),
        "resized:", tostring(resized[frame] ~= nil), "protected:", tostring(frame:IsProtected()))
    end
  end
  -- Party lines print last so they stay visible at the bottom of the chat.
  print("|cffff55ffParty:", "in group:", IsInGroup(), "in raid:", IsInRaid(), "party enabled:", tostring(ns.db.enabled.party))
  for _, plate in ipairs(plates) do
    local unit = plate.namePlateUnitToken
    local okName, name = pcall(UnitName, unit)
    for i = 1, 4 do
      local member = "party" .. i
      if okName and UnitExists(member) and Passes(function() return name == UnitName(member) end) then
        local results = {}
        for _, check in ipairs(PARTY_CHECKS) do
          local matched = Passes(check[2], unit, member)
          results[#results + 1] = check[1] .. "=" .. (matched == nil and "error" or tostring(matched))
        end
        local okKey, key = pcall(ns.CategoryFor, unit)
        print("|cffff55ff" .. member, name, unit, table.concat(results, " "),
          "category:", okKey and tostring(key) or ("error: " .. tostring(key)))
      end
    end
  end
end

function ns.ResetCategory(key)
  local default = defaultsByKey[key]
  ns.db.colors[key] = { unpack(default.color) }
  ns.db.sizes[key] = 1
  ns.db.enabled[key] = default.enabled
end

function ns.ResetAll()
  for _, cat in ipairs(ns.CATEGORIES) do ns.ResetCategory(cat.key) end
end

local function LoadDB()
  PlateColorsDB = PlateColorsDB or {}
  local db = PlateColorsDB
  db.colors = db.colors or {}
  db.enabled = db.enabled or {}
  db.sizes = db.sizes or {}
  for _, cat in ipairs(ns.CATEGORIES) do
    db.colors[cat.key] = db.colors[cat.key] or { unpack(cat.color) }
    db.sizes[cat.key] = db.sizes[cat.key] or 1
    if db.enabled[cat.key] == nil then db.enabled[cat.key] = cat.enabled end
  end
  ns.db = db
end

function UpdatePlate(plate)
  if plate:IsForbidden() then return end
  local bar = HealthBar(plate)
  if not bar then return end
  local unit = plate.namePlateUnitToken or plate.UnitFrame.unit
  -- Unit queries can return secret values the addon isn't allowed to test; those plates keep the game's color.
  local ok, key = pcall(ns.CategoryFor, unit)
  if not ok then key = nil end
  Paint(bar, key and ns.db.colors[key])
  Resize(plate.UnitFrame, plate, key and ns.db.sizes[key] or 1)
end

function HealthBar(plate)
  local frame = plate.UnitFrame
  if not frame then return end
  return frame.healthBar or frame.HealthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
end

function Paint(bar, color)
  if not hooked[bar] then
    hooksecurefunc(bar, "SetStatusBarColor", OnGameColor)
    hooked[bar] = true
  end
  local wasPainted = ourColor[bar] ~= nil
  if color and not wasPainted then gameColor[bar] = Pack(bar:GetStatusBarColor()) end
  ourColor[bar] = color
  painting = true
  if color then
    bar:SetStatusBarColor(color[1], color[2], color[3])
  elseif wasPainted and gameColor[bar] then
    local c = gameColor[bar]
    bar:SetStatusBarColor(unpack(c, 1, c.n))
  end
  painting = false
end

-- The game only re-sends a bar's color when its own choice changes, so whatever it sets is
-- remembered (to restore later) and immediately painted over while a custom color applies.
function OnGameColor(bar, ...)
  if painting then return end
  gameColor[bar] = Pack(...)
  local color = ourColor[bar]
  if not color then return end
  painting = true
  bar:SetStatusBarColor(color[1], color[2], color[3])
  painting = false
end

-- The unit frame is scaled instead of the plate, which is protected in combat, and re-centered
-- so it grows in every direction.
function Resize(frame, plate, size)
  if size == 1 then
    Unresize(frame)
    return
  end
  resized[frame] = true
  frame:SetScale(size)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", plate)
  frame:SetSize(plate:GetSize())
end

-- Mirrors the game's own layout from NamePlateBaseMixin:AcquireUnitFrame, which never sets a scale.
function Unresize(frame)
  if not resized[frame] then return end
  resized[frame] = nil
  frame:SetScale(1)
  frame:ClearAllPoints()
  frame:SetAllPoints(frame:GetParent())
end

local events = CreateFrame("Frame")
for _, event in ipairs({
  "ADDON_LOADED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
  "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_GUILD_UPDATE", "UNIT_FACTION",
}) do
  events:RegisterEvent(event)
end

events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    LoadDB()
    ns.CreateOptions()
    return
  end
  if not ns.db then return end
  if event == "GROUP_ROSTER_UPDATE" then
    -- Refreshes now (below) and again once the new party tokens have settled.
    C_Timer.After(1, ns.RefreshAll)
  end
  if event == "NAME_PLATE_UNIT_ADDED" then
    local plate = C_NamePlate.GetNamePlateForUnit(arg1)
    if plate then UpdatePlate(plate) end
    return
  end
  if event == "NAME_PLATE_UNIT_REMOVED" then
    local plate = C_NamePlate.GetNamePlateForUnit(arg1)
    if not plate or plate:IsForbidden() then return end
    local bar = HealthBar(plate)
    if bar then Paint(bar, nil) end

    return
  end
  ns.RefreshAll()
end)

function Pack(...)
  return { n = select("#", ...), ... }
end
