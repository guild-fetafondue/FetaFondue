---@class ns
local ns = select(2, ...)

---------------------------------------------------------------------------
-- Profession specializations and profession cooldowns, per character.
--   member.specs = { [specSpellID] = true }          member.specsRev = time of the last change
--   member.cds   = { [spellID] = end time (epoch) }  0 = ready; the end time is absolute, so it can be shared
-- Both are read from the game for my own characters (after ns.worldReady) and shared with the guild
-- (sync kinds "SP" and "CD").
---------------------------------------------------------------------------
local S = {}
ns.Specs = S

-- profession key (skill line) -> specializations { spell id, English name }. English names are only a fallback:
-- the real name comes from the game, so French and German clients show their own.
-- { spell id, English name, one word for the charts }. Weaponsmith (9787) is not listed: it breaks down into the Master smiths.
S.LIST = {
    ["164"] = { { 9788, "Armorsmith", "Armorsmith" }, { 17039, "Master Swordsmith", "Swordsmith" }, { 17044, "Master Hammersmith", "Hammersmith" }, { 17041, "Master Axesmith", "Axesmith" } },
    ["165"] = { { 10656, "Dragonscale Leatherworking", "Dragonscale" }, { 10658, "Elemental Leatherworking", "Elemental" }, { 10660, "Tribal Leatherworking", "Tribal" } },
    ["202"] = { { 20222, "Goblin Engineering", "Goblin" }, { 20219, "Gnomish Engineering", "Gnomish" } },
}
-- (ids confirmed by Georgi; the "learn" spells of the quests are not the ones a character keeps: 10657, 10659, 364165, 20220)
-- the order the professions are listed in
S.ORDER = { "164", "165", "202" }
local SURE = { [9788] = true, [17039] = true, [17044] = true, [17041] = true, [10656] = true, [10658] = true, [10660] = true, [20222] = true, [20219] = true }

local specInfo = {}
for key, list in pairs(S.LIST) do
    for _, e in ipairs(list) do specInfo[e[1]] = { id = e[1], key = key, name = e[2], short = e[3], sure = SURE[e[1]] == true } end
end

-- the one word for a specialization (Hammersmith, Dragonscale, ...)
function S.ShortName(id)
    local e = specInfo[id]
    return e and e.short or tostring(id)
end

local function SpellData(id)
    local name, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" then name, icon = info.name, info.iconID or info.originalIconID end
    end
    if not name and GetSpellInfo then
        local ok, n, _, i = pcall(GetSpellInfo, id)
        if ok and type(n) == "string" then name, icon = n, i end
    end
    return name, icon
end

function S.SpecName(id)
    local name = SpellData(id)
    if name then return name, true end
    local e = specInfo[id]
    return e and e.name or ("Specialization #" .. tostring(id)), false
end

function S.SpecIcon(id)
    local _, icon = SpellData(id)
    return icon
end

