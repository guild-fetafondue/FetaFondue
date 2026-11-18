---@class ns
local ns = select(2, ...)

-- How profession data travels between guildies (guild channel only, no whispers)
-- ---------------------------------------------------------------------------
-- 1. Advertise: when your professions change (and at login, and hourly) your client posts a tiny
--    message to the guild: character, and per profession the skill, a revision and the recipe count.
-- 2. Ask: a client that is missing that revision posts "who has this?" to the guild (after a short
--    random wait, and only if nobody else just asked).
-- 3. Answer: one client that has it (the owner answers first) posts the recipe list to the guild in a
--    few small chunks. Everybody who needs it picks it up from that one answer, everybody else
--    ignores it, and anybody who was about to answer too stays quiet.
-- 4. Relay: a client that just logged in says hello; online guildies re-advertise what they have
--    cached (once, with random delays), so data of offline guildies fills in too.
-- Recipes are sent as recipe IDs only; every client turns them into names itself.
-- 5. Details: what a recipe makes and needs (for tooltips) is fetched one recipe at a time, only when
--    somebody actually looks at it: "who knows recipe X?" -> one client answers with the item and
--    materials. Everybody keeps what they learn.

local S = {}
ns.Sync = S

local MAX_MSG = 245       -- addon messages are limited to 255 bytes
local CHUNK = 160         -- recipe payload characters per data message
local REQUEST_TTL = 60    -- do not ask for the same data again for this many seconds
local SERVE_TTL = 30      -- do not answer the same question again for this many seconds
local HEARD_TTL = 30      -- an answer heard this recently counts as "somebody already replied"
local RETRIES = 2         -- ask again this many times if the answer never fully arrived
local RELAY_GAP = 60      -- skip relaying a character somebody advertised this recently
local RELAY_MAX = 30      -- relay at most this many characters per hello
local QUEUE_MAX = 400

local queue, pumping = {}, false
local requested, served, incoming, lastAdvert = {}, {}, {}, {}
local heardAsk, heardData, pendingServe = {}, {}, {}
local infoAsked, infoHeard, infoPending = {}, {}, {}
local relayPending, advertQueued = false, false
local started = false

---------------------------------------------------------------------------
-- Encoding: sorted recipe IDs -> base-36 differences, split into chunks
---------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function ToBase36(n)
    if n == 0 then return "0" end
    local s = ""
    while n > 0 do
        local r = n % 36
        s = DIGITS:sub(r + 1, r + 1) .. s
        n = (n - r) / 36
    end
    return s
end

function S.EncodeIDs(ids)
    local out, prev = {}, 0
    for i, id in ipairs(ids) do
        out[i] = ToBase36(id - prev)
        prev = id
    end
    return table.concat(out, ",")
end

