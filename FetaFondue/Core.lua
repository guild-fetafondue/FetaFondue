local ADDON = ...
---@class ns
local ns = select(2, ...)

ns.PREFIX = "FFondue"

local DEFAULTS = {
    openOnLogin = false,    -- open the main window at login (off unless the player turns it on)
    welcomeSeen = false,   -- the first-run welcome screen has been shown
    debug = false,
    instanceSend = false, -- test setting (/ff instancesend): try to send addon messages inside dungeons and raids. The game refuses them (tested 1.0.1), so it stays off.
    minimap = { angle = 215 },
    mine = {},        -- my characters on this account: [guid] = { name, guild, profs = { [key] = {...} } }
    guilds = {},      -- [guildName] = { members = { [guid] = { name, profs, seen } } }
    requests = {},    -- [my guid] = { { id, name, qty, t }, ... }
    requestRev = {},  -- [my guid] = time of the last change to that list (so guildmates can tell which copy is newer)
    recipeNames = {}, -- [recipeID] = name, learned from profession windows
    recipeInfo = {},  -- [recipeID] = { item = itemID, reagents = { { id, count }, ... }, made, icon, req }
    inspect = {},         -- [guid] = last gear and talents received from that guildie
    talentLayouts = {},   -- [specID] = layout of that class's talent tree (from the game), cached
    recipeReq = {},   -- [recipeID] = exact skill needed, from addons that know it (Profession Master, LibCraftLevels)
    extraZones = { raid = {}, dungeon = {}, capital = {} }, -- zones added with /ff addzone
    extraFinalBosses = {}, -- final boss names added with /ff addboss
    blockedLog = {},
    ignoredCriteria = {},  -- [raid key] = { [step number] = true }: steps of a raid achievement that are set aside (/ff raidcrit)
    extraRaidIDs = {},     -- [raid key] = { instance ids }: raids added with /ff addraidid (the same in every language)
    extraRaidFinal = {},   -- [raid key] = { names = {...}, ids = {...} }: last bosses added with /ff addraidboss
    toasts = true,         -- small messages that close by themselves (achievements)
    raidReminded = {},     -- [raid id:start] = when its 15-minutes reminder was shown
    showOffline = false,   -- the dashboard list also shows guildies who are offline
    finalBossIDs = {},     -- encounter ids of final bosses (learned from clients that know the names)
    itemCache = {},        -- [itemID] = { n = name, i = icon, q = quality }: so item icons show at once
    iconCache = {},        -- [recipeID] = icon
    demo = false,     -- show example numbers on the dashboard
}

local DB

---------------------------------------------------------------------------
-- Small helpers (Sync.lua only talks to the game through these, so it can be tested alone)
---------------------------------------------------------------------------
local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                CopyDefaults(v, dst[k])
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" then
            CopyDefaults(v, dst[k])
        end
    end
end

function ns.Print(msg)
    print("|cffffd100FetaFondue:|r " .. tostring(msg))
end

function ns.Debug(msg)
    if DB and DB.debug then ns.Print("|cff888888[debug]|r " .. tostring(msg)) end
end

function ns.After(delay, fn) C_Timer.After(delay, fn) end

-- the version from the .toc, and the Lua errors of this addon seen this session (for the Admin tab)
ns.errors = { count = 0, last = "" }
function ns.Version()
    if ns.versionText then return ns.versionText end
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, v = pcall(function() return meta and meta(ADDON, "Version") end)
    ns.versionText = (ok and v and v ~= "") and v or "?"
    return ns.versionText
end

-- "0.44.1" against "0.44.0": 1 when a is newer, -1 when older, 0 when the same (or when one is not a version)
function ns.CompareVersions(a, b)
    local function Parts(v)
        local x, y, z = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)$")
        if not x then return nil end
        return { tonumber(x), tonumber(y), tonumber(z) or 0 }
    end
    local pa, pb = Parts(a), Parts(b)
    if not (pa and pb) then return 0 end
    for i = 1, 3 do
        if pa[i] ~= pb[i] then return pa[i] > pb[i] and 1 or -1 end
    end
    return 0
end

-- The admin announces a new version (the Admin tab, after the file is uploaded to the Discord channel): everybody whose addon is older
-- gets a window. The announced version is saved, so a player who logs in later is told too (guildmates who know of it repeat the
-- announcement when somebody logs in, see Sync.lua: that works for everybody who has heard it, whichever version they run).
-- The window never opens in a fight, during a loading screen or before the world is ready: it waits and shows up afterwards.
-- A player who is still on the old version two hours later gets it again (UPDATE_REPEAT seconds), as long as the session lasts.
local UPDATE_REPEAT = 2 * 3600
local loadingScreen = false
local function WatchLoadingScreens()          -- (called once HookEvent exists, further down)
    ns.HookEvent("PLAYER_LEAVING_WORLD", function() loadingScreen = true end)
    ns.HookEvent("LOADING_SCREEN_ENABLED", function() loadingScreen = true end)
    ns.HookEvent("LOADING_SCREEN_DISABLED", function() loadingScreen = false end)
    ns.HookEvent("PLAYER_ENTERING_WORLD", function() loadingScreen = false end)
end

-- true while a window should not pop up: a fight, a loading screen, or the world is not ready yet
function ns.IsBusyForPopup()
    local busy = false
    pcall(function() busy = (InCombatLockdown and InCombatLockdown()) and true or false end)
    -- also not inside a dungeon, raid, battleground or arena: the popup waits until we are out
    local inside = false
    pcall(function()
        local isIn, kind = IsInInstance()
        inside = (isIn and kind and kind ~= "none") and true or false
    end)
    return busy or inside or loadingScreen or not ns.worldReady
end

local updatePending = false
local function ShowIfOlder()
    local announced = ns.DB and ns.DB.announcedVersion
    if not announced or updatePending or not (ns.UI and ns.UI.ShowUpdate) then return end
    if ns.CompareVersions(announced, ns.Version()) <= 0 then return end
    updatePending = true
    local function Try()
        local newest = ns.DB and ns.DB.announcedVersion
        if not newest or ns.CompareVersions(newest, ns.Version()) <= 0 then updatePending = false return end    -- (updated meanwhile)
        if ns.IsBusyForPopup() then ns.After(30, Try) return end
        ns.UI.ShowUpdate(newest)
        ns.After(UPDATE_REPEAT, Try)                          -- (and again later if still on the old version)
    end
    ns.After(2, Try)
end

-- an announcement arrived (or I know one from an earlier session): keep the newest one and tell the player when it is newer than mine
function ns.NoteAnnouncement(ver)
    if not ns.DB or not tostring(ver or ""):match("^%d+%.%d+%.?%d*$") then return end
    if ns.CompareVersions(ver, ns.DB.announcedVersion or "0.0.0") > 0 then ns.DB.announcedVersion = ver end
    ShowIfOlder()
