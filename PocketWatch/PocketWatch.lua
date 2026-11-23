local ADDON, ns = ...

local TICK = 0.1
ns.DEFAULT_COLORS = {
  running = { 1, 0.8, 0, 0.9 },
  paused = { 0.65, 0.65, 0.65, 0.9 },
  border = { 1, 0.8, 0, 0.8 },
  background = { 0, 0, 0, 0.4 },
}

local db, frame, text
-- GetTime() when the current run began; db.elapsed holds the time banked before it.
local runStart
local sinceTick = 0

local function Elapsed()
  if db.running then
    return db.elapsed + (GetTime() - runStart)
  end
  return db.elapsed
end

local function Format(seconds)
  local tenths = math.floor(seconds * 10)
  local h = math.floor(tenths / 36000)
  local m = math.floor(tenths / 600) % 60
  local s = (tenths % 600) / 10
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, math.floor(s))
  end
  return string.format("%02d:%04.1f", m, s)
end

local function Refresh()
  text:SetText(Format(Elapsed()))
  local color = (db.running or db.elapsed == 0) and db.colors.running or db.colors.paused
  text:SetTextColor(unpack(color))
end

function ns.ApplyColors()
  frame:SetBackdropColor(unpack(db.colors.background))
  frame:SetBackdropBorderColor(unpack(db.colors.border))
  Refresh()
end

local function OnUpdate(_, dt)
  sinceTick = sinceTick + dt
  if sinceTick < TICK then
    return
  end
  sinceTick = 0
  Refresh()
end

local function Start()
  if db.running then
    return
  end
  runStart = GetTime()
  db.running = true
  frame:SetScript("OnUpdate", OnUpdate)
  Refresh()
end

local function Pause()
  if not db.running then
    return
  end
  db.elapsed = Elapsed()
  db.running = false
  frame:SetScript("OnUpdate", nil)
  Refresh()
end

local function Reset()
  db.elapsed = 0
  db.running = false
  frame:SetScript("OnUpdate", nil)
  Refresh()
end

local function Toggle()
  if db.running then
    Pause()
  else
    Start()
  end
end

local function PlaceFrame()
  frame:ClearAllPoints()
  if db.pos then
    frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
    return
  end
  frame:SetPoint("TOP", TomTomBlock or Minimap, "BOTTOM", 0, -4)
end

local function SavePosition()
  local point, _, relPoint, x, y = frame:GetPoint()
  db.pos = { point, relPoint, x, y }
end

local function SetShown(shown)
  db.hidden = not shown
  frame:SetShown(shown)
end

local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:AddLine("PocketWatch")
  GameTooltip:AddLine("Left-click: start / pause", 1, 1, 1)
  GameTooltip:AddLine("Right-click: stop and reset", 1, 1, 1)
  GameTooltip:AddLine("Drag: move", 1, 1, 1)
  GameTooltip:AddLine("/pw options for colors, /pw help for commands", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

local function CreateWatch()
  frame = CreateFrame("Button", "PocketWatchFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(120, 32)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:RegisterForDrag("LeftButton")
  frame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })

  text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("CENTER")

  -- A drag ends with a mouse-up that may still fire OnClick; the flag keeps a move from also toggling the watch.
  frame:SetScript("OnMouseDown", function(self) self.dragged = false end)
  frame:SetScript("OnDragStart", function(self)
    self.dragged = true
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)
  frame:SetScript("OnClick", function(self, button)
    if self.dragged then
      return
    end
    if button == "RightButton" then
      Reset()
    else
      Toggle()
    end
  end)
  frame:SetScript("OnEnter", ShowTooltip)
  frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function LoadSettings()
  PocketWatchDB = PocketWatchDB or { elapsed = 0, running = false }
  db = PocketWatchDB
  db.colors = db.colors or {}
  for key, color in pairs(ns.DEFAULT_COLORS) do
    db.colors[key] = db.colors[key] or CopyTable(color)
  end
  ns.db = db
end

local function Restore()
  if db.running then
    -- Real time keeps counting across /reload and logout, like a real stopwatch.
    db.elapsed = db.elapsed + math.max(0, time() - (db.savedAt or time()))
    runStart = GetTime()
    frame:SetScript("OnUpdate", OnUpdate)
  end
  frame:SetShown(not db.hidden)
  ns.ApplyColors()
  PlaceFrame()
  if not db.pos then
    -- TomTom builds its coordinate box on PLAYER_ENTERING_WORLD, after this runs, so re-anchor under it once it exists.
    C_Timer.After(1, PlaceFrame)
  end
end

local COMMANDS = {
  start = Start,
  pause = Pause,
  reset = Reset,
  toggle = Toggle,
  show = function() SetShown(true) end,
  hide = function() SetShown(false) end,
  resetpos = function()
    db.pos = nil
    PlaceFrame()
  end,
  options = function() ns.OpenOptions() end,
}

local function OnSlash(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "" then
    SetShown(not frame:IsShown())
    return
  end
  local command = COMMANDS[msg]
  if not command then
    print("|cffffcc00PocketWatch|r: /pw [start | pause | reset | toggle | show | hide | resetpos | options]")
    return
  end
  command()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, name)
  if event == "PLAYER_LOGOUT" then
    db.elapsed = Elapsed()
    db.savedAt = time()
    return
  end
  if name ~= ADDON then
    return
  end
  LoadSettings()
  CreateWatch()
  Restore()
  ns.CreateOptions()
  SLASH_POCKETWATCH1 = "/pw"
  SLASH_POCKETWATCH2 = "/pocketwatch"
  SlashCmdList.POCKETWATCH = OnSlash
end)