function S.DecodeIDs(str)
    local ids, prev = {}, 0
    for token in str:gmatch("[^,]+") do
        local delta = tonumber(token, 36)
        if not delta or delta < 0 then return nil end
        prev = prev + delta
        ids[#ids + 1] = prev
        if #ids > 3000 then return nil end
    end
    return ids
end

-- Splits on commas so a number never ends up in two chunks.
function S.Chunk(encoded, limit)
    local chunks, cur = {}, ""
    for token in encoded:gmatch("[^,]+") do
        if cur ~= "" and #cur + #token + 1 > limit then
            chunks[#chunks + 1] = cur
            cur = token
        else
            cur = (cur == "") and token or (cur .. "," .. token)
        end
    end
    if cur ~= "" then chunks[#chunks + 1] = cur end
    return chunks
end

local function Clean(s)
    return (tostring(s or ""):gsub("[|;~]", ""))
end

---------------------------------------------------------------------------
-- Outgoing queue: one message at a time, paced, held while the game blocks addon chat
---------------------------------------------------------------------------
local counters = { inN = 0, outN = 0, dropped = 0 }

local function Pump()
    if #queue == 0 then
        pumping = false
        return
    end
    if ns.IsMessagingBlocked() then
        ns.After(5, Pump)
        return
    end
    local item = table.remove(queue, 1)
    local result = ns.RawSend(item.msg, item.channel, item.target)
    if result == "throttled" then
        table.insert(queue, 1, item)
        ns.After(2, Pump)
        return
    end
    counters.outN = counters.outN + 1
    ns.After(0.4, Pump)
end

-- Capture mode: while an advert function runs for the hourly refresh, what it would send is collected instead of sent. If it is
-- exactly what that function sent last time (and that was less than SENT_REFRESH ago), nothing goes out: the guild already has it.
-- A change in the data changes the messages, so changed data always goes out. Order matters for that: lists are sorted.
local capture = nil
local sentFP = {}                      -- [category] = { fp, t } for this session
local SENT_REFRESH = 6 * 3600          -- sent again after this long anyway (so that guildmates who rely on hearing from me still do)

local function Hash(str)               -- a small fixed hash (the same on every run and every machine); 32 bits are enough to tell "same" from "changed"
    local h = 5381
    for i = 1, #str do h = (h * 33 + str:byte(i)) % 4294967296 end
    return h
end
S.Hash = Hash

local function Enqueue(msg, channel, target)
    if capture then capture[#capture + 1] = { msg = msg, channel = channel, target = target } return end
    if #queue >= QUEUE_MAX then table.remove(queue, 1) end
    queue[#queue + 1] = { msg = msg, channel = channel, target = target }
    if not pumping then
        pumping = true
        ns.After(0.05, Pump)
    end
end

-- Run an advert function and send its messages only when they differ from the last time (or when force is set, or the
-- last time was long ago). Returns true when something was sent.
function S.Gated(category, fn, force)
    if capture then fn() return true end                  -- (never nested)
    local buf = {}
    capture = buf
    local ok = pcall(fn)
    capture = nil
    if not ok then force = true end                       -- (a failing advert sends what it had, as before)
    local parts = {}
    for i, it in ipairs(buf) do parts[i] = (it.channel or "") .. "\1" .. it.msg end
    local fp = Hash(#buf .. "\2" .. table.concat(parts, "\2"))
    local now = ns.Time()
    local last = sentFP[category]
    if not force and last and last.fp == fp and now - last.t < SENT_REFRESH then
        counters.savedN = (counters.savedN or 0) + #buf
        return false
    end
    sentFP[category] = { fp = fp, t = now }
    for _, it in ipairs(buf) do Enqueue(it.msg, it.channel, it.target) end
    return #buf > 0
end

---------------------------------------------------------------------------
-- Advertise
---------------------------------------------------------------------------
local function AdvertMessages(guid, m)
    local header = ("A|%s|%s|"):format(guid, Clean(m.name))
    local msgs, cur, len = {}, {}, #header
    local keys = {}
    for key in pairs(m.profs) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local p = m.profs[key]
        local part = table.concat({ key, p.rank or 0, p.max or 0, p.rev or 0, #p.ids, Clean(p.name) }, "~")
        if len + #part + 1 > MAX_MSG and #cur > 0 then
            msgs[#msgs + 1] = header .. table.concat(cur, ";")
            cur, len = {}, #header
        end
        cur[#cur + 1] = part
        len = len + #part + 1
    end
    if #cur > 0 then msgs[#msgs + 1] = header .. table.concat(cur, ";") end
    return msgs
end

local function AdvertiseMember(guid, m)
    for _, msg in ipairs(AdvertMessages(guid, m)) do Enqueue(msg, "GUILD") end
    lastAdvert[guid] = ns.Now()
end

function S.AdvertiseSelf()
    local own = ns.GetOwn()
    if own and ns.guildName then AdvertiseMember(ns.myGUID, own) end
end

-- Called whenever my professions or recipes change; waits a moment so a burst becomes one advert.
function S.OnLocalChange()
    if not started or advertQueued then return end
    advertQueued = true
    ns.After(3, function()
        advertQueued = false
        S.AdvertiseSelf()
    end)
end

function S.Hello()
    if ns.guildName then Enqueue("H|" .. ns.myGUID, "GUILD") end
end

-- What each hourly refresh looks at: the category name is the key of what was sent last time
local HOURLY = {
    { "self",     function() S.AdvertiseSelf() end },
    { "requests", function() S.AdvertiseOwnRequests() end },
    { "stats",    function() S.AdvertiseOwnStats() end },
    { "altlinks", function() S.AdvertiseAltLinks() end },
    { "notes",    function() S.AdvertiseNoteHeader() end },
    { "blacklist", function() S.AdvertiseBlacklist() end },
    { "bossids",  function() S.AdvertiseBossIDs() end },
    { "bank",     function() S.AdvertiseBank() end },
    { "specs",    function() S.AdvertiseSpecs() end },
    { "cooldowns", function() S.AdvertiseCooldowns() end },
    { "joined",   function() S.AdvertiseJoined() end },
}

-- At login everything is told (guildmates who were away have not heard it); every hour only what changed since the last time
-- (and everything once in a while: SENT_REFRESH).
local function Category(cat, force)
    for _, c in ipairs(HOURLY) do
        if c[1] == cat then S.Gated(cat, c[2], force) return end
    end
end

-- my stats, only when they changed (used when the race and the role become readable)
function S.AdvertiseOwnStatsIfChanged() S.Gated("stats", function() S.AdvertiseOwnStats() end) end

-- my achievements again: all of them at login (force), later only when something was added
function S.AdvertiseOwnAchievements(force)
    if not ns.Achievements then return end
    S.Gated("achievements", function() ns.Achievements.AdvertiseOwn() end, force)
end

function S.StartSession()
    if started then return end
    started = true
    ns.After(ns.Random(5, 15), function() Category("self", true) end)
    ns.After(ns.Random(8, 20), function() Category("requests", true) end)
    ns.After(ns.Random(10, 25), function() Category("stats", true) end)
    ns.After(ns.Random(12, 25), S.Hello)
    ns.After(ns.Random(20, 40), function() Category("altlinks", true) end)
    ns.After(ns.Random(25, 45), function() Category("notes", true) end)
    ns.After(ns.Random(22, 42), function() Category("blacklist", true) end)
    ns.After(ns.Random(30, 60), S.AdvertiseStatus)
    ns.After(ns.Random(35, 70), function() Category("bossids", true) end)
    ns.After(ns.Random(40, 80), function() Category("bank", true) end)
    ns.After(ns.Random(50, 100), function() Category("specs", true) end)
    ns.After(ns.Random(55, 110), function() Category("cooldowns", true) end)
    ns.After(ns.Random(45, 90), function() Category("joined", true) end)
    ns.After(45, S.RequestBlacklist)
    ns.After(60, function() ns.PurgeDeparted() end)   -- people who left the guild
    local function Hourly()
        for _, c in ipairs(HOURLY) do S.Gated(c[1], c[2]) end
        S.RequestBlacklist()
        S.AdvertiseStatus()                    -- (always: it is the sign that I am here)
        S.AdvertiseOwnAchievements()
        ns.PurgeDeparted()
        ns.After(3600 + ns.Random(0, 120), Hourly)
    end
    ns.After(3600 + ns.Random(0, 120), Hourly)
end

-- After a dungeon the held messages can go out; nudge the queue.
function S.OnWorldEntered()
    if #queue > 0 and not pumping then
        pumping = true
        ns.After(2, Pump)
    end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function FindMember(guid)
    local own = ns.DB and ns.DB.mine[guid]
    if own then return own end
    local members = ns.GetMembers()
    return members and members[guid] or nil
end

local function Refresh()
    if ns.RefreshUI then ns.RefreshUI() end
end

-- Ask the guild for one profession of one character. Waits a random moment first so that when
-- everybody needs the same data only one question goes out.
local function RequestData(guid, key, rev, attempt)
    attempt = attempt or 1
    local k = guid .. "|" .. key .. "|" .. rev
    local now = ns.Now()
    if attempt == 1 and requested[k] and now - requested[k] < REQUEST_TTL then return end
    requested[k] = now
    ns.After(ns.Random(0, 30) / 10, function()
        local m = FindMember(guid)
        local p = m and m.profs[key]
        if p and p.rev >= rev then return end                       -- already got it
        local t = ns.Now()
        if heardAsk[k] and t - heardAsk[k] < HEARD_TTL then return end  -- somebody else just asked
        if heardData[k] and t - heardData[k] < HEARD_TTL then return end -- the answer is on its way
        heardAsk[k] = t
        Enqueue(("G|%s|%s|%d"):format(guid, key, rev), "GUILD")
    end)
    -- if the answer never fully arrives, ask again
    if attempt <= RETRIES then
        ns.After(45, function()
            local m = FindMember(guid)
            local p = m and m.profs[key]
            if not (p and p.rev >= rev) then
                heardAsk[k], heardData[k] = nil, nil
                RequestData(guid, key, rev, attempt + 1)
            end
        end)
    end
end

-- Is this character in the guild? (a message about somebody who is not is ignored; before the roster is loaded everybody passes)
local function InRoster(guid)
    local roster = ns.GetRoster()
    return roster.total < 1 or roster.byGUID[guid] ~= nil
end

local function HandleAdvert(text, sender)
    local guid, name, rest = text:match("^A|([^|]+)|([^|]*)|(.*)$")
    if not guid or ns.IsMine(guid) or not InRoster(guid) then return end
    name = ns.CleanText(name)
    local members = ns.GetMembers()
    if not members then return end

    lastAdvert[guid] = ns.Now()
    local m = members[guid]
    if not m then
        m = { name = name, profs = {} }
        members[guid] = m
    end
    if name ~= "" then m.name = name end
    m.seen = ns.Time()

    for part in rest:gmatch("[^;]+") do
        local key, rank, max, rev, count, pname = part:match("^([%w_]+)~(%d+)~(%d+)~(%d+)~(%d+)~(.*)$")
        if key then
            rank, max, rev, count = tonumber(rank), tonumber(max), tonumber(rev), tonumber(count)
            pname = ns.CleanText(pname)
            local p = m.profs[key]
            if not p then
                p = { name = pname, rank = 0, max = 0, rev = 0, ids = {} }
                m.profs[key] = p
            end
            if rev > p.rev then
                p.name, p.rank, p.max = pname, rank, max
                if count == 0 then
                    p.ids, p.rev = {}, rev
                else
                    RequestData(guid, key, rev)
                end
            end
        end
    end
    Refresh()
end

local function SendProfession(guid, key, p)
    local chunks = S.Chunk(S.EncodeIDs(p.ids), CHUNK)
    for i, c in ipairs(chunks) do
        Enqueue(("D|%s|%s|%d|%d|%d|%d|%d|%s"):format(guid, key, p.rev, i, #chunks, p.rank or 0, p.max or 0, c), "GUILD")
    end
end

-- Somebody asked "who has this?". Answer only if we hold at least that revision, the owner answers
-- first, and nobody answers if somebody else already did.
local function HandleGet(text)
    local guid, key, reqRev = text:match("^G|([^|]+)|([%w_]+)|(%d+)$")
    if not guid then return end
    reqRev = tonumber(reqRev)
    local k = guid .. "|" .. key .. "|" .. reqRev
    heardAsk[k] = ns.Now()

    local m = FindMember(guid)
    local p = m and m.profs[key]
    if not p or #p.ids == 0 or p.rev < reqRev then return end

    local sk = guid .. "|" .. key .. "|" .. p.rev
    if pendingServe[sk] then return end
    pendingServe[sk] = true

    local owner = ns.IsMine(guid)
    local delay = owner and (ns.Random(5, 20) / 10) or (ns.Random(25, 80) / 10)
    ns.After(delay, function()
        pendingServe[sk] = nil
        local now = ns.Now()
        local cur = FindMember(guid)
        local cp = cur and cur.profs[key]
        if not cp or #cp.ids == 0 then return end
        local csk = guid .. "|" .. key .. "|" .. cp.rev
        if heardData[csk] and now - heardData[csk] < HEARD_TTL then return end  -- somebody already answered
        if served[csk] and now - served[csk] < SERVE_TTL then return end
        served[csk] = now
        heardData[csk] = now
        SendProfession(guid, key, cp)
    end)
end

local function ApplyData(guid, key, rev, rank, max, payload)
    if ns.IsMine(guid) then return end
    local ids = S.DecodeIDs(payload)
    if not ids then return end
    local members = ns.GetMembers()
    if not members then return end

    local m = members[guid]
    if not m then
        m = { name = "?", profs = {} }
        members[guid] = m
    end
    local p = m.profs[key]
    if not p then
        p = { name = key, rank = 0, max = 0, rev = 0, ids = {} }
        m.profs[key] = p
    end
    if rev > p.rev then
        p.ids, p.rev, p.rank, p.max = ids, rev, rank, max
        m.seen = ns.Time()
    end
    Refresh()
end

local function HandleData(text)
    local guid, key, rev, idx, total, rank, max, payload =
        text:match("^D|([^|]+)|([%w_]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if not guid then return end
    rev, idx, total, rank, max = tonumber(rev), tonumber(idx), tonumber(total), tonumber(rank), tonumber(max)
    if total < 1 or total > 60 or idx < 1 or idx > total then return end

    local k = guid .. "|" .. key .. "|" .. rev
    heardData[k] = ns.Now()          -- somebody is answering: nobody else needs to

    if ns.IsMine(guid) then return end
    local m = FindMember(guid)
    local p = m and m.profs[key]
    if p and p.rev >= rev then return end   -- we already have this (or newer): ignore the rest

    local inc = incoming[k]
    if not inc then
        inc = { parts = {}, got = 0, total = total, t = ns.Now() }
        incoming[k] = inc
    end
    if not inc.parts[idx] then
        inc.parts[idx] = payload
        inc.got = inc.got + 1
    end
    if inc.got == inc.total then
        incoming[k] = nil
        local ordered = {}
        for i = 1, inc.total do ordered[i] = inc.parts[i] end
        ApplyData(guid, key, rev, rank, max, table.concat(ordered, ","))
    end

    -- forget transfers that never finished
    local now = ns.Now()
    for ik, v in pairs(incoming) do
        if now - v.t > 120 then incoming[ik] = nil end
    end
end

---------------------------------------------------------------------------
-- Recipe details (item and materials), fetched on demand
---------------------------------------------------------------------------
-- Called when someone looks at a recipe we have no details for.
function S.RequestRecipeInfo(id)
    if not (ns.guildName and ns.DB) or ns.DB.recipeInfo[id] then return end
    local now = ns.Now()
    if infoAsked[id] and now - infoAsked[id] < 30 then return end
    infoAsked[id] = now
    ns.After(ns.Random(0, 15) / 10, function()
        if ns.DB.recipeInfo[id] then return end
        local t = ns.Now()
        if infoHeard[id] and t - infoHeard[id] < 10 then return end -- somebody just asked or answered
        infoHeard[id] = t
        Enqueue("Q|" .. id, "GUILD")
    end)
end

local function EncodeInfo(id, info)
    local parts = {}
    for i, r in ipairs(info.reagents) do
        if i > 12 then break end
        parts[#parts + 1] = r.id .. ":" .. r.count
    end
    local icon = type(info.icon) == "number" and info.icon or 0
    local req = info.req or ns.DB.recipeReq[id] or 0
    return ("I|%d|%d|%s|%d|%d|%d"):format(id, info.item or 0, table.concat(parts, ","), info.made or 1, icon, req)
end

local infoAnswered = {}

-- what we can tell a guildie about a recipe: its details, or at least the exact skill it needs
local function InfoFor(id)
    local info = ns.DB.recipeInfo[id]
    if info then return info end
    if ns.DB.recipeReq[id] then return { reagents = {} } end
    return nil
end

local function HandleInfoAsk(text)
    local id = tonumber(text:match("^Q|(%d+)$"))
    if not id then return end
    infoHeard[id] = ns.Now()
    if not InfoFor(id) or infoPending[id] then return end
    infoPending[id] = true
    -- somebody who knows the recipe themselves answers first
    local knowsIt = false
    local own = ns.GetOwn()
    if own then
        for _, p in pairs(own.profs) do
            for _, rid in ipairs(p.ids) do
                if rid == id then knowsIt = true break end
            end
            if knowsIt then break end
        end
    end
    local delay = knowsIt and (ns.Random(3, 12) / 10) or (ns.Random(15, 50) / 10)
    ns.After(delay, function()
        infoPending[id] = nil
        local info = InfoFor(id)
        if not info then return end
        local t = ns.Now()
        if infoAnswered[id] and t - infoAnswered[id] < 10 then return end -- somebody already answered
        infoAnswered[id] = t
        Enqueue(EncodeInfo(id, info), "GUILD")
    end)
end

local function HandleInfo(text)
    local id, item, list, made, icon, req = text:match("^I|(%d+)|(%d+)|([%d:,]*)|?(%d*)|?(%d*)|?(%d*)$")
    if not id then return end
    id, item, made, icon, req = tonumber(id), tonumber(item), tonumber(made), tonumber(icon) or 0, tonumber(req) or 0
    infoAnswered[id] = ns.Now()
    infoHeard[id] = ns.Now()
    local newReq = false
    if req > 0 and not ns.DB.recipeReq[id] then ns.DB.recipeReq[id], newReq = req, true end
    local have = ns.DB.recipeInfo[id]
    if have then
        -- we already know what it makes; take the icon / exact skill if we lacked them
        local changed = newReq
        if icon > 0 and not have.icon then have.icon, changed = icon, true end
        if req > 0 and not have.req then have.req, changed = req, true end
        if changed and ns.OnRecipeInfo then ns.OnRecipeInfo(id) end
        return
    end
    local reagents = {}
    for rid, count in list:gmatch("(%d+):(%d+)") do
        reagents[#reagents + 1] = { id = tonumber(rid), count = tonumber(count) }
        if #reagents >= 12 then break end
    end
    if item == 0 and #reagents == 0 then
        if newReq and ns.OnRecipeInfo then ns.OnRecipeInfo(id) end   -- only the exact skill came
        return
    end
    ns.DB.recipeInfo[id] = {
        item = item ~= 0 and item or nil, reagents = reagents, made = (made and made > 1) and made or nil,
        icon = icon > 0 and icon or nil, req = req > 0 and req or nil,
    }
    if ns.OnRecipeInfo then ns.OnRecipeInfo(id) end
end

---------------------------------------------------------------------------
-- Requests: everybody's open requests are shared with the guild (small: recipe ID and quantity).
-- Each character pushes its whole list whenever it changes, at login and hourly; the newest
-- revision wins. Deleting the last request pushes an empty list so it disappears for everybody.
---------------------------------------------------------------------------
local reqIncoming, lastReqAdvert = {}, {}
local reqQueued = false

local function AdvertiseRequests(guid, name, rev, list)
    local entries = {}
    for _, r in ipairs(list) do entries[#entries + 1] = r.id .. ":" .. r.qty end
    local chunks = S.Chunk(table.concat(entries, ","), 150)
    if #chunks == 0 then chunks[1] = "" end
    for i, c in ipairs(chunks) do
        Enqueue(("Y|%s|%d|%d|%d|%s|%s"):format(guid, rev, i, #chunks, Clean(name), c), "GUILD")
    end
    lastReqAdvert[guid] = ns.Now()
end

function S.AdvertiseOwnRequests()
    if not (ns.guildName and ns.myGUID and ns.DB) then return end
    local rev = ns.DB.requestRev[ns.myGUID]
    if not rev then return end   -- never had a request
    AdvertiseRequests(ns.myGUID, ns.me or "", rev, ns.DB.requests[ns.myGUID] or {})
end

function S.OnRequestsChanged()
    if not started or reqQueued then return end
    reqQueued = true
    ns.After(2, function()
        reqQueued = false
        S.AdvertiseOwnRequests()
    end)
end

local function HandleRequests(text)
    local guid, rev, idx, total, name, payload =
        text:match("^Y|([^|]+)|(%d+)|(%d+)|(%d+)|([^|]*)|(.*)$")
    if not guid then return end
    rev, idx, total = tonumber(rev), tonumber(idx), tonumber(total)
    if total < 1 or total > 20 or idx < 1 or idx > total then return end
    lastReqAdvert[guid] = ns.Now()
    -- my other characters are authoritative locally; the current one accepts a NEWER copy of its own
    -- list (an officer deleted something while I was offline)
    local self_ = (guid == ns.myGUID)
    if ns.IsMine(guid) and not self_ then return end
    if self_ and rev <= (ns.DB.requestRev[guid] or 0) then return end

    local members = ns.GetMembers()
    if not members then return end
    local m = members[guid]
    if not self_ and m and m.reqs and m.reqs.rev >= rev then return end   -- we already have this or newer

    local k = guid .. "|" .. rev
    local inc = reqIncoming[k]
    if not inc then
        inc = { parts = {}, got = 0, total = total, t = ns.Now() }
        reqIncoming[k] = inc
    end
    if not inc.parts[idx] then
        inc.parts[idx] = payload
        inc.got = inc.got + 1
    end
    if inc.got == inc.total then
        reqIncoming[k] = nil
        local list = {}
        for i = 1, inc.total do
            for id, qty in inc.parts[i]:gmatch("(%d+):(%d+)") do
                if #list < 60 then list[#list + 1] = { id = tonumber(id), qty = tonumber(qty) } end
            end
        end
        if self_ then
            local own = {}
            for _, e in ipairs(list) do
                own[#own + 1] = { id = e.id, qty = e.qty, name = ns.RecipeName(e.id), t = ns.Time() }
            end
            ns.DB.requests[guid] = own
            ns.DB.requestRev[guid] = rev
            Refresh()
            return
        end
        if not m then
            m = { name = name ~= "" and name or "?", profs = {} }
            members[guid] = m
        elseif name ~= "" and (m.name == nil or m.name == "?") then
            m.name = name
        end
        m.reqs = { rev = rev, list = list }
        Refresh()
    end

    local now = ns.Now()
    for ik, v in pairs(reqIncoming) do
        if now - v.t > 120 then reqIncoming[ik] = nil end
    end
end

---------------------------------------------------------------------------
-- Stats: each character shares its counters (dungeons, bosses, crafts, gold looted). Newest revision
-- wins; hearing a message also tells us the guildie runs the addon (needed to share out kill credit).
---------------------------------------------------------------------------
local lastStatsAdvert = {}
local statsQueued = false
local correctionPending, correctionHeard = {}, {}

local function AdvertiseStats(guid, name, st)
    Enqueue(("T|%s|%d|%d|%d|%d|%.0f|%s"):format(guid, st.rev or 0, st.d, st.b, st.c, st.g, Clean(name)), "GUILD")
    lastStatsAdvert[guid] = ns.Now()
    -- which installation (person) this character belongs to
    local members = ns.GetMembers()
    local client = (guid == ns.myGUID and ns.DB.clientID) or (members and members[guid] and members[guid].client)
    local own = ns.GetOwn()
    local created = (guid == ns.myGUID and own and own.created) or (members and members[guid] and members[guid].created) or 0
    if client then Enqueue(("U|%s|%s|%d"):format(guid, client, created), "GUILD") end

    -- the race and the role (from the talents) of the character: for the guild's race and role charts
    -- crafts without smelting (for the "sweatiest crafter")
    if st.cx then       -- (also 0: it tells the others not to use the old total, which still has smelting in it)
        Enqueue(("X|%s|%d"):format(guid, st.cx), "GUILD")
    end
    -- the numbers taken from the game's own statistics (fish caught, deaths from falling, times camped)
    if st.fish then
        Enqueue(("S|%s|%d|0|0"):format(guid, st.fish or 0), "GUILD")      -- (the two zeros are what older versions sent for falls and camps)
    end

    local race, role, tree
    if guid == ns.myGUID then
        if ns.Inspect and own then
            local r1, r2, r3 = ns.Inspect.OwnSummary()
            race, role, tree = r1, r2, r3
            if race and race ~= "" then own.race = race end
            if role and role ~= "" then own.role = role end
            if tree and tree ~= "" then own.tree = tree end
        end
        race, role, tree = own and own.race, own and own.role, own and own.tree
    else
        local mm = members and members[guid]
        race, role, tree = mm and mm.race, mm and mm.role, mm and mm.tree
    end
    if tree and tree ~= "" then Enqueue(("PS|%s|%s"):format(guid, (tree:gsub("[^%a ]", ""):sub(1, 24))), "GUILD") end
    if (race and race ~= "") or (role and role ~= "") then
        Enqueue(("P|%s|%s|%s"):format(guid, (race or ""):gsub("[^%w ]", ""):gsub(" ", "_"), role or ""), "GUILD")
    end
end

function S.AdvertiseOwnStats()
    local own = ns.GetOwn()
    if not (own and own.stats and ns.guildName) then return end
    AdvertiseStats(ns.myGUID, ns.me or own.name, own.stats)
end

function S.OnStatsChanged()
    if not started or statsQueued then return end
    statsQueued = true
    ns.After(5, function()
        statsQueued = false
        S.AdvertiseOwnStats()
    end)
end

-- crafts of a character without smelting: X|guid|number. Only the higher number is ever kept.
local function HandleCraftsX(text)
    local guid, cx = text:match("^X|([^|]+)|(%d+)$")
    if not guid then return end
    cx = math.min(tonumber(cx), S.STAT_CAP.c)
    local st
    if guid == ns.myGUID then
        local own = ns.GetOwn()
        st = own and own.stats
    elseif not ns.IsMine(guid) then
        local members = ns.GetMembers()
        local m = members and members[guid]
        if not m then return end
        m.stats = m.stats or { d = 0, b = 0, c = 0, g = 0, rev = 0 }
        st = m.stats
    end
    if not st then return end
    if st.cx == nil or cx > st.cx then
        st.cx = cx
        Refresh()
    end
end

-- the game's own statistics of a character: S|guid|fish|fall|camp. Each number only ever goes up.
local function HandleGameStats(text)
    local guid, fish, fall, camp = text:match("^S|([^|]+)|(%d+)|(%d+)|(%d+)$")
    if not guid then return end
    local st
    if guid == ns.myGUID then
        local own = ns.GetOwn()
        st = own and own.stats
    elseif not ns.IsMine(guid) then
        local members = ns.GetMembers()
        local m = members and members[guid]
        if not m then return end
        m.stats = m.stats or { d = 0, b = 0, c = 0, g = 0, rev = 0 }
        st = m.stats
    end
    if not st then return end
    local up = false
    for field, value in pairs({ fish = fish }) do
        value = math.min(tonumber(value), S.STAT_CAP.fish)
        if value > (st[field] or 0) then st[field], up = value, true end
    end
    if up then Refresh() end
end

---------------------------------------------------------------------------
-- Specializations (SP|guid|rev|id,id) and profession cooldowns (CD|guid|spell:profession:end;...)
---------------------------------------------------------------------------
local function OwnCharactersHere()
    local out = {}
    for guid, ch in pairs(ns.DB and ns.DB.mine or {}) do
        if ch.guild == ns.guildName then out[#out + 1] = guid end
    end
    return out
end

function S.AdvertiseSpecs()
    if not (ns.guildName and ns.DB) then return end
    for _, guid in ipairs(OwnCharactersHere()) do
        local ch = ns.DB.mine[guid]
        if ch.specs then
            local ids = {}
            for id in pairs(ch.specs) do ids[#ids + 1] = id end
            table.sort(ids)
            Enqueue(("SP|%s|%d|%s"):format(guid, ch.specsRev or 0, table.concat(ids, ",")), "GUILD")
        end
    end
end

function S.AdvertiseCooldowns()
    if not (ns.guildName and ns.DB and ns.Specs) then return end
    local spells = ns.Specs.CooldownSpells()
    for _, guid in ipairs(OwnCharactersHere()) do
        local ch = ns.DB.mine[guid]
        if ch.cds then
            local header = ("CD|%s|"):format(guid)
            local cur, len = {}, #header
            local function Flush()
                if #cur > 0 then Enqueue(header .. table.concat(cur, ";"), "GUILD") end
                cur, len = {}, #header
            end
            local cdIDs = {}
            for id in pairs(ch.cds) do cdIDs[#cdIDs + 1] = id end
            table.sort(cdIDs)
            for _, id in ipairs(cdIDs) do
                local endTime = ch.cds[id]
                local part = ("%d:%s:%d"):format(id, tostring(spells[id] or "0"), endTime or 0)
                if len + #part + 1 > MAX_MSG then Flush() end
                cur[#cur + 1] = part
                len = len + #part + 1
            end
            Flush()
        end
    end
end

local function HandleSpecs(text)
    local guid, rev, list = text:match("^SP|([^|]+)|(%d+)|([%d,]*)$")
    if not guid or ns.IsMine(guid) then return end
    local m = FindMember(guid)
    if not m then return end
    rev = tonumber(rev)
    if rev < (m.specsRev or 0) then return end
    local specs, n = {}, 0
    for id in list:gmatch("%d+") do
        n = n + 1
        if n > 20 then break end
        specs[tonumber(id)] = true
    end
    m.specs, m.specsRev = specs, rev
    Refresh()
end

local function HandleCooldowns(text)
    local guid, list = text:match("^CD|([^|]+)|([%d:;]+)$")
    if not guid or ns.IsMine(guid) then return end
    local m = FindMember(guid)
    if not m then return end
    local db = ns.DB
    db.cdSpells = db.cdSpells or {}
    m.cds = m.cds or {}
    local n = 0
    for idText, key, endText in list:gmatch("(%d+):(%d+):(%d+)") do
        n = n + 1
        if n > 40 then break end
        local id, endTime = tonumber(idText), tonumber(endText)
        if key ~= "0" and not db.cdSpells[id] and not ns.Specs.SEED[id] then db.cdSpells[id] = key end
        -- the later end time wins (a cooldown that was used again); a ready cooldown (0) only replaces one that has run out
        local old = m.cds[id]
        if old == nil or endTime > old or ns.Specs.Remaining(old) == 0 then m.cds[id] = endTime end
    end
    Refresh()
end

-- The gold in the guild bank as somebody last saw it: GB|time|copper|name. The newest sighting wins (it can go up and down).
local lastBankAdvert = -1e9
function S.AdvertiseBank()
    if not (ns.GetGuildBank and ns.guildName) then return end
    local money, ts, by = ns.GetGuildBank()
    if not (money and ts) then return end
    Enqueue(("GB|%d|%.0f|%s"):format(ts, money, Clean(by or "")), "GUILD")
    lastBankAdvert = ns.Now()
end

-- When members joined the guild, as noted by the addon (exact dates only; the hand-made log is built in everywhere):
-- J|guid:time,guid:time,...  The earlier exact date wins.
function S.AdvertiseJoined(guids)
    if not ns.guildName then return end
    local gd = ns.DB and ns.DB.guilds and ns.DB.guilds[ns.guildName]
    if not (gd and gd.joined) then return end
    local list = {}
    local earliest = ns.JoinEarliest()
    for _, guid in ipairs(guids or {}) do
        local j = gd.joined[guid]
        if j and j.exact and j.ts >= earliest then list[#list + 1] = ("%s:%d"):format(guid, j.ts) end
    end
    if not guids then
        for guid, j in pairs(gd.joined) do
            if j.exact and j.ts >= earliest then list[#list + 1] = ("%s:%d"):format(guid, j.ts) end
        end
        table.sort(list)
    end
    local i = 1
    while i <= #list and i <= 120 do
        local chunk, len = {}, 2
        while i <= #list and len + #list[i] + 1 < 200 do chunk[#chunk + 1] = list[i] len = len + #list[i] + 1 i = i + 1 end
        if #chunk == 0 then break end
        Enqueue("J|" .. table.concat(chunk, ","), "GUILD")
    end
end

local function HandleJoined(text)
    local changed = false
    local roster = ns.GetRoster()
    local earliest = ns.JoinEarliest()
    for guid, ts in text:sub(3):gmatch("([^,:|]+):(%d+)") do
        ts = tonumber(ts)
        -- only guild members, and only dates inside the guild's life (not before the addon first looked, not in the future)
        local known = roster.total < 1 or roster.byGUID[guid] ~= nil
        if known and ts and ts >= earliest and ts <= ns.Time() + 86400 and ns.NoteJoined(guid, ts, true, ns.JoinWasLive(guid)) then changed = true end
    end
    if changed then Refresh() end
end

-- I looked into the bank: tell the guild at once
function S.OnGuildBankChanged()
    if started then S.AdvertiseBank() end
end

local function HandleGuildBank(text)
    local ts, money, by = text:match("^GB|(%d+)|(%d+)|(.*)$")
    if not ts then return end
    lastBankAdvert = ns.Now()
    ts = math.min(tonumber(ts), ns.Time() + 600)            -- (a time that has not come yet is not believed)
    by = ns.CleanText(by)
    if ns.Stats and ns.Stats.NoteGuildBank and ns.Stats.NoteGuildBank(money, ts, by) then Refresh() end
end

-- How far a number about a character is believed. The counters only ever go up, so a wrong high number could never be corrected:
--   * nothing above STAT_CAP (a ceiling far above what anybody has reached),
--   * a message about a character is only taken from somebody who is in the guild, about a character who is in the guild,
--   * what the character himself sends (his own addon) is believed up to the ceiling,
--   * what somebody ELSE passes on (a relay for an offline guildie) may raise a number that is already known only by
--     STAT_STEP, and only once per STAT_GAP; the real owner's own message fixes the rest the next time he logs in.
--     A character we know (almost) nothing about may be filled in up to the ceiling at once.
S.STAT_CAP = { d = 3000, b = 30000, c = 300000, g = 1e12, fish = 200000 }
local STAT_STEP = { d = 25, b = 250, c = 2500, g = 1e8 }
local STAT_FRESH = { d = 5, b = 50, c = 500, g = 1e7 }       -- (at or below this a record counts as new)
local STAT_GAP = 600
local relayedUp = {}      -- [guid] = when a passed-on increase of this record was last accepted

local function BoundedStat(field, known, new, owner)
    if new <= known then return new end
    if owner or known <= STAT_FRESH[field] then return new end
    return math.min(new, known + STAT_STEP[field])
end

local function HandleStats(text, sender)
    local guid, rev, d, b, c, g, name = text:match("^T|([^|]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if not guid then return end
    if guid ~= ns.myGUID and not InRoster(guid) then return end
    lastStatsAdvert[guid] = ns.Now()
    rev = tonumber(rev)
    name = ns.CleanText(name)
    local cap = S.STAT_CAP
    -- these are lifetime counters: they only ever go up. Take the highest value heard for each one, so a
    -- reset (lost saved data, a reinstall) or a stale copy can never make the guild totals go down.
    d, b, c = math.min(tonumber(d), cap.d), math.min(tonumber(b), cap.b), math.min(tonumber(c), cap.c)
    g = math.min(tonumber(g), cap.g)
    -- did the character himself send it?
    local who = sender and ns.RosterFind(ns.GetRoster(), sender)
    local owner = who ~= nil and who.guid == guid
    local now = ns.Now()
    local bounded = false           -- (set when a passed-on number had to be held back)

    -- my own current character: if the guild remembers more than I do, I lost some counters (for example
    -- the saved data did not load) - take them back from the guild's copy
    if guid == ns.myGUID then
        local own = ns.GetOwn()
        local st = own and own.stats
        if st then
            local up = false
            local gapOK = not relayedUp[guid] or now - relayedUp[guid] >= STAT_GAP
            local function Take(field, new)
                local known = st[field] or 0
                if new <= known then return end
                local v = BoundedStat(field, known, new, false)
                if v > known and (known <= STAT_FRESH[field] or gapOK) then
                    st[field], up = v, true
                end
            end
            Take("d", d) Take("b", b) Take("c", c) Take("g", g)
            if up then
                relayedUp[guid] = now
                st.rev = math.max(st.rev or 0, rev, ns.Time())
                ns.Debug("restored my counters from the guild's copy")
                Refresh()
            end
        end
        return
    end
    if ns.IsMine(guid) then return end

    local members = ns.GetMembers()
    if not members then return end
    local m = members[guid]
    if not m then
        m = { name = name ~= "" and name or "?", profs = {} }
        members[guid] = m
    elseif name ~= "" and (m.name == nil or m.name == "?") then
        m.name = name
    end
    local st = m.stats
    if not st then
        st = { d = 0, b = 0, c = 0, g = 0, rev = 0 }
        m.stats = st
    end
    st.seen = ns.Time()   -- they are running the addon right now

    -- Their message is LOWER than what we remember (they lost their counters): after a random wait, and
    -- unless somebody else already did, tell the guild (and so them) the numbers we remember.
    local complete = d >= st.d and b >= st.b and c >= st.c and g >= st.g
    if complete then correctionHeard[guid] = ns.Now() end
    if not complete and not correctionPending[guid] then
        correctionPending[guid] = true
        local since = ns.Now()
        ns.After(ns.Random(20, 100) / 10, function()
            correctionPending[guid] = nil
            if (correctionHeard[guid] or -1) >= since then return end
            local mm = ns.GetMembers() and ns.GetMembers()[guid]
            if mm and mm.stats then AdvertiseStats(guid, mm.name, mm.stats) end
        end)
    end

    -- numbers passed on by somebody else are held to a small step (once in a while); the owner's own are not
    local gapOK = owner or not relayedUp[guid] or now - relayedUp[guid] >= STAT_GAP
    local raised = false
    local function Take(field, new)
        local known = st[field]
        if new <= known then return end
        local v = BoundedStat(field, known, new, owner)
        if not (owner or known <= STAT_FRESH[field] or gapOK) then v = known end
        if v > known then st[field] = v raised = true end
    end
    Take("d", d) Take("b", b) Take("c", c) Take("g", g)
    if raised and not owner then relayedUp[guid] = now end
    if rev > (st.rev or 0) then st.rev = rev end
    Refresh()
end

-- An officer (or the guild master) deletes somebody's request: everybody drops it, and the owner's
-- own client drops it from its list too (or picks the change up from a newer copy on next login).
local function ApplyDelete(ownerGUID, recipeID)
    if ns.IsMine(ownerGUID) then
        local list = ns.DB.requests[ownerGUID] or {}
        for i = #list, 1, -1 do
            if list[i].id == recipeID then table.remove(list, i) end
        end
        ns.DB.requestRev[ownerGUID] = ns.Time()
        if ownerGUID == ns.myGUID then S.OnRequestsChanged() end
    else
        local members = ns.GetMembers()
        local m = members and members[ownerGUID]
        if m and m.reqs then
            for i = #m.reqs.list, 1, -1 do
                if m.reqs.list[i].id == recipeID then table.remove(m.reqs.list, i) end
            end
            m.reqs.rev = math.max(m.reqs.rev + 1, ns.Time())
        end
    end
    Refresh()
end

function S.DeleteRequest(ownerGUID, recipeID)
    ApplyDelete(ownerGUID, recipeID)
    Enqueue(("Z|%s|%d"):format(ownerGUID, recipeID), "GUILD")
end

local function HandleDelete(text, sender)
    local guid, id = text:match("^Z|([^|]+)|(%d+)$")
    if not guid then return end
    if not ns.IsOfficerSender(sender) then
        ns.Debug("ignored a request deletion from a non-officer: " .. tostring(sender))
        return
    end
    ApplyDelete(guid, tonumber(id))
end

local function Relay()
    relayPending = false
    local members = ns.GetMembers()
    if not members then return end
    local now, count = ns.Now(), 0
    for guid, m in pairs(members) do
        if count >= RELAY_MAX then break end
        if next(m.profs) and now - (lastAdvert[guid] or -1e9) > RELAY_GAP then
            AdvertiseMember(guid, m)
            count = count + 1
        end
    end
    -- stats of guildies (and mine) that nobody has pushed lately
    for guid, m in pairs(members) do
        if count >= RELAY_MAX then break end
        if now - (lastStatsAdvert[guid] or -1e9) > RELAY_GAP then
            if ns.IsMine(guid) then
                if guid == ns.myGUID then
                    S.AdvertiseOwnStats()
                    count = count + 1
                end
            elseif m.stats then
                AdvertiseStats(guid, m.name, m.stats)
                count = count + 1
            end
        end
    end
    -- the gold in the guild bank, when nobody has said it lately
    if count < RELAY_MAX and now - lastBankAdvert > RELAY_GAP and ns.GetGuildBank and ns.GetGuildBank() then
        S.AdvertiseBank()
        count = count + 1
    end
    -- open requests of guildies (and mine) that nobody has pushed lately
    for guid, m in pairs(members) do
        if count >= RELAY_MAX then break end
        if now - (lastReqAdvert[guid] or -1e9) > RELAY_GAP then
            if ns.IsMine(guid) then
                local list = ns.DB.requests[guid]
                if guid == ns.myGUID and list and #list > 0 then
                    S.AdvertiseOwnRequests()
                    count = count + 1
                end
            elseif m.reqs and #m.reqs.list > 0 then
                AdvertiseRequests(guid, m.name, m.reqs.rev, m.reqs.list)
                count = count + 1
            end
        end
    end
end

-- A new version: the admin presses the button in the Admin tab once the file is in the Discord channel. Nothing is announced by itself.
local lastReleaseHeard = -1e9
function S.AnnounceRelease()
    if not (ns.IsAdmin() and ns.guildName and started) then return false end
    local v = ns.Version()
    if not v:match("^%d+%.%d+%.?%d*$") then return false end
    ns.DB.announcedVersion = v
    lastReleaseHeard = ns.Now()
    Enqueue("UP|" .. v, "GUILD")
    return true
end

local function IsAdminName(sender)
    local mine = ns.Squash(sender)
    local mineNoRealm = ns.Squash((tostring(sender):gsub("%-.*$", "")))
    for admin in pairs(ns.ADMIN_NAMES) do
        local a = ns.Squash(admin)
        if mine == a or mineNoRealm == a then return true end
    end
    return false
end

-- "UP|version" comes from the admin (checked); "UR|version" is a guildmate repeating it for somebody who just logged in
local function HandleRelease(text, sender)
    local kind, ver = text:match("^(U[PR])|(%d+%.%d+%.?%d*)$")
    if not kind then return end
    if kind == "UP" and not IsAdminName(sender) then return end
    lastReleaseHeard = ns.Now()
    ns.NoteAnnouncement(ver)
end

-- somebody logged in: whoever knows the announced version says it again (once for everybody, after a random wait)
local relayWaitUntil = -1e9
local function RelayRelease()
    local v = ns.DB and ns.DB.announcedVersion
    if not v or ns.Now() < relayWaitUntil then return end          -- (one waiting relay is enough, however many logins are heard)
    local wait = ns.Random(20, 90)
    relayWaitUntil = ns.Now() + wait + 1
    ns.After(wait, function()
        if ns.Now() - lastReleaseHeard > 60 then
            lastReleaseHeard = ns.Now()
            Enqueue("UR|" .. v, "GUILD")
        end
    end)
end

local function HandleHello(text)
    local guid = text:match("^H|(.+)$")
    if not guid or guid == ns.myGUID then return end
    RelayRelease()
    if relayPending then return end
    relayPending = true
    ns.After(ns.Random(3, 25), Relay)
end

---------------------------------------------------------------------------
-- Alt / main settings: only officers (rank 0 and 1) can make them; everybody accepts them from officers only
---------------------------------------------------------------------------
local function ApplyAltLink(alt, main, rev)
    local links = ns.GetAltLinks()
    if not links then return false end
    local old = links[alt]
    if old and (old.rev or 0) >= rev then return false end
    links[alt] = { main = main, rev = rev }
    return true
end

-- main: a character's guid (alt of that one), "-" (this is a main), or nil (back to the automatic guess)
function S.SetAltLink(alt, main)
    if not ns.CanModerate() or not alt or not ns.guildName then return false end
    local links = ns.GetAltLinks()
    local rev = math.max(ns.Time(), ((links and links[alt] and links[alt].rev) or 0) + 1)
    main = main or "x"
    if not ApplyAltLink(alt, main, rev) then return false end
    Enqueue(("M|%s|%s|%d"):format(alt, main, rev), "GUILD")
    Refresh()
    return true
end

-- officers repeat all settings now and then, so guildies who were away get them too
function S.AdvertiseAltLinks()
    if not ns.CanModerate() then return end
    local links = ns.GetAltLinks()
    if not links then return end
    local alts = {}
    for alt in pairs(links) do alts[#alts + 1] = alt end
    table.sort(alts)
    for i, alt in ipairs(alts) do
        if i > 80 then break end
        local link = links[alt]
        Enqueue(("M|%s|%s|%d"):format(alt, link.main, link.rev or 0), "GUILD")
    end
end

local function HandleAltLink(text, sender)
    local alt, main, rev = text:match("^M|([^|]+)|([^|]+)|(%d+)$")
    if not alt then return end
    if not ns.IsOfficerSender(sender) then
        ns.Debug("ignored an alt setting from a non-officer: " .. tostring(sender))
        return
    end
    if ApplyAltLink(alt, main, tonumber(rev)) then Refresh() end
end

---------------------------------------------------------------------------
-- The officer notes: officers share several notes over the OFFICER addon channel (only officers receive it).
-- The newest save of a note wins. A note comes in pieces (the title is in every piece); now and then every officer
-- repeats a short list of what the notes are called and how new they are, so that nobody stays behind.
---------------------------------------------------------------------------
local noteIncoming, noteSeen = {}, {}        -- noteSeen[id] = the newest save heard of that note
local NOTE_PIECE = 130

local function NoteEscape(t) return (t:gsub("\\", "\\\\"):gsub("\n", "\\n")) end
local function NoteUnescape(t)
    return (t:gsub("\\(.)", function(c) if c == "n" then return "\n" end return c end))
end

local function SendNote(id)
    local note = ns.Officer.GetNote(id)
    if not note then return end
    local payload = NoteEscape(note.text or "")
    local total = math.max(1, math.ceil(#payload / NOTE_PIECE))
    local by = tostring(note.by or ""):gsub("[|%c]", "")
    local title = tostring(note.title or ""):gsub("[|%c]", " ")
    for i = 1, total do
        Enqueue(("NM|%s|%d|%d|%d|%d|%s|%s|%s"):format(id, note.rev or 0, i, total, note.deleted and 1 or 0, by, title, payload:sub((i - 1) * NOTE_PIECE + 1, i * NOTE_PIECE)), "OFFICER")
    end
end

-- an officer saved (or deleted) a note: share it
function S.SendNote(id)
    if not (ns.CanModerate() and ns.guildName and started) then return false end
    noteSeen[id] = math.max(noteSeen[id] or 0, (ns.Officer.GetNote(id) or {}).rev or 0)
    SendNote(id)
    return true
end

-- the places of notes in the shared list: NP|id:place:time,id:place:time,...  (the newest time wins for each note)
function S.SendOrder(ids)
    if not (ns.CanModerate() and ns.guildName and started) then return false end
    local chunk, len = {}, 0
    local function Flush() if #chunk > 0 then Enqueue("NP|" .. table.concat(chunk, ","), "OFFICER") chunk, len = {}, 0 end end
    for _, id in ipairs(ids or {}) do
        local n = ns.Officer.GetNote(id)
        if n and n.pos and not n.deleted then
            local e = ("%s:%d:%d"):format(id, n.pos, n.posRev or 0)
            if len + #e + 1 > 200 then Flush() end
            chunk[#chunk + 1] = e
            len = len + #e + 1
        end
    end
    Flush()
    return true
end

local function HandleOrder(text, sender, channel)
    if channel ~= "OFFICER" or not ns.CanModerate() then return end
    local changed = false
    for id, pos, rev in text:sub(4):gmatch("(%w+):(%d+):(%d+)") do
        pos, rev = tonumber(pos), tonumber(rev)
        if pos >= 1 and pos <= 99 and rev > 1100000000 and rev <= ns.Time() + 2 * 86400 then
            if ns.Officer.ReceivePos(id, pos, rev) then changed = true end
        end
    end
    if changed then Refresh() end
end

-- the list of notes with their dates (in as many messages as needed)
function S.AdvertiseNoteHeader()
    if not (ns.CanModerate() and ns.guildName and started) then return end
    ns.Officer.Prune()
    local entries, line = ns.Officer.Digest(), nil
    local chunk = {}
    for _, e in ipairs(entries) do
        if #table.concat(chunk, ",") + #e + 1 > 200 then
            Enqueue("ND|" .. table.concat(chunk, ","), "OFFICER")
            chunk = {}
        end
        chunk[#chunk + 1] = e
    end
    -- (an officer who has nothing yet still says so: the others then send everything they have)
    Enqueue("ND|" .. (#chunk > 0 and table.concat(chunk, ",") or "-"), "OFFICER")
    -- and the order of the notes (so that a late officer gets it too)
    local ids = {}
    for _, n in ipairs(ns.Officer.List()) do if n.pos then ids[#ids + 1] = n.id end end
    S.SendOrder(ids)
end

local function HandleNoteDigest(text, sender, channel)
    if channel ~= "OFFICER" or not ns.CanModerate() then return end
    local theirs = {}
    for id, rev in text:gmatch("([%w]+):(%d+)") do
        rev = tonumber(rev)
        theirs[id] = rev
        noteSeen[id] = math.max(noteSeen[id] or 0, rev)
    end
    -- what the sender does not have, or has an older version of: send it, unless another officer was quicker
    for id, note in pairs(ns.Officer.Notes()) do
        local mine = note.rev or 0
        if mine > 0 and mine > (theirs[id] or 0) then
            ns.After(ns.Random(30, 120) / 10, function()
                local now = ns.Officer.GetNote(id)
                if now and (noteSeen[id] or 0) <= mine and (now.rev or 0) == mine then SendNote(id) end
            end)
        end
    end
end

local function HandleNote(text, sender, channel)
    if channel ~= "OFFICER" or not ns.CanModerate() then return end
    local id, rev, idx, total, deleted, by, title, payload = text:match("^NM|(%w+)|(%d+)|(%d+)|(%d+)|([01])|([^|]*)|([^|]*)|(.*)$")
    if not id then return end
    rev, idx, total = tonumber(rev), tonumber(idx), tonumber(total)
    if rev < 1100000000 or rev > ns.Time() + 2 * 86400 or total < 1 or total > 40 or idx < 1 or idx > total then return end
    noteSeen[id] = math.max(noteSeen[id] or 0, rev)
    local mine = ns.Officer.GetNote(id)
    if mine and rev <= (mine.rev or 0) then return end
    local key = id .. ":" .. rev
    local inc = noteIncoming[key]
    if not inc then
        inc = { parts = {}, got = 0, total = total }
        noteIncoming[key] = inc
    end
    if not inc.parts[idx] then
        inc.parts[idx] = payload
        inc.got = inc.got + 1
    end
    if inc.got == inc.total then
        noteIncoming[key] = nil
        local ordered = {}
        for i = 1, inc.total do ordered[i] = inc.parts[i] end
        ns.Officer.Receive(id, rev, ns.CleanText(title), ns.CleanText(NoteUnescape(table.concat(ordered)), true), deleted == "1", by ~= "" and ns.CleanText(by) or ns.DisplayName(sender))
        Refresh()
    end
end

---------------------------------------------------------------------------
-- Talent tree layouts (where each talent of a class sits). The game is not asked for other classes' trees (that
-- fires Blizzard's talent events inside our call and the game blocks it). Whoever has a layout - from their own
-- character or from inspecting somebody - shares it when asked; everybody keeps what they get.
---------------------------------------------------------------------------
local layoutWanted, layoutAsked, layoutHeard, layoutIncoming, layoutSentAt = {}, {}, {}, {}, {}

function S.RequestLayout(specID)
    if not (ns.guildName and started) or not specID or specID <= 0 then return false end
    local now = ns.Now()
    layoutWanted[specID] = now
    if layoutAsked[specID] and now - layoutAsked[specID] < 60 then return true end
    layoutAsked[specID] = now
    Enqueue(("LQ|%d|%s"):format(specID, tostring(ns.Inspect.BuildNumber()):gsub("[^%w%.]", "")), "GUILD")
    return true
end

local function SendLayout(specID)
    local layout = ns.DB.talentLayouts and ns.DB.talentLayouts[specID]
    if not layout then return end
    layoutSentAt[specID] = ns.Now()
    local chunks, cur = {}, ""
    for _, part in ipairs(ns.Inspect.EncodeLayout(layout)) do
        if cur ~= "" and #cur + #part + 1 > 170 then chunks[#chunks + 1] = cur cur = part
        else cur = (cur == "") and part or (cur .. ";" .. part) end
    end
    if cur ~= "" then chunks[#chunks + 1] = cur end
    local build = tostring(layout.build):gsub("[^%w%.]", "")
    for n, c in ipairs(chunks) do
        Enqueue(("LY|%d|%s|%d|%d|%s"):format(specID, build, n, #chunks, c), "GUILD")
    end
end

local function HandleLayoutAsk(text)
    local spec, build = text:match("^LQ|(%d+)|([%w%.]*)$")
    spec = tonumber(spec)
    if not spec then return end
    local mine = ns.DB.talentLayouts and ns.DB.talentLayouts[spec]
    if not mine or tostring(mine.build):gsub("[^%w%.]", "") ~= build then return end
    local asked = ns.Now()
    if layoutSentAt[spec] and asked - layoutSentAt[spec] < 120 then return end
    ns.After(ns.Random(30, 120) / 10, function()
        if (layoutHeard[spec] or -1) >= asked then return end     -- somebody was quicker
        SendLayout(spec)
    end)
end

local function HandleLayoutData(text)
    local spec, build, idx, total, payload = text:match("^LY|(%d+)|([%w%.]*)|(%d+)|(%d+)|(.*)$")
    spec, idx, total = tonumber(spec), tonumber(idx), tonumber(total)
    if not spec or total < 1 or total > 40 or idx < 1 or idx > total then return end
    local now = ns.Now()
    layoutHeard[spec] = now
    local ours = tostring(ns.Inspect.BuildNumber()):gsub("[^%w%.]", "")
    if build ~= ours then return end                              -- another game version: positions may differ
    local cached = ns.DB.talentLayouts and ns.DB.talentLayouts[spec]
    if cached and tostring(cached.build):gsub("[^%w%.]", "") == ours and #cached.nodes > 0 then return end   -- we have it
    local inc = layoutIncoming[spec]
    if not inc or inc.total ~= total then
        inc = { parts = {}, got = 0, total = total, t = now }
        layoutIncoming[spec] = inc
    end
    if not inc.parts[idx] then
        inc.parts[idx] = payload
        inc.got = inc.got + 1
    end
    if inc.got == inc.total then
        layoutIncoming[spec] = nil
        local ordered = {}
        for n = 1, inc.total do ordered[n] = inc.parts[n] end
        local nodes = ns.Inspect.DecodeLayout(table.concat(ordered, ";"))
        if nodes then
            ns.DB.talentLayouts = ns.DB.talentLayouts or {}
            ns.DB.talentLayouts[spec] = { build = ns.Inspect.BuildNumber(), nodes = nodes }
            if ns.OnLayoutData then ns.OnLayoutData(spec) end
        end
    end
    for k, v in pairs(layoutIncoming) do
        if now - v.t > 120 then layoutIncoming[k] = nil end
    end
end

---------------------------------------------------------------------------
-- Shitlist: entries are made by officers; everybody accepts them from officers only and keeps a copy
---------------------------------------------------------------------------
local function EntryMessage(e, kind)
    -- B2|rev|addedAt|gone|by|name|reason   (the reason is last, it may contain anything)
    -- BR| is the same entry passed on by somebody who is not an officer (see HandleBlacklist)
    local head = ("%s|%d|%d|%d|%s|%s|"):format(kind or "B2", e.rev or 0, e.addedAt or 0, e.gone and 1 or 0, ((e.by or ""):gsub("[|]", "")), ((e.name or ""):gsub("[|]", "")))
    local reason = e.reason or ""
    local room = 250 - #head
    if #reason > room then
        reason = reason:sub(1, math.max(0, room))
        -- never cut a multi-byte character in half
        while #reason > 0 and reason:byte(#reason) >= 0x80 and reason:byte(#reason) < 0xC0 do reason = reason:sub(1, #reason - 1) end
        if #reason > 0 and reason:byte(#reason) >= 0xC0 then reason = reason:sub(1, #reason - 1) end
    end
    return head .. reason
end

function S.SendBlacklistEntry(e)
    if ns.guildName then Enqueue(EntryMessage(e), "GUILD") end
end

-- officers repeat the whole list now and then (removals too), so everybody who was away catches up
function S.AdvertiseBlacklist()
    if not (ns.CanModerate() and ns.guildName and ns.Blacklist) then return end
    local all = ns.Blacklist.All()
    table.sort(all, function(a, b) return tostring(a.name) < tostring(b.name) end)
    for i, e in ipairs(all) do
        if i > 120 then break end
        Enqueue(EntryMessage(e), "GUILD")
    end
end

-- Everybody keeps the list and passes it on, officers or not: a guildmate who logs in asks (BQ), and anybody who has newer
-- or more entries answers with BR messages (a random wait, and nobody answers when somebody else already did).
-- Entries are only MADE by officers (the buttons check it, and a direct B2 message is only accepted from officer ranks);
-- BR messages are accepted from any guild member because they only repeat what officers made.
local blHeard, blRelayed = -1000, -1000

function S.RelayBlacklist()
    if not (ns.guildName and ns.Blacklist) then return end
    blRelayed = ns.Now()
    local count = 0
    for _, e in ipairs(ns.Blacklist.All()) do
        count = count + 1
        if count > 120 then break end
        Enqueue(EntryMessage(e, "BR"), "GUILD")
    end
end

function S.RequestBlacklist()
    if not (ns.guildName and started and ns.Blacklist) then return end
    local count, maxRev = ns.Blacklist.Digest()
    Enqueue(("BQ|%d|%d"):format(count, maxRev), "GUILD")
end

local function HandleBlacklistAsk(text)
    local count, maxRev = text:match("^BQ|(%d+)|(%d+)$")
    if not count or not ns.Blacklist then return end
    local mine, newest = ns.Blacklist.Digest()
    if mine == 0 then return end
    if not (newest > tonumber(maxRev) or mine > tonumber(count)) then return end      -- nothing the asker lacks
    local asked = ns.Now()
    ns.After(ns.Random(50, 250) / 10, function()
        if blHeard > asked then return end                       -- somebody else answered meanwhile
        if ns.Now() - blRelayed < 120 then return end
        S.RelayBlacklist()
    end)
end

local function HandleBlacklist(text, sender)
    -- B2 (with the name of the officer who added it), BR (the same, passed on by any guildmate) or B (older versions)
    local relayed = text:sub(1, 3) == "BR|"
    local rev, addedAt, gone, by, name, reason = text:match("^B[2R]|(%d+)|(%d+)|(%d)|([^|]*)|([^|]+)|(.*)$")
    if not rev then
        rev, addedAt, gone, name, reason = text:match("^B|(%d+)|(%d+)|(%d)|([^|]+)|(.*)$")
        by = nil
    end
    if not rev then return end
    if relayed then
        blHeard = ns.Now()
        if not ns.RosterFind(ns.GetRoster(), sender) then
            ns.Debug("ignored a passed-on shitlist entry from somebody not in the guild roster: " .. tostring(sender))
            return
        end
    elseif not ns.IsOfficerSender(sender) then
        ns.Debug("ignored a shitlist change from a non-officer: " .. tostring(sender))
        return
    end
    ns.Blacklist.Apply(name, reason, tonumber(addedAt), gone == "1", tonumber(rev), by)
end

---------------------------------------------------------------------------
-- Status for the admin: version, session, message counts, errors. Everybody's addon sends it now and then.
---------------------------------------------------------------------------
local function BuildNumber()
    local b
    pcall(function() b = select(2, GetBuildInfo()) end)
    return tostring(b or "?")
end

-- what this installation knows about itself
function S.OwnDiag()
    local profs, recipes = 0, 0
    for _, ch in pairs(ns.DB.mine or {}) do
        for _, p in pairs(ch.profs or {}) do
            profs = profs + 1
            recipes = recipes + #(p.ids or {})
        end
    end
    local members = 0
    for _ in pairs(ns.GetMembers() or {}) do members = members + 1 end
    return {
        version = ns.Version(), build = BuildNumber(), session = ns.SessionMinutes(), inN = counters.inN, outN = counters.outN,
        errors = ns.errors.count, profs = profs, recipes = recipes, members = members, lastError = ns.errors.last or "", at = ns.Time(),
    }
end

local lastStatus = -1e9
function S.AdvertiseStatus()
    if not (ns.guildName and started and ns.myGUID) then return end
    local now = ns.Now()
    if now - lastStatus < 60 then return end
    lastStatus = now
    local d = S.OwnDiag()
    local own = ns.GetOwn()
    if own then own.diag = d end
    Enqueue(("W|%s|%s|%s|%d|%d|%d|%d|%d|%d|%d|%s"):format(ns.myGUID, (d.version:gsub("[|]", "")), (d.build:gsub("[|]", "")), d.session, d.inN, d.outN,
        d.errors, d.profs, d.recipes, d.members, (d.lastError:gsub("[|\r\n]+", " "))), "GUILD")
end

local function HandleStatus(text)
    local guid, ver, build, session, inN, outN, errors, profs, recipes, members, lastError =
        text:match("^W|([^|]+)|([^|]*)|([^|]*)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if not guid or ns.IsMine(guid) then return end
    local all = ns.GetMembers()
    if not all then return end
    local m = all[guid]
    if not m then
        local roster = ns.GetRoster()
        local entry = roster.byGUID[guid]
        m = { name = entry and entry.name or "?", profs = {} }
        all[guid] = m
    end
    m.seen = ns.Time()
    m.diag = {
        version = ver, build = build, session = tonumber(session), inN = tonumber(inN), outN = tonumber(outN), errors = tonumber(errors),
        profs = tonumber(profs), recipes = tonumber(recipes), members = tonumber(members), lastError = ns.CleanText(lastError), at = ns.Time(),
    }
end

-- the admin asks everybody to report now (the answers are spread out over a minute)
local lastStatusAsk = -1e9
function S.RequestStatus()
    if not (ns.IsAdmin() and ns.guildName and started) then return false end
    local now = ns.Now()
    if now - lastStatusAsk < 120 then return false end
    lastStatusAsk = now
    Enqueue("WQ|", "GUILD")
    return true
end

local function HandleStatusAsk(sender)
    local mine = ns.Squash(sender)
    local mineNoRealm = ns.Squash((tostring(sender):gsub("%-.*$", "")))
    local isAdmin = false
    for admin in pairs(ns.ADMIN_NAMES) do
        local a = ns.Squash(admin)
        if mine == a or mineNoRealm == a then isAdmin = true end
    end
    if not isAdmin then return end
    ns.After(ns.Random(2, 50), S.AdvertiseStatus)
end

---------------------------------------------------------------------------
-- Final boss encounter ids: boss NAMES are language dependent, ids are not. Clients that know the English
-- names of the final bosses share the ids they have seen, so clients in other languages count dungeons too.
---------------------------------------------------------------------------
function S.AdvertiseBossIDs()
    if not (ns.guildName and started) then return end
    local ids = {}
    for id in pairs(ns.DB.finalBossIDs or {}) do ids[#ids + 1] = id end
    if #ids == 0 then return end
    table.sort(ids)
    local cur = {}
    for _, id in ipairs(ids) do
        cur[#cur + 1] = id
        if #cur >= 24 then
            Enqueue("L|" .. table.concat(cur, ","), "GUILD")
            cur = {}
        end
    end
    if #cur > 0 then Enqueue("L|" .. table.concat(cur, ","), "GUILD") end
end

local function HandleBossIDs(text)
    ns.DB.finalBossIDs = ns.DB.finalBossIDs or {}
    for digits in text:gmatch("(%d+)") do
        local id = tonumber(digits)
        if id and id > 0 and id < 10000000 then ns.DB.finalBossIDs[id] = true end
    end
end

---------------------------------------------------------------------------
-- Achievements (guild firsts): AC|key|date|guid|name. Everybody keeps the earliest date per character.
---------------------------------------------------------------------------
function S.SendCriterion(key, cid, ts, timeKnown)
    if not (ns.guildName and started) then return false end
    Enqueue(("RC|%s|%d|%d|%d"):format(key, cid, ts, timeKnown and 1 or 0), "GUILD")
    return true
end

function S.SendAchievement(key, ts, guid, name, timeKnown)
    if not (ns.guildName and started and guid) then return false end
    Enqueue(("AC|%s|%d|%s|%s|%d"):format(key, ts, guid, (tostring(name or ""):gsub("[|]", ""):sub(1, 40)), timeKnown and 1 or 0), "GUILD")
    return true
end

local function HandleCriterion(text)
    -- RC|raid key|step number|date|1 (the 1 says the time of day is known)
    local key, cid, ts, timeKnown = text:match("^RC|(R:%w+)|(%d+)|(%d+)|?(%d?)$")
    if not key then return end
    ns.Achievements.ReceiveCriterion(key, tonumber(cid), tonumber(ts), timeKnown == "1")
end

local function HandleAchievement(text)
    -- AC|key|date|guid|name|1 (the 1 says the time of day is known); older versions sent no last field
    local key, ts, guid, name, timeKnown = text:match("^AC|([LPR]:%w+:?%d*)|(%d+)|([%w%-]+)|([^|]*)|?(%d?)$")
    if not key or ns.IsMine(guid) then return end
    -- a raid with steps from the game is the guild's only when all steps are met: it is worked out from the steps (RC), not from a claim
    if key:find("^R:") and #ns.Achievements.TrackedCriteria(key) > 0 then return end
    ns.Achievements.Heard(key, guid)
    ns.Achievements.Record(key, guid, name, tonumber(ts), false, timeKnown == "1")
end

---------------------------------------------------------------------------
-- The raid calendar: officers and the guild master add and remove events (Raids.lua); everybody keeps what they
-- send. RE = header of an event, RD = a piece of its text, RX = removal, RQ = "this is what I have" (answered by
-- an officer who has something else).
---------------------------------------------------------------------------
local function Field(text) return (tostring(text or ""):gsub("[%c|]", " ")) end

function S.SendRaid(rec)
    if not (ns.guildName and started) then return false end
    local chunks = ns.Raids.Chunks(ns.Raids.Payload(rec), 170)
    Enqueue(("RE|%s|%d|%d|%d|%d|%s|%s|%s"):format(rec.id, rec.rev, rec.start, rec.addedAt or rec.rev, #chunks, Field(rec.by):sub(1, 30), Field(rec.leader):sub(1, 30), Field(rec.title):sub(1, 60)), "GUILD")
    for i, piece in ipairs(chunks) do
        Enqueue(("RD|%s|%d|%d|%s"):format(rec.id, rec.rev, i, piece), "GUILD")
    end
    return true
end

function S.SendRaidRemoval(id, rev, by)
    if not (ns.guildName and started) then return false end
    Enqueue(("RX|%s|%d|%s"):format(id, rev, Field(by):sub(1, 30)), "GUILD")
    return true
end

-- one character of a Discord name (on = 1) or its removal (on = 0)
function S.SendLink(key, guid, rev, on, cname, by)
    if not (ns.guildName and started) then return false end
    Enqueue(("DL|%s|%s|%d|%d|%s|%s"):format(Field(key):sub(1, 32), guid, rev, on and 1 or 0, Field(cname):sub(1, 30), Field(by):sub(1, 30)), "GUILD")
    return true
end

local lastRaidAdvert = -1000
-- an officer shares the events and the removals of the last month (older events stay in the Calendar, they are not sent again)
function S.AdvertiseRaids()
    if not (ns.guildName and started and ns.CanModerate()) then return end
    lastRaidAdvert = ns.Now()
    local store = ns.DB.guilds[ns.guildName] and ns.DB.guilds[ns.guildName].raids
    if not store then return end
    for _, rec in ipairs(ns.Raids.Shared()) do S.SendRaid(rec) end
    local since = ns.Raids.SharedSince()
    for id, rev in pairs(store.removed or {}) do if rev >= since then S.SendRaidRemoval(id, rev, "") end end
    for key, links in pairs(store.names or {}) do
        for guid, l in pairs(links) do S.SendLink(key, guid, l.rev, l.on, l.cname, l.by) end
    end
end

-- everybody asks once after logging in
function S.RequestRaids()
    if not (ns.guildName and started) then return end
    local count, maxRev = ns.Raids.Digest()
    Enqueue(("RQ|%d|%d"):format(count, maxRev), "GUILD")
end

local function HandleRaidHeader(text, sender)
    if not ns.IsOfficerSender(sender) then return end
    local id, rev, start, addedAt, total, by, leader, title = text:match("^RE|([%w_%-]+)|(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)|([^|]*)|(.*)$")
    if id then ns.Raids.ReceiveHeader(id, rev, start, addedAt, total, by, leader, title) end
end

local function HandleRaidChunk(text, sender)
    if not ns.IsOfficerSender(sender) then return end
    local id, rev, idx, chunk = text:match("^RD|([%w_%-]+)|(%d+)|(%d+)|(.*)$")
    if id then ns.Raids.ReceiveChunk(id, rev, idx, chunk) end
end

local function HandleRaidRemoval(text, sender)
    if not ns.IsOfficerSender(sender) then return end
    local id, rev = text:match("^RX|([%w_%-]+)|(%d+)|")
    if id then ns.Raids.ApplyRemoval(id, tonumber(rev)) end
end

local function HandleLink(text, sender)
    if not ns.IsOfficerSender(sender) then return end
    local key, guid, rev, on, cname, by = text:match("^DL|([^|]+)|([%w%-]+)|(%d+)|([01])|([^|]*)|([^|]*)$")
    if key then ns.Raids.ApplyLink(key, guid, on == "1", rev, cname, by) end
end

local function HandleRaidRequest(text)
    if not ns.CanModerate() then return end
    local count, maxRev = text:match("^RQ|(%d+)|(%d+)$")
    if not count then return end
    local mine, newest = ns.Raids.Digest()
    if tonumber(count) == mine and tonumber(maxRev) == newest then return end
    ns.After(ns.Random(50, 250) / 10, function()
        if ns.Now() - lastRaidAdvert > 120 then S.AdvertiseRaids() end
    end)
end

-- race and role of a character (only used for the charts on the Analytics tab)
local function HandleCharInfo(text)
    local guid, race, role = text:match("^P|([^|]+)|([%w_]*)|([A-Z]?)$")
    if not guid or ns.IsMine(guid) then return end
    local members = ns.GetMembers()
    local m = members and members[guid]
    if not m then return end
    if race ~= "" then m.race = (race:gsub("_", " ")) end
    if role ~= "" then m.role = role end
end

-- the main talent tree of a character (for the spec chart): PS|guid|tree name (the older numeric form is ignored)
local function HandleCharSpec(text)
    local guid, tree = text:match("^PS|([^|]+)|(%a[%a ]*)$")
    if not guid or ns.IsMine(guid) then return end
    local members = ns.GetMembers()
    local m = members and members[guid]
    if not m then return end
    if #tree <= 24 then m.tree = tree end
end

-- which installation (person) a character belongs to, and when that character first submitted data:
-- the oldest character of an installation is the original, the others are its alts
local function HandleClient(text)
    local guid, client, created = text:match("^U|([^|]+)|(%w+)|?(%d*)$")
    if not guid or ns.IsMine(guid) then return end
    local members = ns.GetMembers()
    local m = members and members[guid]
    if m then
        m.client = client
        local c = tonumber(created)
        if c and c > 0 then m.created = c end
    end
end

---------------------------------------------------------------------------
-- Inspect: gear and talents. Anybody can ask (V|guid). The owner's own addon answers first; a guildie who
-- holds a copy (from the owner, or from scanning them in the game) answers if nobody else did. A guildie who
-- scans somebody in the game shares what they saw (E| messages), so everybody can look at that person.
---------------------------------------------------------------------------
local inspectWanted, inspectAsked, inspectIncoming = {}, {}, {}
local inspectServed, inspectHeard, lastShared = -1e9, {}, {}

function S.RequestInspect(guid)
    if not (ns.guildName and started) then return false end
    local now = ns.Now()
    inspectWanted[guid] = now
    if inspectAsked[guid] and now - inspectAsked[guid] < 5 then return true end
    inspectAsked[guid] = now
    Enqueue("V|" .. guid, "GUILD")
    return true
end

-- send a profile (mine, or somebody's we hold) as chunks; rev = when it was captured
local function SendProfile(guid, profile)
    local chunks = ns.Inspect.Chunk(ns.Inspect.Encode(profile), 170)
    local rev = math.floor(profile.at or ns.Time())
    for i, c in ipairs(chunks) do
        Enqueue(("E|%s|%d|%d|%d|%s"):format(guid, rev, i, #chunks, c), "GUILD")
    end
end

-- I just scanned somebody in the game: share it (at most every ten minutes per person)
function S.ShareScan(guid)
    if not (ns.guildName and started) then return end
    local profile = ns.DB.inspect[guid]
    if not profile then return end
    local now = ns.Now()
    if lastShared[guid] and now - lastShared[guid] < 600 then return end
    lastShared[guid] = now
    inspectHeard[guid] = now
    SendProfile(guid, profile)
end

local function HandleViewRequest(text)
    local guid = text:match("^V|(.+)$")
    if not guid then return end
    local now = ns.Now()
    if guid == ns.myGUID then
        if now - inspectServed < 3 then return end
        inspectServed = now
        ns.After(ns.Random(2, 8) / 10, function()
            local profile = ns.Inspect.CaptureSelf()
            profile.at = ns.Time()
            SendProfile(ns.myGUID, profile)
        end)
        return
    end
    -- somebody else's: answer from a copy we hold, but only if nobody answers before us
    local cached = ns.DB.inspect[guid]
    if cached and ns.Time() - (cached.at or 0) < 3 * 86400 and not (lastShared[guid] and now - lastShared[guid] < 120) then
        ns.After(ns.Random(30, 90) / 10, function()
            if (inspectHeard[guid] or -1) >= now then return end
            lastShared[guid] = ns.Now()
            SendProfile(guid, ns.DB.inspect[guid] or cached)
        end)
    end
end

local function HandleInspectData(text)
    local guid, rev, idx, total, payload = text:match("^E|([^|]+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if not guid or guid == ns.myGUID then return end
    local now = ns.Now()
    inspectHeard[guid] = now
    idx, total = tonumber(idx), tonumber(total)
    if total < 1 or total > 40 or idx < 1 or idx > total then return end

    local k = guid .. "|" .. rev
    local inc = inspectIncoming[k]
    if not inc then
        inc = { parts = {}, got = 0, total = total, t = now }
        inspectIncoming[k] = inc
    end
    if not inc.parts[idx] then
        inc.parts[idx] = payload
        inc.got = inc.got + 1
    end
    if inc.got == inc.total then
        inspectIncoming[k] = nil
        local ordered = {}
        for i = 1, inc.total do ordered[i] = inc.parts[i] end
        local profile = ns.Inspect.Decode(table.concat(ordered, "|"))
        profile.at = math.min(tonumber(rev), ns.Time())
        -- stored when we asked for it, or when it is newer than what we have (a guildie shared a scan)
        local wanted = inspectWanted[guid] and now - inspectWanted[guid] <= 120
        local cached = ns.DB.inspect[guid]
        if wanted or not cached or profile.at > (cached.at or 0) then
            if ns.Inspect.Store(guid, profile) and ns.OnInspectData then ns.OnInspectData(guid) end
        end
    end
    for ik, v in pairs(inspectIncoming) do
        if now - v.t > 120 then inspectIncoming[ik] = nil end
    end
end

-- Incoming messages are counted per sender (the game writes the sender's name itself, nobody can use another's): a busy but honest
-- addon sends at most one message every 0.4 s (and about a hundred at once when it answers somebody who just logged in). A bucket of
-- RATE_CAP messages that refills at RATE_REFILL a second takes all of that; what comes in faster than that is dropped. A second bucket
-- limits all senders together, so a flood from many characters at once is limited too.
S.RATE_CAP, S.RATE_REFILL = 150, 4
S.GLOBAL_CAP, S.GLOBAL_REFILL = 300, 30
local senderBucket, senderCount = {}, 0
local globalBucket = { tokens = S.GLOBAL_CAP, t = nil }

local function RateOK(sender)
    local now = ns.Now()
    local key = ns.Squash(tostring(sender or ""))
    local mine = ns.me and ns.Squash(ns.me) == key
    if mine then return true end                      -- (what I sent myself)
    local g = globalBucket
    g.tokens = math.min(S.GLOBAL_CAP, g.tokens + (g.t and (now - g.t) or 0) * S.GLOBAL_REFILL)
    g.t = now
    local b = senderBucket[key]
    if not b then
        if senderCount >= 500 then senderBucket, senderCount = {}, 0 end
        b = { tokens = S.RATE_CAP, t = now }
        senderBucket[key] = b
        senderCount = senderCount + 1
    end
    b.tokens = math.min(S.RATE_CAP, b.tokens + (now - b.t) * S.RATE_REFILL)
    b.t = now
    if b.tokens < 1 or g.tokens < 1 then return false end
    b.tokens, g.tokens = b.tokens - 1, g.tokens - 1
    return true
end

function S.OnMessage(text, sender, channel)
    if not RateOK(sender) then counters.dropped = counters.dropped + 1 return end
    if not ns.guildName or (channel ~= "GUILD" and channel ~= "OFFICER") then return end
    counters.inN = counters.inN + 1
    local kind = text:sub(1, 2)
    -- the officer note travels on the OFFICER channel; everything else on the guild channel
    if kind == "NM" then HandleNote(text, sender, channel) return end
    if kind == "ND" then HandleNoteDigest(text, sender, channel) return end
    if kind == "NP" then HandleOrder(text, sender, channel) return end
    if channel ~= "GUILD" then return end
    if kind == "A|" then HandleAdvert(text, sender)
    elseif kind == "G|" then HandleGet(text)
    elseif kind == "D|" then HandleData(text)
    elseif kind == "Q|" then HandleInfoAsk(text)
    elseif kind == "I|" then HandleInfo(text)
    elseif kind == "H|" then HandleHello(text)
    elseif kind == "Y|" then HandleRequests(text)
    elseif kind == "T|" then HandleStats(text, sender)
    elseif kind == "X|" then HandleCraftsX(text)
    elseif kind == "SP" then HandleSpecs(text)
    elseif kind == "PS" then HandleCharSpec(text)
    elseif kind == "CD" then HandleCooldowns(text)
    elseif kind == "S|" then HandleGameStats(text)
    elseif kind == "GB" then HandleGuildBank(text)
    elseif kind == "J|" then HandleJoined(text)
    elseif kind == "AC" then HandleAchievement(text)
    elseif kind == "RC" then HandleCriterion(text)
    elseif kind == "RE" then HandleRaidHeader(text, sender)
    elseif kind == "RD" then HandleRaidChunk(text, sender)
    elseif kind == "RX" then HandleRaidRemoval(text, sender)
    elseif kind == "RQ" then HandleRaidRequest(text)
    elseif kind == "DL" then HandleLink(text, sender)
    elseif kind == "Z|" then HandleDelete(text, sender)
    elseif kind == "U|" then HandleClient(text)
    elseif kind == "M|" then HandleAltLink(text, sender)
    elseif kind == "P|" then HandleCharInfo(text)
    elseif kind == "B|" or kind == "B2" or kind == "BR" then HandleBlacklist(text, sender)
    elseif kind == "BQ" then HandleBlacklistAsk(text)
    elseif kind == "W|" then HandleStatus(text)
    elseif kind == "LQ" then HandleLayoutAsk(text)
    elseif kind == "LY" then HandleLayoutData(text)
    elseif kind == "L|" then HandleBossIDs(text)
    elseif kind == "WQ" then HandleStatusAsk(sender)
    elseif kind == "UP" or kind == "UR" then HandleRelease(text, sender)
    elseif kind == "V|" then HandleViewRequest(text)
    elseif kind == "E|" then HandleInspectData(text) end
end

-- how many messages were dropped for coming in too fast (/ff sync)
function S.Dropped() return counters.dropped end

-- for tests
S._queueLength = function() return #queue end
