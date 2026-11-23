local _, ns = ...

--[[
Party sync over addon messages (prefix "PartyQuests", PARTY or RAID channel).

  R<nonce>                      "send me your quest data"; everyone answers with an S
  S|A<seq>:<total>:<index>:<chunk>
                                a payload split into chunks: S = full (log + completed), A = log only
  C<id>                         the sender turned in a quest

Payload: <version>;<guid>;<headers>;<active>[;<completed>]
  headers    quest log header names joined by "^"
  active     <id>.<header index> pairs joined by ","
  completed  sorted quest IDs as deltas from the previous ID, joined by ","
Numbers are base 36. Members are keyed by GUID because Forever's sender names can come as
"Name-Realm" or "Name Surname".
]]

local Comm = {}
ns.Comm = Comm

local PREFIX = "PartyQuests"
local VERSION = "1"
local CHUNK = 230
local MAX_TOKENS = 8
local HELLO_COOLDOWN = 10

local SendResult = Enum.SendAddonMessageResult or {
  Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, AddOnMessageLockdown = 11,
}
-- Results that mean "try again later"; any other failure drops the message so it can't block the queue.
local RETRY = {
  [SendResult.AddonMessageThrottle or 3] = true,
  [SendResult.ChannelThrottle or 8] = true,
  [SendResult.AddOnMessageLockdown or 11] = true,
}

local queue, incoming, senderGuid = {}, {}, {}
local tokens, seq, lastHello, lastActive = MAX_TOKENS, 0, 0, nil
local nonce = tostring(math.random(100000, 999999))
local stats = { sent = 0, dropped = 0, received = {}, parsed = {} }

local Pump, SendPayload, Chunks, ActivePart, Send, OnMessage, OnChunk, Parse, ResultName

function Comm.Init()
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  local listener = CreateFrame("Frame")
  listener:RegisterEvent("CHAT_MSG_ADDON")
  listener:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    local count = stats.received[sender] or { messages = 0 }
    count.messages, count.channel, count.at = count.messages + 1, channel, GetTime()
    stats.received[sender] = count
    if channel == "PARTY" or channel == "RAID" then OnMessage(text, sender) end
  end)
  -- Addon messages are rate limited per prefix; refill a small burst allowance about once a second.
  C_Timer.NewTicker(0.25, function()
    tokens = math.min(MAX_TOKENS, tokens + 0.25)
    Pump()
  end)
  if IsInGroup() then Comm.Hello() end
end

