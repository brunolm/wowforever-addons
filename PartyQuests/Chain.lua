local _, ns = ...

local Chain = {}
ns.Chain = Chain

local WIDTH, HEIGHT = 960, 620
local NODE_W, NODE_H, GAP, ROW_GAP, LABEL_H = 220, 54, 10, 18, 18
local PER_ROW = 4
local DEPTH, MAX_NODES = 15, 40
local CONTENT_W = WIDTH - 60

local frame, scroll, content, info
local forButtons, actionButtons, nodePool, linePool, labelPool = {}, {}, {}, {}, {}
local links, questID, forGuid

local Build, ActionButton, Links, Walk, Rows, Render, UpdateActions, PlaceRow, Node, Line, Label, InfoText

--- Opens the chain window on a quest. Needs QuestieDB for prerequisites and follow-ups.
function Chain.Open(id)
  if not id then return end
  Build()
  questID = id
  frame:Show()
  frame:Raise()
  Render()
end

function Chain.Refresh()
  if frame and frame:IsShown() then Render() end
end

function Build()
  if frame then return end
  frame = CreateFrame("Frame", "PartyQuestsChainFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER", 30, -20)
  frame:SetFrameStrata("DIALOG")
  frame:SetFrameLevel(50)
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOPLEFT", 40, -5)
  frame.title:SetPoint("TOPRIGHT", -40, -5)
  frame.title:SetWordWrap(false)
  tinsert(UISpecialFrames, "PartyQuestsChainFrame")

  local forLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  forLabel:SetPoint("TOPLEFT", 16, -34)
  forLabel:SetText("For:")
  for i = 1, 5 do
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(120, 20)
    button:SetPoint("LEFT", forLabel, "RIGHT", 8 + (i - 1) * 124, 0)
    button:SetScript("OnClick", function(self)
      forGuid = self.guid
      Render()
    end)
    forButtons[i] = button
  end
  actionButtons.map = ActionButton("Map", 0, ns.ShowQuestOnMap, ns.MapButtonTip)
  actionButtons.track = ActionButton("Track", 1, ns.TrackQuest, ns.TrackButtonTip)
  actionButtons.share = ActionButton("Share", 2, ns.ShareQuest, ns.ShareButtonTip)

  info =frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info:SetPoint("TOPLEFT", 16, -60)
  info:SetWidth(WIDTH - 32)
  info:SetJustifyH("LEFT")
  info:SetSpacing(3)

  scroll = CreateFrame("ScrollFrame", "PartyQuestsChainScrollFrame", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -150)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(CONTENT_W, 1)
  scroll:SetScrollChild(content)
end

