---@class ns
local ns = select(2, ...)
local R = ns.Raids

---------------------------------------------------------------------------
-- "Invite all" in the raid window (officers and the guild master): invites everybody who signed up for the raid and is
-- online. A Discord name is turned into a character (the one that is online, preferably of the class that signed up).
--
-- After the party became a raid the loot is switched to Master Loot: the one who invites is the master looter, unless the guild's
-- master looter (ns.MASTER_LOOTER) is in the raid: then he is (also when he only joins later).
--
-- Careful with the game: the invites go out one at a time with a pause between them (not twenty at once), they wait while a
-- loading screen is up (combat does not matter), only an officer who is not in somebody else's group can start them, and the group is
-- turned into a raid after five. If the game does not accept an invite that was not started by a click (it may want one
-- click for each), the button changes to "Invite next" and invites one person per click.
---------------------------------------------------------------------------
local I = {}
ns.Invite = I

I.DELAY = 1.0            -- seconds between two invites
I.FIRST_ONLY = 5         -- a party is full at five: then it must become a raid

local state = { running = false }
local runId = 0

-- The game can refuse a call from an addon: it then fires ADDON_ACTION_BLOCKED (and the call does nothing) instead of raising an error.
-- A "guarded" call tells us whether that happened. (The event sometimes names the function UNKNOWN(), so any block of ours during the call counts.)
local blockedFlag = false
local function Guarded(fn, label)
    blockedFlag = false
    ns.blockContext = label           -- (the game's block message then says what we were doing)
    local ok = pcall(fn)
    ns.blockContext = nil
    return ok and not blockedFlag
end

-- what happened, for /ff invitelog (nothing is written in the chat while inviting)
I.log = {}
local function Log(text)
    I.log[#I.log + 1] = ("%s  %s"):format(date("%H:%M:%S", ns.Time()), text)
    while #I.log > 60 do table.remove(I.log, 1) end
end
function I.PrintLog()
    ns.Print("Invite log (newest last):")
    for _, line in ipairs(I.log) do ns.Print("  " .. line) end
    if #I.log == 0 then ns.Print("  nothing yet") end
end
I.note = nil            -- something the player has to do themselves (shown next to the button)

-- The raid: made as soon as somebody has joined, also after the last invite went out (the run may be over before anybody accepts)
local conv = { need = false, blocked = false, last = -100, tries = 0, untilT = 0 }

-- who is invited: signed up and late (they are on their way); not bench, tentative or absent
local INVITE_STATES = { signed = true, late = true }

local function InvitePerson(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    else
        error("no invite function")
    end
end

local function InRaid() local ok, v = pcall(IsInRaid) return ok and v == true end
local function GroupSize() local ok, v = pcall(GetNumGroupMembers) return ok and tonumber(v) or 1 end
-- A loading screen: the invites wait for it to end (combat does not matter: an invite works in combat, and the people invited may be fighting)
local function Loading()
    local ok, st = pcall(function() return ns.Blacklist and ns.Blacklist.State and ns.Blacklist.State() end)
    return ok and st ~= nil and st.loading == true
end

-- may I invite? (not in a group, or I lead it or help to lead it)
local function CanLead()
    local inGroup = true
    pcall(function() inGroup = IsInGroup == nil or IsInGroup() end)
    if not inGroup then return true end
    local leader, assistant = true, false
    pcall(function() if UnitIsGroupLeader then leader = UnitIsGroupLeader("player") end end)
    pcall(function() if UnitIsGroupAssistant then assistant = UnitIsGroupAssistant("player") end end)
    return leader or assistant
end

-- is this character in my group already?
local function InMyGroup(guid)
    local prefix, n
    if InRaid() then prefix, n = "raid", GroupSize() else prefix, n = "party", math.max(0, GroupSize() - 1) end
    for i = 1, n do
        local found = false
        pcall(function() found = UnitExists(prefix .. i) and UnitGUID(prefix .. i) == guid end)
        if found then return true end
    end
    return false
end

-- Who would be invited: { list = { { name, char, class, guid, discord } }, offline, unmatched, inGroup, mine }
function I.Plan(rec)
    local roster = ns.GetRoster()
    local plan = { list = {}, offline = {}, unmatched = {}, inGroup = {}, mine = {} }
    local signed = {}
    for _, s in ipairs(rec.signups or {}) do if INVITE_STATES[s.st] then signed[#signed + 1] = s end end
    table.sort(signed, function(a, b)
        if (a.p or 0) ~= (b.p or 0) then return (a.p or 0) < (b.p or 0) end
        return a.n < b.n
    end)
    local done = {}
    for _, s in ipairs(signed) do
        local entries = R.ResolveAll(s.n, roster)
        if #entries == 0 then
            plan.unmatched[#plan.unmatched + 1] = s.n
        else
            local pick, anyOnline, firstKnown
            for _, e in ipairs(entries) do
                local re = e.guid and roster.byGUID[e.guid]
                if re then
                    firstKnown = firstKnown or re
                    if re.online then
                        anyOnline = anyOnline or re
                        if s.c ~= "" and re.class == s.c then pick = pick or re end      -- the class that signed up
                    end
                end
            end
            pick = pick or anyOnline
            if not pick then
                plan.offline[#plan.offline + 1] = firstKnown and ns.DisplayName(firstKnown.name) or R.CharName(s.n, roster)
            elseif not done[pick.guid] then
                done[pick.guid] = true
                local char = ns.DisplayName(pick.name)
                if pick.guid == ns.myGUID then
                    plan.mine[#plan.mine + 1] = char
                elseif InMyGroup(pick.guid) then
                    plan.inGroup[#plan.inGroup + 1] = char
                else
                    plan.list[#plan.list + 1] = { name = pick.name, char = char, class = pick.class, guid = pick.guid, discord = s.n }
                end
            end
        end
    end
    return plan
end

local function Changed() if I.OnChanged then I.OnChanged() end end

-- Which raids "Invite all" was pressed for in this session (and so which raid windows show who has come)
I.invitedRaids = {}
function I.WasInvited(id) return id ~= nil and I.invitedRaids[id] == true end

-- Does this raid window show who has come? Officers and the guild master see it for a raid Invite all was pressed for (by me), and
-- also when somebody else pressed it: an officer who signed up for the raid and is in a group sees it (that is the raid group).
function I.ShowProgress(rec)
    if not (rec and ns.CanModerate()) then return false, nil end
    if I.WasInvited(rec.id) then return true, I.GroupProgress(rec) end
    if GroupSize() > 1 then
        local progress = I.GroupProgress(rec)
        if progress.mine then return true, progress end
    end
    return false, nil
end

-- Of the people who signed up (signed up or late) for a raid: who is in my group now, who is not.
-- Returns { inGroup = { [signup] = true }, missing = { signup, ... } }.
function I.GroupProgress(rec)
    local roster = ns.GetRoster()
    local res = { inGroup = {}, missing = {} }
    for _, s in ipairs(rec.signups or {}) do
        if INVITE_STATES[s.st] then
            local here = false
            for _, e in ipairs(R.ResolveAll(s.n, roster)) do
                if e.guid and (e.guid == ns.myGUID or InMyGroup(e.guid)) then here = true break end
            end
            if here then res.inGroup[s] = true else res.missing[#res.missing + 1] = s end
            for _, e in ipairs(R.ResolveAll(s.n, roster)) do
                if e.guid and e.guid == ns.myGUID then res.mine = true end          -- (I signed up for this raid myself)
            end
        end
    end
    return res
end

---------------------------------------------------------------------------
-- Master Loot
---------------------------------------------------------------------------
local function UnitNameFull(unit)
    local name
    pcall(function() name = GetUnitName and GetUnitName(unit, true) or UnitName(unit) end)
    return name
end

-- the raid unit ("raid3") of a character, found by its id
local function RaidUnitOf(guid)
    local n = GroupSize()
    for i = 1, n do
        local found = false
        pcall(function() found = UnitExists("raid" .. i) and UnitGUID("raid" .. i) == guid end)
        if found then return "raid" .. i end
    end
end

local function IsLeader()
    local leader = true
    pcall(function() if UnitIsGroupLeader then leader = UnitIsGroupLeader("player") end end)
    return leader
end

-- who is the master looter now: the id of that character, or nil
local function CurrentMasterGUID()
    local method, partyID, raidID
    pcall(function()
        if C_PartyInfo and C_PartyInfo.GetLootMethod then method, partyID, raidID = C_PartyInfo.GetLootMethod()
        elseif GetLootMethod then method, partyID, raidID = GetLootMethod() end
    end)
    local master = (Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter) or "master"
    if method ~= master then return nil, false end
    local guid
    pcall(function()
        if raidID and raidID > 0 then guid = UnitGUID("raid" .. raidID)
        elseif partyID == 0 then guid = UnitGUID("player")
        elseif partyID then guid = UnitGUID("party" .. partyID) end
    end)
    return guid, true
end

local function SetMaster(name)
    return Guarded(function()
        local method = (Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter) or "master"
        if C_PartyInfo and C_PartyInfo.SetLootMethod then C_PartyInfo.SetLootMethod(method, name)
        elseif SetLootMethod then SetLootMethod("master", name) else error("no loot function") end
    end, "setting Master Loot")
end

-- the guild's master looter as a roster entry (nil when none is set or he is not in the guild)
local function WantedMasterLooter()
    if not ns.MASTER_LOOTER then return nil end
    return ns.GetRoster().bySquash[ns.Squash(ns.MASTER_LOOTER)]
end

-- Master Loot on, with the right master looter. Returns true when it is right (now or already).
function I.ApplyLoot()
    if not (InRaid() and IsLeader()) then return false end
    local targetGUID, targetName = ns.myGUID, UnitNameFull("player")
    local want = WantedMasterLooter()
    if want and want.guid and want.guid ~= ns.myGUID then
        local unit = RaidUnitOf(want.guid)
        if unit then targetGUID, targetName = want.guid, UnitNameFull(unit) end
    end
    local current, isMaster = CurrentMasterGUID()
    if isMaster and current == targetGUID then return true end
    if not targetName then return false end
    local ok = SetMaster(targetName)
    Log(("Master Loot for %s: %s"):format(tostring(targetName), ok and "asked" or "refused"))
    if not ok then
        I.note = "Could not set Master Loot: do it yourself."
        I.lootWatchUntil = nil
        Changed()
    end
    return ok
end

-- The party becomes a raid as soon as somebody has joined (two in the group), always, while the other invites carry on
-- (and after the last invite too: the people may accept later).
I.lootPending = false
local function TryConvert()
    if not conv.need or conv.blocked or InRaid() or GroupSize() < 2 then return end
    if ns.Now() > conv.untilT then conv.need = false return end
    if ns.Now() - conv.last < 3 or conv.tries >= 5 then return end
    conv.last = ns.Now()
    conv.tries = conv.tries + 1
    I.lootPending = true
    local ok = Guarded(function()
        if C_PartyInfo and C_PartyInfo.ConvertToRaid then C_PartyInfo.ConvertToRaid() elseif ConvertToRaid then ConvertToRaid() end
    end, "turning the group into a raid")
    Log(("convert to raid asked (try %d, %d in the group): %s"):format(conv.tries, GroupSize(), ok and "accepted by the game" or "refused"))
    if not ok then
        conv.blocked = true
        I.lootPending = false
        I.note = "Could not make the raid: do it yourself."
        Changed()
    end
end

-- the moment it is a raid (the game may take a moment): Master Loot, and watch for the guild's master looter to join
local function CheckLoot()
    if I.lootPending and InRaid() then
        Log("the group is a raid now")
        I.lootPending = false
        I.ApplyLoot()
        I.lootWatchUntil = ns.Now() + 60
    end
end

-- every two seconds while it matters: the group may have changed without us seeing the event
local function Poll()
    TryConvert()
    CheckLoot()
    if conv.need and not conv.blocked and not InRaid() and ns.Now() < conv.untilT then ns.After(2, Poll) end
end

-- he may join after the raid was made: for a while a change of the group checks again
I.lootWatchUntil = nil
local lastLootTry = -100
ns.HookEvent("GROUP_ROSTER_UPDATE", function()
    TryConvert()
    CheckLoot()
    if not (I.lootWatchUntil and ns.Now() < I.lootWatchUntil) then return end
    if ns.Now() - lastLootTry < 2 then return end
    lastLootTry = ns.Now()
    local want = WantedMasterLooter()
    if I.ApplyLoot() and (not want or want.guid == ns.myGUID or RaidUnitOf(want.guid)) then I.lootWatchUntil = nil end
end)

function I.State()
    if not state.running then return { running = false } end
    return { running = true, mode = state.mode, left = #state.queue, invited = state.invited, total = state.total, raidId = state.rec and state.rec.id, plan = state.plan }
end

-- what the button shows after something happened (nothing is written in the chat)
I.message = nil
I.last = nil            -- the plan and the number of invites of the last run

local function Finish()
    local plan, invited = state.plan, state.invited
    state = { running = false }
    runId = runId + 1
    I.last = { plan = plan, invited = invited }
    I.message = ("Invited %d."):format(invited)
    Changed()
end

-- stop waiting for somebody to join (and making the raid)
function I.CancelRaidWatch()
    conv.need = false
    I.lootPending = false
end

function I.Stop(reason)
    if not state.running then return end
    I.CancelRaidWatch()
    I.message = ("Stopped%s: %d invited, %d left."):format(reason and (" (" .. reason .. ")") or "", state.invited, #state.queue)
    I.last = { plan = state.plan, invited = state.invited }
    state = { running = false }
    runId = runId + 1
    Changed()
end

-- the lines of the tooltip over the button: who is invited and who is not, and why
function I.Details(plan)
    local lines = {}
    local function Add(title, list)
        if #list > 0 then lines[#lines + 1] = ("%s (%d): %s"):format(title, #list, table.concat(list, ", ")) end
    end
    local names = {}
    for _, p in ipairs(plan.list) do names[#names + 1] = p.char end
    Add("To invite", names)
    Add("Signed up but offline", plan.offline)
    Add("Not matched to a character", plan.unmatched)
    Add("Already in your group", plan.inGroup)
    return lines
end

-- the game blocked something we asked for (see Guarded)
function I.OnBlocked(addon)
    if addon == "FetaFondue" then blockedFlag = true end
end

-- one step: invite the next person (and plan the next step when inviting by itself)
function I.Step(fromClick)
    if not state.running then return end
    if Loading() then
        state.waits = (state.waits or 0) + 1
        if state.waits > 30 then I.Stop("a loading screen that does not end") return end
        local id = runId
        ns.After(1, function() if id == runId then I.Step(fromClick) end end)
        return
    end
    state.waits = 0
    local nextOne = state.queue[1]
    if not nextOne then Finish() return end
    -- the party becomes a raid as soon as somebody has joined (the invites go on meanwhile)
    TryConvert()
    CheckLoot()
    -- a full party (five) that is not a raid yet cannot take another one: wait for the raid
    if not InRaid() and GroupSize() >= I.FIRST_ONLY then
        state.fullWaits = (state.fullWaits or 0) + 1
        if conv.blocked or state.fullWaits > 8 or (conv.tries >= 5 and state.fullWaits > 3) then
            I.Stop("the group could not be turned into a raid: do it yourself and press the button again")
            return
        end
        local id = runId
        ns.After(1.5, function() if id == runId then I.Step() end end)
        return
    end
    local ok = Guarded(function() InvitePerson(nextOne.name) end, "inviting " .. tostring(nextOne.char))
    Log(("invite %s: %s"):format(tostring(nextOne.char), ok and "sent" or "refused"))
    if not ok then
        if state.mode == "auto" and not fromClick then
            -- the game wants a click for each invite: from now on one invite per click
            state.mode = "manual"
            I.message = "The game wants a click for each invite."
            Changed()
        else
            I.Stop("the game did not accept the invite")
        end
        return
    end
    table.remove(state.queue, 1)
    state.invited = state.invited + 1
    Changed()
    if #state.queue == 0 then Finish() return end
    if state.mode == "auto" then
        local id = runId
        ns.After(I.DELAY, function() if id == runId then I.Step() end end)
    end
end

-- start inviting for a raid; returns true, or false and why not
function I.Start(rec)
    if not ns.CanModerate() then return false, "Only officers and the guild master can invite." end
    if state.running then return false, "Already inviting." end
    if not CanLead() then return false, "You are in a group but you do not lead it." end
    local plan = I.Plan(rec)
    if #plan.list == 0 then
        I.last = { plan = plan, invited = 0 }
        return false, "Nobody to invite."
    end
    I.invitedRaids[rec.id] = true
    I.message = nil
    I.note = nil
    local queue = {}
    for i, p in ipairs(plan.list) do queue[i] = p end
    runId = runId + 1
    state = { running = true, mode = "auto", queue = queue, total = #queue, invited = 0, plan = plan, rec = rec }
    -- always a raid (also for five people or fewer), unless it already is one: for the next two minutes the addon waits for the
    -- first person to join (the run itself may be over by then) and makes it
    conv = { need = not InRaid(), blocked = false, last = -100, tries = 0, untilT = ns.Now() + 120 }
    Log(("start: %d to invite, raid wanted: %s"):format(#queue, tostring(conv.need)))
    ns.After(2, Poll)
    I.Step()
    return true
end

-- a click while inviting: stop (inviting by itself) or send the next invite (one per click)
function I.Click()
    if not state.running then return end
    if state.mode == "manual" then I.Step(true) else I.Stop("stopped by you") end
end
