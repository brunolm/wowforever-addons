local _, ns = ...

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 1040, 560
local ROW_H = 18
local NAME_W, LEVEL_W, SHARABLE_W, CELL_W, BUTTON_W = 240, 64, 76, 92, 60
local ACTIONS_W = 3 * BUTTON_W
local LIST_TOP, LIST_BOTTOM = 84, 40
local POOL = math.ceil((HEIGHT - LIST_TOP - LIST_BOTTOM) / ROW_H) + 1
local MAX_COLUMNS = 5
local ZONE_ROWS = 16
local TAB_W = 116
local TABS = {
  { key = "share", label = "Share from me" },
  { key = "active", label = "In progress" },
  { key = "done", label = "Party completed" },
  { key = "mine", label = "My completed" },
}

-- `levels` is { min, max } when the search text is a level ("25") or a range ("20-25").
local state = { tab = "share", zone = nil, shareOnly = false, query = "", levels = nil }
local frame, scroll, content, header, emptyText, statusText, shareAllButton, zoneButton, zonePopup
local tabButtons, rowPool, list, columns, zones, shareable = {}, {}, {}, {}, {}, {}

local Build, BuildToolbar, BuildHeader, BuildList, BuildFooter, BuildZonePopup
local Collect, CollectIds, MergeByName, MakeRows, CompletedCount, Filter, Matches, Render, RenderVisible, FillHeader
local CreateRow, FillRow, CellX, ShowZonePopup, UpdateStatus, ShareAll, RowButton, ParseLevels
local Tooltip = ns.Tooltip

function UI.Toggle()
  Build()
  frame:SetShown(not frame:IsShown())
  if frame:IsShown() then
    ns.Comm.Hello()
    UI.Refresh()
  end
end

-- Questie's party data arrives without an event, so refresh every few seconds while the window is open.
local refresher
local function StartRefresher()
  refresher = refresher or C_Timer.NewTicker(5, ns.Changed)
end
local function StopRefresher()
  if refresher then refresher:Cancel() end
  refresher = nil
end

function UI.Refresh()
  if not (frame and frame:IsShown()) then return end
  Collect()
  Render()
end

function Build()
  if frame then return end
  frame = CreateFrame("Frame", "PartyQuestsFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnShow", StartRefresher)
  frame:SetScript("OnHide", function()
    StopRefresher()
    if zonePopup then zonePopup:Hide() end
  end)
  frame:Hide()
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOP", 0, -5)
  frame.title:SetText("PartyQuests")
  tinsert(UISpecialFrames, "PartyQuestsFrame")
  BuildToolbar()
  BuildHeader()
  BuildList()
  BuildFooter()
  BuildZonePopup()
end

function BuildToolbar()
  for i, tab in ipairs(TABS) do
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(TAB_W - 4, 22)
    button:SetPoint("TOPLEFT", 12 + (i - 1) * TAB_W, -30)
    button:SetText(tab.label)
    button:SetScript("OnClick", function()
      state.tab, state.zone = tab.key, nil
      scroll:SetVerticalScroll(0)
      UI.Refresh()
    end)
    tabButtons[tab.key] = button
  end

  zoneButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  zoneButton:SetSize(170, 22)
  zoneButton:SetPoint("TOPLEFT", 12 + #TABS * TAB_W + 4, -30)
  zoneButton:SetScript("OnClick", function() ShowZonePopup(not zonePopup:IsShown()) end)

  local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  check:SetSize(24, 24)
  check:SetPoint("LEFT", zoneButton, "RIGHT", 10, 0)
  check:SetScript("OnClick", function(self)
    state.shareOnly = self:GetChecked()
    UI.Refresh()
  end)
  check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
  check.label:SetText("Only sharable")
  frame.shareOnly = check

  -- The template's own OnTextChanged shows its hint text and clear button, so hook it rather than replace it.
  local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
  search:SetSize(150, 20)
  search:SetPoint("TOPRIGHT", -16, -31)
  if type(search.Instructions) == "table" then search.Instructions:SetText("Name, zone or level") end
  search:HookScript("OnTextChanged", function(self)
    state.query = strtrim(self:GetText()):lower()
    state.levels = ParseLevels(state.query)
    UI.Refresh()
  end)
  search:HookScript("OnEnter", function(self)
    Tooltip(self, "Search", "Matches quest or zone names. A number matches the quest level: 25, or a range like 20-25.")
  end)
  search:HookScript("OnLeave", GameTooltip_Hide)
end

function ParseLevels(query)
  local low, high = query:match("^(%d+)%s*%-%s*(%d+)$")
  if low then return { math.min(tonumber(low), tonumber(high)), math.max(tonumber(low), tonumber(high)) } end
  local level = tonumber(query:match("^(%d+)$") or "")
  return level and { level, level } or nil
end

function BuildHeader()
  header = CreateFrame("Frame", nil, frame)
  header:SetSize(WIDTH - 50, ROW_H)
  header:SetPoint("TOPLEFT", 16, -60)
  local function label(justify)
    local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetJustifyH(justify)
    text:SetWordWrap(false)
    return text
  end
  header.name = label("LEFT")
  header.name:SetPoint("LEFT", 0, 0)
  header.name:SetWidth(NAME_W - 6)
  header.name:SetText("Quest")
  header.level = label("CENTER")
  header.level:SetPoint("LEFT", NAME_W, 0)
  header.level:SetWidth(LEVEL_W)
  header.level:SetText("Level")
  header.sharable = label("CENTER")
  header.sharable:SetPoint("LEFT", NAME_W + LEVEL_W, 0)
  header.sharable:SetWidth(SHARABLE_W)
  header.sharable:SetText("Sharable")
  header.cells = {}
  for i = 1, MAX_COLUMNS do
    header.cells[i] = label("CENTER")
    header.cells[i]:SetWidth(CELL_W - 4)
  end
  local line = header:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 0.15)
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", 0, -3)
  line:SetPoint("BOTTOMRIGHT", 0, -3)
