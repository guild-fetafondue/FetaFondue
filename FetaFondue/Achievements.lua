---@class ns
local ns = select(2, ...)

-- Guild firsts, tracked by the addon from several sources that are used together:
--   * the first in the guild to reach level 60 (on any class), and on each class,
--   * the first to max out (300 skill) each of twelve professions,
--   * the guild's first clear of the Barrow Deeps, Hyjal Summit and Onyxia (guild achievements: who did it is not shown): the game lists the
--     steps of its raid achievements (usually one boss each); every step counts once its boss dies with RAID_MIN or more guildies in the
--     group, and the achievement is the guild's when all steps are done. Where the game gives no steps, the last boss alone counts.
--
--   1. the addon watching its own characters: the level (and the moment of a level up), the skill of the professions,
--      and the last boss of a raid (see Stats.lua: it counts when RAID_MIN or more guildies are in the group);
--   2. the guild roster, which shows the level and class of EVERY member, also those who do not use the addon: a level
--      60 is claimed for them too, from the day the addon first saw it (no time; the exact time when it saw the level up);
--   3. the game's own achievements of my character (when the game offers them): they carry the real date of what was
--      earned before the addon saw it, and replace the day it was first seen when that is earlier.
-- What the addon finds it shares; everybody keeps the earliest. Seen happening while playing, the time is known.

local A = {}
ns.Achievements = A

-- the classes and the pictures (icon file ids of the game's class icons)
local CLASSES = {
    { "WARRIOR", "Warrior", 626008 }, { "PALADIN", "Paladin", 626003 }, { "HUNTER", "Hunter", 626000 },
    { "ROGUE", "Rogue", 626005 }, { "PRIEST", "Priest", 626004 }, { "SHAMAN", "Shaman", 626006 },
    { "MAGE", "Mage", 626001 }, { "WARLOCK", "Warlock", 626007 }, { "DRUID", "Druid", 625999 },
}
-- the professions (ids as used all over the addon), the picture and the title of a master ("Alchemist")
local PROFS = {
    { 171, "Alchemy", 136240, "Alchemist" }, { 164, "Blacksmithing", 136241, "Blacksmith" },
    { 333, "Enchanting", 136244, "Enchanter" }, { 202, "Engineering", 136243, "Engineer" },
    { 165, "Leatherworking", 136247, "Leatherworker" }, { 197, "Tailoring", 136249, "Tailor" },
    { 186, "Mining", "Interface\\Icons\\Trade_Mining", "Miner" }, { 182, "Herbalism", "Interface\\Icons\\Trade_Herbalism", "Herbalist" },
    { 393, "Skinning", "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", "Skinner" }, { 185, "Cooking", "Interface\\Icons\\INV_Misc_Food_15", "Cook" },
    { 356, "Fishing", "Interface\\Icons\\Trade_Fishing", "Angler" }, { 129, "First Aid", "Interface\\Icons\\Spell_Holy_SealOfSacrifice", "First Aider" },
}
-- the raids: key, picture, name, what it is (how a raid is recognised is in Data.lua: ns.RAID_CLEARS); the icon also tells which
-- of the game's raid achievements is meant (they are listed in the game's category GAME_RAID_CATEGORY)
local RAIDS = {
    { "R:BARROW", 1417431, "Conqueror of the Deeps", "the Barrow Deeps" },
    { "R:HYJAL", 409547, "Conqueror of the Wilds", "Hyjal Summit" },
    { "R:ONYXIA", 254650, "Conqueror of the Lair", "Onyxia's Lair" },
}

-- the game's achievement categories (Forever's data): classes and the six crafting professions. Their achievements are
-- recognised by the number in the description (60 or 300: the same in every language).
local GAME_CLASS_CATEGORY = {
    WARRIOR = 15585, PALADIN = 15580, HUNTER = 15578, ROGUE = 15582, PRIEST = 15581, SHAMAN = 15583, MAGE = 15579, WARLOCK = 15584, DRUID = 15577,
}
local GAME_RAID_CATEGORY = 15594
local GAME_PROF_CATEGORY = { [171] = 15587, [164] = 15588, [333] = 15589, [202] = 15590, [165] = 15591, [197] = 15592 }