end
function ns.CheckAnnouncement() ShowIfOlder() end

-- where in our code we were when something happened: the call stack, shortened
local function StackText()
    local ok, s = pcall(function() return debugstack and debugstack(3, 12, 0) end)
    if not ok or type(s) ~= "string" then return "" end
    s = s:gsub("[Ii]nterface\\[Aa]dd[Oo]ns\\", ""):gsub("[|]", "/")
    return s:sub(1, 800)
end
ns.StackText = StackText

-- The game also reports blocked and forbidden actions as an error MESSAGE to the error handler (that is where
-- tools like BugSack get them from), and it does so inside the call that was blocked: so the call stack at that moment
-- shows which of our functions made it. This is installed as early as possible, when the addon loads.
local function InstallErrorCapture()
    if ns.errorCaptureInstalled or not (geterrorhandler and seterrorhandler) then return end
    ns.errorCaptureInstalled = true
    local old = geterrorhandler()
    seterrorhandler(function(msg)
        local ok = pcall(function()
            local text = tostring(msg)
            local ours = text:find("FetaFondue", 1, true) ~= nil
            if ours then
                ns.errors.count = ns.errors.count + 1
                local short = text:gsub("[Ii]nterface\\[Aa]dd[Oo]ns\\FetaFondue\\", ""):gsub("[\r\n|]+", " ")
                ns.errors.last = short:sub(1, 140)
            end
            local aboutBlock = text:find("ADDON_ACTION", 1, true) or text:find("protected function", 1, true)
                or text:find("forbidden function", 1, true) or text:find("blocked from an action", 1, true)
            if ours and aboutBlock and ns.NoteBlocked then
                ns.NoteBlocked("MESSAGE", ADDON, (text:gsub("[\r\n|]+", " ")):sub(1, 220), StackText())
            end
        end)
        if old then return old(msg) end
    end)
end
ns.InstallErrorCapture = InstallErrorCapture
InstallErrorCapture()

-- Lower case for names in UTF-8: the game's own lower() only knows the plain letters, so "Élodie" and "élodie" or "Jäger" and
-- "jäger" would not look alike on a French or German client. This one also lowers the accented Latin letters (À-Þ, Œ, Š, Ž).
local function Lower(s)
    s = tostring(s or ""):lower()
    s = s:gsub("\195([\128-\158])", function(b) if b == "\151" then return nil end return "\195" .. string.char(b:byte() + 32) end)
    s = s:gsub("\197\146", "\197\147"):gsub("\197\160", "\197\161"):gsub("\197\189", "\197\190")
    return s
end
ns.Lower = Lower

-- letters only, lower case: "Purple Xtazy", "Purple-Xtazy-Realm" and "purplextazy" all look alike
local function Squash(s) return (Lower(s):gsub("[%s%-_'`\"]", "")) end
ns.Squash = Squash