end

function BuildList()
  scroll = CreateFrame("ScrollFrame", "PartyQuestsScrollFrame", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -LIST_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -32, LIST_BOTTOM)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(WIDTH - 50, 1)
  scroll:SetScrollChild(content)
  scroll:HookScript("OnVerticalScroll", function() RenderVisible() end)
  for i = 1, POOL do rowPool[i] = CreateRow() end
  emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("TOP", scroll, "TOP", 0, -40)
  emptyText:SetWidth(WIDTH - 120)
end

function BuildFooter()
  statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusText:SetPoint("BOTTOMLEFT", 16, 16)
  statusText:SetPoint("RIGHT", -260, 0)
  statusText:SetJustifyH("LEFT")
  statusText:SetWordWrap(false)

  local sync = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  sync:SetSize(80, 22)
  sync:SetPoint("BOTTOMRIGHT", -12, 10)
  sync:SetText("Sync")
  sync:SetScript("OnClick", function() ns.Comm.Hello(true) end)
  sync:SetScript("OnEnter", function(self) Tooltip(self, "Ask the party for their quest logs again") end)
  sync:SetScript("OnLeave", GameTooltip_Hide)

  shareAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  shareAllButton:SetSize(140, 22)
  shareAllButton:SetPoint("RIGHT", sync, "LEFT", -6, 0)
  shareAllButton:SetText("Share all I can")
  shareAllButton:SetScript("OnClick", ShareAll)
end

