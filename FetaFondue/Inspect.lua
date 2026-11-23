---@class ns
local ns = select(2, ...)

-- Looking at a guildie's gear and talents.
--  * Gear: the game's own inspect (reaches far on WoW Forever) or the guildie's addon.
--  * Talents: what we share is only WHICH talents have points (node id -> rank) and the specialization id.
--    The layout of the tree (where each talent sits, its spell, its lines) comes from the receiving game
--    itself: the game's "view" talent config can load the tree of any class from a specialization id.
--    The layout is cached, so the view config is only borrowed once per class.

local I = {}
ns.Inspect = I

-- inventory slot ID, label, picture of an empty slot (in the order of the paper doll)
I.SLOTS = {
    { 1, "Head", "Head" }, { 2, "Neck", "Neck" }, { 3, "Shoulders", "Shoulder" }, { 15, "Back", "Back" },
    { 5, "Chest", "Chest" }, { 4, "Shirt", "Shirt" }, { 19, "Tabard", "Tabard" }, { 9, "Wrists", "Wrists" },
    { 10, "Hands", "Hands" }, { 6, "Waist", "Waist" }, { 7, "Legs", "Legs" }, { 8, "Feet", "Feet" },
    { 11, "Ring 1", "Finger" }, { 12, "Ring 2", "Finger" }, { 13, "Trinket 1", "Trinket" }, { 14, "Trinket 2", "Trinket" },
    { 16, "Main Hand", "MainHand" }, { 17, "Off Hand", "SecondaryHand" }, { 18, "Ranged", "Ranged" },
}

---------------------------------------------------------------------------
-- Role from the talents: the three trees of a class, left to right (names as WoW Forever lists them,
-- for example on wowforever.gg / talentsforever.com), and what each one is played as
---------------------------------------------------------------------------
I.TREES = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" },
    SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral", "Restoration" },
}
I.ROLES = {
    WARRIOR = { "DPS", "DPS", "TANK" },
    PALADIN = { "HEALER", "TANK", "DPS" },
    HUNTER = { "DPS", "DPS", "DPS" },
    ROGUE = { "DPS", "DPS", "DPS" },
    PRIEST = { "HEALER", "HEALER", "DPS" },
    SHAMAN = { "DPS", "DPS", "HEALER" },
    MAGE = { "DPS", "DPS", "DPS" },
    WARLOCK = { "DPS", "DPS", "DPS" },
    DRUID = { "DPS", "FERAL", "HEALER" },   -- Feral can be played as a tank or as damage
}
I.ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DPS = "DPS", FERAL = "Feral", FERAL_TANK = "Feral Tank", FERAL_DPS = "Feral DPS", FERAL_HYBRID = "Feral Hybrid" }
I.ROLE_COLOR = { TANK = "ff4a9fff", HEALER = "ff40ff40", DPS = "ffff5050", FERAL = "ffffa040", FERAL_TANK = "ff4a9fff", FERAL_DPS = "ffff5050", FERAL_HYBRID = "ffffa040" }

-- Feral druids (level 60 and the two talents that decide it; below 60 or with neither: plain "Feral"):
--   Primal Bite and Shifting Power -> Feral Hybrid; Primal Bite only -> Feral Tank; Shifting Power only -> Feral DPS
-- The talents are found by the NAME of their spell in the game's own language, or by spell id (I.FERAL_SPELLS: add the ids here so that it also
-- works on French and German clients; without them those clients simply show plain "Feral").
I.FERAL_LEVEL = 60
I.FERAL_SPELLS = { bite = {}, shifting = {} }          -- [spellId] = true
local FERAL_NAMES = { bite = "Primal Bite", shifting = "Shifting Power" }

local spellNames = {}
local function SpellNameOf(id)
    if not id or id <= 0 then return nil end
    if spellNames[id] then return spellNames[id] end
    local name
    pcall(function()
        if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id)
        elseif C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(id)
            name = type(info) == "table" and info.name or nil
        elseif GetSpellInfo then name = (GetSpellInfo(id)) end
    end)
    if type(name) == "string" and name ~= "" then spellNames[id] = name return name end
    return nil
end

-- has the setup points in Primal Bite / in Shifting Power? (nil, nil when the layout is not known)
function I.FeralTalents(profile, sp)
    sp = sp or (profile and I.ActiveSetup(profile))
    if not profile or not sp or (sp.spec or 0) <= 0 then return nil, nil end
    local layout = I.GetLayout(sp.spec, profile.level)
    if not layout then return nil, nil end
    local bite, shifting = false, false
    for _, n in ipairs(layout.nodes) do
        if ((sp.ranks or {})[n.id] or 0) > 0 then
            local name = SpellNameOf(n.spell)
            if I.FERAL_SPELLS.bite[n.spell or 0] or (name and name == FERAL_NAMES.bite) then bite = true end
            if I.FERAL_SPELLS.shifting[n.spell or 0] or (name and name == FERAL_NAMES.shifting) then shifting = true end
        end
    end
    return bite, shifting
end

function I.FeralRole(profile, sp)
    if not profile or (profile.level or 0) < I.FERAL_LEVEL then return "FERAL" end
    local bite, shifting = I.FeralTalents(profile, sp)
    if bite and shifting then return "FERAL_HYBRID" end
    if bite then return "FERAL_TANK" end
    if shifting then return "FERAL_DPS" end
    return "FERAL"
end

-- how a role counts in the tank / healer / damage numbers (Analytics, the planner): the hybrid and a plain Feral with the damage dealers
function I.BaseRole(role)
    if role == "FERAL_TANK" then return "TANK" end
    if role == "FERAL" or role == "FERAL_DPS" or role == "FERAL_HYBRID" then return "DPS" end
    return role
end