--- Asks the party for their data and sends ours. `force` skips the cooldown.
function Comm.Hello(force)
  if not IsInGroup() or (not force and GetTime() - lastHello < HELLO_COOLDOWN) then return end
  lastHello = GetTime()
  queue[#queue + 1] = "R" .. nonce
  SendPayload("S")
end

--- Says hello when someone in the party hasn't sent their data yet.
function Comm.OnRoster()
  if not IsInGroup() then return end
  for i = 1, GetNumSubgroupMembers() do
    local guid = UnitGUID("party" .. i)
    if guid and not (issecretvalue and issecretvalue(guid)) and not ns.remote[guid] then
      ns.Debounce("hello", 2, Comm.Hello)
      return
    end
  end
end

function Comm.OnLogChanged()
  if not IsInGroup() then return end
  ns.Debounce("active", 3, function()
    if ActivePart() ~= lastActive then SendPayload("A") end
  end)
end

function Comm.OnTurnedIn(id)
  if not IsInGroup() then return end
  queue[#queue + 1] = "C" .. Comm.B36(id)
  Pump()
end

function Comm.B36(n)
  local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  if n == 0 then return "0" end
  local s = ""
  while n > 0 do
    local d = n % 36
    s = digits:sub(d + 1, d + 1) .. s
    n = (n - d) / 36
  end
  return s
end

function Comm.EncodeIds(set)
  local out, prev = {}, 0
  for i, id in ipairs(ns.SortedKeys(set)) do
    out[i] = Comm.B36(id - prev)
    prev = id
  end
  return table.concat(out, ",")
end

function Comm.DecodeIds(text)
  local set, prev = {}, 0
  for part in (text or ""):gmatch("[^,]+") do
    prev = prev + (tonumber(part, 36) or 0)
    set[prev] = true
  end
  return set
end

function SendPayload(kind)
  if not IsInGroup() then return end
  local active = ActivePart()
  lastActive = active
  local payload = VERSION .. ";" .. UnitGUID("player") .. ";" .. active
  if kind == "S" then payload = payload .. ";" .. Comm.EncodeIds(ns.OwnCompleted()) end
  -- A newer payload replaces any unsent chunks of the same kind.
  for i = #queue, 1, -1 do
    if queue[i]:sub(1, 1) == kind then table.remove(queue, i) end
  end
  seq = (seq + 1) % 1296
  local chunks = Chunks(payload)
  for i, chunk in ipairs(chunks) do
    queue[#queue + 1] = ("%s%s:%s:%s:%s"):format(kind, Comm.B36(seq), Comm.B36(#chunks), Comm.B36(i), chunk)
  end
  Pump()
end

-- Splits on UTF-8 character boundaries, so no message carries half a character (accented zone names
-- on non-English clients).
function Chunks(payload)
  local chunks, first = {}, 1
  while first <= #payload do
    local last = math.min(first + CHUNK - 1, #payload)
    while last < #payload and last > first do
      local nextByte = payload:byte(last + 1)
      if nextByte < 0x80 or nextByte > 0xBF then break end
      last = last - 1
    end
    chunks[#chunks + 1] = payload:sub(first, last)
    first = last + 1
  end
  return chunks
end

function ActivePart()
  local log = ns.OwnLog()
  local headers, index, items = {}, {}, {}
  for _, id in ipairs(ns.SortedKeys(log.active)) do
    local zone = (log.zones[id] or ""):gsub("[%^;,%.|]", " ")
    if not index[zone] then
      headers[#headers + 1] = zone
      index[zone] = #headers - 1
    end
    items[#items + 1] = Comm.B36(id) .. "." .. Comm.B36(index[zone])
  end
  return table.concat(headers, "^") .. ";" .. table.concat(items, ",")
end

-- Sends queued messages while the burst allowance lasts; a throttled or restricted send stays queued.
-- AreOutgoingAddonChatMessagesRestricted() reports true on Forever while party messages still go
-- through, so only the send result decides.
function Pump()
  while #queue > 0 and tokens >= 1 do
    local channel = Comm.Channel()
    if not channel then
      wipe(queue)
      return
    end
    local result = Send(queue[1], channel)
    stats.lastResult = result
    if RETRY[result] then
      tokens = 0
      return
    end
    table.remove(queue, 1)
    tokens = tokens - 1
    if result == SendResult.Success then
      stats.sent = stats.sent + 1
    else
      stats.dropped = stats.dropped + 1
      stats.lastError = ResultName(result)
    end
  end
end

function Comm.Channel()
  return IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil
end

-- The send result as an Enum.SendAddonMessageResult code; older clients return a boolean or nothing.
function Send(text, channel)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel)
  if not ok then
    stats.lastLuaError = tostring(result)
    return SendResult.GeneralError or 9
  end
  if result == nil or result == true then return SendResult.Success end
  if result == false then return SendResult.GeneralError or 9 end
  return result
end

function OnMessage(text, sender)
  local kind, body = text:sub(1, 1), text:sub(2)
  if kind == "R" then
    if body ~= nonce then ns.Debounce("reply", 1 + math.random() * 2, function() SendPayload("S") end) end
  elseif kind == "S" or kind == "A" then
    OnChunk(kind, body, sender)
  elseif kind == "C" then
    local entry = ns.remote[senderGuid[sender] or ""]
    local id = tonumber(body, 36)
    if entry and id then
      if entry.completed then entry.completed[id] = true end
      entry.active[id] = nil
      ns.Changed()
    end
  end
end

function OnChunk(kind, body, sender)
  local seqText, totalText, indexText, data = body:match("^(%w+):(%w+):(%w+):(.*)$")
  local total, index = tonumber(totalText or "", 36), tonumber(indexText or "", 36)
  if not (seqText and total and index) then return end
  local key = sender .. kind
  local buffer = incoming[key]
  if not buffer or buffer.seq ~= seqText then
    buffer = { seq = seqText, parts = {}, count = 0 }
    incoming[key] = buffer
  end
  if not buffer.parts[index] then
    buffer.parts[index] = data
    buffer.count = buffer.count + 1
  end
  if buffer.count == total then
    incoming[key] = nil
    Parse(kind, table.concat(buffer.parts, "", 1, total), sender)
  end
end

function Parse(kind, payload, sender)
  local version, guid, headers, active, completed = strsplit(";", payload)
  if version ~= VERSION or not guid or guid == "" or guid == UnitGUID("player") then return end
  stats.parsed[sender] = { guid = guid, kind = kind, at = GetTime() }
  senderGuid[sender] = guid
  local zoneNames = headers ~= "" and { strsplit("^", headers) } or {}
  local entry = ns.remote[guid] or {}
  entry.active, entry.zones = {}, {}
  for item in (active or ""):gmatch("[^,]+") do
    local idText, headerText = strsplit(".", item)
    local id = tonumber(idText, 36)
    if id then
      entry.active[id] = true
      local zone = zoneNames[(tonumber(headerText or "", 36) or -1) + 1]
      if zone and zone ~= "" then entry.zones[id] = zone end
    end
  end
  if kind == "S" then entry.completed = Comm.DecodeIds(completed) end
  entry.updated = time()
  ns.remote[guid] = entry
  ns.Changed()
end

--- Lines describing the sync state, for /pq debug.
function Comm.DebugLines()
  local lines = {}
  local function add(format, ...) lines[#lines + 1] = "  " .. format:format(...) end
  local restricted = C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()
  local registered = C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered(PREFIX)
  add("channel %s, %d other member(s), prefix registered: %s, sending restricted: %s",
    tostring(Comm.Channel() or "none (not in a group)"), GetNumSubgroupMembers(), tostring(registered), tostring(restricted))
  add("sent %d, dropped %d, queued %d, last result %s%s", stats.sent, stats.dropped, #queue,
    stats.lastResult and ResultName(stats.lastResult) or "none",
    stats.lastError and (", last error " .. stats.lastError) or "")
  if stats.lastLuaError then add("send error: %s", stats.lastLuaError) end
  if not next(stats.received) then add("received nothing from anyone yet") end
  for sender, count in pairs(stats.received) do
    local parsed = stats.parsed[sender]
    add("from %s: %d message(s) on %s, %ds ago; %s", sender, count.messages, tostring(count.channel),
      math.floor(GetTime() - count.at), parsed and ("full data from " .. parsed.guid) or "no complete data yet")
  end
  return lines
end

function ResultName(result)
  for name, value in pairs(SendResult) do
    if value == result then return ("%s (%s)"):format(name, tostring(result)) end
  end
  return tostring(result)
end
