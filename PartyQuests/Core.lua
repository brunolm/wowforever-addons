local _, ns = ...

-- cmangos QUEST_FLAGS_SHARABLE, the bit QuestieDB's questFlags field uses.
local SHARABLE_FLAG = 8
local COLORS = { has = "9cc3ff", done = "8fd18f", ok = "1eff00", bad = "ff8080", neutral = "b0b0b0", unknown = "808080" }

-- Party members' quest data received over addon messages, by GUID. Filled by Comm.lua.
ns.remote = {}

local questCache, requestedTitles, pending = {}, {}, {}
local ownLog, ownCompleted
local UnitNames, Unknown

-- Unit queries can return secret values on this client; those are treated as unknown.
local function Readable(value)
  return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
  "QUEST_DATA_LOAD_RESULT", "UNIT_LEVEL", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
  events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    ns.Comm.Init()
  elseif event == "GROUP_ROSTER_UPDATE" then
    ns.Comm.OnRoster()
  elseif event == "QUEST_LOG_UPDATE" then
    ownLog = nil
    ns.Comm.OnLogChanged()
  elseif event == "QUEST_TURNED_IN" then
    if ownCompleted then ownCompleted[arg1] = true end
    ns.Comm.OnTurnedIn(arg1)
  end
  ns.Changed()
end)

SLASH_PARTYQUESTS1 = "/pq"
SLASH_PARTYQUESTS2 = "/partyquests"
SlashCmdList.PARTYQUESTS = function(msg)
  local command = strtrim(msg or ""):lower()
  if command == "sync" then
    ns.Comm.Hello(true)
    print("PartyQuests: asked the party for their quest logs.")
    return
  end
  if command == "debug" then
    ns.PrintDebug()
    return
  end
  ns.UI.Toggle()
end