function BuildZonePopup()
  zonePopup = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  zonePopup:SetSize(220, ZONE_ROWS * ROW_H + 10)
  zonePopup:SetPoint("TOPLEFT", zoneButton, "BOTTOMLEFT", 0, -2)
  zonePopup:SetFrameLevel(frame:GetFrameLevel() + 20)
  zonePopup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  zonePopup:SetBackdropColor(0.05, 0.06, 0.08, 0.97)
  zonePopup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  zonePopup:EnableMouseWheel(true)
  zonePopup.offset = 0
  zonePopup:SetScript("OnMouseWheel", function(self, delta)
    self.offset = math.max(0, math.min(#zones + 1 - ZONE_ROWS, self.offset - delta * 3))
    ShowZonePopup(true)
  end)
  zonePopup.buttons = {}
  for i = 1, ZONE_ROWS do
    local button = CreateFrame("Button", nil, zonePopup)
    button:SetSize(210, ROW_H)
    button:SetPoint("TOPLEFT", 5, -5 - (i - 1) * ROW_H)
    button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("LEFT", 4, 0)
    button.text:SetPoint("RIGHT", -4, 0)
    button.text:SetJustifyH("LEFT")
    button:SetScript("OnClick", function(self)
      state.zone = self.zone
      ShowZonePopup(false)
      scroll:SetVerticalScroll(0)
      UI.Refresh()
    end)
    zonePopup.buttons[i] = button
  end
  zonePopup:Hide()
end

function ShowZonePopup(show)
  if not show then
    zonePopup:Hide()
    return
  end
  local entries = { false }
  for _, zone in ipairs(zones) do entries[#entries + 1] = zone end
  for i, button in ipairs(zonePopup.buttons) do
    local zone = entries[zonePopup.offset + i]
    button.zone = zone or nil
    button.text:SetText(zone == false and "All zones" or zone or "")
    button:SetShown(zone ~= nil)
  end
  zonePopup:SetHeight(math.min(#entries, ZONE_ROWS) * ROW_H + 10)
  zonePopup:Show()
end

-- Builds `columns` (the members shown), `zones` (for the picker) and `list` (zone headers and quest rows).
function Collect()
  local members = ns.Members()
  if state.tab == "share" or state.tab == "mine" then
    columns = {}
    for i = 2, #members do columns[#columns + 1] = members[i] end
  else
    columns = members
  end
  while #columns > MAX_COLUMNS do table.remove(columns) end
  local rows = MakeRows(CollectIds(members), members)
  local zoneSet = {}
  for _, row in ipairs(rows) do zoneSet[row.zone] = true end
  zones = ns.SortedKeys(zoneSet)
  if state.zone and not zoneSet[state.zone] then state.zone = nil end
  list = Filter(rows)
end

-- Groups of quest IDs, one per row. Completed quests merge by name: a repeatable gets a new ID each time.
function CollectIds(members)
  local groups = {}
  if state.tab == "share" then
    for _, id in ipairs(ns.SortedKeys(members[1].active)) do groups[#groups + 1] = { id } end
  elseif state.tab == "active" then
    local all = {}
    for _, m in ipairs(members) do
      for id in pairs(m.active) do all[id] = true end
    end
    for _, id in ipairs(ns.SortedKeys(all)) do groups[#groups + 1] = { id } end
  elseif state.tab == "mine" then
    groups = MergeByName({ members[1] })
  else
    local known = {}
    for _, m in ipairs(columns) do
      if m.completed then known[#known + 1] = m end
    end
    if #known < 2 then return groups end
    for _, ids in ipairs(MergeByName(known)) do
      local everyone = true
      for _, m in ipairs(known) do everyone = everyone and CompletedCount(m, ids) > 0 end
      if not everyone then groups[#groups + 1] = ids end
    end
  end
  return groups
end

-- The members' completed quest IDs grouped by quest name.
function MergeByName(members)
  local byName, order = {}, {}
  for _, m in ipairs(members) do
    for id in pairs(m.completed or {}) do
      local name = ns.QuestTitle(id)
      if not byName[name] then
        byName[name] = {}
        order[#order + 1] = name
      end
      if not tContains(byName[name], id) then table.insert(byName[name], id) end
    end
  end
  local groups = {}
  for i, name in ipairs(order) do groups[i] = byName[name] end
  return groups
end

function MakeRows(groups, members)
  local rows = {}
  for _, ids in ipairs(groups) do
    local id = ids[1]
    local row = { ids = ids, id = id, name = ns.QuestTitle(id), zone = ns.QuestZone(id, members), cells = {} }
    if state.tab == "mine" then
      local times = CompletedCount(members[1], ids)
      row.label = times > 1 and ("%s |cff808080x%d|r"):format(row.name, times) or row.name
    end
    for i, m in ipairs(columns) do
      local cell
      if state.tab == "share" then
        cell = ns.ShareStatus(id, m)
        row.canShare = row.canShare or cell.share
      elseif state.tab == "active" then
        cell = ns.Status(id, m)
        if cell.kind == "ok" then cell = { kind = "neutral", text = cell.text, tip = cell.tip } end
      else
        local count = CompletedCount(m, ids)
        if count > 0 then
          cell = { kind = "done", text = count > 1 and ("done x" .. count) or "done" }
        elseif state.tab == "done" and m.completed and not ns.OnQuest(m, id) then
          cell = { kind = "unknown", text = "-" }
        else
          cell = ns.Status(id, m)
        end
      end
      row.cells[i] = cell
    end
    rows[#rows + 1] = row
  end
  return rows
end

function CompletedCount(m, ids)
  local count = 0
  for _, id in ipairs(ids) do
    if m.completed and m.completed[id] then count = count + 1 end
  end
  return count
end

-- Applies the zone, search and share-only filters, sorts by zone then name, and inserts zone headers.
function Filter(rows)
  local kept = {}
  for _, row in ipairs(rows) do
    if Matches(row) and (not state.zone or row.zone == state.zone) and not (state.shareOnly and state.tab == "share" and not row.canShare) then
      kept[#kept + 1] = row
    end
  end
  table.sort(kept, function(a, b)
    if a.zone ~= b.zone then return a.zone < b.zone end
    return a.name < b.name
  end)
  local out, zone = {}, nil
  for _, row in ipairs(kept) do
    if row.zone ~= zone then
      zone = row.zone
      out[#out + 1] = { header = zone }
    end
    out[#out + 1] = row
  end
  return out
end

-- A level search matches the quest level (QuestieDB); anything else matches quest or zone names.
function Matches(row)
  if state.levels then
    local q = ns.QuestData(row.id)
    return q ~= nil and q.lvl >= state.levels[1] and q.lvl <= state.levels[2]
  end
  return state.query == "" or row.name:lower():find(state.query, 1, true) or row.zone:lower():find(state.query, 1, true)
end

function Render()
  for key, button in pairs(tabButtons) do
    if key == state.tab then button:LockHighlight() else button:UnlockHighlight() end
  end
  zoneButton:SetText("Zone: " .. (state.zone or "All zones"))
  frame.shareOnly:SetShown(state.tab == "share")
  frame.shareOnly:SetChecked(state.shareOnly)
  FillHeader()
  shareable = {}
  for _, row in ipairs(list) do
    if row.canShare and ns.IsSharable(row.id) ~= false then shareable[#shareable + 1] = row.id end
  end
  shareAllButton:SetShown(state.tab == "share")
  shareAllButton:SetEnabled(#shareable > 0 and not InCombatLockdown())
  content:SetHeight(math.max(1, #list * ROW_H))
  local maxScroll = math.max(0, #list * ROW_H - scroll:GetHeight())
  if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end
  scroll:UpdateScrollChildRect()
  RenderVisible()
  local empty = #list == 0
  emptyText:SetShown(empty)
  if empty then
    local known = 0
    for _, m in ipairs(columns) do
      if m.completed then known = known + 1 end
    end
    if state.tab == "done" and known < 2 then
      emptyText:SetText("Completed quests need a party member with PartyQuests. Questie doesn't share completed quests.")
    elseif state.tab == "mine" and not next(ns.OwnCompleted()) then
      emptyText:SetText("No completed quests yet.")
    elseif state.tab == "share" and not IsInGroup() then
      emptyText:SetText("Join a party to compare quests. Quest names still open their chain.")
    else
      emptyText:SetText("No quests match.")
    end
  end
  UpdateStatus()
end

function FillHeader()
  header.sharable:SetShown(state.tab == "share")
  for i, text in ipairs(header.cells) do
    local m = columns[i]
    text:ClearAllPoints()
    text:SetPoint("LEFT", CellX(i) + 2, 0)
    text:SetText(m and ("|c%s%s|r"):format(ns.ClassColor(m), m.name) or "")
  end
end

function RenderVisible()
  local first = math.floor(scroll:GetVerticalScroll() / ROW_H) + 1
  for i, row in ipairs(rowPool) do
    local index = first + i - 1
    local item = list[index]
    if item then
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_H)
      FillRow(row, item, index)
      row:Show()
    else
      row:Hide()
    end
  end
end

function CellX(i)
  return NAME_W + LEVEL_W + (state.tab == "share" and SHARABLE_W + ACTIONS_W or 0) + (i - 1) * CELL_W
end

function CreateRow()
  local row = CreateFrame("Frame", nil, content)
  row:SetSize(WIDTH - 50, ROW_H)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.zone:SetPoint("LEFT", 4, -2)

  row.name = CreateFrame("Button", nil, row)
  row.name:SetSize(NAME_W - 6, ROW_H)
  row.name:SetPoint("LEFT", 4, 0)
  row.name.text = row.name:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name.text:SetAllPoints()
  row.name.text:SetJustifyH("LEFT")
  row.name.text:SetWordWrap(false)
  row.name:SetScript("OnClick", function(self) ns.Chain.Open(self.questID) end)
  row.name:SetScript("OnEnter", function(self)
    self.text:SetTextColor(1, 0.82, 0)
    ns.QuestTooltip(self, self.questID, ns.Member("player", true), "Click to see the quest chain")
  end)
  row.name:SetScript("OnLeave", function(self)
    self.text:SetTextColor(1, 1, 1)
    GameTooltip_Hide()
  end)

  row.level = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.level:SetPoint("LEFT", NAME_W, 0)
  row.level:SetWidth(LEVEL_W)
  row.sharable = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.sharable:SetPoint("LEFT", NAME_W + LEVEL_W, 0)
  row.sharable:SetWidth(SHARABLE_W)

  row.cells = {}
  for i = 1, MAX_COLUMNS do
    local cell = CreateFrame("Frame", nil, row)
    cell:SetSize(CELL_W - 4, ROW_H)
    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.text:SetAllPoints()
    cell.text:SetWordWrap(false)
    cell:SetScript("OnEnter", function(self) if self.tip then Tooltip(self, self.tip) end end)
    cell:SetScript("OnLeave", GameTooltip_Hide)
    row.cells[i] = cell
  end

  row.share = RowButton(row, "Share", 0, ns.ShareQuest, ns.ShareButtonTip)
  row.track = RowButton(row, "Track", 1, ns.TrackQuest, ns.TrackButtonTip)
  row.map = RowButton(row, "Map", 2, ns.ShowQuestOnMap, ns.MapButtonTip)
  return row
end

--- A small button in the actions column (after Sharable) of the Share tab; `slot` counts from 0.
function RowButton(row, text, slot, onClick, tip)
  local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  button:SetSize(BUTTON_W - 6, ROW_H - 2)
  button:SetText(text)
  button:SetNormalFontObject("GameFontNormalSmall")
  button:SetHighlightFontObject("GameFontHighlightSmall")
  button:SetDisabledFontObject("GameFontDisableSmall")
  button:SetPoint("LEFT", NAME_W + LEVEL_W + SHARABLE_W + 3 + slot * BUTTON_W, 0)
  button:SetMotionScriptsWhileDisabled(true)
  button:SetScript("OnClick", function(self) onClick(self.questID) end)
  button:SetScript("OnEnter", function(self) Tooltip(self, tip(self)) end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  return button
end

function FillRow(row, item, index)
  local isHeader = item.header ~= nil
  row.zone:SetShown(isHeader)
  row.name:SetShown(not isHeader)
  row.level:SetShown(not isHeader)
  row.sharable:SetShown(not isHeader and state.tab == "share")
  row.bg:SetColorTexture(1, 1, 1, (not isHeader and index % 2 == 0) and 0.04 or 0)
  if isHeader then
    row.zone:SetText(item.header)
    for _, cell in ipairs(row.cells) do cell:Hide() end
    row.share:Hide()
    row.track:Hide()
    row.map:Hide()
    return
  end
  row.name.questID = item.id
  row.name.text:SetText(item.label or item.name)
  row.level:SetText(ns.LevelText(item.id))
  local sharable = ns.IsSharable(item.id)
  row.sharable:SetText(sharable == nil and "|cff808080?|r" or sharable and "|cff1eff00yes|r" or "|cff808080no|r")
  for i, cell in ipairs(row.cells) do
    local status = item.cells[i]
    cell:SetShown(status ~= nil)
    if status then
      cell:ClearAllPoints()
      cell:SetPoint("LEFT", CellX(i), 0)
      cell.text:SetText(ns.Colorize(status))
      cell.tip = status.tip
    end
  end
  local actions = state.tab == "share"
  row.share:SetShown(actions and sharable ~= false)
  row.share:SetEnabled(ns.CanShare(item.id))
  row.track:SetShown(actions)
  row.track:SetEnabled(ns.CanTrack())
  row.map:SetShown(actions)
  for _, button in ipairs({ row.share, row.track, row.map }) do button.questID = item.id end
end

function UpdateStatus()
  if not IsInGroup() then
    statusText:SetText("Not in a group: only your own quests are shown.")
    return
  end
  local parts = {}
  for i, m in ipairs(ns.Members()) do
    if i > 1 then
      local sync = m.source == "partyquests" and (m.completed and "|cff8fd18fsynced|r" or "|cffb0b0b0log only|r")
        or m.source == "questie" and "|cffb0b0b0Questie (log only)|r" or "|cff808080no data|r"
      parts[#parts + 1] = ("|c%s%s|r %s"):format(ns.ClassColor(m), m.name, sync)
    end
  end
  statusText:SetText(table.concat(parts, "   "))
end

-- Shares one quest per second; the game throttles quest sharing.
function ShareAll()
  local ids = { unpack(shareable) }
  local i = 0
  C_Timer.NewTicker(1, function(ticker)
    i = i + 1
    if not ids[i] or InCombatLockdown() then
      ticker:Cancel()
      return
    end
    ns.ShareQuest(ids[i])
  end, #ids)
end