-- points: { points in the 1st tree, 2nd, 3rd } -> name of the main tree, role (nil while levelling: under 5 points)
function I.RoleFor(classFile, points)
    local best, bestPoints, total = nil, -1, 0
    for i = 1, 3 do
        local p = points and points[i] or 0
        total = total + p
        if p > bestPoints then best, bestPoints = i, p end
    end
    if total < 5 or not best then return nil, nil end
    local names, roles = I.TREES[classFile], I.ROLES[classFile]
    return names and names[best] or nil, roles and roles[best] or nil
end

---------------------------------------------------------------------------
-- The three trees of a class on ONE shared grid
---------------------------------------------------------------------------
I.GRID = 600          -- the game puts talents 600 units apart, in columns and in rows
local MAX_ROW, MAX_COL = 8, 4   -- anything further out is a stray (positions that do not fit the grid)

-- nodes: { id, x, y, rank, max, spell, edges }. The trees are the groups of columns separated by wide gaps
-- (at most three, left to right). Returns { { nodes, points }, ... }
function I.GroupNodes(all)
    table.sort(all, function(a, b) return a.x < b.x end)
    local xs, last = {}, nil
    for _, n in ipairs(all) do
        if n.x ~= last then xs[#xs + 1] = n.x last = n.x end
    end
    local gaps = {}
    for i = 2, #xs do gaps[#gaps + 1] = xs[i] - xs[i - 1] end
    table.sort(gaps)
    -- the usual gap between neighbouring columns (a low percentile, so a few huge gaps do not distort it)
    local usual = gaps[math.max(1, math.ceil(#gaps * 0.25))] or 0
    local threshold = math.max(1800, usual * 3)
    local groups, cur, prevX = {}, nil, nil
    for _, n in ipairs(all) do
        if not cur or (prevX and n.x - prevX > threshold and #groups < 3) then
            cur = { nodes = {}, points = 0 }
            groups[#groups + 1] = cur
        end
        cur.nodes[#cur.nodes + 1] = n
        cur.points = cur.points + (n.rank or 0)
        prevX = n.x
    end
    return groups
end

-- Gives every talent a row (node.gr, shared by all trees: tier 1 is at the same height everywhere) and a
-- column (node.gc, counted inside its own tree), both from 0. Strays are put next to the talent they are
-- connected to, or in a row below the others. Sets g.cols for every tree and returns the number of rows.
function I.PlaceOnGrid(groups)
    local GRID = I.GRID
    local minY = math.huge
    for _, g in ipairs(groups) do for _, n in ipairs(g.nodes) do minY = math.min(minY, n.y) end end

    local rows = 1
    for _, g in ipairs(groups) do
        local minX = math.huge
        for _, n in ipairs(g.nodes) do minX = math.min(minX, n.x) end
        local byID, taken, strays = {}, {}, {}
        local before, after = {}, {}    -- lines: before[id] = a talent that is needed for it, after[id] = talents needing it
        for _, n in ipairs(g.nodes) do byID[n.id] = n end
        for _, n in ipairs(g.nodes) do
            n.gr = math.floor((n.y - minY) / GRID + 0.5)
            n.gc = math.floor((n.x - minX) / GRID + 0.5)
            for _, t in ipairs(n.edges or {}) do
                if byID[t] then
                    before[t] = before[t] or n
                    after[n.id] = after[n.id] or {}
                    table.insert(after[n.id], byID[t])
                end
            end
        end
        local lastNormal = 0
        for _, n in ipairs(g.nodes) do
            if n.gr > MAX_ROW or n.gc > MAX_COL or n.gr < 0 or n.gc < 0 then
                strays[#strays + 1] = n
            else
                taken[n.gr .. "," .. n.gc] = true
                lastNormal = math.max(lastNormal, n.gr)
            end
        end
        local function Free(r, c) return r >= 0 and r <= MAX_ROW and c >= 0 and c <= MAX_COL and not taken[r .. "," .. c] end
        for _, n in ipairs(strays) do
            local row, col
            local from = before[n.id]
            local to = after[n.id] and after[n.id][1]
            if from and from.gr <= MAX_ROW and from.gc <= MAX_COL and from.gr >= 0 then
                row, col = from.gr + 1, from.gc
            elseif to and to.gr <= MAX_ROW and to.gc <= MAX_COL and to.gr >= 0 then
                row, col = to.gr - 1, to.gc
            else
                row, col = math.min(MAX_ROW, lastNormal + 1), 0
            end
            -- the nearest free cell: same row first, then the rows below
            local placed = false
            for r = row, MAX_ROW do
                for c = col, MAX_COL do
                    if not placed and Free(r, c) then n.gr, n.gc, placed = r, c, true end
                end
                for c = 0, col - 1 do
                    if not placed and Free(r, c) then n.gr, n.gc, placed = r, c, true end
                end
            end
            if not placed then n.gr, n.gc = MAX_ROW, MAX_COL end
            taken[n.gr .. "," .. n.gc] = true
        end
        local cols = 1
        for _, n in ipairs(g.nodes) do
            rows = math.max(rows, n.gr + 1)
            cols = math.max(cols, n.gc + 1)
        end
        g.cols = cols
    end
    return rows
end

---------------------------------------------------------------------------
-- Gear
---------------------------------------------------------------------------
local function Trim(itemString)
    -- keep the first fields of the link (item, enchant, gems, suffix, unique id, level...): enough to rebuild it
    local fields, n, len = {}, 0, 0
    for f in (itemString .. ":"):gmatch("([^:]*):") do
        if len + #f + 1 > 140 or n >= 14 then break end
        n = n + 1
        fields[n] = f
        len = len + #f + 1
    end
    return table.concat(fields, ":")
end

-- one equipped item as "id:enchant:gem1:..." or nil. The link can be missing while the item's data
-- is not loaded yet, so fall back to the plain item ID.
function I.ReadSlot(unit, slot)
    local s
    pcall(function()
        local link = GetInventoryItemLink and GetInventoryItemLink(unit, slot)
        s = link and link:match("|Hitem:([%-%d:]+)|h")
        if s then s = Trim(s) end
    end)
    if s then return s end
    pcall(function()
        local id = GetInventoryItemID and GetInventoryItemID(unit, slot)
        if id and id > 0 then
            s = tostring(id) .. ":0:0:0:0:0:0:0"
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        end
    end)
    return s
end

---------------------------------------------------------------------------
-- Talents: the layout of a class's tree (from the game, cached) and the ranks somebody has put in it
---------------------------------------------------------------------------
local function ActiveConfigID()
    local id
    pcall(function() id = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() end)
    return id
end

local function InspectConfigID()
    local id = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    return id or -1
end

local function BuildNumber()
    local build
    pcall(function() build = select(2, GetBuildInfo()) end)
    return build or ""
end

-- every talent of a trait config with its place, its spell and its lines: { nodes = { {id, x, y, max, spell, edges} } }
local function ReadLayout(configID)
    local nodes = {}
    pcall(function()
        local cfg = C_Traits.GetConfigInfo(configID)
        for _, treeID in ipairs(cfg and cfg.treeIDs or {}) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                if node and node.ID and node.isVisible ~= false and (node.maxRanks or 0) > 0 then
                    local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
                    local spell = 0
                    if entryID then
                        local entry = C_Traits.GetEntryInfo(configID, entryID)
                        local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                        spell = def and (def.spellID or def.overriddenSpellID) or 0
                    end
                    local edges = {}
                    for _, e in ipairs(node.visibleEdges or {}) do
                        if e.targetNode then edges[#edges + 1] = e.targetNode end
                    end
                    nodes[#nodes + 1] = {
                        id = node.ID, x = math.floor(node.posX or 0), y = math.floor(node.posY or 0),
                        max = node.maxRanks, spell = spell, edges = edges,
                    }
                end
            end
        end
    end)
    return nodes
end

-- The layout for a specialization. Cached in the saved data (once per class and game build).
-- configID: a config we can read it from right now (mine, or the one the game filled by inspecting somebody).
--
-- The game's "view" talent config is NOT used: loading it fires the game's talent events at once, inside our
-- own call, so Blizzard's talent window runs its code while our addon is on the call stack and the game blocks it
-- ("AddOn has been blocked from an action only available to the Blizzard UI"). A layout we cannot read ourselves
-- is asked from the guild instead (see Sync.lua): somebody who plays that class shares it.
function I.GetLayout(specID, level, configID)
    if not specID or specID <= 0 then return nil end
    ns.DB.talentLayouts = ns.DB.talentLayouts or {}
    local build = BuildNumber()
    local cached = ns.DB.talentLayouts[specID]
    if cached and cached.build == build and #cached.nodes > 0 then return cached end
    if not configID then return nil end
    local nodes = ReadLayout(configID)
    if not nodes or #nodes == 0 then return nil end
    cached = { build = build, nodes = nodes }
    ns.DB.talentLayouts[specID] = cached
    return cached
end

I.BuildNumber = BuildNumber

-- A layout as a list of short parts for the guild channel: "id:x:y:max:spell:edge.edge" for every talent
function I.EncodeLayout(layout)
    local parts = {}
    for _, n in ipairs(layout.nodes or {}) do
        parts[#parts + 1] = ("%d:%d:%d:%d:%d:%s"):format(n.id, n.x, n.y, n.max, n.spell or 0, table.concat(n.edges or {}, "."))
    end
    return parts
end

-- the other way; nil when the data is not sane
function I.DecodeLayout(str)
    local nodes = {}
    for part in str:gmatch("[^;]+") do
        local id, x, y, max, spell, edges = part:match("^(%d+):(%-?%d+):(%-?%d+):(%d+):(%d+):([%d%.]*)$")
        if not id then return nil end
        id, x, y, max, spell = tonumber(id), tonumber(x), tonumber(y), tonumber(max), tonumber(spell)
        if max < 1 or max > 20 or math.abs(x) > 1e7 or math.abs(y) > 1e7 then return nil end
        local list = {}
        for e in edges:gmatch("%d+") do list[#list + 1] = tonumber(e) end
        nodes[#nodes + 1] = { id = id, x = x, y = y, max = max, spell = spell, edges = list }
        if #nodes > 150 then return nil end
    end
    if #nodes == 0 then return nil end
    return nodes
end

-- which talents have points: { [nodeID] = rank }, and how many
local function ReadRanks(configID)
    local ranks, count = {}, 0
    pcall(function()
        local cfg = C_Traits.GetConfigInfo(configID)
        for _, treeID in ipairs(cfg and cfg.treeIDs or {}) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                local rank = node and (node.activeRank or node.ranksPurchased) or 0
                if rank > 0 then
                    ranks[node.ID or nodeID] = rank
                    count = count + 1
                end
            end
        end
    end)
    return ranks, count
end

local function OwnSpecID()
    local id
    pcall(function() id = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID() end)
    if not id then
        pcall(function()
            local info = C_SpecializationInfo
            local index = info and info.GetSpecialization and info.GetSpecialization()
            if index and info.GetSpecializationInfo then id = (info.GetSpecializationInfo(index)) end
        end)
    end
    return id
end

local function InspectedSpecID(unit)
    local id
    pcall(function()
        id = (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization and C_SpecializationInfo.GetInspectSpecialization(unit))
            or (GetInspectSpecialization and GetInspectSpecialization(unit))
    end)
    return id
end

-- Which of the two talent groups (dual specialization: 1 = Primary, 2 = Secondary) is active right now; nil when the game does not say.
local function ActiveGroup()
    local g
    pcall(function()
        local info = C_SpecializationInfo
        g = info and info.GetActiveSpecGroup and info.GetActiveSpecGroup()
        if type(g) ~= "number" and GetActiveTalentGroup then g = GetActiveTalentGroup() end
    end)
    if type(g) == "number" and g >= 1 and g <= 2 then return g end
    return nil
end

-- The talent setups of MY character: the active one, and (dual specialization) the other one.
-- Each: { spec = specialization id, ranks = { [nodeID] = rank }, active = true/false, group = 1 or 2 }.
-- On WoW Forever the game cannot show the talents of the group that is NOT active (the probe found no saved configs for it), so every
-- time a group is active its talents are kept (ns.DB.talentGroups[guid][group]); the other group is then the copy from the last time it
-- was active. (Saved talent configs, when a client has them, are used first.)
local function CaptureOwnSpecs(level)
    local specs = {}
    if not ns.worldReady then return specs end       -- not right at login (see ns.worldReady in Core.lua)
    local specID = OwnSpecID() or 0
    local active = ActiveConfigID()
    if not active then return specs end
    local ranks, rankCount = ReadRanks(active)
    local group = ActiveGroup()
    specs[1] = { spec = specID, ranks = ranks, active = true, group = group }
    I.GetLayout(specID, level, active)      -- my own tree is the cheapest way to learn my class's layout
    local saved
    if group and ns.DB and ns.myGUID then
        ns.DB.talentGroups = ns.DB.talentGroups or {}
        saved = ns.DB.talentGroups[ns.myGUID]
        if not saved then saved = {} ns.DB.talentGroups[ns.myGUID] = saved end
        if rankCount > 0 then saved[group] = { spec = specID, ranks = ranks, at = ns.Time() } end
    end

    local function AddOther(configID, otherSpec)
        if #specs >= 2 or configID == active then return end
        local r, count = ReadRanks(configID)
        if count > 0 then specs[#specs + 1] = { spec = otherSpec, ranks = r, active = false } end
    end
    pcall(function()
        if not (C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID) then return end
        -- other saved setups of the same specialization
        for _, id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do AddOther(id, specID) end
        -- another specialization of the class
        local info = C_SpecializationInfo
        local _, _, classID = UnitClass("player")
        local n = info and info.GetNumSpecializationsForClassID and info.GetNumSpecializationsForClassID(classID) or 0
        for i = 1, n do
            local otherSpec = info.GetSpecializationInfoForClassID and (info.GetSpecializationInfoForClassID(classID, i))
            if otherSpec and otherSpec ~= specID then
                for _, id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(otherSpec) or {}) do AddOther(id, otherSpec) end
            end
        end
    end)
    -- the group that is not active: the copy kept from the last time it was
    if #specs < 2 and group and saved and saved[3 - group] and next(saved[3 - group].ranks or {}) ~= nil then
        local o = saved[3 - group]
        specs[2] = { spec = o.spec or 0, ranks = o.ranks, active = false, group = 3 - group }
    elseif #specs >= 2 and group then
        specs[2].group = 3 - group
    end
    return specs
end

-- keeps the older single-setup fields (spec, ranks) in step with the active setup
function I.Normalize(p)
    if not p.specs or #p.specs == 0 then
        p.specs = {}
        if (p.spec or 0) > 0 or next(p.ranks or {}) ~= nil then
            p.specs[1] = { spec = p.spec or 0, ranks = p.ranks or {}, active = true }
        end
    end
    local act = p.specs[1]
    for _, sp in ipairs(p.specs) do if sp.active then act = sp end end
    if act then p.spec, p.ranks = act.spec, act.ranks else p.spec, p.ranks = 0, {} end
    return p
end

---------------------------------------------------------------------------
-- Character stats (what the game's character panel shows). Only MY OWN character can be read; a guildie's addon shares them
-- with the rest of the profile. Out of combat and after worldReady only, everything inside pcall, a stat the game does not
-- have is simply missing (and so hidden). Crit and haste exist three times (melee, ranged, spell): all three are kept and the
-- window shows the highest one, like the game's own panel does.
---------------------------------------------------------------------------
I.STAT_KEYS = { "ilvl", "hp", "pw", "pt", "str", "agi", "sta", "int", "spi", "ap", "rap", "cm", "cr", "cs", "hm", "hr", "hs",
    "apen", "sdmg", "sheal", "spen", "def", "defmax", "dodge", "block", "parry", "armor" }
local STAT_SET = {}
for _, k in ipairs(I.STAT_KEYS) do STAT_SET[k] = true end

local function Num(v)
    if type(v) ~= "number" then return nil end
    local secret = false
    pcall(function() if issecretvalue and issecretvalue(v) then secret = true end end)
    if secret or v ~= v then return nil end
    return v
end

-- calls a global function of the game; nil when it is not there or fails. Returns up to three results.
local function Call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    return res[2], res[3], res[4]
end

-- the lowest of a per-school value over the magic schools 2..7 (holy to arcane), like the game's panel shows it
local function LowestSchool(name)
    local low
    for school = 2, 7 do
        local v = Num((Call(name, school)))
        if v then low = low and math.min(low, v) or v end
    end
    return low
end

-- "Defense" skill: the game's own function when there is one, else the skill line of that name (English, French, German client)
local DEFENSE_NAMES = { ["Defense"] = true, ["Défense"] = true, ["Defence"] = true, ["Verteidigung"] = true }
local function DefenseSkill()
    local base, mod = Call("UnitDefense", "player")
    if Num(base) then
        local level = Num(UnitLevel and UnitLevel("player")) or 0
        return base + (Num(mod) or 0), level * 5
    end
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil, nil end
    local names = {}
    for n in pairs(DEFENSE_NAMES) do names[n] = true end
    if type(_G.DEFENSE) == "string" then names[_G.DEFENSE] = true end      -- (the game's own word for it, in the client's language)
    -- the skills tab only lists the lines under headers that are open: open them all for a moment, then close the ones that were closed
    local collapsed, opened = {}, false
    pcall(function()
        for i = 1, (GetNumSkillLines() or 0) do
            local name, header, expanded = GetSkillLineInfo(i)
            if header and not expanded and name then collapsed[name] = true end
        end
        if next(collapsed) ~= nil and ExpandSkillHeader then ExpandSkillHeader(0) opened = true end
    end)
    local rank, max
    pcall(function()
        for i = 1, (GetNumSkillLines() or 0) do
            local name, header, _, r, _, modifier, m = GetSkillLineInfo(i)
            if not header and names[name or ""] then
                if Num(r) then rank = r + (Num(modifier) or 0) end
                max = Num(m)
                return
            end
        end
    end)
    if opened and CollapseSkillHeader then
        pcall(function()
            for i = (GetNumSkillLines() or 0), 1, -1 do
                local name, header = GetSkillLineInfo(i)
                if header and collapsed[name or ""] then CollapseSkillHeader(i) end
            end
        end)
    end
    return rank, max
end

-- average item level of what is equipped: the game's number when it has one, else the plain average of the equipped items
local ILVL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local function AverageItemLevel()
    local avg, equipped = Call("GetAverageItemLevel")
    local v = Num(equipped) or Num(avg)
    if v and v > 0 then return v end
    local sum, count = 0, 0
    for _, slot in ipairs(ILVL_SLOTS) do
        pcall(function()
            local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
            if not link then return end
            local level
            if C_Item and C_Item.GetDetailedItemLevelInfo then level = C_Item.GetDetailedItemLevelInfo(link)
            elseif GetDetailedItemLevelInfo then level = GetDetailedItemLevelInfo(link) end
            if not Num(level) and GetItemInfo then level = select(4, GetItemInfo(link)) end
            level = Num(level)
            if level and level > 0 then sum, count = sum + level, count + 1 end
        end)
    end
    if count > 0 then return sum / count end
    return nil
end

local lastStats
function I.ReadStats()
    if not ns.worldReady then return lastStats end
    local inCombat = false
    pcall(function() inCombat = InCombatLockdown and InCombatLockdown() or false end)
    if inCombat then return lastStats end
    local s = {}
    local function Put(key, v, digits)
        v = Num(v)
        if not v or v <= 0 then return end
        s[key] = digits and (tonumber(("%." .. digits .. "f"):format(v)) or 0) or math.floor(v + 0.5)
    end
    Put("ilvl", AverageItemLevel(), 2)
    Put("hp", (Call("UnitHealthMax", "player")))
    Put("pw", (Call("UnitPowerMax", "player")))
    s.pt = Num((Call("UnitPowerType", "player")))
    for i, key in ipairs({ "str", "agi", "sta", "int", "spi" }) do
        local _, effective = Call("UnitStat", "player", i)
        Put(key, effective)
    end
    for _, pair in ipairs({ { "ap", "UnitAttackPower" }, { "rap", "UnitRangedAttackPower" } }) do
        local base, pos, neg = Call(pair[2], "player")
        if Num(base) then Put(pair[1], base + (Num(pos) or 0) + (Num(neg) or 0)) end
    end
    Put("cm", (Call("GetCritChance")), 2)
    Put("cr", (Call("GetRangedCritChance")), 2)
    Put("cs", LowestSchool("GetSpellCritChance"), 2)
    local hm = Num((Call("GetMeleeHaste"))) or Num((Call("GetHaste")))
    Put("hm", hm, 2)
    -- ranged haste: the game returns the haste and the ranged-only bonus (an ammo pouch or quiver) and its panel adds them
    local r1, r2, r3 = Call("GetRangedHaste")
    local hr
    for _, v in ipairs({ Num(r1) or false, Num(r2) or false, Num(r3) or false }) do if v then hr = (hr or 0) + v end end
    Put("hr", hr, 2)
    Put("hs", Num((Call("GetSpellHaste"))) or hm, 2)           -- (no spell haste function seen: it matched the melee haste)
    local penRating = type(_G.CR_ARMOR_PENETRATION) == "number" and Num((Call("GetCombatRatingBonus", _G.CR_ARMOR_PENETRATION))) or nil
    Put("apen", Num((Call("GetArmorPenetration"))) or penRating, 2)
    Put("sdmg", LowestSchool("GetSpellBonusDamage"))
    Put("sheal", (Call("GetSpellBonusHealing")))
    Put("spen", (Call("GetSpellPenetration")))
    local def, defMax = DefenseSkill()
    Put("def", def)
    if s.def then Put("defmax", defMax) end
    Put("dodge", (Call("GetDodgeChance")), 2)
    Put("block", (Call("GetBlockChance")), 2)
    Put("parry", (Call("GetParryChance")), 2)
    local _, armor = Call("UnitArmor", "player")
    Put("armor", armor)
    if next(s) == nil then return lastStats end
    lastStats = s
    return s
end

-- Reads a unit: my own character ("player"), or somebody the game let us inspect (gear, and their talents
-- when the game hands out the inspect data: only the active setup).
function I.Capture(unit)
    local p = { level = 0, race = "", class = "", items = {}, spec = 0, ranks = {}, specs = {}, src = "owner" }
    pcall(function()
        p.level = UnitLevel(unit) or 0
        if UnitRace then
            local localized, token = UnitRace(unit)
            p.race = token or localized or ""
        end
        local _, classFile = UnitClass(unit)
        p.class = classFile or ""
    end)
    for _, slot in ipairs(I.SLOTS) do
        local s = I.ReadSlot(unit, slot[1])
        if s then p.items[slot[1]] = s end
    end
    if unit == "player" then
        p.specs = CaptureOwnSpecs(p.level)
        p.stats = I.ReadStats()
    else
        p.src = "scan"
        local valid = false
        pcall(function() valid = C_Traits and C_Traits.HasValidInspectData and C_Traits.HasValidInspectData() end)
        if valid then
            local spec = InspectedSpecID(unit) or 0
            local ranks = ReadRanks(InspectConfigID())
            if next(ranks) ~= nil then
                p.specs = { { spec = spec, ranks = ranks, active = true } }
                if spec > 0 then I.GetLayout(spec, p.level, InspectConfigID()) end
            end
        end
    end
    return I.Normalize(p)
end

function I.CaptureSelf() return I.Capture("player") end

-- A light, read-only look at my own gear and talents for the welcome window: how many equipment slots are filled
-- and how many talent points are spent where. It reads only; and nothing before the world has been up for a few seconds.
function I.SelfBrief()
    local brief = { items = 0, points = 0, tree = nil, talents = false, ready = ns.worldReady == true }
    if not ns.worldReady then return brief end
    for _, slot in ipairs(I.SLOTS) do
        local id
        pcall(function() id = GetInventoryItemID and GetInventoryItemID("player", slot[1]) end)
        if id and id > 0 then brief.items = brief.items + 1 end
    end
    pcall(function()
        local active = ActiveConfigID()
        if not active then return end
        local ranks, count = ReadRanks(active)
        if count == 0 then return end
        brief.talents = true
        local _, classFile = UnitClass("player")
        local profile = { class = classFile or "", level = UnitLevel("player") or 0, spec = OwnSpecID() or 0, ranks = ranks }
        I.GetLayout(profile.spec, profile.level, active)
        local points = I.TreePoints(profile)
        if points then
            local total = 0
            for _, p in ipairs(points) do total = total + p end
            brief.points = total
            brief.tree = I.RoleFor(classFile, points)
        end
    end)
    return brief
end

-- the setup that is active right now (the first one when none is marked)
function I.ActiveSetup(p)
    I.Normalize(p)
    for _, sp in ipairs(p.specs) do if sp.active then return sp end end
    return p.specs[1]
end

-- points per tree (left to right) of one talent setup of a profile; nil without the class layout
function I.TreePoints(profile, sp)
    sp = sp or (profile and I.ActiveSetup(profile))
    if not profile or not sp or (sp.spec or 0) <= 0 then return nil end
    local layout = I.GetLayout(sp.spec, profile.level)
    if not layout then return nil end
    local all = {}
    for _, n in ipairs(layout.nodes) do
        all[#all + 1] = { id = n.id, x = n.x, y = n.y, rank = math.min((sp.ranks or {})[n.id] or 0, n.max) }
    end
    local points = {}
    for i, g in ipairs(I.GroupNodes(all)) do points[i] = g.points end
    return points
end

-- the main tree and the role (TANK / HEALER / DPS / FERAL) of a setup; of the active one by default
function I.RoleOfProfile(profile, sp)
    local points = I.TreePoints(profile, sp)
    if not points then return nil end
    local tree, role = I.RoleFor(profile.class, points)
    if role == "FERAL" then role = I.FeralRole(profile, sp) end
    return tree, role
end

-- one letter for sharing: T, H, D; Feral druids: F (plain), B (tank), C (damage), Y (hybrid)
local ROLE_CODE = { TANK = "T", HEALER = "H", DPS = "D", FERAL = "F", FERAL_TANK = "B", FERAL_DPS = "C", FERAL_HYBRID = "Y" }
I.ROLE_CODE = ROLE_CODE
I.CODE_ROLE = { T = "TANK", H = "HEALER", D = "DPS", F = "FERAL", B = "FERAL_TANK", C = "FERAL_DPS", Y = "FERAL_HYBRID" }

-- what to share about MY character besides gear: its race and role
function I.OwnSummary()
    local race, role, tree = "", "", ""
    if not ns.worldReady then
        pcall(function() if UnitRace then local localized, token = UnitRace("player") race = token or localized or "" end end)
        return race, role, tree
    end
    pcall(function()
        if UnitRace then
            local localized, token = UnitRace("player")
            race = token or localized or ""
        end
    end)
    pcall(function()
        local _, classFile = UnitClass("player")
        local profile = { class = classFile or "", level = UnitLevel("player") or 0, spec = OwnSpecID() or 0, ranks = {} }
        local configID = ActiveConfigID()
        if configID then
            profile.ranks = ReadRanks(configID)
            I.GetLayout(profile.spec, profile.level, configID)
        end
        local t, r = I.RoleOfProfile(profile)
        role = r and ROLE_CODE[r] or ""
        tree = t or ""
    end)
    return race, role, tree
end

-- My talent setups (with dual specialization two), the active one first: { { tree = "Enhancement", role = "D" (T, H, D, F or ""), active = true }, ... }.
-- A setup whose tree cannot be told yet (fewer than 5 points: a spare setup nobody uses) is left out. nil when nothing could be read.
-- Only after the world is ready, and read-only (see CaptureOwnSpecs).
function I.OwnSetups()
    if not ns.worldReady then return nil end
    local list
    pcall(function()
        local _, classFile = UnitClass("player")
        local level = UnitLevel("player") or 0
        local specs = CaptureOwnSpecs(level)
        if #specs == 0 then return end
        local profile = I.Normalize({ class = classFile or "", level = level, specs = specs })
        local order = {}
        for _, sp in ipairs(profile.specs) do if sp.active then order[#order + 1] = sp end end
        for _, sp in ipairs(profile.specs) do if not sp.active then order[#order + 1] = sp end end
        list = {}
        for _, sp in ipairs(order) do
            local tree, role = I.RoleOfProfile(profile, sp)
            if tree and tree ~= "" then
                list[#list + 1] = { tree = tree, role = role and ROLE_CODE[role] or "", active = sp.active == true }
            end
        end
    end)
    return list
end

-- Keep my own tree, role and setups (own.tree, own.role, own.setups, own.setupsRev) in step with the game. Returns true when they
-- changed (a respec, the other specialization made active, a first reading). setupsRev is the time of the last change: it travels with
-- the setups so that an old copy never replaces a newer one. Nothing is changed when the game could not be read.
function I.RefreshOwn()
    local own = ns.GetOwn()
    if not own or not ns.worldReady then return false end
    local list = I.OwnSetups()
    if not list or #list == 0 then return false end
    local function Sig(setups)
        local out = {}
        for _, s in ipairs(setups or {}) do out[#out + 1] = (s.role or "") .. ":" .. (s.tree or "") end
        return table.concat(out, "|")
    end
    local changed = Sig(list) ~= Sig(own.setups) or not own.setupsRev
    own.setups = list
    own.tree = list[1].tree
    if list[1].role ~= "" then own.role = list[1].role end
    if changed then own.setupsRev = ns.Time() end
    return changed
end

-- the name of the talent tree with the most points of a guildmate's inspect profile (as the player details show it), or nil
function I.TreeOfProfile(profile)
    if not profile then return nil end
    local ok, tree = pcall(function()
        local t = I.RoleOfProfile(profile)
        return t
    end)
    return ok and tree or nil
end

---------------------------------------------------------------------------
-- The game's own inspect (reaches further on WoW Forever): works for anybody we can point at, so
-- group members, our target, and everybody with a nameplate - without them running the addon.
---------------------------------------------------------------------------
local function SameGUID(unit, guid)
    local ok, res = pcall(function() return UnitGUID(unit) == guid end)
    return ok and res == true
end

function I.FindUnit(guid)
    local units = { "target", "mouseover", "focus" }
    for i = 1, 4 do units[#units + 1] = "party" .. i end
    for i = 1, 40 do units[#units + 1] = "raid" .. i end
    for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
    for _, u in ipairs(units) do
        if SameGUID(u, guid) then return u end
    end
    return nil
end

I.pending = nil   -- { guid, unit } while we wait for INSPECT_READY

function I.StartNative(guid)
    if not NotifyInspect then return false end
    local unit = I.FindUnit(guid)
    if not unit then return false end
    local can = true
    pcall(function() if CanInspect then can = CanInspect(unit) end end)
    if not can then return false end
    if not pcall(NotifyInspect, unit) then return false end
    I.pending = { guid = guid, unit = unit }
    return true
end

-- Put a profile into the saved copies. A scan (somebody inspected them in the game) only knows the active
-- setup: it updates gear, level, race and the matching setup, and keeps the other setup we already had
-- (from their own addon). Newer data wins. Returns the stored profile, or nil when it was not newer.
function I.Store(guid, profile)
    I.Normalize(profile)
    local old = ns.DB.inspect[guid]
    if old then
        I.Normalize(old)
        if (profile.at or 0) < (old.at or 0) then return nil end
        if profile.src == "scan" then
            local merged = { level = profile.level, race = profile.race ~= "" and profile.race or old.race,
                class = profile.class ~= "" and profile.class or old.class, items = profile.items, at = profile.at,
                src = "scan", specs = {} }
            local scanSpec = profile.specs[1]
            -- which of their old setups did the scan see? the one with the same specialization that looks most like it
            local bestIndex, bestScore = nil, -1
            if scanSpec then
                for n, sp in ipairs(old.specs) do
                    if sp.spec == scanSpec.spec then
                        local score = 0
                        for id, r in pairs(scanSpec.ranks) do if (sp.ranks or {})[id] == r then score = score + 1 end end
                        if sp.active then score = score + 0.5 end
                        if score > bestScore then bestIndex, bestScore = n, score end
                    end
                end
            end
            for n, sp in ipairs(old.specs) do
                if n == bestIndex then
                    merged.specs[#merged.specs + 1] = { spec = sp.spec, ranks = scanSpec.ranks, active = true, group = sp.group }
                else
                    merged.specs[#merged.specs + 1] = { spec = sp.spec, ranks = sp.ranks, active = false, group = sp.group }
                end
            end
            if scanSpec and not bestIndex then
                if #merged.specs >= 2 then table.remove(merged.specs) end
                merged.specs[#merged.specs + 1] = { spec = scanSpec.spec, ranks = scanSpec.ranks, active = true }
            end
            if not scanSpec then merged.specs = old.specs end   -- the game gave no talents: keep what we had
            profile = I.Normalize(merged)
        end
    end
    if old and not profile.stats and old.stats then profile.stats = old.stats end   -- a scan (or an older addon) has no stats: keep what we had
    ns.DB.inspect[guid] = profile
    -- keep the saved copies few
    local count, oldest, oldestAt = 0, nil, nil
    for g, p in pairs(ns.DB.inspect) do
        count = count + 1
        if not oldestAt or (p.at or 0) < oldestAt then oldest, oldestAt = g, p.at or 0 end
    end
    if count > 150 and oldest then ns.DB.inspect[oldest] = nil end
    return profile
end

-- INSPECT_READY: the game has the other player's gear and talents ready
function I.OnInspectReady(guid)
    local pending = I.pending
    if not pending or pending.guid ~= guid then return end
    I.pending = nil
    local unit = SameGUID(pending.unit, guid) and pending.unit or I.FindUnit(guid)
    if not unit then return end
    local profile = I.Capture(unit)
    profile.at = ns.Time()
    pcall(function() if ClearInspectPlayer then ClearInspectPlayer() end end)
    if next(profile.items) == nil and #profile.specs == 0 then return end
    local stored = I.Store(guid, profile)
    if stored then
        if ns.OnInspectData then ns.OnInspectData(guid) end
        -- tell the other guildies who use the addon what we just saw
        if ns.Sync and ns.Sync.ShareScan then ns.Sync.ShareScan(guid) end
    end
end

---------------------------------------------------------------------------
-- Encoding for the guild channel: a list of small parts, packed into messages of about 170 characters
---------------------------------------------------------------------------
local function Clean(s) return (tostring(s or ""):gsub("[|;:=,]", " ")) end

function I.Encode(p)
    I.Normalize(p)
    local parts = { ("h=%d,%s,%s"):format(p.level or 0, Clean(p.race), Clean(p.class)) }
    parts[#parts + 1] = "o=" .. (p.src == "scan" and "S" or "O")    -- from their own addon, or scanned by a guildie
    for _, slot in ipairs(I.SLOTS) do
        local s = p.items[slot[1]]
        if s then parts[#parts + 1] = ("i%d=%s"):format(slot[1], s) end
    end
    -- the stats: "t=key:value,key:value,..." six at a time (older addons skip the part they do not know)
    if p.stats then
        local pairsOut = {}
        for _, k in ipairs(I.STAT_KEYS) do
            local v = p.stats[k]
            if type(v) == "number" then pairsOut[#pairsOut + 1] = k .. ":" .. tostring(v) end
        end
        for i = 1, #pairsOut, 6 do
            parts[#parts + 1] = "t=" .. table.concat(pairsOut, ",", i, math.min(i + 5, #pairsOut))
        end
    end
    -- which talent group (1 Primary, 2 Secondary) each setup is: "u=<group of setup 1>,<group of setup 2>" (0 = not known; older addons skip it)
    do
        local groups, any = {}, false
        for n, sp in ipairs(p.specs) do
            groups[n] = tostring(sp.group or 0)
            if sp.group then any = true end
        end
        if any then parts[#parts + 1] = "u=" .. table.concat(groups, ",") end
    end
    -- every talent setup: "s<n>=<specID>,<1 if active>" then its ranks "k<n>=id:rank,id:rank,..." a few per part
    for n, sp in ipairs(p.specs) do
        parts[#parts + 1] = ("s%d=%d,%d"):format(n, sp.spec or 0, sp.active and 1 or 0)
        local ids = {}
        for id in pairs(sp.ranks or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        local cur = {}
        for _, id in ipairs(ids) do
            cur[#cur + 1] = id .. ":" .. sp.ranks[id]
            if #cur >= 10 then
                parts[#parts + 1] = ("k%d=%s"):format(n, table.concat(cur, ","))
                cur = {}
            end
        end
        if #cur > 0 then parts[#parts + 1] = ("k%d=%s"):format(n, table.concat(cur, ",")) end
    end
    return parts
end

function I.Chunk(parts, limit)
    local chunks, cur = {}, ""
    for _, part in ipairs(parts) do
        if cur ~= "" and #cur + #part + 1 > limit then
            chunks[#chunks + 1] = cur
            cur = part
        else
            cur = (cur == "") and part or (cur .. "|" .. part)
        end
    end
    if cur ~= "" then chunks[#chunks + 1] = cur end
    return chunks
end

function I.Decode(str)
    local p = { level = 0, race = "", class = "", items = {}, spec = 0, ranks = {}, specs = {}, src = "owner" }
    local setups, groupOf = {}, {}
    for part in str:gmatch("[^|]+") do
        local kind = part:sub(1, 1)
        if kind == "h" then
            local level, race, class = part:match("^h=(%d+),([^,]*),(.*)$")
            if level then p.level, p.race, p.class = tonumber(level), race, class end
        elseif kind == "o" then
            p.src = part:sub(3, 3) == "S" and "scan" or "owner"
        elseif kind == "t" then
            for key, value in part:gmatch("(%a+):([%d%.]+)") do
                local n = tonumber(value)
                if STAT_SET[key] and n and n >= 0 and n <= 1e8 then
                    p.stats = p.stats or {}
                    p.stats[key] = n
                end
            end
        elseif kind == "i" then
            local slot, s = part:match("^i(%d+)=([%-%d:]+)$")
            if slot and tonumber(slot) <= 30 then p.items[tonumber(slot)] = s end
        elseif kind == "s" then
            local n, spec, active = part:match("^s(%d+)=(%d+),(%d)$")
            n = tonumber(n)
            if n and n >= 1 and n <= 4 then setups[n] = setups[n] or { ranks = {} } setups[n].spec = tonumber(spec) setups[n].active = active == "1" end
        elseif kind == "k" then
            local n = tonumber(part:match("^k(%d*)=")) or 1     -- older senders had a single setup: "k="
            if n >= 1 and n <= 4 then
                setups[n] = setups[n] or { ranks = {}, active = true, spec = 0 }
                for id, rank in part:gmatch("(%d+):(%d+)") do
                    if tonumber(rank) <= 20 then setups[n].ranks[tonumber(id)] = tonumber(rank) end
                end
            end
        elseif kind == "u" then
            local n = 0
            for g in (part:match("^u=([%d,]+)$") or ""):gmatch("%d+") do
                n = n + 1
                if tonumber(g) == 1 or tonumber(g) == 2 then groupOf[n] = tonumber(g) end
            end
        elseif kind == "p" then   -- older senders: the specialization id of their single setup
            local spec = tonumber(part:match("^p=(%d+)$"))
            if spec then setups[1] = setups[1] or { ranks = {}, active = true } setups[1].spec = spec end
        end
    end
    for n = 1, 4 do
        if setups[n] then
            setups[n].group = groupOf[n]
            p.specs[#p.specs + 1] = setups[n]
        end
    end
    return I.Normalize(p)
end