function ns.PrintDebug()
  local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  print("PartyQuests " .. (metadata("PartyQuests", "Version") or "?") .. " sync status:")
  for _, line in ipairs(ns.Comm.DebugLines()) do print(line) end
  for i = 1, GetNumSubgroupMembers() do
    local unit = "party" .. i
    local guid, name = UnitGUID(unit), UnitName(unit)
    local m = ns.Member(unit)
    local data = "not shown (unreadable GUID)"
    if m then
      local completed = m.completed and #ns.SortedKeys(m.completed) or "unknown"
      data = ("source %s, %d in log, completed %s"):format(tostring(m.source or "none"), #ns.SortedKeys(m.active), completed)
    end
    print(("  %s: %s, %s"):format(unit, Readable(name) and name or "?", Readable(guid) and (guid .. "; " .. data) or data))
  end
end

--- Runs `fn` once, `delay` seconds after the last call with the same key.
function ns.Debounce(key, delay, fn)
  pending[key] = (pending[key] or 0) + 1
  local token = pending[key]
  C_Timer.After(delay, function()
    if pending[key] == token then fn() end
  end)
end

function ns.Changed()
  ns.Debounce("render", 0.2, function()
    ns.UI.Refresh()
    ns.Chain.Refresh()
  end)
end

--- The player and their party (in a raid, their subgroup), player first.
function ns.Members()
  local list = { ns.Member("player", true) }
  if IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      local m = ns.Member("party" .. i)
      if m then list[#list + 1] = m end
    end
  end
  return list
end

function ns.Member(unit, isSelf)
  if not UnitExists(unit) then return nil end
  local guid = UnitGUID(unit)
  if not Readable(guid) then return nil end
  local name = UnitName(unit)
  local _, classFile, classID = UnitClass(unit)
  local _, _, raceID = UnitRace(unit)
  local level = UnitLevel(unit)
  local m = {
    unit = unit,
    guid = guid,
    isSelf = isSelf,
    name = Readable(name) and name or UNKNOWN,
    classFile = Readable(classFile) and classFile or nil,
    classID = Readable(classID) and classID or 0,
    raceID = Readable(raceID) and raceID or 0,
    level = Readable(level) and level or 0,
  }
  if isSelf then
    local log = ns.OwnLog()
    m.active, m.zones, m.completed, m.source = log.active, log.zones, ns.OwnCompleted(), "self"
  elseif ns.remote[guid] then
    local remote = ns.remote[guid]
    m.active, m.zones, m.completed, m.source = remote.active, remote.zones, remote.completed, "partyquests"
  else
    local questieLog = ns.QuestieLog(unit)
    m.active, m.zones, m.source = questieLog or {}, {}, questieLog and "questie" or nil
  end
  -- `synced`: the member's quest log is known; `completed` stays nil unless PartyQuests sent it.
  m.synced = m.source ~= nil
  return m
end

--- Quests in a party member's log from Questie's own party sync (only when both have Questie). Questie
--- shares no completed quests. It keys players by sender name, which on Forever is "Firstname Lastname".
function ns.QuestieLog(unit)
  local comms = ns.QuestieModule("QuestieComms")
  local logs = type(comms) == "table" and comms.remoteQuestLogs
  if type(logs) ~= "table" then return nil end
  local names = UnitNames(unit)
  local active, any = {}, false
  for questID, players in pairs(logs) do
    for playerName in pairs(type(players) == "table" and players or {}) do
      if type(playerName) == "string" and names[playerName:lower()] then
        active[questID] = true
        any = true
      end
    end
  end
  return any and active or nil
end

-- Every spelling a party member's name can take in addon messages: "Name", "Name Surname", "Name-Realm".
function UnitNames(unit)
  local names = {}
  local function add(value)
    if Readable(value) and type(value) == "string" and value ~= "" then names[value:lower()] = true end
  end
  local function addPair(first, second)
    if not (Readable(first) and Readable(second)) or type(first) ~= "string" or type(second) ~= "string" or second == "" then return end
    add(first .. " " .. second)
    add(first .. "-" .. second)
  end
  add(GetUnitName(unit, true))
  add(GetUnitName(unit, false))
  local first, second = UnitName(unit)
  add(first)
  addPair(first, second)
  if UnitFullName then addPair(UnitFullName(unit)) end
  return names
end

function ns.ClassColor(m)
  local color = m.classFile and RAID_CLASS_COLORS[m.classFile]
  return color and color.colorStr or "ffffffff"
end

--- Quest IDs in the player's log, with the log header (usually the zone) each one sits under.
function ns.OwnLog()
  if ownLog then return ownLog end
  local active, zones, header = {}, {}, nil
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and info.isHeader then
      header = info.title
    elseif info and info.questID and info.questID > 0 and not info.isHidden then
      active[info.questID] = true
      zones[info.questID] = header
    end
  end
  ownLog = { active = active, zones = zones }
  return ownLog
end

function ns.OwnCompleted()
  if ownCompleted then return ownCompleted end
  ownCompleted = {}
  for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs() or {}) do
    ownCompleted[id] = true
  end
  return ownCompleted
end

--- QuestieDB's record for a quest, or nil when QuestieDB isn't loaded or doesn't know the quest.
function ns.QuestData(id)
  local cached = questCache[id]
  if cached ~= nil then return cached or nil end
  local db = _G.QuestDB
  local data = false
  if db and db.Exists and db.Exists(id) then
    local function get(key)
      local ok, value = pcall(db.Get, id, key)
      return ok and value or nil
    end
    data = {
      name = get("name"),
      req = get("requiredLevel") or 0,
      lvl = get("questLevel") or 0,
      races = get("requiredRaces") or 0,
      classes = get("requiredClasses") or 0,
      preS = get("preQuestSingle") or {},
      preG = get("preQuestGroup") or {},
      excl = get("exclusiveTo") or {},
      next = get("nextQuestInChain") or 0,
      breadcrumbFor = get("breadcrumbForQuestId") or 0,
      flags = get("questFlags") or 0,
      zone = get("zoneOrSort") or 0,
      objectivesText = get("objectivesText"),
      reputation = get("reputationReward"),
    }
  end
  questCache[id] = data
  return data or nil
end

function ns.QuestTitle(id)
  local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
  if title and title ~= "" then return title end
  local q = ns.QuestData(id)
  if q and q.name then return q.name end
  if not requestedTitles[id] and C_QuestLog.RequestLoadQuestByID then
    requestedTitles[id] = true
    C_QuestLog.RequestLoadQuestByID(id)
  end
  return "Quest " .. id
end

--- A member's quest log header for the quest, else its QuestieDB zone, else "Other".
function ns.QuestZone(id, members)
  for _, m in ipairs(members or {}) do
    if m.zones[id] then return m.zones[id] end
  end
  local q = ns.QuestData(id)
  if q and q.zone > 0 and C_Map.GetAreaInfo then
    local name = C_Map.GetAreaInfo(q.zone)
    if name and name ~= "" then return name end
  end
  return "Other"
end

function ns.LevelText(id)
  local q = ns.QuestData(id)
  if not q or q.lvl == 0 then return "-" end
  return q.req > 0 and ("%d (%d)"):format(q.lvl, q.req) or tostring(q.lvl)
end

--- True or false when known; nil when the quest is in nobody's data.
function ns.IsSharable(id)
  if ns.OwnLog().active[id] and C_QuestLog.IsPushableQuest then
    local ok, pushable = pcall(C_QuestLog.IsPushableQuest, id)
    if ok and pushable ~= nil then return pushable == true end
  end
  local q = ns.QuestData(id)
  if q then return math.floor(q.flags / SHARABLE_FLAG) % 2 == 1 end
  return nil
end

function ns.OnQuest(m, id)
  if m.active[id] then return true end
  if m.synced or not C_QuestLog.IsUnitOnQuest then return false end
  local ok, onQuest = pcall(C_QuestLog.IsUnitOnQuest, m.unit, id)
  return ok and onQuest == true
end

--- What a member can do with a quest: { kind, text, tip }. `maybe` marks a guess (missing data).
function ns.Status(id, m)
  if ns.OnQuest(m, id) then return { kind = "has", text = "in log" } end
  if m.completed and m.completed[id] then return { kind = "done", text = "done" } end
  local q = ns.QuestData(id)
  if not q then
    if not m.completed then return Unknown(m) end
    return { kind = "ok", maybe = true, text = "can take?", tip = "Not in QuestieDB: requirements unknown" }
  end
  if q.races ~= 0 and m.raceID > 0 and not ns.HasBit(q.races, ns.RaceBit(m.raceID)) then
    return { kind = "bad", text = "wrong race", tip = "Not available to this race or faction" }
  end
  if q.classes ~= 0 and m.classID > 0 and not ns.HasBit(q.classes, m.classID - 1) then
    return { kind = "bad", text = "wrong class", tip = "Not available to this class" }
  end
  if m.completed then
    for _, other in ipairs(q.excl) do
      if m.completed[other] or m.active[other] then
        return { kind = "bad", text = "excluded", tip = "Took an alternative instead: " .. ns.QuestTitle(other) }
      end
    end
    local missing, allInLog = ns.MissingPrereqs(q, m)
    if #missing > 0 then
      local tip = "Needs " .. table.concat(missing, "; ")
      if allInLog then return { kind = "neutral", text = "next", tip = tip .. " (in the quest log now)" } end
      return { kind = "bad", text = "needs prereq", tip = tip }
    end
  end
  if m.level < q.req then
    return { kind = "bad", text = "lvl " .. q.req, tip = ("Needs level %d (%s is %d)"):format(q.req, m.name, m.level) }
  end
  if not m.completed then return Unknown(m) end
  return { kind = "ok", text = "can take" }
end

-- Without the member's completed quests there's no telling whether they did this one already.
function Unknown(m)
  local tip = m.source == "questie"
    and ("Only Questie's data for %s: their quest log is known, not which quests they've done"):format(m.name)
    or ("%s doesn't have PartyQuests or Questie: nothing is known about their quests"):format(m.name)
  return { kind = "unknown", text = "unknown", tip = tip }
end

--- Status for sharing one of the player's quests with a member; `share` marks members it can go to.
function ns.ShareStatus(id, m)
  local s = ns.Status(id, m)
  local sharable = ns.IsSharable(id)
  if s.kind == "unknown" then
    s.share = sharable == true
    return s
  end
  if s.kind ~= "ok" then return s end
  if sharable == false then
    return { kind = "neutral", text = s.text, tip = "Not sharable: they pick it up from the quest giver" }
  end
  if sharable and not s.maybe then return { kind = "ok", text = "can share", share = true } end
  return { kind = "unknown", text = "can share?", tip = s.tip, share = sharable == true }
end

--- QuestieDB semantics: preQuestSingle needs any one done, preQuestGroup needs all of them done.
function ns.MissingPrereqs(q, m)
  local missing, allInLog = {}, true
  if #q.preS > 0 then
    local done, inLog, names = false, false, {}
    for _, p in ipairs(q.preS) do
      if m.completed[p] then done = true end
      if m.active[p] then inLog = true end
      names[#names + 1] = ns.QuestTitle(p)
    end
    if not done then
      missing[#missing + 1] = (#q.preS > 1 and "one of " or "") .. table.concat(names, ", ")
      allInLog = allInLog and inLog
    end
  end
  for _, p in ipairs(q.preG) do
    if not m.completed[p] then
      missing[#missing + 1] = ns.QuestTitle(p)
      allInLog = allInLog and m.active[p] == true
    end
  end
  return missing, allInLog
end

function ns.Colorize(status)
  return ("|cff%s%s|r"):format(COLORS[status.kind] or COLORS.neutral, status.text)
end

--- Only quests in the player's own log can be shared, in a group and out of combat.
function ns.CanShare(id)
  return ns.OwnLog().active[id] == true and ns.IsSharable(id) ~= false and IsInGroup() and not InCombatLockdown()
end

--- Shares a quest from the player's log with the party. Blocked in combat.
function ns.ShareQuest(id)
  if not ns.CanShare(id) then return end
  local logIndex = C_QuestLog.GetLogIndexForQuestID(id)
  if not logIndex then return end
  local previous = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
  C_QuestLog.SetSelectedQuest(id)
  QuestLogPushQuest(logIndex)
  C_QuestLog.SetSelectedQuest(previous or 0)
end

--- QuestieDB race masks: bit (race id - 1), except Skyborne (races 95/96), which Forever puts on bits 32/33.
function ns.RaceBit(raceID)
  if raceID == 95 then return 32 end
  if raceID == 96 then return 33 end
  return raceID - 1
end

--- Masks exceed 32 bits (Skyborne), so test with arithmetic instead of bit operations.
function ns.HasBit(mask, bit)
  return bit >= 0 and math.floor(mask / 2 ^ bit) % 2 == 1
end

--- A Questie module, or nil when Questie isn't loaded.
function ns.QuestieModule(name)
  return QuestieLoader and ns.Call(QuestieLoader.ImportModule, QuestieLoader, name) or nil
end

local function Results(ok, ...)
  if ok then return ... end
end

--- Calls an API that may be missing or error on this client; returns nothing on failure.
function ns.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  return Results(pcall(fn, ...))
end

function ns.SortedKeys(set)
  local keys = {}
  for key in pairs(set or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end
