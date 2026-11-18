---@class ns
local ns = select(2, ...)

-- The raid calendar of the addon. Officers and the guild master paste the JSON of a Raid-Helper event into the
-- Management tab; the event is added here and shared with everybody who uses the addon (Sync.lua). The addon does
-- not use the game's calendar for any of this. Times are unix times (the same moment everywhere), shown in each
-- player's own time.

local R = {}
ns.Raids = R

---------------------------------------------------------------------------
-- a small JSON reader (the game has none)
---------------------------------------------------------------------------
local function Utf8(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40, 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local ESCAPES = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
local NULL = {}          -- JSON null (a table nobody else has)

local ParseValue
local function SkipSpace(s, i) return s:find("[^ \t\r\n]", i) or (#s + 1) end

local function ParseString(s, i)       -- s:sub(i, i) is the opening quote
    local out = {}
    i = i + 1
    while true do
        local j = s:find('["\\]', i)
        if not j then return nil, "a text is not closed" end
        out[#out + 1] = s:sub(i, j - 1)
        if s:sub(j, j) == '"' then return table.concat(out), j + 1 end
        local c = s:sub(j + 1, j + 1)
        if c == "u" then
            local hex = s:match("^%x%x%x%x", j + 2)
            if not hex then return nil, "a broken \\u escape" end
            local cp, advance = tonumber(hex, 16), 6
            if cp >= 0xD800 and cp <= 0xDBFF then
                local low = s:match("^\\u(%x%x%x%x)", j + 6)
                low = low and tonumber(low, 16)
                if low and low >= 0xDC00 and low <= 0xDFFF then
                    cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
                    advance = 12
                end
            end
            out[#out + 1] = Utf8(cp)
            i = j + advance
        else
            out[#out + 1] = ESCAPES[c] or c
            i = j + 2
        end
    end
end

ParseValue = function(s, i, depth)
    if depth > 40 then return nil, "nested too deep" end
    i = SkipSpace(s, i)
    local c = s:sub(i, i)
    if c == "{" then
        local obj = {}
        i = SkipSpace(s, i + 1)
        if s:sub(i, i) == "}" then return obj, i + 1 end
        while true do
            i = SkipSpace(s, i)
            if s:sub(i, i) ~= '"' then return nil, "a name was expected at position " .. i end
            local key, nextI = ParseString(s, i)
            if not key then return nil, nextI end
            i = SkipSpace(s, nextI)
            if s:sub(i, i) ~= ":" then return nil, "a colon was expected at position " .. i end
            local value
            value, nextI = ParseValue(s, i + 1, depth + 1)
            if value == nil then return nil, nextI end
            obj[key] = value
            i = SkipSpace(s, nextI)
            local d = s:sub(i, i)
            if d == "," then i = i + 1
            elseif d == "}" then return obj, i + 1
            else return nil, "a comma or } was expected at position " .. i end
        end
    elseif c == "[" then
        local arr = {}
        i = SkipSpace(s, i + 1)
        if s:sub(i, i) == "]" then return arr, i + 1 end
        while true do
            local value, nextI = ParseValue(s, i, depth + 1)
            if value == nil then return nil, nextI end
            arr[#arr + 1] = value
            i = SkipSpace(s, nextI)
            local d = s:sub(i, i)
            if d == "," then i = i + 1
            elseif d == "]" then return arr, i + 1
            else return nil, "a comma or ] was expected at position " .. i end
        end
    elseif c == '"' then
        return ParseString(s, i)
    elseif s:find("^true", i) then return true, i + 4
    elseif s:find("^false", i) then return false, i + 5
    elseif s:find("^null", i) then return NULL, i + 4
    else
        local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
        if num and num ~= "" and num ~= "-" then return tonumber(num), i + #num end
        return nil, "something unexpected at position " .. i
    end
end

-- returns the value, or nil and what is wrong
function R.DecodeJSON(text)
    if type(text) ~= "string" then return nil, "nothing to read" end
    if #text > 300000 then return nil, "that is too much text" end
    text = text:gsub("^\239\187\191", "")         -- a byte order mark
    local value, nextI = ParseValue(text, 1, 0)
    if value == nil then return nil, nextI end
    local rest = SkipSpace(text, nextI)
    if rest <= #text then return nil, "there is more text after the end at position " .. rest end
    return value
end

---------------------------------------------------------------------------
-- reading a Raid-Helper event
---------------------------------------------------------------------------
local CLASS_TOKEN = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST", shaman = "SHAMAN",
    mage = "MAGE", warlock = "WARLOCK", druid = "DRUID",
}
-- Raid-Helper uses some "classes" for the state of a sign-up
local STATE_WORDS = { absence = "absent", absent = "absent", declined = "absent", bench = "bench", benched = "bench",
    late = "late", tentative = "tentative", maybe = "tentative" }
-- Raid-Helper's classic templates have a "Tank" class (Protection, Protection1, Guardian) next to the real ones:
-- the real class then comes from the specialization ("1" at the end tells two classes' same-named specs apart)
local SPEC_CLASS = {
    arms = "WARRIOR", fury = "WARRIOR", protection = "WARRIOR",
    holy1 = "PALADIN", protection1 = "PALADIN", retribution = "PALADIN",
    balance = "DRUID", dreamstate = "DRUID", feral = "DRUID", restoration = "DRUID", guardian = "DRUID",
    assassination = "ROGUE", combat = "ROGUE", subtlety = "ROGUE",
    beastmastery = "HUNTER", marksmanship = "HUNTER", survival = "HUNTER",
    discipline = "PRIEST", holy = "PRIEST", shadow = "PRIEST", smite = "PRIEST",
    arcane = "MAGE", fire = "MAGE", frost = "MAGE",
    affliction = "WARLOCK", demonology = "WARLOCK", destruction = "WARLOCK",
    elemental = "SHAMAN", enhancement = "SHAMAN", restoration1 = "SHAMAN",
}
local VALID_ROLE = { T = true, H = true, M = true, R = true, D = true }
local VALID_STATE = { signed = true, bench = true, late = true, tentative = true, absent = true }

local function Clean(text, limit)
    text = tostring(text or ""):gsub("[%c|~^]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return text:sub(1, limit or 60)
end

local function Pick(t, ...)
    for i = 1, select("#", ...) do
        local v = t[(select(i, ...))]
        if v ~= nil and v ~= NULL and v ~= "" then return v end
    end
    return nil
end

local function RoleOf(role, spec)
    local r = tostring(role or ""):lower()
    local s = tostring(spec or ""):lower()
    if r:find("tank") then return "T" end
    if r:find("heal") then return "H" end
    if r:find("melee") then return "M" end
    if r:find("range") then return "R" end
    if r:find("dps") or r:find("damage") then return "D" end
    return "O"
end

-- Looks for the event in the pasted JSON. Returns { id, title, desc, start, leader, signups } or nil and why not.
function R.ParseEvent(text)
    local data, err = R.DecodeJSON(text)
    if data == nil then return nil, err or "that is not JSON" end
    if type(data) ~= "table" or data == NULL then return nil, "that is not an event" end
    -- some exports wrap the event: { "event": { ... } } or { "data": { ... } }
    if data.title == nil and type(data.event) == "table" then data = data.event end
    if data.title == nil and type(data.data) == "table" then data = data.data end
    if #data > 0 and type(data[1]) == "table" then data = data[1] end

    local title = Pick(data, "title", "displayTitle", "name")
    if type(title) ~= "string" then return nil, "there is no title in it" end
    local start = Pick(data, "startTime", "starttime", "unixtime", "startTimestamp", "start")
    start = tonumber(start)
    if start and start > 100000000000 then start = math.floor(start / 1000) end     -- milliseconds
    if not start or start < 1100000000 or start > 4100000000 then
        return nil, "there is no start time in it (a number of seconds, usually \"startTime\")"
    end
    local ev = {
        id = Clean(tostring(Pick(data, "id", "eventId", "messageId") or ""), 24):gsub("[^%w_%-]", ""),
        title = Clean(title, 60),
        desc = Clean(Pick(data, "description", "desc") or "", 300),
        start = math.floor(start),
        leader = Clean(Pick(data, "leaderName", "leader", "author", "organizer") or "", 30),
        org = "",
        signups = {},
    }
    if ev.id == "" then
        local h = 5381
        for k = 1, #ev.title do h = (h * 33 + ev.title:byte(k)) % 2147483647 end
        ev.id = ("t%d-%d"):format(ev.start, h)
    end
    -- "organized by": who made the event in Discord (the creator), else the leader
    local creator = data.creator
    if type(creator) == "table" then ev.org = Clean(Pick(creator, "name", "username", "displayName") or "", 30) end
    local list = Pick(data, "signUps", "signups", "signUpList", "attendees") or {}
    if type(list) == "table" then
        for _, e in ipairs(list) do
            if type(e) == "table" and #ev.signups < 80 then
                local name = Clean(Pick(e, "name", "username", "displayName") or "", 24)
                if name ~= "" then
                    local cls = tostring(Pick(e, "className", "class") or "")
                    local rawSpec = Clean(Pick(e, "specName", "spec") or "", 20)
                    local spec = (rawSpec:gsub("%d+$", ""))
                    local status = tostring(Pick(e, "status") or ""):lower()
                    local state = STATE_WORDS[cls:lower()] or STATE_WORDS[status] or "signed"
                    local role = RoleOf(Pick(e, "roleName", "role") or (cls:lower() == "tank" and "tank" or nil), spec)
                    local token = CLASS_TOKEN[cls:lower()] or ""
                    if token == "" and state == "signed" then token = SPEC_CLASS[rawSpec:lower()] or "" end
                    if state ~= "signed" and token == "" then spec = "" end
                    -- the slot the player signed up in (Raid-Helper's "Tank" is a slot of its own, next to the classes)
                    local group = (cls:lower() == "tank") and "TANK" or (CLASS_TOKEN[cls:lower()] or "")
                    local position = math.max(0, math.min(999, math.floor(tonumber(Pick(e, "position")) or 0)))
                    ev.signups[#ev.signups + 1] = { n = name, c = token, s = spec, r = role, st = state, g = group, p = position }
                end
            end
        end
    end
    -- the limits per role of the template (999 = no limit): "Tanks 3/3"; and the order of the roles
    ev.limits = {}
    ev.roleOrder = ""
    local roles = Pick(data, "roles")
    if type(roles) == "table" then
        for _, ro in ipairs(roles) do
            if type(ro) == "table" then
                local code = RoleOf(Pick(ro, "name", "cName"), "")
                local limit = tonumber(Pick(ro, "limit"))
                if VALID_ROLE[code] and limit and limit > 0 and limit < 999 then ev.limits[code] = math.floor(limit) end
                if (code == "T" or code == "H" or code == "M" or code == "R") and not ev.roleOrder:find(code, 1, true) then ev.roleOrder = ev.roleOrder .. code end
            end
        end
    end
    -- the order of the classes of the template (Tank, Warrior, ...): the same order as in Discord
    ev.classOrder = {}
    local classes = Pick(data, "classes")
    if type(classes) == "table" then
        for _, cl in ipairs(classes) do
            if type(cl) == "table" then
                local nm = tostring(Pick(cl, "name", "cName") or ""):lower()
                local token = (nm == "tank") and "TANK" or CLASS_TOKEN[nm]
                if token and #ev.classOrder < 12 then ev.classOrder[#ev.classOrder + 1] = token end
            end
        end
    end
    -- the colour of the event (the stripe at the left of the message in Discord): "171,71,188" or "#ab47bc"
    local function ColorHex(v)
        v = tostring(v or "")
        local cr, cg, cb = v:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
        if cr then return ("%02x%02x%02x"):format(math.min(255, tonumber(cr)), math.min(255, tonumber(cg)), math.min(255, tonumber(cb))) end
        local hex = v:match("^#?(%x%x%x%x%x%x)$")
        return hex and hex:lower() or nil
    end
    ev.color = ColorHex(Pick(data, "color")) or (type(data.advancedSettings) == "table" and ColorHex(data.advancedSettings.color)) or nil
    return ev
end

---------------------------------------------------------------------------
-- the stored events
---------------------------------------------------------------------------
local function Store()
    local g = ns.guildName
    if not (ns.DB and g) then return nil end
    local gd = ns.DB.guilds[g]
    if not gd then
        gd = { members = {} }
        ns.DB.guilds[g] = gd
    end
    gd.raids = gd.raids or { events = {}, removed = {} }
    gd.raids.events = gd.raids.events or {}
    gd.raids.removed = gd.raids.removed or {}
    gd.raids.names = gd.raids.names or {}
    -- (the first version kept one character per Discord name: names[key] = { guid, cname, rev, by })
    for key, m in pairs(gd.raids.names) do
        if m.guid ~= nil then
            gd.raids.names[key] = (m.guid ~= "") and { [m.guid] = { on = true, cname = m.cname or "", rev = m.rev or 0, by = m.by or "" } } or {}
        end
    end
    return gd.raids
end

-- all events, the first one first
function R.List()
    local out = {}
    for _, rec in pairs((Store() or {}).events or {}) do out[#out + 1] = rec end
    table.sort(out, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        return a.id < b.id
    end)
    return out
end

-- the raids still to come (one that started less than three hours ago still counts), the first one first
function R.Upcoming()
    local out = {}
    local now = ns.Time()
    for _, rec in ipairs(R.List()) do
        if rec.start + 3 * 3600 >= now then out[#out + 1] = rec end
    end
    return out
end

function R.Get(id) return ((Store() or {}).events or {})[id] end

-- Events stay in the Calendar for good, but only the last month is shared and compared between the officers (the traffic
-- must not grow with the years); so a new officer sees the last month, not the whole history.
R.SHARE_DAYS = 30
function R.SharedSince() return ns.Time() - R.SHARE_DAYS * 86400 end
function R.Shared()
    local out, since = {}, R.SharedSince()
    for _, rec in ipairs(R.List()) do
        if rec.start >= since then out[#out + 1] = rec end
    end
    return out
end

-- what I have (of the last month): how many events and the newest change (also removals): shared so the others know whether they miss something
function R.Digest()
    local store = Store()
    if not store then return 0, 0 end
    local count, maxRev = 0, 0
    local since = R.SharedSince()
    for _, rec in pairs(store.events) do
        if rec.start >= since then
            count = count + 1
            if rec.rev > maxRev then maxRev = rec.rev end
        end
    end
    for _, rev in pairs(store.removed) do
        if rev >= since and rev > maxRev then maxRev = rev end
    end
    for _, links in pairs(store.names or {}) do
        for _, l in pairs(links) do
            count = count + 1
            if l.rev > maxRev then maxRev = l.rev end
        end
    end
    return count, maxRev
end

-- Takes an event in (from me or from an officer's message): the newer change wins, a removal wins over an older
-- add. Returns true when something changed.
function R.Apply(rec)
    local store = Store()
    if not (store and type(rec) == "table" and rec.id and rec.start and rec.rev) then return false end
    if (store.removed[rec.id] or 0) >= rec.rev then return false end
    local old = store.events[rec.id]
    if old and old.rev >= rec.rev then return false end
    store.removed[rec.id] = nil
    store.events[rec.id] = rec
    if R.OnChanged then R.OnChanged() end
    return true
end

function R.ApplyRemoval(id, rev)
    local store = Store()
    rev = tonumber(rev)
    if not (store and id and rev) then return false end
    local old = store.events[id]
    if (store.removed[id] or 0) >= rev and not (old and old.rev <= rev) then return false end
    if old and old.rev > rev then return false end       -- added again after that removal
    store.removed[id] = rev
    store.events[id] = nil
    if R.OnChanged then R.OnChanged() end
    return true
end

-- Officers and the guild master add an event from the pasted JSON. Returns the stored event and whether it
-- replaced one that was there (same Raid-Helper event pasted again: new sign-ups), or nil and why not.
function R.Add(ev, by)
    if not ns.CanModerate() then return nil, "only officers and the guild master can add events" end
    local store = Store()
    if not (store and ev and ev.id) then return nil, "the guild is not known yet" end
    local old = store.events[ev.id]
    local now = ns.Time()
    local rev = math.max(now, ((old and old.rev) or 0) + 1, (store.removed[ev.id] or 0) + 1)
    local rec = { id = ev.id, title = ev.title, desc = ev.desc, start = ev.start, leader = ev.leader, signups = ev.signups, limits = ev.limits or {}, org = ev.org or "",
        color = ev.color, roleOrder = ev.roleOrder or "", classOrder = ev.classOrder or {},
        addedAt = now, by = Clean(by or "?", 30), rev = rev }
    R.Apply(rec)
    if ns.Sync and ns.Sync.SendRaid then ns.Sync.SendRaid(rec) end
    return rec, old ~= nil
end

function R.Remove(id, by)
    if not ns.CanModerate() then return false end
    local store = Store()
    local old = store and store.events[id]
    if not old then return false end
    local rev = math.max(ns.Time(), old.rev + 1)
    R.ApplyRemoval(id, rev)
    if ns.Sync and ns.Sync.SendRaidRemoval then ns.Sync.SendRaidRemoval(id, rev, Clean(by or "?", 30)) end
    return true
end

-- Events are never forgotten (the Calendar shows the old ones too); only the dashboard leaves out what is over (R.Upcoming).
-- (Removals are kept as well: a removed event that somebody still has must not come back.)

---------------------------------------------------------------------------
-- what travels: a header and the rest in pieces. Receivers collect the pieces.
---------------------------------------------------------------------------
-- the text after the header: description, then the sign-ups, "~" between, "^" between the fields of a sign-up
function R.Payload(rec)
    local limits = {}
    for _, code in ipairs({ "T", "H", "M", "R", "D" }) do
        if rec.limits and rec.limits[code] then limits[#limits + 1] = code .. rec.limits[code] end
    end
    -- (an older version of the addon skips the piece that starts with "#", and a sign-up with more fields)
    local parts = { Clean(rec.desc, 300), "#" .. table.concat(limits, ","), "@" .. Clean(rec.org or "", 30),
        "$" .. (rec.color or ""), "!" .. (rec.roleOrder or ""), ">" .. table.concat(rec.classOrder or {}, ",") }
    for _, s in ipairs(rec.signups or {}) do
        parts[#parts + 1] = table.concat({ Clean(s.n, 24), s.c or "", Clean(s.s, 20), s.r or "O", s.st or "signed", s.g or "", tostring(s.p or 0) }, "^")
    end
    return table.concat(parts, "~")
end

local function ParsePayload(text)
    local parts = {}
    for piece in (text .. "~"):gmatch("(.-)~") do parts[#parts + 1] = piece end
    local desc = table.remove(parts, 1) or ""
    local signups, limits, org, color, roleOrder, classOrder = {}, {}, "", nil, "", {}
    for _, piece in ipairs(parts) do
        local special = not piece:find("^", 1, true)       -- (a sign-up always has "^" in it)
        local first = piece:sub(1, 1)
        if special and first == "@" then
            org = Clean(piece:sub(2), 30)
        elseif special and first == "$" then
            color = piece:sub(2):match("^%x%x%x%x%x%x$")
        elseif special and first == "!" then
            roleOrder = piece:sub(2):gsub("[^THMR]", ""):sub(1, 4)
        elseif special and first == ">" then
            for token in piece:sub(2):gmatch("%u+") do if #classOrder < 12 then classOrder[#classOrder + 1] = token end end
        elseif special and first == "#" then
            for code, n in piece:gmatch("(%u)(%d+)") do
                if VALID_ROLE[code] then limits[code] = math.min(tonumber(n), 998) end
            end
        else
            local n, c, s, r, st, g, p = piece:match("^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)%^?([^%^]*)%^?([^%^]*)$")
            if n and n ~= "" and #signups < 80 then
                if c ~= "" and not CLASS_TOKEN[c:lower()] and not c:match("^%u+$") then c = "" end
                if g ~= "" and not g:match("^%u+$") then g = "" end
                signups[#signups + 1] = { n = n:sub(1, 24), c = c:sub(1, 12), s = s:sub(1, 20), r = VALID_ROLE[r] and r or "O",
                    st = VALID_STATE[st] and st or "signed", g = g:sub(1, 12), p = math.max(0, math.min(999, tonumber(p) or 0)) }
            end
        end
    end
    return desc, signups, limits, org, color, roleOrder, classOrder
end

-- the text cut into pieces of at most `size` bytes, never in the middle of a character
function R.Chunks(text, size)
    local out, i = {}, 1
    while i <= #text do
        local j = math.min(#text, i + size - 1)
        while j < #text and j > i do
            local b = text:byte(j + 1)
            if b >= 0x80 and b < 0xC0 then j = j - 1 else break end     -- the next piece would start inside a character
        end
        out[#out + 1] = text:sub(i, j)
        i = j + 1
    end
    return out
end

local pending = {}      -- [id .. ":" .. rev] = { header, chunks, got, total, t }

local function Finish(p)
    local text = {}
    for i = 1, p.total do text[i] = p.chunks[i] or "" end
    local desc, signups, limits, org, color, roleOrder, classOrder = ParsePayload(table.concat(text))
    local h = p.header
    return R.Apply({ id = h.id, title = h.title, desc = desc, start = h.start, leader = h.leader, signups = signups, limits = limits, org = org, color = color, roleOrder = roleOrder, classOrder = classOrder,
        addedAt = h.addedAt, by = h.by, rev = h.rev })
end

-- the header of an event: id, rev, start, added at, number of pieces, who added it, who leads it, title
function R.ReceiveHeader(id, rev, start, addedAt, total, by, leader, title)
    rev, start, addedAt, total = tonumber(rev), tonumber(start), tonumber(addedAt), tonumber(total)
    if not (id and rev and start and addedAt and total) or total < 0 or total > 40 then return false end
    if start < 1100000000 or start > 4100000000 or rev > ns.Time() + 86400 then return false end
    local key = id .. ":" .. rev
    local now = ns.Time()
    for k, p in pairs(pending) do if now - p.t > 180 then pending[k] = nil end end
    local p = pending[key] or { chunks = {}, got = 0, t = now }
    pending[key] = p
    p.header = { id = id, rev = rev, start = start, addedAt = addedAt, by = Clean(by, 30), title = Clean(title, 60), leader = Clean(leader, 30) }
    p.total = total
    if total == 0 then
        pending[key] = nil
        return Finish(p)
    end
    if p.got >= total then pending[key] = nil return Finish(p) end
    return false
end

function R.ReceiveChunk(id, rev, idx, chunk)
    rev, idx = tonumber(rev), tonumber(idx)
    if not (id and rev and idx) or idx < 1 or idx > 40 then return false end
    local key = id .. ":" .. rev
    local p = pending[key]
    if not p then
        p = { chunks = {}, got = 0, t = ns.Time() }
        pending[key] = p
    end
    if not p.chunks[idx] then
        p.chunks[idx] = chunk
        p.got = p.got + 1
    end
    if p.header and p.total and p.got >= p.total then
        pending[key] = nil
        return Finish(p)
    end
    return false
end

---------------------------------------------------------------------------
-- how an event is described
---------------------------------------------------------------------------
-- counts for the sign-ups: { signed, tanks, healers, damage, other, bench, late, tentative, absent }
function R.Counts(rec)
    local c = { signed = 0, tanks = 0, healers = 0, melee = 0, ranged = 0, dps = 0, damage = 0, other = 0, bench = 0, late = 0, tentative = 0, absent = 0 }
    for _, s in ipairs(rec.signups or {}) do
        if s.st == "signed" then
            c.signed = c.signed + 1
            if s.r == "T" then c.tanks = c.tanks + 1
            elseif s.r == "H" then c.healers = c.healers + 1
            elseif s.r == "M" then c.melee = c.melee + 1 c.damage = c.damage + 1
            elseif s.r == "R" then c.ranged = c.ranged + 1 c.damage = c.damage + 1
            elseif s.r == "D" then c.dps = c.dps + 1 c.damage = c.damage + 1
            else c.other = c.other + 1 end
        elseif c[s.st] ~= nil then
            c[s.st] = c[s.st] + 1
        end
    end
    return c
end

-- "Signed up: 24 (3 tanks, 6 healers, 15 damage)"
function R.SignedText(rec)
    local c = R.Counts(rec)
    if c.signed == 0 then return "Nobody signed up yet" end
    local parts = {}
    if c.tanks > 0 then parts[#parts + 1] = c.tanks .. (c.tanks == 1 and " tank" or " tanks") end
    if c.healers > 0 then parts[#parts + 1] = c.healers .. (c.healers == 1 and " healer" or " healers") end
    if c.damage > 0 then parts[#parts + 1] = c.damage .. " dps" end
    if c.other > 0 then parts[#parts + 1] = c.other .. " other" end
    return ("Signed up: %d%s"):format(c.signed, #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "")
end

-- "Bench 2, late 1, tentative 1, absent 3" (empty when nothing)
function R.OthersText(rec)
    local c = R.Counts(rec)
    local parts = {}
    if c.bench > 0 then parts[#parts + 1] = "bench " .. c.bench end
    if c.late > 0 then parts[#parts + 1] = "late " .. c.late end
    if c.tentative > 0 then parts[#parts + 1] = "tentative " .. c.tentative end
    if c.absent > 0 then parts[#parts + 1] = "absent " .. c.absent end
    return table.concat(parts, ", ")
end


-- "in 2 days", "in 3 h 20 min", "started 40 min ago"
function R.Relative(start)
    local d = start - ns.Time()
    local function Span(secs)
        secs = math.abs(secs)
        if secs >= 2 * 86400 then return math.floor(secs / 86400 + 0.5) .. " days" end
        if secs >= 86400 then return "1 day" end
        if secs >= 3600 then
            local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
            return m > 0 and (h .. " h " .. m .. " min") or (h .. " h")
        end
        return math.max(1, math.floor(secs / 60)) .. " min"
    end
    if d > 60 then return "in " .. Span(d) end
    if d >= -60 then return "starting now" end
    return "started " .. Span(d) .. " ago"
end

---------------------------------------------------------------------------
-- Discord names. A sign-up carries the Discord name of a player, not the name of a character. Officers match
-- Discord names to guild characters (Discord names window); the match is shared with everybody. Without a match the
-- addon tries the obvious: a Discord name that is the name of exactly one guild character, or its first word.
---------------------------------------------------------------------------
function R.NameKey(name)
    local k = tostring(name or ""):gsub("[%c|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return ((ns.Lower and ns.Lower(k) or k:lower()):sub(1, 32))
end

-- The characters an officer matched to this Discord name (a player can have several): { { guid, cname, rev, by }, ... }
function R.Links(name)
    local store = Store()
    local out = {}
    for guid, l in pairs((store and store.names[R.NameKey(name)]) or {}) do
        if l.on then out[#out + 1] = { guid = guid, cname = l.cname, rev = l.rev, by = l.by } end
    end
    table.sort(out, function(a, b) return (a.cname ~= b.cname) and (a.cname < b.cname) or (a.guid < b.guid) end)
    return out
end

-- one link (or its removal, on = false) from me or from an officer's message; the newer change wins
function R.ApplyLink(key, guid, on, rev, cname, by)
    local store = Store()
    rev = tonumber(rev)
    if not (store and key and key ~= "" and rev and type(guid) == "string" and guid:find("^[%w%-]+$")) then return false end
    store.names[key] = store.names[key] or {}
    local old = store.names[key][guid]
    if old and old.rev >= rev then return false end
    store.names[key][guid] = { on = on == true, cname = Clean(cname, 30), rev = rev, by = Clean(by, 30) }
    if R.OnChanged then R.OnChanged() end
    return true
end

local function SendLinkChange(name, guid, on, cname, by)
    if not ns.CanModerate() then return false end
    local store = Store()
    local key = R.NameKey(name)
    if not (store and key ~= "" and guid and guid ~= "") then return false end
    local old = store.names[key] and store.names[key][guid]
    local rev = math.max(ns.Time(), (old and old.rev or 0) + 1)
    if not R.ApplyLink(key, guid, on, rev, cname or "", by or "") then return false end
    if ns.Sync and ns.Sync.SendLink then ns.Sync.SendLink(key, guid, rev, on, cname or "", by or "") end
    return true
end

-- officers: this character belongs to this Discord name (a name can have several characters)
function R.AddLink(name, guid, cname, by) return SendLinkChange(name, guid, true, cname, by) end
function R.RemoveLink(name, guid, by)
    local old = R.Links(name)
    for _, l in ipairs(old) do if l.guid == guid then return SendLinkChange(name, guid, false, l.cname, by) end end
    return false
end
function R.ClearLinks(name, by)
    local any = false
    for _, l in ipairs(R.Links(name)) do
        if SendLinkChange(name, l.guid, false, l.cname, by) then any = true end
    end
    return any
end

-- The characters of a Discord name: the matches an officer made ("mapped"), else the one guild character that has the
-- same name or first word ("auto"). Returns a list of roster entries (or { guid, name } for a character that is not in
-- the roster) and how they were found; an empty list when unknown. Pass the roster when asking many times.
-- Characters of the same person, as far as the addon knows (officer-set alt links and the shared-data guess)
local function GroupRoot(guid)
    local o = ns.GetOriginalOf and ns.GetOriginalOf(guid)
    return o or guid
end

-- all guild characters of the same person as this one (this one included): a set { [guid] = roster entry }
function R.RelatedGuids(guid, roster)
    roster = roster or ns.GetRoster()
    local root = GroupRoot(guid)
    local out = {}
    for _, e in ipairs(roster.list) do
        if e.guid and GroupRoot(e.guid) == root then out[e.guid] = e end
    end
    return out
end

function R.ResolveAll(name, roster)
    local key = R.NameKey(name)
    if key == "" then return {} end
    roster = roster or ns.GetRoster()
    local links = R.Links(name)
    if #links > 0 then
        local out = {}
        for _, l in ipairs(links) do out[#out + 1] = roster.byGUID[l.guid] or { guid = l.guid, name = l.cname } end
        return out, "mapped"
    end
    local hits = {}
    for _, e in ipairs(roster.list) do
        local full = R.NameKey(ns.DisplayName(e.name) or e.name)
        if full == key or full:match("^(%S+)") == key then hits[#hits + 1] = e end
    end
    -- a character that is known to be an alt (or to have alts) is not matched by its name: the name belongs to a
    -- person with several characters, so an officer picks them (the picker highlights the related ones)
    if #hits == 1 and hits[1].guid then
        local n = 0
        for _ in pairs(R.RelatedGuids(hits[1].guid, roster)) do n = n + 1 end
        if n > 1 then return {} end
    end
    if #hits == 1 then return hits, "auto" end
    return {}
end

-- The characters to highlight when linking a Discord name: everybody related (alts and mains, as far as the addon knows)
-- to the characters it is linked to and to the characters that have its name. { [guid] = roster entry }
function R.RelatedToName(name, roster)
    roster = roster or ns.GetRoster()
    local seeds = {}
    for _, l in ipairs(R.Links(name)) do seeds[#seeds + 1] = l.guid end
    for _, e in ipairs(R.NameCandidates(name, roster)) do seeds[#seeds + 1] = e.guid end
    local out = {}
    for _, g in ipairs(seeds) do
        for guid, e in pairs(R.RelatedGuids(g, roster)) do out[guid] = e end
    end
    return out
end

-- the guild characters a Discord name points at by its NAME, with or without an officer's match: the starting point of
-- the picker, which highlights the characters related to them
function R.NameCandidates(name, roster)
    local key = R.NameKey(name)
    roster = roster or ns.GetRoster()
    local out = {}
    for _, e in ipairs(roster.list) do
        local full = R.NameKey(ns.DisplayName(e.name) or e.name)
        if e.guid and (full == key or full:match("^(%S+)") == key) then out[#out + 1] = e end
    end
    return out
end

-- the first character of a Discord name, or nil (see ResolveAll)
function R.Resolve(name, roster)
    local list, how = R.ResolveAll(name, roster)
    return list[1], how
end

-- the Discord names in the stored events (and the given extra sign-ups): { { name, key, count } }, unknown ones first
function R.KnownNames(extra, roster)
    roster = roster or ns.GetRoster()
    local seen, out = {}, {}
    local function Add(s)
        local key = R.NameKey(s.n)
        if key == "" then return end
        if not seen[key] then
            seen[key] = { name = s.n, key = key, count = 0 }
            out[#out + 1] = seen[key]
        end
        seen[key].count = seen[key].count + 1
        -- the classes this Discord name signed up with (helps to pick the right character)
        if s.c and s.c ~= "" and s.st == "signed" then
            seen[key].classSet = seen[key].classSet or {}
            if not seen[key].classSet[s.c] then
                seen[key].classSet[s.c] = true
                seen[key].classes = seen[key].classes or {}
                table.insert(seen[key].classes, s.c)
            end
        end
    end
    for _, rec in ipairs(R.List()) do for _, s in ipairs(rec.signups or {}) do Add(s) end end
    for _, s in ipairs(extra or {}) do Add(s) end
    for _, item in ipairs(out) do
        item.entries, item.how = R.ResolveAll(item.name, roster)
        item.entry = item.entries[1]
        -- not matched, but a character has this name: it is known to have alts, so an officer picks them
        item.suggest = item.entry == nil and #R.NameCandidates(item.name, roster) > 0
    end
    table.sort(out, function(a, b)
        if (a.entry == nil) ~= (b.entry == nil) then return a.entry == nil end
        return a.key < b.key
    end)
    return out
end

-- how many of these sign-ups cannot be matched to a guild character
function R.UnmatchedCount(signups, roster)
    roster = roster or ns.GetRoster()
    local n = 0
    for _, s in ipairs(signups or {}) do
        if s.st == "signed" and not R.Resolve(s.n, roster) then n = n + 1 end
    end
    return n
end

-- is this guild character me, or another character of mine (same main, as the officers set it)?
local function IsMineGuid(guid)
    if not guid then return false end
    if ns.IsMine(guid) then return true end
    local root = GroupRoot(guid)
    for mine in pairs(ns.DB.mine or {}) do
        if GroupRoot(mine) == root then return true end
    end
    return false
end

R.IsMineGuid = IsMineGuid

-- The guild characters of a sign-up: the characters its Discord name is linked to (no alts or mains of them).
function R.CandidateChars(discord, roster)
    local list, seen = {}, {}
    for _, e in ipairs(R.ResolveAll(discord, roster)) do
        local entry = roster.byGUID[e.guid or ""] or e
        if entry.guid and not seen[entry.guid] then seen[entry.guid] = true list[#list + 1] = entry end
    end
    return list
end

-- Is a sign-up online: only when the character that signed up is (the one of the class that signed up when there are several).
-- Returns the online roster entry or nil, and the characters.
function R.SignupOnline(s, roster)
    local cands = R.CandidateChars(s.n, roster)
    local pick
    for _, e in ipairs(cands) do
        if e.online and (not pick or (s.c ~= "" and e.class == s.c and pick.class ~= s.c)) then pick = e end
    end
    return pick, cands, pick ~= nil
end

-- my own sign-up in an event: by the match between the Discord name and my characters, or by the name of my
-- character (with or without the realm part): or nil
function R.MyEntry(rec)
    local roster = ns.GetRoster()
    local mine = ns.me and ns.Squash and ns.Squash((tostring(ns.me):gsub("%-.*$", ""))) or nil
    local first = ns.me and ns.Squash and ns.Squash((tostring(ns.me):match("^(%S+)") or "")) or nil
    for _, s in ipairs(rec.signups or {}) do
        for _, entry in ipairs(R.ResolveAll(s.n, roster)) do
            if IsMineGuid(entry.guid) then return s end
        end
        local n = ns.Squash and ns.Squash(s.n) or s.n:lower()
        if n == mine or n == first or (ns.me and n == ns.Squash(ns.me)) then return s end
    end
    return nil
end

local STATE_TEXT = { signed = "signed up", bench = "on the bench", late = "late", tentative = "tentative", absent = "absent" }
function R.StateText(entry) return STATE_TEXT[entry.st] or entry.st end

---------------------------------------------------------------------------
-- the clock: the game's own option (Time Manager: local time or server time "ST")
---------------------------------------------------------------------------
function R.UseLocalTime()
    local v
    pcall(function() v = GetCVar and GetCVar("timeMgrUseLocalTime") end)
    if v == nil then return true end
    return v ~= "0" and v ~= false
end

-- seconds that server time is ahead of UTC (from the server hour and minute), or nil when the game does not say
function R.ServerOffset()
    local h, m
    pcall(function() h, m = GetGameTime() end)
    if not (h and m) then return nil end
    local utc = date("!*t", ns.Time())
    local diff = (h * 60 + m) - (utc.hour * 60 + utc.min)
    diff = ((diff + 720) % 1440) - 720
    return math.floor(diff / 15 + 0.5) * 15 * 60
end

local function ServerClock()
    if R.UseLocalTime() then return nil end
    return R.ServerOffset()
end

function R.ZoneSuffix() return ServerClock() and " ST" or "" end

-- date fields of a moment in the player's clock
function R.DateTable(ts)
    local off = ServerClock()
    if off then return date("!*t", ts + off) end
    return date("*t", ts)
end

function R.Format(ts, fmt)
    local off = ServerClock()
    if off then return date("!" .. fmt, ts + off) end
    return date(fmt, ts)
end

function R.TimeText(ts) return R.Format(ts, "%H:%M") .. R.ZoneSuffix() end
function R.DateText(ts) return R.Format(ts, "%d %B %Y") end
function R.WhenText(ts) return R.Format(ts, "%a %d %b %Y, %H:%M") .. R.ZoneSuffix() end

-- "in 2 days", or for an old event "2 months ago" (as the Discord message says it)
function R.RelativeLong(start)
    local d = start - ns.Time()
    if d > -60 then return R.Relative(start) end
    local secs = -d
    if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. " min ago" end
    if secs < 86400 then return math.floor(secs / 3600) .. " h ago" end
    if secs < 60 * 86400 then
        local days = math.floor(secs / 86400)
        return days .. (days == 1 and " day ago" or " days ago")
    end
    local months = math.floor(secs / (30 * 86400))
    return months .. (months == 1 and " month ago" or " months ago")
end

---------------------------------------------------------------------------
-- characters instead of Discord names
---------------------------------------------------------------------------
-- the name to show for a Discord name: the character it is matched to (the main when one of several is the main of the
-- others), or the Discord name itself when nobody is known
function R.CharName(discord, roster)
    local list = R.ResolveAll(discord, roster)
    if #list == 0 then return discord end
    local set = {}
    for _, e in ipairs(list) do set[e.guid or ""] = e end
    local pick = list[1]
    for _, e in ipairs(list) do
        local o = e.guid and ns.GetOriginalOf and ns.GetOriginalOf(e.guid)
        if o and set[o] then pick = set[o] break end
    end
    local name = ns.DisplayName(pick.name or "")
    return (name ~= "") and name or discord
end

local STATE_ORDER = { { "signed", "Signed up" }, { "tentative", "Tentative" }, { "bench", "Bench" }, { "late", "Late" }, { "absent", "Absence" } }
R.STATE_ORDER = STATE_ORDER

-- the sign-ups by state, with character names: { { state, label, count, names } } (states nobody is in are left out)
function R.StateGroups(rec, roster)
    roster = roster or ns.GetRoster()
    local out = {}
    for _, st in ipairs(STATE_ORDER) do
        local names = {}
        for _, s in ipairs(rec.signups or {}) do
            if s.st == st[1] then names[#names + 1] = R.CharName(s.n, roster) end
        end
        if #names > 0 then out[#out + 1] = { state = st[1], label = st[2], count = #names, names = names } end
    end
    return out
end

-- what the dashboard and the reminder show: name, description, when, how long, who organizes, the sign-ups by state
-- "1 tank, 2 healers, 3 dps" (what is signed up, by role)
function R.RoleCountsText(rec)
    local c = R.Counts(rec)
    local parts = {}
    if c.tanks > 0 then parts[#parts + 1] = c.tanks .. (c.tanks == 1 and " tank" or " tanks") end
    if c.healers > 0 then parts[#parts + 1] = c.healers .. (c.healers == 1 and " healer" or " healers") end
    if c.damage > 0 then parts[#parts + 1] = c.damage .. " dps" end
    if c.other > 0 then parts[#parts + 1] = c.other .. " other" end
    return table.concat(parts, ", ")
end

-- "Tentative 1, Bench 2, Late 1, Absence 5" (an option nobody is in is left out); empty when none
function R.OtherStatesText(rec)
    local c = R.Counts(rec)
    local parts = {}
    for _, st in ipairs({ { "tentative", "Tentative" }, { "bench", "Bench" }, { "late", "Late" }, { "absent", "Absence" } }) do
        if c[st[1]] > 0 then parts[#parts + 1] = ("%s %d"):format(st[2], c[st[1]]) end
    end
    return table.concat(parts, ", ")
end

function R.Summary(rec, roster)
    roster = roster or ns.GetRoster()
    return {
        title = rec.title,
        desc = (rec.desc and rec.desc ~= "") and rec.desc or nil,
        when = R.WhenText(rec.start),
        left = R.Relative(rec.start),
        organizer = (rec.org and rec.org ~= "" and rec.org) or ((rec.leader and rec.leader ~= "") and rec.leader or nil),
        states = R.StateGroups(rec, roster),
        signed = R.Counts(rec).signed,
        roles = R.RoleCountsText(rec),
        others = R.OtherStatesText(rec),
        mine = R.MyEntry(rec),
    }
end

---------------------------------------------------------------------------
-- 15 minutes before: the reminder and the glow
---------------------------------------------------------------------------
R.SOON = 15 * 60

-- within 15 minutes before the start (and a few minutes after it)
function R.IsSoon(rec)
    local d = rec.start - ns.Time()
    return d <= R.SOON and d >= -300
end

-- my sign-up in this raid if it counts (signed up, tentative, late or bench; not absent)
function R.MyActiveEntry(rec)
    local me = R.MyEntry(rec)
    if me and me.st ~= "absent" then return me end
    return nil
end

-- the first raid that starts soon and that I (or an alt) am signed up for
function R.SoonMine()
    for _, rec in ipairs(R.Upcoming()) do
        if R.IsSoon(rec) and R.MyActiveEntry(rec) then return rec end
    end
    return nil
end

-- every few seconds: when such a raid is near and the game is calm, the reminder opens, once per raid
function R.CheckReminder()
    if not (ns.DB and ns.worldReady) then return end
    local rec = R.SoonMine()
    if not rec then return end
    ns.DB.raidReminded = ns.DB.raidReminded or {}
    local key = rec.id .. ":" .. rec.start
    if ns.DB.raidReminded[key] then return end
    -- not during combat and loading screens: wait
    if ns.Blacklist and ns.Blacklist.IsCalm and not ns.Blacklist.IsCalm() then return end
    ns.DB.raidReminded[key] = ns.Time()
    for k, at in pairs(ns.DB.raidReminded) do
        if ns.Time() - at > 3 * 86400 then ns.DB.raidReminded[k] = nil end
    end
    if ns.UI and ns.UI.ShowRaidReminder then ns.UI.ShowRaidReminder(rec) end
end

local reminding = false
function R.StartReminders()
    if reminding then return end
    reminding = true
    local function Tick()
        R.CheckReminder()
        ns.After(15, Tick)
    end
    ns.After(15, Tick)
end