-- Text that came from somebody else's addon and is shown to the player: no colour codes, links or pictures (a "|" starts one of
-- those in the game's text). Plain text loses every "|" and line break; with keepLayout (a note) the new lines and any "|" that
-- is not part of a code stay.
local function StripCodes(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", ""):gsub("|[nN]", " "))
end
function ns.CleanText(text, keepLayout)
    text = tostring(text or "")
    if not text:find("[|%c]") then return text end
    text = StripCodes(text)
    if keepLayout then
        return (text:gsub("[%z\1-\8\11-\31\127]", " "))
    end
    return (text:gsub("|", ""):gsub("%c", " "))
end

-- the names this character goes by: with and without a realm part ("Name-Realm")
local function MyNames()
    local names = {}
    local function Add(s)
        if type(s) ~= "string" or s == "" then return end
        names[#names + 1] = Squash(s)
        names[#names + 1] = Squash((s:gsub("%-.*$", "")))
    end
    Add(ns.me)
    pcall(function()
        local n, realm = UnitName("player")
        Add(n)
        if n and realm and realm ~= "" then Add(n .. realm) end
        if GetUnitName then Add(GetUnitName("player", true)) end
    end)
    return names
end

-- The game tells us when it blocks an addon from an action only the Blizzard UI may do. We log every such event
-- (whoever it was for), with the function it named and what the addon was reacting to. Events that arrive before
-- the saved data is loaded wait in a small buffer.
ns.blocked = { count = 0, pending = {} }
local blockedAnnounced = false
local function StoreBlocked(info)
    DB.blockedLog = DB.blockedLog or {}
    table.insert(DB.blockedLog, info)
    while #DB.blockedLog > 10 do table.remove(DB.blockedLog, 1) end
end
function ns.NoteBlocked(kind, addon, func, stack)
    local mine = (addon == ADDON)
    local info = { kind = kind, addon = tostring(addon), func = tostring(func), event = tostring(ns.lastEvent), at = ns.Time and ns.Time() or 0,
        stack = stack or StackText(), n = 1, context = ns.blockContext }
    if ns.Invite and ns.Invite.OnBlocked then ns.Invite.OnBlocked(addon, func) end
    if mine then
        ns.blocked.count = ns.blocked.count + 1
        ns.blocked.last = info
        ns.errors.count = ns.errors.count + 1
        ns.errors.last = ("%s %s after %s"):format(kind, info.func, info.event):sub(1, 140)
    end
    -- the same thing again within a few seconds is one entry that counts up
    local log = DB and (DB.blockedLog or {}) or ns.blocked.pending
    local last = log[#log]
    if last and last.kind == info.kind and last.addon == info.addon and last.func == info.func and info.at - (last.at or 0) <= 5 then
        last.n = (last.n or 1) + 1
    elseif DB then
        StoreBlocked(info)
    else
        table.insert(ns.blocked.pending, info)
    end
    -- only tell the player when it is this addon (other addons' blocks are written to the log, quietly)
    if mine and not blockedAnnounced then
        blockedAnnounced = true
        ns.Print(("The game blocked an action (%s, %s%s). Please type /ff blocked and send the lines to the officers."):format(info.addon, info.func, info.context and (", while: " .. info.context) or ""))
    end
end
function ns.ADDON_ACTION_BLOCKED(addon, func) ns.NoteBlocked("BLOCKED", addon, func) end
function ns.ADDON_ACTION_FORBIDDEN(addon, func) ns.NoteBlocked("FORBIDDEN", addon, func) end

-- is this the admin (see Data.lua)?
function ns.IsAdmin()
    if ns.myGUID and ns.ADMIN_GUIDS[ns.myGUID] then return true end
    for _, mine in ipairs(MyNames()) do
        for admin in pairs(ns.ADMIN_NAMES) do
            if mine == Squash(admin) then return true end
        end
    end
    return false
end

local sessionStart = GetTime and GetTime() or 0
function ns.SessionMinutes() return math.max(0, math.floor(((GetTime and GetTime() or 0) - sessionStart) / 60)) end
function ns.Now() return GetTime() end
function ns.Time() return time() end
function ns.Random(a, b) return math.random(a, b) end

function ns.DisplayName(name)
    if not name then return "?" end
    if Ambiguate then return Ambiguate(name, "guild") end
    return name
end

---------------------------------------------------------------------------
-- Sending (addon messages)
---------------------------------------------------------------------------
-- Is sending addon chat held back right now? The game's own chat lockdown always holds it, and so does being inside a dungeon or raid: the game
-- refuses addon messages sent from inside an instance (tested in 1.0.1: the send came back refused, while receiving works fine). The messages
-- wait in the queue and go out after we leave. The test setting "instanceSend" (/ff instancesend, off by default) makes the addon try anyway;
-- when the game refuses, the message is kept and sending stops until we are out (ns.instRefused). /ff instance shows what happened.
ns.instStats = { ok = 0, refused = 0, received = 0 }
ns.instRefused = false
function ns.InInstance()
    local inside = false
    pcall(function() inside = IsInInstance() and true or false end)
    return inside
end
function ns.IsMessagingBlocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return true
    end
    if not ns.InInstance() then
        ns.instRefused = false
        return false
    end
    if ns.instRefused then return true end
    return not (ns.DB and ns.DB.instanceSend == true)
end

-- Returns "ok", "throttled" (try again later) or "dropped".
function ns.RawSend(msg, channel, target)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not fn then return "dropped" end
    local ok, res = pcall(fn, ns.PREFIX, msg, channel, target)
    ns.lastSendCode = ok and tostring(res) or ("error: " .. tostring(res))
    if not ok then return "dropped" end
    if res == 3 or res == 8 or res == 10 then return "throttled" end -- addon / channel / chat throttle
    if type(res) == "number" and res ~= 0 then return "dropped" end
    return "ok"
end

---------------------------------------------------------------------------
-- Guild, roster and stored members
---------------------------------------------------------------------------
function ns.RequestRoster()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

function ns.GuildName()
    if not IsInGuild() then return nil end
    local g = GetGuildInfo("player")
    if g and g ~= "" then return g end
    return nil
end

-- Snapshot of the guild roster: online state by character GUID (and by name as a fallback).
-- Building it asks the game about every member and tidies every name, and it is asked for very often (once per incoming
-- officer message, on every roster update, by the windows...). So one snapshot is kept and reused until the game says the
-- roster changed (GUILD_ROSTER_UPDATE) or ROSTER_TTL seconds have passed. Nobody changes a snapshot they get: treat it as read-only.
ns.ROSTER_TTL = 15
local rosterCache, rosterBuiltAt = nil, -1e9
function ns.InvalidateRoster() rosterCache = nil end

function ns.GetRoster()
    if rosterCache and (ns.Now() - rosterBuiltAt) < ns.ROSTER_TTL then return rosterCache end
    local roster = { byGUID = {}, byName = {}, bySquash = {}, list = {}, total = 0, online = 0 }
    if not IsInGuild() then return roster end
    local total = GetNumGuildMembers() or 0
    for i = 1, total do
        local name, rankName, rankIndex, level, classDisplay, zone, note, _, isOnline, status, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if name then
            local entry = { name = name, online = isOnline and true or false, level = level, class = classFile, guid = guid, zone = zone, status = status,
                rank = rankName, rankIndex = rankIndex, classDisplay = classDisplay, note = note }
            entry.sq = ns.Squash(name)                                      -- (the tidied names are kept: TrackJoins and others need them too)
            entry.sqPlain = ns.Squash((name:gsub("%-.*$", "")))
            if not entry.online and GetGuildRosterLastOnline then
                -- how long ago the member was last online: years, months, days, hours (the game's own rough measure)
                local ok, y, mo, d, h = pcall(GetGuildRosterLastOnline, i)
                if ok and y then entry.offlineFor = (((tonumber(y) or 0) * 365 + (tonumber(mo) or 0) * 30 + (tonumber(d) or 0)) * 24 + (tonumber(h) or 0)) * 3600 end
            end
            if guid then roster.byGUID[guid] = entry end
            roster.byName[name] = entry
            local plain = entry.sqPlain
            roster.bySquash[entry.sq] = entry
            roster.bySquash[plain] = roster.bySquash[plain] or entry
            roster.list[#roster.list + 1] = entry
            roster.total = roster.total + 1
            if entry.online then roster.online = roster.online + 1 end
        end
    end
    -- (an empty roster is not kept: at login it is empty until the game has sent the members)
    if roster.total > 0 then rosterCache, rosterBuiltAt = roster, ns.Now() end
    return roster
end

---------------------------------------------------------------------------
-- When did a member join the guild? The game does not say, so the addon notes the day it first sees somebody appear in the roster
-- (exact = true). Whoever was already there when the addon first looked is only known to be there "before" that day (exact = false).
-- Addon users share what they noted (Sync.lua); the exact date beats a "before", and between two dates the earlier one wins.
---------------------------------------------------------------------------
local function GuildStore()
    local g = ns.guildName
    return g and ns.DB and ns.DB.guilds and ns.DB.guilds[g] or nil
end

-- { ts = unix time, exact = bool } or nil
function ns.GetJoined(guid)
    local gd = GuildStore()
    return gd and gd.joined and guid and gd.joined[guid] or nil
end

-- returns true when it changed what we know
-- live = seen happening in this session (see ns.JoinWasLive); only then a toast
-- The earliest join date that is believed: the day the addon first looked (before that it did not exist, so nobody can have an exact date).
function ns.JoinEarliest()
    local d = ns.JOIN_DEFAULT
    return d and ns.CivilToTime(d[1], d[2], d[3]) or 0
end

function ns.NoteJoined(guid, ts, exact, live)
    local gd = GuildStore()
    ts = tonumber(ts)
    if not (gd and guid and ts and ts > 0) then return false end
    gd.joined = gd.joined or {}
    local old = gd.joined[guid]
    local isNew = old == nil
    exact = exact and true or false
    local better = not old
    if old then
        if exact and not old.exact then better = true
        elseif exact == old.exact and ts < old.ts then better = true end
    end
    if better then gd.joined[guid] = { ts = ts, exact = exact } end
    if better and isNew and exact and live then ns.AnnounceJoin(guid, ts) end
    return better
end

-- Toasts are for what happens while I am online: something that happened before I logged in (and reaches me only as synced
-- data from a guildmate) never gets one, even when it is only a few minutes old.
ns.loadedAt = time()
function ns.HappenedWhileOnline(ts)
    return type(ts) == "number" and ts >= (ns.loadedAt or 0) - 2
end

-- The one rule for every toast: it needs a time, the time is within the last 15 minutes and not before I logged in, and the world is ready.
function ns.ToastAllowed(ts)
    if not ns.worldReady or type(ts) ~= "number" then return false end
    if math.abs(ns.Time() - ts) > 15 * 60 then return false end
    return ns.HappenedWhileOnline(ts)
end

-- A member who has just joined the guild (seen live, not an old date from the log or a first look at the roster): a toast.
-- Whoever noted it first shows it; a date heard later from a guildmate is not new for him, so nobody sees it twice.
function ns.AnnounceJoin(guid, ts)
    if not (ns.worldReady and ns.UI and ns.UI.JoinToast) then return end
    if ns.IsMine and ns.IsMine(guid) then return end
    if math.abs(ns.Time() - ts) > 15 * 60 then return end
    if not ns.HappenedWhileOnline(ts) then return end
    ns.UI.JoinToast(guid, ts)
end

-- Look at the roster: the first time, everybody present is "before today"; later, a new name is a member who joined (now, exactly).
-- Returns the guids that are new or improved, for sharing.
-- noon UTC of a calendar date (plain arithmetic), and back: day, month, year
function ns.CivilToTime(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return (era * 146097 + doe - 719468) * 86400 + 43200
end
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
function ns.DateText(ts)
    local z = math.floor(ts / 86400) + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    local y = yoe + era * 400 + (m <= 2 and 1 or 0)
    return ("%02d %s %d"):format(d, MONTHS[m], y)
end

-- "Last seen 3 days ago" from the roster's rough measure (years, months, days, hours)
function ns.LastSeenText(entry)
    local secs = entry and entry.offlineFor
    if not secs then return "Offline" end
    local h = math.floor(secs / 3600)
    local function Plural(n, w) return ("%d %s%s ago"):format(n, w, n == 1 and "" or "s") end
    if h < 1 then return "Last seen less than an hour ago" end
    if h < 24 then return "Last seen " .. Plural(h, "hour") end
    local d = math.floor(h / 24)
    if d < 30 then return "Last seen " .. Plural(d, "day") end
    if d < 365 then return "Last seen " .. Plural(math.floor(d / 30), "month") end
    return "Last seen " .. Plural(math.floor(d / 365), "year")
end

-- Who was in the roster when I first looked in THIS session (after the world is ready, so the roster is complete). Somebody who
-- is not in this list but appears later joined while I was online; somebody who is in it may have joined while I was away.
ns.joinBaseline = nil
function ns.JoinWasLive(guid)
    return ns.joinBaseline ~= nil and guid ~= nil and ns.joinBaseline[guid] == nil
end

function ns.TrackJoins()
    local gd = GuildStore()
    if not (gd and IsInGuild and IsInGuild()) then return {} end
    local roster = ns.GetRoster()
    if roster.total < 1 then return {} end
    local now = ns.Time()
    local first = not gd.joinedBase
    gd.joinedBase = gd.joinedBase or now
    local dflt = ns.JOIN_DEFAULT and ns.CivilToTime(ns.JOIN_DEFAULT[1], ns.JOIN_DEFAULT[2], ns.JOIN_DEFAULT[3]) or now
    local changed = {}
    if ns.worldReady and not ns.joinBaseline then
        ns.joinBaseline = {}
        for _, e in ipairs(roster.list) do if e.guid then ns.joinBaseline[e.guid] = true end end
    end
    for _, e in ipairs(roster.list) do
        if e.guid then
            local have = gd.joined and gd.joined[e.guid]
            if not have then
                local ts, exact = now, true
                if first then ts, exact = dflt, false end
                if ns.NoteJoined(e.guid, ts, exact, ns.JoinWasLive(e.guid)) then changed[#changed + 1] = e.guid end
            end
        end
    end
    return changed
end

-- A roster entry by name. The game writes the same character as "Purple Xtazy", "Purple-Xtazy" or just
-- "Purple" in different places, so names are also compared without case, spaces and dashes.
function ns.RosterFind(roster, name)
    if not name or name == "" then return nil end
    local e = roster.byName[name] or roster.byName[ns.DisplayName(name)]
    if e then return e end
    return roster.bySquash[ns.Squash(name)]
end
function ns.FindRosterEntry(roster, guid, name)
    return roster.byGUID[guid] or ns.RosterFind(roster, name) or nil
end

-- my own full name: the roster's spelling when the roster is known, else the name and "realm" part joined
function ns.FullName()
    local roster = ns.myGUID and ns.GetRoster()
    local e = roster and roster.byGUID[ns.myGUID]
    if e and e.name then return ns.DisplayName(e.name) end
    local n, realm
    pcall(function() n, realm = UnitName("player") end)
    if n and realm and realm ~= "" then return n .. " " .. realm end
    return n
end

function ns.GetMembers()
    if not DB then return nil end
    local g = ns.guildName
    if not g then return nil end
    local gd = DB.guilds[g]
    if not gd then
        gd = { members = {} }
        DB.guilds[g] = gd
    end
    return gd.members
end

-- Guild master and officers may delete other people's requests.
function ns.CanModerate()
    local ok, res = pcall(function()
        if IsGuildLeader and IsGuildLeader() then return true end
        if CanEditOfficerNote and CanEditOfficerNote() then return true end
        if C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() then return true end
        return false
    end)
    return ok and res or false
end

-- Did this addon message come from the guild master / an officer (top two ranks)?
-- Alt / main settings made by officers: [altGUID] = { main = mainGUID | "-" (this is a main, not an alt) |
-- "x" (setting removed: back to the automatic guess), rev = time of the change }
function ns.GetAltLinks()
    if not DB then return nil end
    local g = ns.guildName
    if not g then return nil end
    local gd = DB.guilds[g]
    if not gd then
        gd = { members = {} }
        DB.guilds[g] = gd
    end
    gd.altLinks = gd.altLinks or {}
    return gd.altLinks
end

-- who may guild-invite: what the game says (CanGuildInvite), or rank 4 and higher (rank index 0-3: guild master ... Big Feta)
ns.INVITE_MAX_RANK_INDEX = 3
function ns.CanInviteToGuild()
    local ok = false
    pcall(function() if CanGuildInvite and CanGuildInvite() then ok = true end end)
    if ok then return true end
    pcall(function()
        local e = ns.myGUID and ns.GetRoster().byGUID[ns.myGUID]
        if e and e.rankIndex ~= nil and e.rankIndex <= ns.INVITE_MAX_RANK_INDEX then ok = true end
    end)
    return ok
end

-- The officer ranks of this guild: guild master (index 0) and the three ranks below it. Whoever the game lets change officer
-- things (ns.CanModerate) is in that range, so everything an officer sends is accepted by everybody. (Until 0.48.5 this was
-- index 1: officers on the lower officer ranks were ignored by every client, the guild master's included.)
ns.OFFICER_MAX_RANK_INDEX = 3
ns.officerRejects = {}      -- the last officer-only messages that were refused: { at, sender, why }, newest last (/ff shitlist)

local function NoteReject(sender, why)
    local list = ns.officerRejects
    list[#list + 1] = { at = (ns.Time and ns.Time()) or 0, sender = tostring(sender), why = why }
    while #list > 10 do table.remove(list, 1) end
end

function ns.IsOfficerSender(sender)
    local e = ns.RosterFind(ns.GetRoster(), sender)
    if not e then NoteReject(sender, "not found in the guild roster") return false end
    if e.rankIndex == nil then NoteReject(sender, "rank unknown") return false end
    if e.rankIndex > ns.OFFICER_MAX_RANK_INDEX then
        NoteReject(sender, ("rank index %d (%s) is below the officer ranks"):format(e.rankIndex, tostring(e.rank)))
        return false
    end
    return true
end

function ns.GetOwn() return DB and ns.myGUID and DB.mine[ns.myGUID] or nil end
function ns.IsMine(guid) return DB and DB.mine[guid] ~= nil end

-- Own data lives in DB.mine; the guild member table points at the same tables so every
-- character of mine that is in this guild shows up in the Workshop right away.
function ns.OnGuildKnown()
    local g = ns.GuildName()
    if not g then return false end
    ns.guildName = g
    -- now the roster is known: use the guild's spelling of my own name
    local full = ns.FullName()
    if full and full ~= ns.me then
        ns.me = full
        if DB.mine[ns.myGUID] then DB.mine[ns.myGUID].name = full end
    end
    local own = ns.GetOwn()
    if own then own.guild = g end
    local members = ns.GetMembers()
    for guid, ch in pairs(DB.mine) do
        if ch.guild == g then members[guid] = ch end
    end
    return true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
-- Events: ns.<EVENT> is the main handler; other files can add more with ns.HookEvent(event, fn)
local hooks = {}
function ns.HookEvent(event, fn)
    hooks[event] = hooks[event] or {}
    table.insert(hooks[event], fn)
    if frame then pcall(frame.RegisterEvent, frame, event) end
end

function ns.Dispatch(event, ...)
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then ns.lastEvent = event end      -- (for /ff blocked)
    local fn = ns[event]
    if fn then fn(...) end
    for _, h in ipairs(hooks[event] or {}) do h(...) end
end
frame:SetScript("OnEvent", function(_, event, ...) ns.Dispatch(event, ...) end)

-- The two blocked-action events come first, so that anything the game objects to later in this list is reported to us.
-- (COMBAT_LOG_EVENT_UNFILTERED is NOT here: the game forbids addons to register it, and registering it made the
-- game block the whole addon every time it loaded: "blocked from an action only available to the Blizzard UI".)
local EVENTS = {
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
    "ADDON_LOADED", "PLAYER_LOGIN", "GUILD_ROSTER_UPDATE", "CHAT_MSG_ADDON",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "CRAFT_SHOW", "CRAFT_UPDATE", "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED",
    "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED",
    "ZONE_CHANGED_NEW_AREA", "INSPECT_READY", "SPELL_DATA_LOAD_RESULT", "ENCOUNTER_END", "BOSS_KILL", "LFG_COMPLETION_REWARD",
    "SCENARIO_CRITERIA_UPDATE", "SCENARIO_UPDATE", "PLAYER_MONEY", "MAIL_INBOX_UPDATE", "PLAYER_LEVEL_UP",
    "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANK_UPDATE_MONEY",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
}
-- pcall: if this client lacks one of the events we skip it instead of erroring.
for _, ev in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, ev) end
WatchLoadingScreens()        -- (after the blocked-action events, which must stay first)
pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")

function ns.ADDON_LOADED(name)
    if name ~= ADDON then return end
    FetaFondueDB = FetaFondueDB or {}
    DB = FetaFondueDB
    CopyDefaults(DEFAULTS, DB)
    -- a random id of this installation: the guild can tell how many people (not characters) run the addon
    if not DB.clientID then DB.clientID = ("%08x%04x"):format(math.random(1, 2147483647), math.random(0, 65535)) end
    ns.DB = DB
    for _, info in ipairs(ns.blocked.pending) do StoreBlocked(info) end      -- blocked events that came before the saved data
    ns.blocked.pending = {}
end

function ns.PLAYER_LOGIN()
    InstallErrorCapture()
    ns.myGUID = UnitGUID("player")
    ns.me = ns.FullName()
    DB.mine[ns.myGUID] = DB.mine[ns.myGUID] or { name = ns.me, profs = {} }
    -- when this character first submitted data: the oldest character of an installation is its original
    if not DB.mine[ns.myGUID].created then DB.mine[ns.myGUID].created = ns.Time() end
    DB.mine[ns.myGUID].name = ns.me
    ns.Stats.Init()

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(ns.PREFIX)
    end

    ns.InitUI()
    ns.RequestRoster()

    -- The guild name is not always known the instant we log in.
    local tries = 0
    local function WhenGuildKnown()
        tries = tries + 1
        if ns.OnGuildKnown() then
            ns.Professions.RefreshKnown()
            ns.Sync.StartSession()
            if ns.CheckAnnouncement then ns.CheckAnnouncement() end
            if ns.RefreshUI then ns.RefreshUI() end
        elseif tries < 6 and IsInGuild() ~= false then
            ns.After(3, WhenGuildKnown)
        end
    end
    ns.After(4, function()
        if ns.UI.ShowOnLogin then ns.UI.ShowOnLogin() elseif DB.openOnLogin then ns.ShowDashboard() end
        WhenGuildKnown()
    end)
end

-- Reading talents and gear through the game's talent system right at login can make the game fire its (synchronous)
-- talent events while Blizzard's own UI is still starting: so none of that is done until the world has been up for
-- a few seconds (ns.worldReady).
ns.worldReady = false
-- Every loading screen (a dungeon, a portal, a hearthstone) fires this event, not only the login. The start-up reading and
-- telling (stats, achievements, raids, the cooldown loop) is for the start of a session: it ran again on every loading screen
-- until 0.48.7, which sent the same data to the guild again and started another cooldown loop each time.
local sessionStarted = false
function ns.PLAYER_ENTERING_WORLD()
    ns.Sync.OnWorldEntered()
    ns.Stats.UpdateRun()
    ns.After(10, function()
        ns.worldReady = true
        if ns.RefreshUI then ns.RefreshUI() end
        if sessionStarted then return end
        sessionStarted = true
        -- now that race and role can be read, tell the guild
        if ns.Sync and ns.Sync.AdvertiseOwnStats then ns.After(5, ns.Sync.AdvertiseOwnStatsIfChanged or ns.Sync.AdvertiseOwnStats) end
        -- my specializations and profession cooldowns
        if ns.Specs then ns.After(6, ns.Specs.Start) end
        -- and read my achievements (the guild firsts), a little later
        if ns.Achievements then
            ns.After(8, function() ns.Achievements.CheckOwn() end)
            ns.After(11, function() ns.Achievements.ScanGame() ns.Achievements.ScanRaidCriteria() end)       -- (the game's own data: real dates for what was earned before)
            ns.After(14, function() ns.Achievements.ScanRoster() end)     -- (everybody in the guild: their level and class)
            ns.After(50, function() if ns.Sync and ns.Sync.AdvertiseOwnAchievements then ns.Sync.AdvertiseOwnAchievements(true) else ns.Achievements.AdvertiseOwn() end end)
            ns.After(60, function() ns.Achievements.AdvertiseSteps() end)      -- (once the sender is ready: what the first read could not send)
        end
        -- the raid calendar: forget old events, ask the officers what is new; officers share theirs
        ns.After(30, function()
            if ns.Raids then ns.Raids.StartReminders() end
            if ns.Sync and ns.Sync.RequestRaids then ns.Sync.RequestRaids() end
            if ns.Sync and ns.Sync.AdvertiseRaids and ns.CanModerate() then ns.After(15, ns.Sync.AdvertiseRaids) end
        end)
    end)
end

-- Remove everything we know about people who are no longer in the guild: professions, requests, race and
-- role, gear and talents, alt settings. The same for their other characters (same installation, or linked
-- by an officer), because the whole person is gone. Their share of the lifetime counters is kept in
-- "archived" so the guild totals do not drop. Returns how many characters were removed.
function ns.PurgeDeparted()
    local g = ns.guildName
    local gd = g and DB.guilds[g]
    if not (gd and gd.members) then return 0 end
    local roster = ns.GetRoster()
    if roster.total < 1 then return 0 end          -- roster not loaded: nobody is "gone" yet

    -- somebody who left and comes back is a new member: forget the old date (not when the roster looks half loaded)
    if gd.joined then
        local known, absent = 0, {}
        for guid in pairs(gd.joined) do
            known = known + 1
            if not roster.byGUID[guid] and not ns.IsMine(guid) then absent[#absent + 1] = guid end
        end
        if #absent > 0 and roster.total >= known * 0.8 then
            for _, guid in ipairs(absent) do gd.joined[guid] = nil end
        end
    end

    local members = gd.members
    local gone, total, goneCount = {}, 0, 0
    for guid, m in pairs(members) do
        total = total + 1
        if not ns.IsMine(guid) and not ns.FindRosterEntry(roster, guid, m.name) then
            gone[guid] = true
            goneCount = goneCount + 1
        end
    end
    if goneCount == 0 then return 0 end
    if total >= 6 and goneCount > total * 0.5 then return 0 end   -- looks like a half-loaded roster: do nothing

    -- the same person: the same installation, or characters an officer linked together
    local links = gd.altLinks or {}
    local set = {}
    for guid in pairs(gone) do set[guid] = true end
    for guid in pairs(gone) do
        local client = members[guid].client
        if client then
            for other, om in pairs(members) do if om.client == client then set[other] = true end end
        end
        local link = links[guid]
        local main = link and link.main
        if main and main ~= "-" and main ~= "x" then
            set[main] = true
            for alt, l in pairs(links) do if l.main == main then set[alt] = true end end
        end
        for alt, l in pairs(links) do if l.main == guid then set[alt] = true end end
    end

    gd.archived = gd.archived or { d = 0, b = 0, c = 0, g = 0 }
    local removed = 0
    for guid in pairs(set) do
        if not ns.IsMine(guid) and members[guid] then
            local st = members[guid].stats
            if st then
                gd.archived.d, gd.archived.b = gd.archived.d + (st.d or 0), gd.archived.b + (st.b or 0)
                gd.archived.c, gd.archived.g = gd.archived.c + (st.cx or st.c or 0), gd.archived.g + (st.g or 0)
            end
            members[guid] = nil
            if DB.inspect then DB.inspect[guid] = nil end
            links[guid] = nil
            removed = removed + 1
        end
    end
    for alt, l in pairs(links) do if set[l.main] then links[alt] = nil end end
    if removed > 0 then
        ns.Debug(("removed %d characters of people who left the guild"):format(removed))
        if ns.RefreshUI then ns.RefreshUI() end
    end
    return removed
end

local lastPurge = -1e9
function ns.GUILD_ROSTER_UPDATE()
    ns.InvalidateRoster()                          -- (the game says the roster changed: the next look builds a fresh snapshot)
    if not ns.guildName then ns.OnGuildKnown() end
    if ns.guildName and ns.DB then
        local changed = ns.TrackJoins()
        if #changed > 0 and ns.Sync and ns.Sync.AdvertiseJoined then
            local first = {}
            for _, g in ipairs(changed) do first[#first + 1] = g end
            ns.After(ns.Random(3, 20), function() ns.Sync.AdvertiseJoined(first) end)
        end
    end
    -- now and then (not on every roster update): drop the data of people who left
    if ns.Now() - lastPurge > 600 then
        lastPurge = ns.Now()
        ns.After(5, function() ns.PurgeDeparted() end)
    end
    if ns.RefreshUI then ns.RefreshUI() end
end

function ns.CHAT_MSG_ADDON(prefix, text, channel, sender)
    if prefix ~= ns.PREFIX or type(text) ~= "string" then return end
    ns.heardFrom = ns.heardFrom or {}
    ns.heardFrom[ns.Squash((tostring(sender):gsub("%-.*$", "")))] = { t = GetTime(), kind = text:sub(1, 2), inside = ns.InInstance() }
    if ns.InInstance() then ns.instStats.received = ns.instStats.received + 1 end
    ns.Sync.OnMessage(text, sender, channel)
end

local function Scan()
    ns.Professions.ScheduleScan()
    if ns.Specs and ns.Specs.OnWindow then ns.Specs.OnWindow() end
end
ns.TRADE_SKILL_SHOW = Scan
ns.TRADE_SKILL_LIST_UPDATE = Scan
ns.TRADE_SKILL_DATA_SOURCE_CHANGED = Scan
ns.CRAFT_SHOW = Scan
ns.CRAFT_UPDATE = Scan
function ns.NEW_RECIPE_LEARNED(recipeID) ns.Professions.OnRecipeLearned(recipeID) end
function ns.SKILL_LINES_CHANGED() ns.Professions.ScheduleKnownRefresh() end
function ns.GET_ITEM_INFO_RECEIVED() if ns.UI and ns.UI.OnItemData then ns.UI.OnItemData() end end
function ns.INSPECT_READY(guid) ns.Inspect.OnInspectReady(guid) end
function ns.SPELL_DATA_LOAD_RESULT() if ns.UI and ns.UI.OnItemData then ns.UI.OnItemData() end end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Probe()
    local version, _, _, toc = GetBuildInfo()
    ns.Print(("Client %s, interface %s"):format(tostring(version), tostring(toc)))
    ns.Print(("Guild: %s"):format(tostring(ns.guildName)))
    ns.Print(("Messaging blocked right now: %s"):format(tostring(ns.IsMessagingBlocked())))

    local roster = ns.GetRoster()
    local anyGUID = next(roster.byGUID) ~= nil
    ns.Print(("Roster: %d members, %d online, GUIDs in roster: %s"):format(roster.total, roster.online, tostring(anyGUID)))

    ns.Print("Profession APIs: " .. table.concat({
        "GetProfessions=" .. tostring(GetProfessions ~= nil),
        "C_TradeSkillUI=" .. tostring(C_TradeSkillUI ~= nil),
        "GetNumTradeSkills=" .. tostring(GetNumTradeSkills ~= nil),
        "GetNumCrafts=" .. tostring(GetNumCrafts ~= nil),
    }, ", "))

    local known = ns.Professions.ReadKnownProfessions()
    if known and #known > 0 then
        for _, k in ipairs(known) do
            ns.Print(("  profession: %s (key %s) %s/%s"):format(k.name, k.key, tostring(k.rank), tostring(k.max)))
        end
    else
        ns.Print("  GetProfessions returned nothing; professions are learned from open profession windows only.")
    end

    local own = ns.GetOwn()
    if own then
        for key, p in pairs(own.profs) do
            ns.Print(("  stored: %s (key %s) %s/%s, %d recipes"):format(tostring(p.name), key, tostring(p.rank), tostring(p.max), #p.ids))
        end
    end

    local members = ns.GetMembers() or {}
    local n = 0
    for _ in pairs(members) do n = n + 1 end
    ns.Print(("Guild members with profession data: %d"):format(n))
    ns.Stats.Probe()
    local infoCount = 0
    for _ in pairs(DB.recipeInfo) do infoCount = infoCount + 1 end
    ns.Print(("Recipes with item and material details stored: %d"):format(infoCount))
    local pm = _G.ProfessionMasterApi ~= nil
    local lcl = false
    if _G.LibStub then
        local ok, lib = pcall(_G.LibStub, "LibCraftLevels-1.0", true)
        lcl = ok and lib ~= nil
    end
    local known, total = 0, 0
    local own = ns.GetOwn()
    if own then
        for _, p in pairs(own.profs) do
            for _, id in ipairs(p.ids) do
                total = total + 1
                if ns.Professions.ExactSkill(id) then known = known + 1 end
            end
        end
    end
    ns.Print(("Skill data sources: Profession Master = %s, LibCraftLevels = %s. Exact skill known for %d of your %d recipes."):format(
        pm and "yes" or "no", lcl and "yes" or "no", known, total))
    ns.Print("Item APIs: " .. table.concat({
        "GetRecipeSchematic=" .. tostring(C_TradeSkillUI ~= nil and C_TradeSkillUI.GetRecipeSchematic ~= nil),
        "GetTradeSkillReagentInfo=" .. tostring(GetTradeSkillReagentInfo ~= nil),
        "GetCraftReagentInfo=" .. tostring(GetCraftReagentInfo ~= nil),
        "SetItemByID=" .. tostring(GameTooltip ~= nil and GameTooltip.SetItemByID ~= nil),
    }, ", "))

    local infoCount, sampleID, sample = 0, nil, nil
    for id, info in pairs(ns.DB.recipeInfo) do
        infoCount = infoCount + 1
        if not sample and #info.reagents > 0 then sampleID, sample = id, info end
    end
    ns.Print(("Recipe details stored (item + materials): %d"):format(infoCount))
    if sample then
        local parts = {}
        for _, r in ipairs(sample.reagents) do parts[#parts + 1] = ("%dx item %d"):format(r.count, r.id) end
        ns.Print(("  example: %s -> item %s, materials: %s"):format(ns.RecipeName(sampleID), tostring(sample.item), table.concat(parts, ", ")))
    end
end

SLASH_FETAFONDUE1 = "/ff"
SLASH_FETAFONDUE2 = "/fetafondue"
SlashCmdList["FETAFONDUE"] = function(input)
    local cmd = ((input or ""):match("^%s*(%S*)") or ""):lower()

    if cmd == "" then
        ns.ToggleDashboard()
    elseif cmd == "workshop" or cmd == "sweatshop" then
        ns.ShowWorkshop()
    elseif cmd == "whoami" then
        local n, realm
        pcall(function() n, realm = UnitName("player") end)
        ns.Print(("You are: %s (realm part: %s). GUID: %s"):format(tostring(n), tostring(realm), tostring(ns.myGUID)))
        ns.Print(("Full name as the addon uses it: %s. Admin tab: %s."):format(tostring(ns.me), ns.IsAdmin() and "ON" or "off"))
    elseif cmd == "toast" then
        local arg = (input or ""):match("^%s*%S+%s+(%S+)") or ""
        if arg == "off" then
            ns.DB.toasts = false
            ns.Print("Toasts are OFF.")
        elseif arg == "on" then
            ns.DB.toasts = true
            ns.Print("Toasts are ON.")
        else
            if ns.DB.toasts == false then ns.Print("Toasts are off (/ff toast on turns them on).") else ns.UI.TestToast() end
        end
    elseif cmd == "raids" then
        ns.Stats.PrintRaids()
    elseif cmd == "invitelog" then
        ns.Invite.PrintLog()
    elseif cmd == "raidcrit" then
        ns.Stats.RaidCrit(input)
    elseif cmd == "addraidid" then
        ns.Stats.AddRaidID(input)
    elseif cmd == "addraidboss" then
        ns.Stats.AddRaidBoss(input)
    elseif cmd == "achievements" then
        if ns.Achievements then ns.Achievements.Diagnose() end
    elseif cmd == "blocked" then
        local log = DB.blockedLog or {}
        ns.Print(("Blocked actions logged: %d (this session: %d)"):format(#log, ns.blocked.count))
        for _, b in ipairs(log) do
            ns.Print(("  %s for %s: %s%s%s (right after the event %s) at %s"):format(b.kind, tostring(b.addon), b.func, (b.n or 1) > 1 and (" x" .. b.n) or "", b.context and (" while: " .. b.context) or "", b.event, date("%Y-%m-%d %H:%M:%S", b.at)))
            local n = 0
            for line in tostring(b.stack or ""):gmatch("[^\n]+") do
                n = n + 1
                if n > 7 then break end
                ns.Print("      " .. line)
            end
        end
        if #log == 0 then ns.Print("  none") end
        local function Registered(ev)
            local okR, res = pcall(function() return frame:IsEventRegistered(ev) end)
            return okR and tostring(res) or "error"
        end
        ns.Print(("The addon listens for the game's blocked-action events: BLOCKED=%s, FORBIDDEN=%s. Last error text seen: %s"):format(Registered("ADDON_ACTION_BLOCKED"), Registered("ADDON_ACTION_FORBIDDEN"), (ns.errors.last ~= "" and ns.errors.last) or "none"))
    elseif cmd == "taint" then
        -- the game's own log of what tainted what (World of Warcraft\_forever_\Logs\taint.log): the exact answer
        local arg = (input or ""):match("^%s*%S+%s+(%S+)") or ""
        local value = (arg == "off") and "0" or "2"
        local set = (C_CVar and C_CVar.SetCVar) or SetCVar
        local ok = pcall(set, "taintLog", value)
        if ok and arg == "off" then
            ns.Print("The game's taint log is OFF.")
        elseif ok then
            ns.Print("The game's taint log is ON. Type /reload, log in again until the problem shows, then send the file Logs\\taint.log (in your World of Warcraft _forever_ folder) to the officers. Turn it off with /ff taint off.")
        else
            ns.Print("Could not change the taint log setting. You can type /console taintLog 2 yourself.")
        end
    elseif cmd == "shitlist" or cmd == "blacklist" then
        if ns.Blacklist then ns.Blacklist.Diagnose() end
    elseif cmd == "welcome" then
        ns.UI.ShowWelcome()
    elseif cmd == "login" then
        DB.openOnLogin = not DB.openOnLogin
        ns.Print("Open the window on login: " .. (DB.openOnLogin and "ON" or "OFF"))
        if ns.UI and ns.UI.RefreshHome then ns.UI.RefreshHome() end
    elseif cmd == "scan" then
        local ok, msg = ns.Professions.ScanOpen()
        ns.Print(msg or (ok and "Scan done." or "Nothing scanned."))
    elseif cmd == "sync" then
        ns.Sync.AdvertiseSelf()
        ns.Sync.Hello()
        ns.Print("Sharing your professions and asking the guild for theirs.")
        ns.Print(("Messages from guildmates dropped because they came in too fast: %d."):format(ns.Sync.Dropped()))
    elseif cmd == "instance" then
        local st = ns.instStats
        local rest = (input or ""):match("^%s*%S+%s+(.-)%s*$") or ""
        if rest == "reset" then
            st.ok, st.refused, st.received, ns.instRefused, ns.lastSendCode, ns.heardFrom = 0, 0, 0, false, nil, {}
            ns.Print("Instance counters cleared.")
            return
        end
        local who = rest and rest ~= "" and ns.Squash(rest) or nil
        if who then
            local h = ns.heardFrom and ns.heardFrom[who]
            if h then
                ns.Print(("Last message from %s: %d s ago (type %s). I was %s when it arrived."):format(rest, math.floor(GetTime() - h.t), h.kind, h.inside and "inside an instance" or "outside"))
            else
                ns.Print(("No message from %s since the counters were cleared."):format(rest))
            end
            return
        end
        ns.Print(("Inside an instance: %s. Sending held back now: %s. Setting (/ff instancesend): %s."):format(
            tostring(ns.InInstance()), tostring(ns.IsMessagingBlocked()), (ns.DB.instanceSend == true) and "try to send" or "hold back (default)"))
        ns.Print(("Sent inside instances and accepted: %d. Refused by the game: %d. Last result code of a send: %s."):format(st.ok, st.refused, tostring(ns.lastSendCode)))
        ns.Print(("Messages received while inside an instance: %d. Messages waiting to be sent: %d. /ff instance <name> shows when somebody was last heard."):format(st.received, ns.Sync.QueueLength and ns.Sync.QueueLength() or -1))
    elseif cmd == "instancesend" then
        DB.instanceSend = not (DB.instanceSend == true)
        ns.Print("Sending inside dungeons and raids: " .. (DB.instanceSend and "try (test)" or "held back until you are out"))
    elseif cmd == "debug" then
        DB.debug = not DB.debug
        ns.Print("Debug output: " .. (DB.debug and "ON" or "OFF"))
    elseif cmd == "probe" then
        Probe()
    elseif cmd == "talentprobe" then
        ns.TalentProbe((input or ""):match("^%s*%S+%s*(.-)%s*$"))
    elseif cmd == "demo" then
        DB.demo = not DB.demo
        ns.Print("Demo numbers on the dashboard: " .. (DB.demo and "ON" or "OFF"))
        ns.RefreshUI()
    elseif cmd == "bank" then
        ns.Stats.BankProbe()
    elseif cmd == "stats" then
        ns.Stats.Probe()
    elseif cmd == "addzone" then
        local kind, zone = (input or ""):match("^%s*%S+%s+(%S+)%s+(.-)%s*$")
        kind = kind and kind:lower()
        if kind and zone and zone ~= "" and DB.extraZones[kind] then
            table.insert(DB.extraZones[kind], zone:lower())
            ns.Print(("Added \"%s\" to the %s zones."):format(zone, kind))
            ns.RefreshUI()
        else
            ns.Print("Usage: /ff addzone dungeon|raid|capital <zone name>")
        end
    elseif cmd == "addboss" then
        local boss = (input or ""):match("^%s*%S+%s+(.-)%s*$")
        if boss and boss ~= "" then
            DB.extraFinalBosses[boss:lower()] = true
            ns.Print(("\"%s\" now counts as a final boss (dungeon cleared)."):format(boss))
        else
            ns.Print("Usage: /ff addboss <final boss name>")
        end
    else
        ns.Print("Commands: /ff (open/close), /ff sweatshop, /ff welcome, /ff scan, /ff sync, /ff stats, /ff login, /ff whoami, /ff shitlist, /ff blocked, /ff achievements, /ff toast [on|off], /ff raids, /ff addraidboss <onyxia|hyjal|barrow> <boss name or id>, /ff addraidid <onyxia|hyjal|barrow> <instance id>, /ff raidcrit <raid> <ignore|use> <step number>, /ff invitelog, /ff taint [off], /ff debug, /ff probe, /ff talentprobe [view [specID]], /ff demo, /ff addzone <dungeon|raid|capital> <zone>, /ff addboss <name>")
    end
end