-- every achievement the tab shows, in the order of the tab
local defs, byKey = {}, {}
local function Add(def) defs[#defs + 1] = def byKey[def.key] = def end
Add({ key = "L:ANY:60", group = "level", kind = "person", label = "First to Level 60", icon = "Interface\\Icons\\Achievement_Level_60",
    desc = "The first in the guild to reach level 60." })
for _, c in ipairs(CLASSES) do
    Add({ key = "L:" .. c[1] .. ":60", group = "class", kind = "person", class = c[1], className = c[2], label = "Master " .. c[2], icon = c[3],
        desc = ("The first in the guild to reach level 60 on a %s."):format(c[2]) })
end
for _, p in ipairs(PROFS) do
    Add({ key = ("P:%d:300"):format(p[1]), group = "craft", kind = "person", profession = p[1], label = "Artisan " .. p[4], icon = p[3],
        desc = ("The first in the guild to reach 300 skill in %s."):format(p[2]) })
end
for _, r in ipairs(RAIDS) do
    Add({ key = r[1], group = "raid", kind = "raid", place = r[4], label = r[3], icon = r[2],
        desc = ("First guild clear of %s (the last boss killed with 5 or more guildies in the group)."):format(r[4]) })
end
A.defs, A.byKey = defs, byKey
A.RAID_MIN = 5        -- a raid counts as cleared by the guild when its last boss dies with this many guildies in the group
A.GROUPS = { { "level", "Level 60" }, { "class", "Classes" }, { "craft", "Professions" }, { "raid", "Raids" } }

function A.Label(key)
    local def = byKey[key]
    if not def then return key end
    -- the class in the player's language when the game knows it
    if def.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[def.class] then
        return "Master " .. LOCALIZED_CLASS_NAMES_MALE[def.class]
    end
    return def.label
end
function A.Icon(key) local def = byKey[key] return def and def.icon end

---------------------------------------------------------------------------
-- who earned what (shared by the whole guild)
---------------------------------------------------------------------------
local function Store()
    local g = ns.guildName
    if not (ns.DB and g) then return nil end
    local gd = ns.DB.guilds[g]
    if not gd then
        gd = { members = {} }
        ns.DB.guilds[g] = gd
    end
    gd.achievements = gd.achievements or {}
    return gd.achievements
end

-- everybody who earned it, the first one first: { { guid, name, ts, time }, ... }
-- ("First to Level 60" is whoever reached level 60 first on any class)
function A.Holders(key)
    local out = {}
    local function Collect(k)
        for guid, e in pairs((Store() or {})[k] or {}) do out[#out + 1] = { guid = guid, name = e.name, ts = e.ts, time = e.time == true, class = k:match("^L:(%u+):60$") } end
    end
    if key == "L:ANY:60" then
        for _, c in ipairs(CLASSES) do Collect("L:" .. c[1] .. ":60") end
    else
        Collect(key)
    end
    table.sort(out, function(a, b)
        if a.ts ~= b.ts then return a.ts < b.ts end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- Somebody who joined the guild AFTER the day he earned something did not earn it for the guild. Only a join date that is known exactly counts
-- (the 5 November default is a guess: there the character stays eligible), and the comparison is by day.
function A.Eligible(guid, ts)
    local j = ns.GetJoined and ns.GetJoined(guid)
    if not (j and j.exact and tonumber(j.ts) and tonumber(ts)) then return true end
    return math.floor(j.ts / 86400) <= math.floor(ts / 86400)
end

-- From 1.0.22: an achievement that was claimed more than 12 hours ago and that most addon users have by now is not given later to somebody
-- who did not have the addon in those first 12 hours (a roster scan of a guildie without the addon, or an addon installed later that
-- finds the character already past the mark). What is seen happening (the time is known) always counts. "Most addon users have it": more than
-- half of the addon users (one per installation) have been heard from since the first claim, so the claim has reached them.
A.LATE_HOURS = 12
function A.MostHaveIt(firstTs)
    local users, got, seen = 0, 0, {}
    local function Count(client, synced)
        if seen[client] then return end
        seen[client] = true
        users = users + 1
        if synced then got = got + 1 end
    end
    Count((ns.DB and ns.DB.clientID) or "me", true)            -- (me: this client has the data)
    for guid, m in pairs(ns.GetMembers() or {}) do
        if not ns.IsMine(guid) and (m.seen or m.diag) then
            Count(m.client or ("c:" .. tostring(guid)), (m.seen or 0) >= firstTs)
        end
    end
    return got * 2 > users
end

-- did this character have the addon within 12 hours of the first claim? (members and installs from before 1.0.22 count as having had it)
local function HadAddon(guid, firstTs)
    local since
    if ns.IsMine(guid) then
        since = ns.DB and ns.DB.addonSince or 0
    else
        local m = (ns.GetMembers() or {})[guid]
        if not (m and (m.seen or m.diag)) then return false end
        since = m.addonSince or 0
    end
    return since <= firstTs + A.LATE_HOURS * 3600
end

-- true when this claim is too late to be given (see above)
function A.LateClaim(key, guid)
    local holders = A.Holders(key)
    if #holders == 0 then return false end
    for _, h in ipairs(holders) do if h.guid == guid then return false end end
    local firstTs = holders[1].ts
    if ns.Time() - firstTs <= A.LATE_HOURS * 3600 then return false end
    if HadAddon(guid, firstTs) then return false end
    return A.MostHaveIt(firstTs)
end

-- Remember that a character earned something (from the game for my own, from a message for the others).
-- Only the earliest date per character and achievement is kept. Returns true when something changed.
function A.Record(key, guid, name, ts, quiet, timeKnown)
    local def = byKey[key]
    if key == "L:ANY:60" then return false end
    local store = Store()
    if not (def and store) then return false end
    ts = tonumber(ts)
    if not ts or ts < 1100000000 or ts > ns.Time() + 2 * 86400 then return false end
    if type(guid) ~= "string" or guid == "" then return false end
    if not A.Eligible(guid, ts) then return false end
    if not timeKnown and A.LateClaim(key, guid) then return false end
    name = tostring(name or "?"):gsub("[|]", ""):sub(1, 40)
    store[key] = store[key] or {}
    local old = store[key][guid]
    -- the same day, the old one knows the time of day and this one only the date: keep the one with the time
    if old and old.time and not timeKnown and math.abs(old.ts - ts) < 86400 then return false end
    if old and old.ts <= ts then
        if old.name ~= name and name ~= "?" then old.name = name end
        -- the same day, and this one knows the time of day and the old one does not: keep this one
        if timeKnown and not old.time and ts - old.ts < 86400 then
            store[key][guid] = { ts = ts, name = name, time = true }
            if A.OnChanged then A.OnChanged() end
            return true
        end
        return false
    end
    local firstEver = #A.Holders(key) == 0
    local anyFirst = key:find("^L:%u+:60$") ~= nil and #A.Holders("L:ANY:60") == 0
    store[key][guid] = { ts = ts, name = name, time = timeKnown == true or nil }
    -- a toast for everybody with the addon, but only when this was seen happening (the time is known) and just now
    if firstEver and timeKnown and ns.Time() - ts <= 15 * 60 and ns.HappenedWhileOnline(ts) and ns.UI and ns.UI.AchievementToast then
        ns.UI.AchievementToast(key, name, guid, ts)
        if anyFirst then ns.UI.AchievementToast("L:ANY:60", name, guid, ts) end
    end
    if not quiet and firstEver and ns.Time() - ts < 3 * 86400 then
        if def.kind == "raid" then
            ns.Print(("The guild has cleared %s for the first time!"):format(A.Label(key)))
        else
            ns.Print(("%s is the first in the guild to earn %s!"):format(name, A.Label(key)))
        end
    end
    if A.OnChanged then A.OnChanged() end
    return true
end

---------------------------------------------------------------------------
-- watching my own characters
---------------------------------------------------------------------------
A.sent = 0
local sentThisSession = {}

-- what I earned: tell everybody once per session (the sender spaces the messages out)
local function ShareMine(key, ts, timeKnown)
    if sentThisSession[key] then return end
    if ns.Sync and ns.Sync.SendAchievement and ns.Sync.SendAchievement(key, ts, ns.myGUID, ns.me, timeKnown) then
        sentThisSession[key] = true       -- (when the sender is not ready yet, it is tried again later)
        A.sent = A.sent + 1
    end
end

-- The level of this character and the skill of its professions (which the addon reads anyway): 60 and 300 are
-- the marks. Seen crossing the mark while playing: the time is known. Already past it when first seen: the day it was
-- first seen counts (the real day is not known). Called at login, on a level up and when the professions are read.
local lastLevel, lastRank = nil, {}
function A.CheckOwn(levelNow)
    local own = ns.GetOwn and ns.GetOwn()
    if not (own and ns.myGUID) then return end
    local store = Store() or {}
    -- level 60 on the class of this character
    local level = tonumber(levelNow)
    if not level then pcall(function() level = UnitLevel and UnitLevel("player") end) end
    local classFile
    pcall(function() classFile = select(2, UnitClass("player")) end)
    if level and classFile then
        local before = lastLevel
        lastLevel = level
        local key = "L:" .. classFile .. ":60"
        if level >= 60 and byKey[key] and not (store[key] and store[key][ns.myGUID]) then
            local live = before ~= nil and before < 60
            A.Record(key, ns.myGUID, ns.me, ns.Time(), not live, live)
            ShareMine(key, ns.Time(), live)
        end
    end
    -- 300 skill in a profession
    for _, def in ipairs(defs) do
        if def.profession then
            local p = (own.profs or {})[tostring(def.profession)]
            local rank = p and tonumber(p.rank) or 0
            local before = lastRank[def.profession]
            if p then lastRank[def.profession] = rank end        -- (a profession that is not known yet says nothing)
            if p and rank >= 300 and not (store[def.key] and store[def.key][ns.myGUID]) then
                local live = before ~= nil and before < 300
                A.Record(def.key, ns.myGUID, ns.me, ns.Time(), not live, live)
                ShareMine(def.key, ns.Time(), live)
            end
        end
    end
end

-- The guild has cleared a raid: by default now and seen live; with a date when it is worked out from the steps
function A.RecordRaidClear(key, ts, timeKnown)
    local def = byKey[key]
    if not (def and def.kind == "raid" and ns.myGUID) then return false end
    ts = ts or ns.Time()
    if timeKnown == nil then timeKnown = true end
    local recent = ns.Time() - ts <= 15 * 60
    A.Record(key, ns.myGUID, ns.me, ts, not recent, timeKnown)
    ShareMine(key, ts, timeKnown)
    return true
end

---------------------------------------------------------------------------
-- The steps (criteria) of the raid achievements
--   The game lists the steps of its own raid achievements: usually one boss each. They are read from the game (their numbers are
--   the same on every client). A step is done for the GUILD when its boss dies with RAID_MIN or more guildies in the group: that is
--   saved per guild, shared with the guildies (earliest wins), and when all steps are done the guild has the achievement.
--   A raid without steps from the game is cleared by its last boss (see Stats.lua), as before.
---------------------------------------------------------------------------
A.criteria = {}            -- [raid key] = { { id, name, asset, type } ... } as the game lists them
A.achievementID = {}       -- [raid key] = the game's achievement number
A.criteriaRead = nil       -- when the game was last asked

local function Lc(text) return ns.Lower and ns.Lower(text) or tostring(text or ""):lower() end

local function ProgressStore()
    local g = ns.guildName
    local gd = ns.DB and g and ns.DB.guilds[g]
    if not gd then return nil end
    gd.raidProgress = gd.raidProgress or {}
    return gd.raidProgress
end

local function RaidKeyByIcon(icon)
    for _, r in ipairs(RAIDS) do if r[2] == icon then return r[1] end end
end

-- ask the game for the steps of its raid achievements
function A.ScanRaidCriteria()
    if not (GetCategoryNumAchievements and GetAchievementInfo and GetAchievementNumCriteria and GetAchievementCriteriaInfo) then
        A.criteriaRead = false
        return 0
    end
    local found = 0
    local num = 0
    pcall(function() num = GetCategoryNumAchievements(GAME_RAID_CATEGORY) or 0 end)
    for i = 1, num do
        local ok, id, _, _, _, _, _, _, _, _, icon = pcall(GetAchievementInfo, GAME_RAID_CATEGORY, i)
        local key = ok and id and RaidKeyByIcon(icon)
        if key then
            local list, count = {}, 0
            pcall(function() count = GetAchievementNumCriteria(id) or 0 end)
            for c = 1, count do
                local ok2, cname, ctype, _, _, _, _, _, asset, _, cid = pcall(GetAchievementCriteriaInfo, id, c)
                if ok2 and cid and cid ~= 0 then list[#list + 1] = { id = cid, name = cname or "", type = ctype, asset = tonumber(asset) or 0 } end
            end
            A.criteria[key] = list
            A.achievementID[key] = id
            found = found + #list
        end
    end
    A.criteriaRead = ns.Time()
    for _, r in ipairs(RAIDS) do A.EvaluateRaid(r[1]) end     -- (steps that were done before the list was known)
    if A.OnChanged then A.OnChanged() end
    return found
end

-- the steps that count: the game's list without the ones set aside (in the code or with /ff raidcrit)
function A.TrackedCriteria(key)
    local out = {}
    local ignored = (ns.DB and ns.DB.ignoredCriteria and ns.DB.ignoredCriteria[key]) or {}
    local fixed = {}
    for _, raid in ipairs(ns.RAID_CLEARS or {}) do
        if raid.key == key then for _, id in ipairs(raid.ignoreCriteria or {}) do fixed[id] = true end end
    end
    for _, c in ipairs(A.criteria[key] or {}) do
        if not ignored[c.id] and not fixed[c.id] then out[#out + 1] = c end
    end
    return out
end

-- how far the guild is: done, total and the steps with their dates
function A.RaidProgress(key)
    local tracked = A.TrackedCriteria(key)
    local progress = (ProgressStore() or {})[key] or {}
    local steps, done = {}, 0
    for _, c in ipairs(tracked) do
        local p = progress[c.id]
        steps[#steps + 1] = { id = c.id, name = c.name, done = p ~= nil, ts = p and p.ts, time = p and p.time }
        if p then done = done + 1 end
    end
    return done, #tracked, steps
end

-- a step is done (the earliest date wins; the same day, the one with the time of day wins)
function A.RecordCriterion(key, cid, ts, timeKnown)
    local store = ProgressStore()
    if not (store and byKey[key] and byKey[key].kind == "raid" and tonumber(cid) and ts and ts >= 1100000000 and ts <= ns.Time() + 2 * 86400) then return false end
    store[key] = store[key] or {}
    local old = store[key][cid]
    if old and old.time and not timeKnown and math.abs(old.ts - ts) < 86400 then return false end
    if old and old.ts <= ts then return false end
    store[key][cid] = { ts = ts, time = timeKnown == true or nil }
    return true
end

-- all steps done: the guild has the achievement (from the last step's date)
function A.EvaluateRaid(key)
    local tracked = A.TrackedCriteria(key)
    if #tracked == 0 then return false end
    local progress = (ProgressStore() or {})[key] or {}
    local latest, latestTime, complete = 0, false, true
    for _, c in ipairs(tracked) do
        local p = progress[c.id]
        if not p then
            complete = false
        elseif p.ts > latest then
            latest, latestTime = p.ts, p.time == true
        end
    end
    if not complete then
        -- Not all steps are met: the achievement is not completed, whatever was claimed without the steps (by the last boss alone)
        local store = Store()
        if store and store[key] and next(store[key]) then
            store[key] = nil
            if A.OnChanged then A.OnChanged() end
        end
        return false
    end
    if #A.Holders(key) > 0 then return false end
    return A.RecordRaidClear(key, latest, latestTime)
end

-- a boss died in this raid with enough guildies in the group: the steps that belong to it are done.
-- A step belongs to the boss by the encounter number (the same in every language), or by the name (both are in the client's language).
function A.RecordBossKill(key, bossName, encounterID)
    local lname = Lc(bossName)
    local any = false
    for _, c in ipairs(A.TrackedCriteria(key)) do
        local cname = Lc(c.name)
        local byID = encounterID and encounterID ~= 0 and c.asset == encounterID
        local byName = cname ~= "" and lname ~= "" and (cname == lname or lname:find(cname, 1, true) ~= nil or cname:find(lname, 1, true) ~= nil)
        if byID or byName then
            any = true
            local ts = ns.Time()
            if A.RecordCriterion(key, c.id, ts, true) then
                local id = "C|" .. key .. "|" .. c.id
                if not sentThisSession[id] and ns.Sync and ns.Sync.SendCriterion and ns.Sync.SendCriterion(key, c.id, ts, true) then sentThisSession[id] = true end
            end
        end
    end
    A.EvaluateRaid(key)
    if A.OnChanged then A.OnChanged() end
    return any
end

-- a step that a guildmate saw
local heardStep = {}
function A.ReceiveCriterion(key, cid, ts, timeKnown)
    heardStep["C|" .. key .. "|" .. tostring(cid)] = true
    if A.RecordCriterion(key, cid, ts, timeKnown) then
        A.EvaluateRaid(key)
        if A.OnChanged then A.OnChanged() end
    end
end

-- The steps this addon knows, once a session after a random wait (and not when a guildmate sent that step meanwhile): somebody who
-- was offline when a boss died learns the steps this way, so everybody ends up with the same list.
function A.AdvertiseSteps()
    local store = ProgressStore() or {}
    for key, steps in pairs(store) do
        for cid in pairs(steps) do
            local id = "C|" .. key .. "|" .. cid
            if not sentThisSession[id] and not heardStep[id] then
                sentThisSession[id] = true
                ns.After(ns.Random(2, 90), function()
                    if heardStep[id] then return end
                    local cur = (ProgressStore() or {})[key] and ProgressStore()[key][cid]
                    if cur and ns.Sync and ns.Sync.SendCriterion then ns.Sync.SendCriterion(key, cid, cur.ts, cur.time) end
                end)
            end
        end
    end
end

-- sending the claim of somebody else (found in the roster): after a random wait, and not when somebody else already sent it
local heard = {}
function A.Heard(key, guid) heard[key .. "|" .. tostring(guid)] = true end
local function ShareClaim(key, guid)
    local id = key .. "|" .. guid
    if sentThisSession[id] or heard[id] then return end
    sentThisSession[id] = true
    ns.After(ns.Random(2, 60), function()
        if heard[id] then return end
        local holder = (Store() or {})[key] and Store()[key][guid]
        if holder and ns.Sync and ns.Sync.SendAchievement then
            ns.Sync.SendAchievement(key, holder.ts, guid, holder.name, holder.time)
            A.sent = A.sent + 1
        end
    end)
end

-- The guild roster: the level and class of every member, with or without the addon. A member at level 60 or more claims
-- Master <class> (and First to Level 60). First seen at 60: the day it was first seen counts (no time). Seen going from
-- below 60 to 60 (the last level is remembered): the exact time. The addon first looks at the roster when it is installed:
-- everybody who is already 60 is claimed on that day.
function A.ScanRoster()
    local g = ns.guildName
    if not (ns.DB and g and ns.DB.guilds[g] and IsInGuild and IsInGuild()) then return end
    local gd = ns.DB.guilds[g]
    gd.levels = gd.levels or {}
    local store = Store() or {}
    local roster = ns.GetRoster()
    if roster.total == 0 then return end
    -- "live" = I saw the level change between two looks in THIS session: what changed while I was offline is not a news item
    local sessionBefore = A.sessionLevels
    if not sessionBefore and ns.worldReady then sessionBefore = {} end
    local newSession = sessionBefore and not A.sessionLevels
    A.sessionLevels = sessionBefore
    for _, e in ipairs(roster.list) do
        local level = tonumber(e.level)
        if e.guid and e.class and level then
            local before = (not newSession and sessionBefore) and sessionBefore[e.guid] or nil
            if sessionBefore then sessionBefore[e.guid] = level end
            gd.levels[e.guid] = level
            local key = "L:" .. e.class .. ":60"
            if level >= 60 and byKey[key] and not (store[key] and store[key][e.guid]) then
                local live = before ~= nil and before < 60
                if A.Record(key, e.guid, ns.DisplayName(e.name), ns.Time(), not live, live) then
                    if e.guid == ns.myGUID then ShareMine(key, ns.Time(), live) else ShareClaim(key, e.guid) end
                end
            end
        end
    end
end

-- The game's own achievements of my character, when the game offers them (a second source): the real date of what
-- was earned before the addon saw it. An achievement counts for this character when it is its class (or its profession
-- at 300), the character is at that mark, and the game does not say another character earned it.
A.available, A.lastScan, A.categoryCounts = nil, nil, {}
local function ReadCategory(catID)
    local out, num = {}, 0
    pcall(function() num = GetCategoryNumAchievements(catID) or 0 end)
    A.categoryCounts[catID] = num
    for i = 1, num do
        local ok, id, name, points, completed, month, day, year, desc, flags, icon, reward, isGuild, byMe = pcall(GetAchievementInfo, catID, i)
        if ok and id then out[#out + 1] = { completed = completed, month = month, day = day, year = year, desc = desc, byMe = byMe } end
    end
    return out
end

-- days since 1970 from a calendar date, then seconds (noon): plain arithmetic, no clock functions
local function CivilToEpoch(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return (era * 146097 + doe - 719468) * 86400 + 12 * 3600
end
A.CivilToEpoch = CivilToEpoch

local function TierIn(desc, wanted)
    for digits in tostring(desc or ""):gmatch("%d+") do
        if wanted[tonumber(digits)] then return true end
    end
    return false
end

function A.ScanGame()
    if not (GetCategoryNumAchievements and GetAchievementInfo and ns.myGUID) then
        A.available = false
        return 0
    end
    A.available = true
    local own = ns.GetOwn()
    if not own then return 0 end
    local improved = 0
    local function Take(key, entry)
        if not (entry.completed and entry.byMe ~= false) then return end
        local year, month, day = tonumber(entry.year), tonumber(entry.month), tonumber(entry.day)
        if not (year and month and day) then return end
        if year < 100 then year = year + 2000 end
        local ts = CivilToEpoch(year, month, day)
        local before = (Store() or {})[key] and Store()[key][ns.myGUID]
        if A.Record(key, ns.myGUID, ns.me, ts, true, false) then
            improved = improved + 1
            if before then
                -- the date got earlier: tell the others again
                if ns.Sync and ns.Sync.SendAchievement then
                    local now = Store()[key][ns.myGUID]
                    ns.Sync.SendAchievement(key, now.ts, ns.myGUID, ns.me, now.time)
                end
            else
                ShareMine(key, ts, false)
            end
        end
    end
    -- level 60 on the class I am playing
    local level, classFile
    pcall(function() level = UnitLevel("player") classFile = select(2, UnitClass("player")) end)
    if classFile and GAME_CLASS_CATEGORY[classFile] and (tonumber(level) or 0) >= 60 then
        for _, entry in ipairs(ReadCategory(GAME_CLASS_CATEGORY[classFile])) do
            if TierIn(entry.desc, { [60] = true }) then Take("L:" .. classFile .. ":60", entry) end
        end
    end
    -- 300 skill in a crafting profession that I have at 300
    for profession, category in pairs(GAME_PROF_CATEGORY) do
        local p = (own.profs or {})[tostring(profession)]
        if p and (tonumber(p.rank) or 0) >= 300 then
            for _, entry in ipairs(ReadCategory(category)) do
                if TierIn(entry.desc, { [300] = true }) then Take(("P:%d:300"):format(profession), entry) end
            end
        end
    end
    A.lastScan = ns.Time()
    if A.OnChanged then A.OnChanged() end
    return improved
end

-- when the roster changes (now and then, not on every update)
local rosterQueued = false
ns.HookEvent("GUILD_ROSTER_UPDATE", function()
    if rosterQueued or not ns.worldReady then return end
    rosterQueued = true
    ns.After(30, function()
        rosterQueued = false
        A.ScanRoster()
    end)
end)

function ns.PLAYER_LEVEL_UP(level)
    ns.After(2, function() A.CheckOwn(level) end)
end

-- every hour: what my characters earned, again (so that guildmates who were away get it)
function A.AdvertiseOwn()
    if not ns.myGUID then return end
    for key, holders in pairs(Store() or {}) do
        local mine = holders[ns.myGUID]
        if mine and ns.Sync and ns.Sync.SendAchievement then ns.Sync.SendAchievement(key, mine.ts, ns.myGUID, mine.name, mine.time) end
    end
end

-- the list of the tab: group titles and achievements with who was first (for a raid: the guild's first clear)
function A.Rows()
    local rows = {}
    for _, group in ipairs(A.GROUPS) do
        rows[#rows + 1] = { header = group[2] }
        for _, def in ipairs(defs) do
            if def.group == group[1] then
                local holders = A.Holders(def.key)
                local item = { def = def, holders = holders, first = holders[1] }
                if def.kind == "raid" then
                    item.done, item.total, item.steps = A.RaidProgress(def.key)
                    -- with steps from the game it is completed only when every step is met
                    if item.total > 0 and item.done < item.total then item.holders, item.first = {}, nil end
                end
                rows[#rows + 1] = item
            end
        end
    end
    return rows
end

-- /ff achievements: what this addon knows (to find out why something is not shown)
function A.Diagnose()
    ns.Print(("Achievements: the addon's own tracking and the guild roster, plus the game's achievements when it has them (game lists achievements: %s; last read %s). Level seen: %s. Shared this session: %d."):format(
        tostring(A.available), A.lastScan and date("%H:%M:%S", A.lastScan) or "never", tostring(lastLevel), A.sent))
    local seen = {}
    for cat, n in pairs(A.categoryCounts) do seen[#seen + 1] = ("%d:%d"):format(cat, n) end
    table.sort(seen)
    ns.Print("Achievements the game returned per category (category:number; 0 means the game does not know the category): " .. (#seen > 0 and table.concat(seen, " ") or "none read yet"))
    local mine, all = 0, 0
    for _, def in ipairs(defs) do
        local holders = A.Holders(def.key)
        if #holders > 0 then all = all + 1 end
        for _, h in ipairs(holders) do if h.guid == ns.myGUID then mine = mine + 1 end end
        if #holders > 0 then
            local text = {}
            for i, h in ipairs(holders) do if i <= 4 then text[#text + 1] = tostring(h.name) end end
            ns.Print(("  %s: %d known (%s)"):format(def.key, #holders, table.concat(text, ", ")))
        end
    end
    ns.Print(("Achievements known: %d of %d, earned by this character: %d"):format(all, #defs, mine))
end