--- A button for the quest at the center of the chain, on the For row; `slot` counts from the right.
function ActionButton(text, slot, onClick, tip)
  local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  button:SetSize(70, 20)
  button:SetPoint("TOPRIGHT", -16 - slot * 74, -30)
  button:SetText(text)
  button:SetMotionScriptsWhileDisabled(true)
  button:SetScript("OnClick", function() onClick(questID) end)
  button:SetScript("OnEnter", function(self)
    self.questID = questID
    ns.Tooltip(self, tip(self))
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  return button
end

function Render()
  local members = ns.Members()
  local m = members[1]
  for _, member in ipairs(members) do
    if member.guid == forGuid then m = member end
  end
  forGuid = m.guid
  for i, button in ipairs(forButtons) do
    local member = members[i]
    button:SetShown(member ~= nil)
    if member then
      button.guid = member.guid
      button:SetText(("|c%s%s|r"):format(ns.ClassColor(member), member.name))
      if member.guid == forGuid then button:LockHighlight() else button:UnlockHighlight() end
    end
  end

  frame.title:SetText(("%s  |cffaaaaaa%s · level %s · #%d|r"):format(ns.QuestTitle(questID), ns.QuestZone(questID, members),
    ns.LevelText(questID), questID))
  UpdateActions()
  info:SetText(InfoText(questID, m, members))
  scroll:ClearAllPoints()
  scroll:SetPoint("TOPLEFT", 12, -(68 + info:GetStringHeight() + 10))
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)

  for _, pool in ipairs({ nodePool, linePool, labelPool }) do
    for _, item in ipairs(pool) do item:Hide() end
    pool.used = 0
  end
  local y = 0
  local before = Rows(Walk(questID, function(id) return ns.SortedKeys(Links().before[id]) end), true)
  local after = Rows(Walk(questID, function(id) return ns.SortedKeys(Links().after[id]) end), false)
  y = Label(y, #before > 0 and "Before" or "No earlier quests")
  for _, row in ipairs(before) do y = Line(PlaceRow(row, y, m)) end
  y = PlaceRow({ questID }, y, m)
  for _, row in ipairs(after) do y = PlaceRow(row, Line(y), m) end
  y = Label(y, #after > 0 and "After" or "No follow-up quests")
  content:SetHeight(y + 10)
  scroll:SetVerticalScroll(0)
  scroll:UpdateScrollChildRect()
end

function UpdateActions()
  actionButtons.share:SetEnabled(ns.CanShare(questID))
  actionButtons.track:SetEnabled(ns.CanTrack())
end

--- Links between all QuestieDB quests, built once: prerequisites, nextQuestInChain and breadcrumbs.
function Links()
  if links then return links end
  links = { before = {}, after = {} }
  local db = _G.QuestDB
  local ok, ids = false, nil
  if db and db.GetAllIds then ok, ids = pcall(db.GetAllIds) end
  if not ok or type(ids) ~= "table" then return links end
  local function link(from, to)
    links.after[from] = links.after[from] or {}
    links.after[from][to] = true
    links.before[to] = links.before[to] or {}
    links.before[to][from] = true
  end
  for key, value in pairs(ids) do
    local id = type(value) == "number" and value or key
    local q = ns.QuestData(id)
    if q then
      for _, p in ipairs(q.preS) do link(p, id) end
      for _, p in ipairs(q.preG) do link(p, id) end
      if q.next > 0 then link(id, q.next) end
      if q.breadcrumbFor > 0 then link(id, q.breadcrumbFor) end
    end
  end
  return links
end

--- Breadth-first distances from `start`, capped by depth and node count.
function Walk(start, nextOf)
  local dist, queue, head, count = { [start] = 0 }, { start }, 1, 0
  while head <= #queue and count < MAX_NODES do
    local id = queue[head]
    head = head + 1
    if dist[id] < DEPTH then
      for _, n in ipairs(nextOf(id)) do
        if dist[n] == nil then
          dist[n] = dist[id] + 1
          queue[#queue + 1] = n
          count = count + 1
        end
      end
    end
  end
  dist[start] = nil
  return dist
end

--- Quest IDs grouped by distance; earlier quests come farthest first.
function Rows(dist, farthestFirst)
  local byDistance = {}
  for id, d in pairs(dist) do
    byDistance[d] = byDistance[d] or {}
    table.insert(byDistance[d], id)
  end
  local rows = {}
  for _, d in ipairs(ns.SortedKeys(byDistance)) do
    table.sort(byDistance[d])
    table.insert(rows, farthestFirst and 1 or #rows + 1, byDistance[d])
  end
  return rows
end

function PlaceRow(ids, y, m)
  local shown = math.min(#ids, PER_ROW)
  local more = #ids - shown
  local width = shown * NODE_W + (shown - 1) * GAP
  local x = (CONTENT_W - width) / 2
  for i = 1, shown do Node(ids[i], x + (i - 1) * (NODE_W + GAP), y, m) end
  if more > 0 then
    local text = Label(y + NODE_H / 2 - LABEL_H / 2, "+" .. more .. " more", true)
    local last = labelPool[labelPool.used]
    last:ClearAllPoints()
    last:SetPoint("TOPLEFT", content, "TOPLEFT", x + width + GAP, -(y + NODE_H / 2 - LABEL_H / 2))
    return math.max(text, y + NODE_H)
  end
  return y + NODE_H
end

function Node(id, x, y, m)
  nodePool.used = nodePool.used + 1
  local node = nodePool[nodePool.used]
  if not node then
    node = CreateFrame("Button", nil, content, "BackdropTemplate")
    node:SetSize(NODE_W, NODE_H)
    node:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    node.title = node:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    node.title:SetPoint("TOPLEFT", 6, -5)
    node.title:SetPoint("RIGHT", -6, 0)
    node.title:SetJustifyH("LEFT")
    node.title:SetWordWrap(false)
    node.meta = node:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    node.meta:SetPoint("TOPLEFT", node.title, "BOTTOMLEFT", 0, -3)
    node.meta:SetPoint("RIGHT", -6, 0)
    node.meta:SetJustifyH("LEFT")
    node.meta:SetWordWrap(false)
    node.status = node:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    node.status:SetPoint("TOPLEFT", node.meta, "BOTTOMLEFT", 0, -3)
    node.status:SetJustifyH("LEFT")
    node:SetScript("OnClick", function(self) Chain.Open(self.questID) end)
    node:SetScript("OnEnter", function(self)
      self:SetBackdropBorderColor(1, 0.82, 0, 1)
      ns.QuestTooltip(self, self.questID, self.member, "Click to center the chain on this quest")
    end)
    node:SetScript("OnLeave", function(self)
      self:SetBackdropBorderColor(unpack(self.border))
      GameTooltip_Hide()
    end)
    nodePool[nodePool.used] = node
  end
  local q = ns.QuestData(id)
  local status = ns.Status(id, m)
  local sharable = ns.IsSharable(id)
  node.questID = id
  node.member = m
  node.border = id == questID and { 1, 0.82, 0, 1 } or { 0.3, 0.32, 0.36, 1 }
  node:SetBackdropColor(0.1, 0.11, 0.14, 0.95)
  node:SetBackdropBorderColor(unpack(node.border))
  node.title:SetText(ns.QuestTitle(id))
  local meta = { ns.QuestZone(id), "level " .. ns.LevelText(id) }
  if q and q.breadcrumbFor > 0 then meta[#meta + 1] = "breadcrumb" end
  meta[#meta + 1] = "#" .. id
  node.meta:SetText(table.concat(meta, " · "))
  node.status:SetText(ns.Colorize(status) .. "   " .. (sharable == nil and "|cff808080sharable?|r"
    or sharable and "|cff1eff00sharable|r" or "|cff808080not sharable|r"))
  node:ClearAllPoints()
  node:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
  node:Show()
end

function Line(y)
  linePool.used = linePool.used + 1
  local line = linePool[linePool.used]
  if not line then
    line = content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.6, 0.6, 0.6, 0.6)
    line:SetSize(2, ROW_GAP - 4)
    linePool[linePool.used] = line
  end
  line:ClearAllPoints()
  line:SetPoint("TOP", content, "TOPLEFT", CONTENT_W / 2, -(y + 2))
  line:Show()
  return y + ROW_GAP
end

function Label(y, text, inline)
  labelPool.used = labelPool.used + 1
  local label = labelPool[labelPool.used]
  if not label then
    label = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    labelPool[labelPool.used] = label
  end
  label:ClearAllPoints()
  label:SetPoint("TOP", content, "TOPLEFT", CONTENT_W / 2, -y)
  label:SetText(inline and text or text:upper())
  label:Show()
  return y + LABEL_H
end

function InfoText(id, m, members)
  local q = ns.QuestData(id)
  local sharable = ns.IsSharable(id)
  local lines = {
    ("|c%s%s|r: %s   %s"):format(ns.ClassColor(m), m.name, ns.Colorize(ns.Status(id, m)),
      sharable == nil and "sharable?" or sharable and "|cff1eff00sharable|r" or "not sharable"),
  }
  if #members > 1 then
    local party = {}
    for _, member in ipairs(members) do
      party[#party + 1] = ("|c%s%s|r %s"):format(ns.ClassColor(member), member.name, ns.Colorize(ns.Status(id, member)))
    end
    lines[#lines + 1] = "|cffaaaaaaParty:|r " .. table.concat(party, "   ")
  end
  local objectives = q and q.objectivesText
  if type(objectives) == "table" and #objectives > 0 then
    lines[#lines + 1] = "|cffaaaaaaObjectives:|r " .. table.concat(objectives, " ")
  end
  if not q then
    lines[#lines + 1] = "|cff808080Not in QuestieDB: no prerequisites or follow-ups known.|r"
    return table.concat(lines, "\n")
  end
  local function refs(label, ids)
    if #ids == 0 then return end
    local parts = {}
    for _, other in ipairs(ids) do parts[#parts + 1] = ns.QuestTitle(other) .. " (" .. ns.Colorize(ns.Status(other, m)) .. ")" end
    lines[#lines + 1] = ("|cffaaaaaa%s:|r %s"):format(label, table.concat(parts, ", "))
  end
  refs(#q.preS > 1 and "Needs one of" or "Needs", q.preS)
  refs("Needs all of", q.preG)
  refs("Breadcrumb for", q.breadcrumbFor > 0 and { q.breadcrumbFor } or {})
  refs("Can't do with", q.excl)
  refs("Leads to", ns.SortedKeys(Links().after[id]))
  return table.concat(lines, "\n")
end
