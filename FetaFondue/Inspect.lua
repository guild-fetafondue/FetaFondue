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
I.ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DPS = "DPS", FERAL = "Tank or DPS" }
I.ROLE_COLOR = { TANK = "ff4a9fff", HEALER = "ff40ff40", DPS = "ffff5050", FERAL = "ffffa040" }

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

-- The talent setups of MY character: the active one, and (dual specialization) the other one.
-- Each: { spec = specialization id, ranks = { [nodeID] = rank }, active = true/false }.
-- The other setup is read from the game's saved talent configs of the class (unverified on WoW Forever
-- until somebody with dual specialization runs /ff talentprobe).
local function CaptureOwnSpecs(level)
    local specs = {}
    if not ns.worldReady then return specs end       -- not right at login (see ns.worldReady in Core.lua)
    local specID = OwnSpecID() or 0
    local active = ActiveConfigID()
    if not active then return specs end
    local ranks = ReadRanks(active)
    specs[1] = { spec = specID, ranks = ranks, active = true }
    I.GetLayout(specID, level, active)      -- my own tree is the cheapest way to learn my class's layout

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
    return I.RoleFor(profile.class, points)
end

-- one letter for sharing: T, H, D (and F for Feral druids, counted with damage dealers elsewhere)
local ROLE_CODE = { TANK = "T", HEALER = "H", DPS = "D", FERAL = "F" }
I.ROLE_CODE = ROLE_CODE
I.CODE_ROLE = { T = "TANK", H = "HEALER", D = "DPS", F = "FERAL" }

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
                    merged.specs[#merged.specs + 1] = { spec = sp.spec, ranks = scanSpec.ranks, active = true }
                else
                    merged.specs[#merged.specs + 1] = { spec = sp.spec, ranks = sp.ranks, active = false }
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
    local setups = {}
    for part in str:gmatch("[^|]+") do
        local kind = part:sub(1, 1)
        if kind == "h" then
            local level, race, class = part:match("^h=(%d+),([^,]*),(.*)$")
            if level then p.level, p.race, p.class = tonumber(level), race, class end
        elseif kind == "o" then
            p.src = part:sub(3, 3) == "S" and "scan" or "owner"
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
        elseif kind == "p" then   -- older senders: the specialization id of their single setup
            local spec = tonumber(part:match("^p=(%d+)$"))
            if spec then setups[1] = setups[1] or { ranks = {}, active = true } setups[1].spec = spec end
        end
    end
    for n = 1, 4 do if setups[n] then p.specs[#p.specs + 1] = setups[n] end end
    return I.Normalize(p)
end