-- the specializations to list for a profession: the sure ones, the ones the game knows and the ones somebody has
function S.SpecsOf(key)
    local out, have = {}, {}
    local members = ns.GetMembers() or {}
    for _, m in pairs(members) do
        for id in pairs(m.specs or {}) do have[id] = true end
    end
    for _, e in ipairs(S.LIST[key] or {}) do
        local id = e[1]
        local _, real = SpellData(id)
        if specInfo[id].sure or real or have[id] then out[#out + 1] = id end
    end
    return out
end

-- who has a specialization: { { guid, member }, ... }
function S.Holders(specID)
    local out = {}
    for guid, m in pairs(ns.GetMembers() or {}) do
        if m.specs and m.specs[specID] then out[#out + 1] = { guid = guid, member = m } end
    end
    table.sort(out, function(a, b) return (a.member.name or "") < (b.member.name or "") end)
    return out
end

local function Known(id)
    local ok, v = pcall(function()
        if IsPlayerSpell then return IsPlayerSpell(id) end
        if IsSpellKnown then return IsSpellKnown(id) end
        return false
    end)
    return ok and v and true or false
end

-- read my own specializations (only for the professions this character has)
function S.ReadOwn()
    local own = ns.GetOwn()
    if not own or not ns.worldReady then return end
    local now = {}
    for key, list in pairs(S.LIST) do
        if own.profs and own.profs[key] then
            for _, e in ipairs(list) do
                if Known(e[1]) then now[e[1]] = true end
            end
        end
    end
    local old, changed = own.specs or {}, false
    for id in pairs(now) do if not old[id] then changed = true end end
    for id in pairs(old) do if not now[id] then changed = true end end
    if own.specs == nil then changed = true end
    own.specs = now
    if changed then
        own.specsRev = ns.Time()
        if ns.Sync and ns.Sync.AdvertiseSpecs then ns.Sync.AdvertiseSpecs() end
        if ns.RefreshUI then ns.RefreshUI() end
    end
end

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
-- cooldowns we know from the start: spell id -> { profession key, English name }
S.SEED = {
    [18560] = { "197", "Mooncloth" },
    [1317279] = { "171", "Transmute: Legionite" },
    [17187] = { "171", "Transmute: Arcanite" },
    [17559] = { "171", "Transmute: Air to Fire" },
    [17560] = { "171", "Transmute: Fire to Earth" },
    [17561] = { "171", "Transmute: Earth to Water" },
    [17562] = { "171", "Transmute: Water to Air" },
    [17563] = { "171", "Transmute: Undeath to Water" },
    [17564] = { "171", "Transmute: Water to Undeath" },
    [17565] = { "171", "Transmute: Life to Earth" },
    [17566] = { "171", "Transmute: Earth to Life" },
    [11479] = { "171", "Transmute: Iron to Gold" },
    [11480] = { "171", "Transmute: Mithril to Truesilver" },
    [25146] = { "171", "Transmute: Elemental Fire" },
    [19566] = { "165", "Salt Shaker", item = true },
}
-- Salt Shaker is an item's use spell, not a recipe: a leatherworker has it only when its cooldown is (or was) running, because a ready one
-- cannot be told from "no shaker". Cooldowns that share a timer are NOT linked (not confirmed yet).
local MIN_DISCOVER = 600       -- a recipe on a cooldown longer than this (seconds) is a profession cooldown

local function Cooldown(id)
    local start, duration
    pcall(function()
        if C_Spell and C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(id)
            if type(info) == "table" then start, duration = info.startTime, info.duration end
        elseif GetSpellCooldown then
            start, duration = GetSpellCooldown(id)
        end
    end)
    return tonumber(start) or 0, tonumber(duration) or 0
end

-- the cooldown spells everybody knows about: seed + discovered + received
function S.CooldownSpells()
    local out = {}
    for id, e in pairs(S.SEED) do out[id] = e[1] end
    local db = ns.DB
    for id, key in pairs(db and db.cdSpells or {}) do out[id] = key end
    return out
end

function S.CooldownName(id)
    local name = SpellData(id)
    if name then return name end
    local e = S.SEED[id]
    return e and e[2] or ("Recipe #" .. tostring(id))
end

-- remaining seconds of a cooldown entry (nil = nothing known)
function S.Remaining(endTime)
    if not endTime or endTime <= 0 then return 0 end
    local left = endTime - ns.Time()
    if left < 0 then return 0 end
    return left
end

function S.TimeText(seconds)
    if seconds <= 0 then return "Ready" end
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    if m > 0 then return ("%dm"):format(m) end
    return "<1m"
end

-- read the cooldowns of my own character. Known recipes that are on a long cooldown are added to the list.
-- skipDiscovery: only read the cooldowns that are known (the cheap part). The discovery of new cooldown recipes asks the game about every recipe
-- I know, so it runs at login, after a craft of a recipe and when a profession window opens, not on every refresh.
function S.ScanOwn(skipDiscovery)
    local own = ns.GetOwn()
    if not own or not ns.worldReady or not ns.DB then return end
    local inCombat = false
    pcall(function() inCombat = InCombatLockdown and InCombatLockdown() or false end)
    if inCombat then return end
    local db = ns.DB
    db.cdSpells = db.cdSpells or {}
    own.cds = own.cds or {}
    local known = {}            -- recipe id -> profession key (what I can craft)
    for key, p in pairs(own.profs or {}) do
        for _, id in ipairs(p.ids or {}) do known[id] = key end
    end
    -- discovery
    for id, key in pairs(skipDiscovery and {} or known) do
        if not db.cdSpells[id] and not S.SEED[id] then
            local start, duration = Cooldown(id)
            if start > 0 and duration >= MIN_DISCOVER then db.cdSpells[id] = key end
        end
    end
    local changed = false
    for id, key in pairs(S.CooldownSpells()) do
        local seed = S.SEED[id]
        local eligible = known[id] ~= nil
        if seed and seed.item then
            local st, du = Cooldown(id)
            eligible = own.profs and own.profs[seed[1]] ~= nil and ((st > 0 and du > 2) or own.cds[id] ~= nil)
        end
        if eligible then
            local start, duration = Cooldown(id)
            local left = 0
            if start > 0 and duration > 2 then
                left = start + duration - GetTime()
                if left < 2 then left = 0 end
            end
            local endTime = left > 0 and (ns.Time() + math.floor(left)) or 0
            local old = own.cds[id]
            if old == nil or math.abs((old or 0) - endTime) > 60 or (old > 0) ~= (endTime > 0) then
                own.cds[id] = endTime
                changed = true
            end
        end
    end
    if changed then
        own.cdsRev = ns.Time()
        if ns.Sync and ns.Sync.AdvertiseCooldowns then ns.Sync.AdvertiseCooldowns() end
        if ns.RefreshUI then ns.RefreshUI() end
    end
end

local scanQueued, scanDiscover = false, false
function S.ScheduleScan(delay, discover)
    if discover then scanDiscover = true end
    if scanQueued then return end
    scanQueued = true
    ns.After(delay or 2, function()
        scanQueued = false
        local skip = not scanDiscover
        scanDiscover = false
        S.ScanOwn(skip)
    end)
end

-- the recipes I know as a set: a cast is looked up in it in one step (it used to walk the whole list of every profession for every cast).
-- It is rebuilt when a profession window opens, and at the latest every five minutes.
local recipeSet, recipeSetAt = nil, -1e9
function S.InvalidateRecipes() recipeSet = nil end
local function Recipes(own)
    local now = ns.Now()
    if recipeSet and now - recipeSetAt < 300 then return recipeSet end
    recipeSet, recipeSetAt = {}, now
    for _, p in pairs(own.profs or {}) do
        for _, id in ipairs(p.ids or {}) do recipeSet[id] = true end
    end
    return recipeSet
end

-- a spell of mine went off: when it is a recipe, its cooldown may have started
function S.OnCast(spellID)
    local own = ns.GetOwn()
    if not own or not ns.worldReady then return end
    if Recipes(own)[spellID] then S.ScheduleScan(1.5, true) end
end

-- a profession window opened (or its list changed): look for new cooldown recipes, at most every five minutes
local lastWindowScan = -1e9
function S.OnWindow()
    S.InvalidateRecipes()
    local now = ns.Now()
    if now - lastWindowScan < 300 then return end
    lastWindowScan = now
    S.ScheduleScan(4, true)
end

-- listing for the Cooldowns tab: { { key, name, rows = { { guid, member, spell, left } } } }, each list by the least time left
function S.ListByProfession()
    local groups, byKey = {}, {}
    local spells = S.CooldownSpells()
    for guid, m in pairs(ns.GetMembers() or {}) do
        for id, endTime in pairs(m.cds or {}) do
            local key = spells[id] or "?"
            local g = byKey[key]
            if not g then
                g = { key = key, name = ns.Professions.ProfessionName(key, "Other"), rows = {} }
                byKey[key] = g
                groups[#groups + 1] = g
            end
            g.rows[#g.rows + 1] = { guid = guid, member = m, spell = id, left = S.Remaining(endTime) }
        end
    end
    for _, g in ipairs(groups) do
        table.sort(g.rows, function(a, b)
            if a.left ~= b.left then return a.left < b.left end
            if a.spell ~= b.spell then return a.spell < b.spell end
            return (a.member.name or "") < (b.member.name or "")
        end)
    end
    table.sort(groups, function(a, b) return a.name < b.name end)
    return groups
end

-- the first time after the world is ready, and then every ten minutes
function S.Start()
    local first = true
    local function Loop()
        S.ReadOwn()
        S.ScanOwn(not first)           -- (new cooldown recipes are looked for at login, not every ten minutes)
        first = false
        ns.After(600, Loop)
    end
    Loop()
end
