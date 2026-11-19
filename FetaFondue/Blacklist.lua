---@class ns
local ns = select(2, ...)

-- The shitlist: characters officers and the guild master do not want to play with.
--  * Only officers and the guild master can add, edit and remove entries (everybody else's changes are ignored).
--  * Every addon user gets the list, and a warning when a listed character is in their party or raid.
--  * The warning shows when the character was added and the reason. Not who added it: that is only shown to
--    officers on the Management screen.

local B = {}
ns.Blacklist = B

local MAX_NAME, MAX_REASON, MAX_ENTRIES = 40, 200, 200

-- "Ghost Mage-Realm " -> "ghost mage"
function B.Normalize(name)
    name = tostring(name or ""):gsub("%-.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name:lower()
end

local function Store()
    local g = ns.guildName
    if not (ns.DB and g) then return nil end
    local gd = ns.DB.guilds[g]
    if not gd then
        gd = { members = {} }
        ns.DB.guilds[g] = gd
    end
    gd.blacklist = gd.blacklist or {}
    return gd.blacklist
end

-- every entry that is on the list now, newest first
function B.List()
    local out = {}
    for _, e in pairs(Store() or {}) do
        if not e.gone then out[#out + 1] = e end
    end
    table.sort(out, function(a, b)
        if (a.addedAt or 0) ~= (b.addedAt or 0) then return (a.addedAt or 0) > (b.addedAt or 0) end
        return a.name < b.name
    end)
    return out
end

local function Squash(s)
    if ns.Squash then return ns.Squash(s) end
    return (tostring(s or ""):lower():gsub("[%s%-_'`\"]", ""))
end

-- Tidying a name (case, spaces, dashes) is the costly part of looking for it, and the same few names are looked at over and over
-- (every group change looks at every group member, with up to four spellings each). So the tidy form of a name is remembered.
local squashMemo, squashMemoSize = {}, 0
local function SquashMemo(s)
    local v = squashMemo[s]
    if v then return v end
    if squashMemoSize >= 1000 then squashMemo, squashMemoSize = {}, 0 end      -- (names of strangers pass by all day: never grow without end)
    v = Squash(s)
    squashMemo[s] = v
    squashMemoSize = squashMemoSize + 1
    return v
end

-- the entry for a character name; case, spaces and a realm suffix do not matter
function B.Find(name)
    local store = Store()
    if not store or next(store) == nil then return nil end
    local e = store[B.Normalize(name)]
    if e and not e.gone then return e end
    local want = SquashMemo(B.Normalize(name))
    if want == "" then return nil end
    for _, entry in pairs(store) do
        if not entry.gone and SquashMemo(entry.name) == want then return entry end
    end
    return nil
end

-- every entry including the removed ones (officers repeat these so that removals reach everybody)
function B.All()
    local out = {}
    for _, e in pairs(Store() or {}) do out[#out + 1] = e end
    return out
end

-- how many entries there are (removed ones too) and the newest revision: what a guildmate compares when asking for the list
function B.Digest()
    local n, newest = 0, 0
    for _, e in pairs(Store() or {}) do
        n = n + 1
        if (e.rev or 0) > newest then newest = e.rev end
    end
    return n, newest
end

-- Put an entry in (from an officer's own change, or a message from an officer). Newer revisions win.
function B.Apply(name, reason, addedAt, gone, rev, by)
    local store = Store()
    if not store then return false end
    -- (these come from other players' addons as well: no colour codes, links or line breaks)
    name, by = ns.CleanText(name), by and ns.CleanText(by)
    reason = ns.CleanText(reason, true):gsub("[\r\n]+", " ")       -- (a reason may hold a "|" that is not a code)
    local key = B.Normalize(name)
    if key == "" then return false end
    local old = store[key]
    if old and (old.rev or 0) >= rev then return false end
    store[key] = {
        name = tostring(name):gsub("%-.*$", ""):sub(1, MAX_NAME), reason = tostring(reason or ""):sub(1, MAX_REASON),
        addedAt = addedAt, gone = gone and true or false, rev = rev,
        by = (by and by ~= "" and by) or (old and old.by) or nil,       -- who added it (a change of the reason keeps the first one)
    }
    if ns.RefreshUI then ns.RefreshUI() end
    if B.OnChanged then B.OnChanged() end
    B.Check()
    return true
end

local function NextRev(key)
    local old = (Store() or {})[key]
    return math.max(ns.Time(), ((old and old.rev) or 0) + 1)
end

local function Share(entry)
    if ns.Sync and ns.Sync.SendBlacklistEntry then ns.Sync.SendBlacklistEntry(entry) end
end

-- the officer's actions: add, change the reason, remove
function B.Add(name, reason)
    if not ns.CanModerate() then return false, "Only officers and the guild master can change the shitlist." end
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    reason = tostring(reason or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if B.Normalize(name) == "" then return false, "Enter the character's name." end
    if reason == "" then return false, "Enter a reason." end
    local key = B.Normalize(name)
    local count = 0
    for _ in pairs(Store() or {}) do count = count + 1 end
    if count >= MAX_ENTRIES and not (Store() or {})[key] then return false, "The list is full." end
    local old = (Store() or {})[key]
    local addedAt = (old and not old.gone and old.addedAt) or ns.Time()      -- re-adding keeps the original date
    local by = (old and not old.gone and old.by) or ns.DisplayName(ns.me or "?")
    if B.Apply(name, reason, addedAt, false, NextRev(key), by) then Share(Store()[key]) end
    return true
end

function B.EditReason(name, reason)
    if not ns.CanModerate() then return false, "Only officers and the guild master can change the shitlist." end
    local e = B.Find(name)
    if not e then return false, "That character is not on the list." end
    reason = tostring(reason or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if reason == "" then return false, "Enter a reason." end
    local key = B.Normalize(name)
    if B.Apply(e.name, reason, e.addedAt, false, NextRev(key), e.by) then Share(Store()[key]) end
    return true
end

function B.Remove(name)
    if not ns.CanModerate() then return false end
    local e = B.Find(name)
    if not e then return false end
    local key = B.Normalize(name)
    if B.Apply(e.name, e.reason, e.addedAt, true, NextRev(key), e.by) then Share(Store()[key]) end
    return true
end

---------------------------------------------------------------------------
-- Who is in my group right now
---------------------------------------------------------------------------
local present = {}      -- normalized names of listed people seen in the group (so each one is warned about once)
local pending = {}      -- warnings waiting for a quiet moment: { entry, ... }
local loading = false   -- a loading screen is up
local pollQueued = false

local function GroupUnits()
    local units = {}
    local n = 0
    pcall(function() n = GetNumGroupMembers() or 0 end)
    local raid = false
    pcall(function() raid = IsInRaid() end)
    if raid then
        for i = 1, n do units[#units + 1] = "raid" .. i end
    else
        for i = 1, math.max(0, n - 1) do units[#units + 1] = "party" .. i end
    end
    return units
end

local function InCombat()
    local c = false
    pcall(function() c = UnitAffectingCombat("player") or InCombatLockdown() end)
    return c and true or false
end

-- warnings of other kinds wait here: { kind = "invite" | "scan", list = {...} }. They are shown one at a time, and only
-- when we are not in combat, not loading and not inside a dungeon or raid.
local queuedOther = {}
local otherPoll = false
local function ShowOther()
    otherPoll = false
    if #queuedOther == 0 then return end
    if loading or InCombat() or (ns.IsBusyForPopup and ns.IsBusyForPopup()) then
        otherPoll = true
        ns.After(30, ShowOther)
        return
    end
    local item = table.remove(queuedOther, 1)
    if ns.UI and ns.UI.ShowBlacklistWarning then ns.UI.ShowBlacklistWarning(item.list, item.kind) end
    if #queuedOther > 0 then otherPoll = true ns.After(5, ShowOther) end
end
local function QueueOther(kind, list)
    queuedOther[#queuedOther + 1] = { kind = kind, list = list }
    if not otherPoll then otherPoll = true ns.After(1, ShowOther) end
end

local function TryShow()
    pollQueued = false
    if #pending == 0 then return end
    if loading or InCombat() then
        -- not now: during combat and loading screens we wait
        pollQueued = true
        ns.After(2, TryShow)
        return
    end
    local list = pending
    pending = {}
    if ns.UI and ns.UI.ShowBlacklistWarning then ns.UI.ShowBlacklistWarning(list) end
end

local function Queue(entry)
    pending[#pending + 1] = entry
    if not pollQueued then
        pollQueued = true
        ns.After(1, TryShow)
    end
end

-- every way the game can spell the name of a unit
local function UnitNames(unit)
    local out, unknown = {}, false
    local function Add(s)
        if type(s) ~= "string" or s == "" then return end
        if s == "Unknown" or (UNKNOWNOBJECT and s == UNKNOWNOBJECT) then unknown = true return end
        out[#out + 1] = s
    end
    pcall(function()
        local n, realm = UnitName(unit)
        Add(n)
        if n and realm and realm ~= "" then
            Add(n .. "-" .. realm)
            Add(n .. " " .. realm)       -- a first name and a last name the game keeps apart
        end
        if GetUnitName then Add(GetUnitName(unit, true)) end
    end)
    return out, unknown
end

local recheckQueued = false
local function InGroup()
    local n = 0
    pcall(function() n = GetNumGroupMembers() or 0 end)
    return n > 1
end

-- names of people who just joined are not always known yet: look again while the group exists
local Check
local function ScheduleRecheck()
    if recheckQueued or not InGroup() then return end
    recheckQueued = true
    ns.After(15, function()
        recheckQueued = false
        Check()
    end)
end

-- is anybody on the list at all? (then there is nothing to look for)
local function AnyEntries()
    for _, e in pairs(Store() or {}) do
        if not e.gone then return true end
    end
    return false
end

local unknownQueued = false

-- look at the group: anybody on the list who was not there before is warned about
Check = function()
    if not AnyEntries() then
        for key in pairs(present) do present[key] = nil end
        return
    end
    local seen = {}
    local anyUnknown = false
    for _, unit in ipairs(GroupUnits()) do
        local names, unknown = UnitNames(unit)
        if unknown then anyUnknown = true end
        for _, name in ipairs(names) do
            local entry = B.Find(name)
            if entry then
                local key = B.Normalize(entry.name)
                seen[key] = true
                if not present[key] then
                    present[key] = true
                    Queue(entry)
                end
                break
            end
        end
    end
    -- people who left the group are warned about again when they come back
    for key in pairs(present) do
        if not seen[key] then present[key] = nil end
    end
    if anyUnknown and not unknownQueued then
        -- (one look-again at a time: every look used to start another one while a name stayed unknown)
        unknownQueued = true
        ns.After(3, function() unknownQueued = false Check() end)
    end
    ScheduleRecheck()
end
B.Check = Check

-- what /ff shitlist prints: why a warning did or did not appear
function B.Diagnose()
    local list = B.List()
    ns.Print(("Shitlist: %d entries. Loading screen flag: %s. In combat: %s. Warnings waiting: %d."):format(#list, tostring(loading), tostring(InCombat()), #pending))
    for _, e in ipairs(list) do ns.Print(("  on the list: '%s' (matching as '%s')"):format(e.name, Squash(B.Normalize(e.name)))) end
    do
        local mine = ns.myGUID and ns.GetRoster().byGUID[ns.myGUID]
        ns.Print(("Me: rank index %s (%s), may change officer things: %s. Officer ranks are index 0 to %d."):format(
            tostring(mine and mine.rankIndex), tostring(mine and mine.rank), tostring(ns.CanModerate()), ns.OFFICER_MAX_RANK_INDEX or -1))
        local rej = ns.officerRejects or {}
        ns.Print(("Officer-only messages refused this session (last 10): %d"):format(#rej))
        for _, r in ipairs(rej) do ns.Print(("  from %s: %s"):format(r.sender, r.why)) end
    end
    local units = GroupUnits()
    ns.Print(("In a group: %s (%d other members to check)"):format(tostring(InGroup()), #units))
    for _, unit in ipairs(units) do
        local names, unknown = UnitNames(unit)
        local hit = false
        for _, n in ipairs(names) do if B.Find(n) then hit = true end end
        ns.Print(("  %s: %s%s -> %s"):format(unit, #names > 0 and table.concat(names, " / ") or "(no name yet)", unknown and " [name still unknown]" or "", hit and "ON THE LIST" or "not on the list"))
    end
end

-- Events about the group come in bursts (a raid forming, a pull with many name updates). Look at once, and at most once a
-- second after that: anything that arrives in between is covered by one look a little later.
local CHECK_GAP = 1
local lastCheck, soonQueued = -1e9, false
function B.CheckSoon()
    local now = ns.Now()
    if now - lastCheck >= CHECK_GAP then
        lastCheck = now
        Check()
    elseif not soonQueued then
        soonQueued = true
        ns.After(CHECK_GAP - (now - lastCheck) + 0.05, function()
            soonQueued = false
            lastCheck = ns.Now()
            Check()
        end)
    end
end

local followUpsQueued = false
ns.HookEvent("GROUP_ROSTER_UPDATE", function()
    B.CheckSoon()
    -- names of people who just joined arrive a little later: look again after 2 and 6 seconds (once for a whole burst of events)
    if not followUpsQueued then
        followUpsQueued = true
        ns.After(2, function() B.CheckSoon() end)
        ns.After(6, function() followUpsQueued = false B.CheckSoon() end)
    end
end)
-- (the game sends this for every unit that gets a name: nameplates, targets... only the people in my group matter)
ns.HookEvent("UNIT_NAME_UPDATE", function(unit)
    if unit ~= nil and not (type(unit) == "string" and (unit:find("^party%d") or unit:find("^raid%d"))) then return end
    B.CheckSoon()
end)
ns.HookEvent("LOADING_SCREEN_ENABLED", function() loading = true end)
ns.HookEvent("LOADING_SCREEN_DISABLED", function()
    ns.After(3, function()
        loading = false
        B.Check()
    end)
end)
ns.HookEvent("PLAYER_ENTERING_WORLD", function()
    -- a loading screen has just ended: wait a moment, then look at the group
    ns.After(4, function()
        loading = false
        B.Check()
    end)
end)
ns.HookEvent("PLAYER_REGEN_ENABLED", function()
    if #pending > 0 and not pollQueued then
        pollQueued = true
        ns.After(2, TryShow)
    end
end)

-- for tests and for the officers' preview
-- no combat and no loading screen: a good moment to show a window
function B.IsCalm() return not loading and not InCombat() end

function B.State() return { present = present, pending = pending, loading = loading } end
function B.SetLoading(v) loading = v and true or false end

---------------------------------------------------------------------------
-- A guild invite sent with the game's own invite (the guild window, /ginvite, a macro): the invite cannot be stopped, but the
-- person who sent it is told at once when the name is on the list. (Invites from the Management button are checked before.)
---------------------------------------------------------------------------
function B.OnGuildInvite(name)
    local e = type(name) == "string" and B.Find(name)
    if e then QueueOther("invite", { e }) return true end
    return false
end
pcall(function()
    if hooksecurefunc and GuildInvite then hooksecurefunc("GuildInvite", function(n) B.OnGuildInvite(n) end) end
    if hooksecurefunc and C_GuildInfo and C_GuildInfo.Invite then hooksecurefunc(C_GuildInfo, "Invite", function(n) B.OnGuildInvite(n) end) end
end)

---------------------------------------------------------------------------
-- Once a day, officers and the guild master: who of the guild is on the list? Everybody who is allowed to see it looks by
-- himself at his first quiet moment after 20 hours since his last look, so nothing has to be agreed between them: each of
-- them sees one popup a day, and none when nobody matches.
---------------------------------------------------------------------------
local SCAN_EVERY = 20 * 3600
local function GuildData()
    local g = ns.guildName
    return g and ns.DB and ns.DB.guilds and ns.DB.guilds[g] or nil
end

-- the roster members whose names are on the list: { { name, reason, addedAt }, ... }
function B.MatchesInGuild()
    local out = {}
    for _, e in ipairs(ns.GetRoster().list) do
        local hit = B.Find(e.name)
        if hit then out[#out + 1] = { name = ns.DisplayName(e.name), reason = hit.reason, addedAt = hit.addedAt } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- returns the matches when a scan was due and done (also an empty list), nil when it was not the time
function B.DailyScan(force)
    local gd = GuildData()
    if not gd then return nil end
    if not force and gd.shitScan and ns.Time() - gd.shitScan < SCAN_EVERY then return nil end
    if not (ns.CanModerate and ns.CanModerate()) then return nil end
    if ns.GetRoster().total < 1 then return nil end
    gd.shitScan = ns.Time()
    local list = B.MatchesInGuild()
    if #list > 0 then QueueOther("scan", list) end
    return list
end

local function ScanLoop()
    pcall(B.DailyScan)
    ns.After(3600, ScanLoop)
end
ns.HookEvent("PLAYER_ENTERING_WORLD", function()
    -- the roster needs a moment after logging in
    ns.After(90, function() pcall(B.DailyScan) end)
end)
ns.After(3700, ScanLoop)
ns.HookEvent("GUILD_ROSTER_UPDATE", function() pcall(B.DailyScan) end)
