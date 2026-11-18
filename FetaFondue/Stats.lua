---@class ns
local ns = select(2, ...)

-- FetaFondue Now:     read from the guild roster (needs nobody else to run the addon).
-- FetaFondue Forever: lifetime counters (dungeons cleared, bosses killed, crafts, gold looted and made at the auction house).
-- Every character counts its own and shares the numbers over the guild channel; the guild total is
-- the sum over everybody we know about. Three more counters (fish caught, deaths from falling, times camped) are read from
-- the game's own Statistics, and the gold in the guild bank is remembered when somebody looks into it.

local T = {}
ns.Stats = T

local PEER_TTL = 14 * 24 * 3600 -- a guildie counts as "running the addon" for 14 days after we last heard from them

---------------------------------------------------------------------------
-- FetaFondue Now
---------------------------------------------------------------------------
local function ZoneMatches(list, zone)
    for _, z in ipairs(list) do
        if zone:find(z, 1, true) then return true end
    end
    return false
end

-- The zone names above are English. The roster shows zone names in the language of the client that LOOKS at
-- it, so every client also learns the names of the same places in its own language from the game (by the
-- instance id and the map id of the capitals).
local localZones = { raid = {}, dungeon = {}, capital = {} }
local ZONE_IDS = {
    raid = { 409, 249, 469, 309, 509, 531, 533 },
    dungeon = { 389, 36, 43, 33, 48, 34, 90, 47, 189, 129, 70, 209, 349, 109, 230, 229, 429, 289, 329 },
}
local CAPITAL_MAPS = { 1453, 1455, 1457, 1454, 1456, 1458 }

function T.LocalizeZones()
    local here
    pcall(function() here = GetRealZoneText and GetRealZoneText() end)
    local function AddName(kind, name)
        if type(name) == "string" and name ~= "" and name ~= here then
            local n = name:lower()
            for _, have in ipairs(localZones[kind]) do if have == n then return end end
            table.insert(localZones[kind], n)
        end
    end
    for kind, ids in pairs(ZONE_IDS) do
        for _, id in ipairs(ids) do
            pcall(function() AddName(kind, GetRealZoneText and GetRealZoneText(id)) end)
        end
    end
    for _, mapID in ipairs(CAPITAL_MAPS) do
        pcall(function()
            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
            AddName("capital", info and info.name)
        end)
    end
end

-- "raid", "dungeon", "capital" or nil (open world)
local function ZoneKind(zone)
    if type(zone) ~= "string" or zone == "" then return nil end
    zone = zone:lower()
    for _, kind in ipairs({ "raid", "dungeon", "capital" }) do
        if ZoneMatches(ns.ZONES[kind], zone) or ZoneMatches(ns.DB.extraZones[kind], zone) or ZoneMatches(localZones[kind], zone) then return kind end
    end
    return nil
end
T.ZoneKind = ZoneKind

local function IsAFK(status)
    if type(status) == "number" then return status == 1 end
    if type(status) == "string" then
        local s = status:upper()
        return s:find("AFK", 1, true) ~= nil or s:find("AWAY", 1, true) ~= nil
    end
    return false
end

-- Every online guildie lands in exactly one bucket: afk, raid, dungeon, capital or world.
function ns.GetNowStats()
    if ns.DB and ns.DB.demo then
        return { members = 24, online = 17, afk = 2, raid = 3, dungeon = 5, capital = 2, world = 5 }
    end
    local s = { members = 0, online = 0, afk = 0, raid = 0, dungeon = 0, capital = 0, world = 0 }
    if not IsInGuild() then return s end
    local roster = ns.GetRoster()
    s.members = roster.total
    for _, e in ipairs(roster.list) do
        if e.online then
            s.online = s.online + 1
            if IsAFK(e.status) then
                s.afk = s.afk + 1
            else
                local kind = ZoneKind(e.zone)
                if kind then s[kind] = s[kind] + 1 else s.world = s.world + 1 end
            end
        end
    end
    return s
end

-- Online guildies with what we know about them (for the dashboard list and its tooltips).
-- If the character shares an installation with an older one (one that submitted data first), returns that
-- original character's guid and name; nil for originals and for characters we know nothing about.
function ns.GetOriginalOf(guid)
    -- 1. what an officer set (it wins over any guess)
    local links = ns.GetAltLinks() or {}
    local link = links[guid]
    if link and link.main ~= "x" then
        if link.main == "-" then return nil end                 -- set as a main
        local roster = ns.GetRoster()
        local entry = roster.byGUID[link.main]
        local m = (ns.GetMembers() or {})[link.main]
        local name = (entry and entry.name) or (m and m.name)
        if name and link.main ~= guid then return link.main, name, "set" end
    end

    -- 2. the guess: the oldest character of the same installation
    local members = ns.GetMembers() or {}
    local function ClientOf(g, m) return m.client or (ns.IsMine(g) and ns.DB.clientID) or nil end
    local me = members[guid]
    local client = me and ClientOf(guid, me)
    if not client then return nil end
    local best, bestAge
    for g, m in pairs(members) do
        if ClientOf(g, m) == client then
            local age = m.created or math.huge
            if not best or age < bestAge or (age == bestAge and tostring(g) < tostring(best)) then best, bestAge = g, age end
        end
    end
    if best and best ~= guid then return best, members[best].name, "auto" end
    return nil
end

-- the characters of the guild that are alts of this one: { "Name", ... } sorted (empty for an alt or a character without alts)
function ns.GetAltsOf(guid)
    local out = {}
    if not guid then return out end
    for _, e in ipairs(ns.GetRoster().list) do
        if e.guid and e.guid ~= guid then
            local main = ns.GetOriginalOf(e.guid)
            if main == guid then out[#out + 1] = ns.DisplayName(e.name) end
        end
    end
    table.sort(out)
    return out
end

-- my own characters and my known alts: everything that hangs together with this character (the same main, the officers' alt
-- links or the automatic guess) plus every character of mine on this account. { [guid] = true } (not including this character)
function ns.GetMyFamilyGUIDs()
    local out = {}
    local me = ns.myGUID
    if not me then return out end
    local main = ns.GetOriginalOf(me) or me
    out[main] = true
    for _, e in ipairs(ns.GetRoster().list) do
        if e.guid and (e.guid == main or ns.GetOriginalOf(e.guid) == main) then out[e.guid] = true end
    end
    for guid in pairs((ns.DB and ns.DB.mine) or {}) do out[guid] = true end
    out[me] = nil
    return out
end

-- the professions of a character we have data about: { { name, rank }, ... } by name (empty when we know nothing)
function ns.GetProfessionList(guid)
    local list = {}
    local m = guid and (ns.GetMembers() or {})[guid]
    if m then
        for key, p in pairs(m.profs or {}) do
            list[#list + 1] = { name = ns.Professions.ProfessionName(key, p.name), rank = p.rank or 0 }
        end
        table.sort(list, function(a, b) return a.name < b.name end)
    end
    return list
end

function ns.GetOnlineMembers(includeOffline)
    local out = {}
    if not IsInGuild() then return out end
    local members = ns.GetMembers() or {}
    local roster = ns.GetRoster()
    for _, e in ipairs(roster.list) do
        if e.online or includeOffline then
            local m = e.guid and members[e.guid] or nil
            local _, originalName, altSource = ns.GetOriginalOf(e.guid)
            local originalShown = originalName and ns.DisplayName(originalName) or nil
            out[#out + 1] = {
                altOf = originalShown and originalShown:match("^(%S+)") or nil, altOfFull = originalShown, altSource = altSource,
                online = e.online and true or false,
                name = ns.DisplayName(e.name), fullName = e.name, guid = e.guid, level = e.level, class = e.class,
                classDisplay = e.classDisplay, rank = e.rank, zone = e.zone, note = e.note,
                afk = IsAFK(e.status), kind = ZoneKind(e.zone), profs = ns.GetProfessionList(e.guid),
                stats = m and m.stats or nil, mine = e.guid ~= nil and e.guid == ns.myGUID,
            }
        end
    end
    -- the ones who are online first (all of them are when offline guildies are not asked for)
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return out
end

-- The highest level in the guild (online or not) and everybody who has it: level, { {name, class}, ... }
-- the characters we have data about (still in the guild), with their guid
local function KnownCharacters()
    local out = {}
    local roster = ns.GetRoster()
    for guid, m in pairs(ns.GetMembers() or {}) do
        local entry = ns.FindRosterEntry(roster, guid, m.name)
        if roster.total == 0 or entry then out[#out + 1] = { guid = guid, m = m, name = ns.DisplayName(entry and entry.name or m.name), online = entry and entry.online or false, class = entry and entry.class } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- How many characters have each profession: { { key, name, icon, count, names }, ... } most common first, the biggest count
function ns.GetProfessionDistribution()
    local counts, names, classes, ranks = {}, {}, {}, {}
    if ns.DB and ns.DB.demo then
        counts = { ["171"] = 6, ["164"] = 9, ["333"] = 4, ["202"] = 5, ["182"] = 8, ["165"] = 11, ["186"] = 7, ["393"] = 10, ["197"] = 6, ["185"] = 14, ["129"] = 12, ["356"] = 9 }
    else
        for _, c in ipairs(KnownCharacters()) do
            for key in pairs(c.m.profs) do
                counts[key] = (counts[key] or 0) + 1
                names[key] = names[key] or {}
                classes[key] = classes[key] or {}
                ranks[key] = ranks[key] or {}
                table.insert(names[key], c.name)
                table.insert(classes[key], c.class or "")
                table.insert(ranks[key], (c.m.profs[key].rank or 0) > 0 and tostring(c.m.profs[key].rank) or "")
            end
        end
    end
    local list, biggest = {}, 0
    for _, id in ipairs(ns.PROFESSION_ORDER) do
        local key = tostring(id)
        local n = counts[key] or 0
        list[#list + 1] = { key = key, name = ns.PROFESSIONS[id] or key, icon = ns.PROFESSION_ICONS[id], count = n, names = names[key] or {}, classes = classes[key] or {}, levels = ranks[key] or {} }
        if n > biggest then biggest = n end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return list, biggest
end

-- What race each character is: { { name, count, names }, ... } most common first, total with a known race
function ns.GetRaceDistribution()
    local counts, names, classes, total = {}, {}, {}, 0
    if ns.DB and ns.DB.demo then
        for race, n in pairs({ Troll = 7, Orc = 6, Undead = 5, Tauren = 4, ["Night Elf"] = 3, Human = 2 }) do counts[race] = n total = total + n names[race] = {} classes[race] = {} end
    else
        for _, c in ipairs(KnownCharacters()) do
            local race = c.m.race
            if (not race or race == "") and ns.DB.inspect and ns.DB.inspect[c.guid] then race = ns.DB.inspect[c.guid].race end
            if race and race ~= "" then
                race = ns.RaceName(race)
                counts[race] = (counts[race] or 0) + 1
                names[race] = names[race] or {}
                classes[race] = classes[race] or {}
                table.insert(names[race], c.name)
                table.insert(classes[race], c.class or "")
                total = total + 1
            end
        end
    end
    local list, biggest = {}, 0
    for race, n in pairs(counts) do
        list[#list + 1] = { name = race, count = n, names = names[race] or {}, classes = classes[race] or {} }
        if n > biggest then biggest = n end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return list, total, biggest
end

-- Tank, healer or damage (from the talents): { { key, label, count, names } x3 }, total known, characters unknown
function ns.GetRoleDistribution()
    local order = { { "TANK", "Tanks" }, { "HEALER", "Healers" }, { "DPS", "DPS" } }
    local rows = { TANK = { names = {}, classes = {} }, HEALER = { names = {}, classes = {} }, DPS = { names = {}, classes = {} } }
    local known, unknown, unkNames, unkClasses = 0, 0, {}, {}
    if ns.DB and ns.DB.demo then
        rows.TANK.count, rows.HEALER.count, rows.DPS.count = 4, 6, 14
        known, unknown = 24, 3
    else
        for _, c in ipairs(KnownCharacters()) do
            local role
            local code = c.m.role
            if code and code ~= "" then role = ns.Inspect and ns.Inspect.CODE_ROLE[code]
            elseif ns.DB.inspect and ns.DB.inspect[c.guid] and ns.Inspect then
                local _, r = ns.Inspect.RoleOfProfile(ns.DB.inspect[c.guid])
                role = r
            end
            if role == "FERAL" then role = "DPS" end          -- Feral can tank or deal damage: counted with damage
            if role and rows[role] then
                rows[role].count = (rows[role].count or 0) + 1
                table.insert(rows[role].names, c.name)
                table.insert(rows[role].classes, c.class or "")
                known = known + 1
            else
                unknown = unknown + 1
                table.insert(unkNames, c.name)
                table.insert(unkClasses, c.class or "")
            end
        end
    end
    local list, biggest = {}, 0
    for _, o in ipairs(order) do
        local r = rows[o[1]]
        r.count = r.count or 0
        list[#list + 1] = { key = o[1], label = o[2], count = r.count, names = r.names, classes = r.classes }
        if r.count > biggest then biggest = r.count end
    end
    return list, known, unknown, biggest, unkNames, unkClasses
end

-- Which talent tree each character mainly plays, as the player details show it ("Enhancement Shaman"): { { label, count, names, classes, class } },
-- grouped by class (the class with the most common spec first), known, unknown, biggest, unknown names and classes. The tree is shared by every addon user (PS message) or comes from an
-- inspect profile we hold.
function ns.GetSpecDistribution()
    local rows, order, known, unknown, unkNames, unkClasses = {}, {}, 0, 0, {}, {}
    if ns.DB and ns.DB.demo then
        return { { label = "Fury Warrior", count = 5, names = {}, classes = {}, class = "WARRIOR" }, { label = "Frost Mage", count = 4, names = {}, classes = {}, class = "MAGE" } }, 9, 3, 5, {}, {}
    end
    for _, c in ipairs(KnownCharacters()) do
        local tree = c.m.tree
        if (not tree or tree == "") and ns.Inspect and ns.DB.inspect and ns.DB.inspect[c.guid] then tree = ns.Inspect.TreeOfProfile(ns.DB.inspect[c.guid]) end
        if tree and tree ~= "" then
            local class = (LOCALIZED_CLASS_NAMES_MALE and c.class and LOCALIZED_CLASS_NAMES_MALE[c.class]) or (c.class and (c.class:sub(1, 1) .. c.class:sub(2):lower())) or ""
            local label = class ~= "" and (tree .. " " .. class) or tree
            local r = rows[label]
            if not r then r = { label = label, count = 0, names = {}, classes = {}, class = c.class } rows[label] = r order[#order + 1] = r end
            r.count = r.count + 1
            table.insert(r.names, c.name)
            table.insert(r.classes, c.class or "")
            known = known + 1
        else
            unknown = unknown + 1
            table.insert(unkNames, c.name)
            table.insert(unkClasses, c.class or "")
        end
    end
    -- grouped by class: the class whose best spec has the most characters comes first (then the class with more characters
    -- overall); inside a class the more common spec comes first
    local classBest, classAll = {}, {}
    for _, r in ipairs(order) do
        local k = r.class or ""
        classBest[k] = math.max(classBest[k] or 0, r.count)
        classAll[k] = (classAll[k] or 0) + r.count
    end
    table.sort(order, function(a, b)
        local ka, kb = a.class or "", b.class or ""
        if ka ~= kb then
            if classBest[ka] ~= classBest[kb] then return classBest[ka] > classBest[kb] end
            if classAll[ka] ~= classAll[kb] then return classAll[ka] > classAll[kb] end
            return ka < kb
        end
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    local biggest = 0
    for _, r in ipairs(order) do if r.count > biggest then biggest = r.count end end
    biggest = math.max(biggest, unknown)
    return order, known, unknown, biggest, unkNames, unkClasses
end

-- Mains and alts: an alt is a character an officer linked to another one or that shares an installation with an older character.
-- A main is known as one when we know its installation (or an officer set it); characters we know nothing about are not counted.
function ns.GetMainAltDistribution()
    local rows = {
        { key = "MAIN", label = "Mains", count = 0, names = {}, classes = {} },
        { key = "ALT", label = "Alts", count = 0, names = {}, classes = {} },
    }
    if ns.DB and ns.DB.demo then
        rows[1].count, rows[2].count = 12, 9
        return rows, 21, 12
    end
    local links = ns.GetAltLinks() or {}
    local total, biggest = 0, 0
    for _, c in ipairs(KnownCharacters()) do
        local row
        if ns.GetOriginalOf(c.guid) then
            row = rows[2]
        elseif (links[c.guid] and links[c.guid].main == "-") or c.m.client or ns.IsMine(c.guid) then
            row = rows[1]
        end
        if row then
            row.count = row.count + 1
            table.insert(row.names, c.name)
            table.insert(row.classes, c.class or "")
            total = total + 1
        end
    end
    for _, r in ipairs(rows) do if r.count > biggest then biggest = r.count end end
    return rows, total, biggest
end

-- Professions that are not counted in the recipe chart (they have no recipes worth comparing)
local NO_RECIPE_CHART = { ["129"] = true, ["182"] = true, ["186"] = true, ["356"] = true, ["393"] = true }

-- How many different recipes the guild knows together per profession (a recipe known by several characters counts once):
-- { { key, name, icon, count, names, classes }, ... } most recipes first, the total, the biggest count
function ns.GetRecipeDistribution()
    local sets, who = {}, {}
    if ns.DB and ns.DB.demo then
        local list = {}
        for i, id in ipairs({ 171, 164, 333, 202, 165, 197, 185, 755 }) do
            list[i] = { key = tostring(id), name = ns.PROFESSIONS[id] or tostring(id), icon = ns.PROFESSION_ICONS[id], count = 120 - i * 9, names = {}, classes = {} }
        end
        return list, 600, 111
    end
    for _, c in ipairs(KnownCharacters()) do
        for key, p in pairs(c.m.profs or {}) do
            if not NO_RECIPE_CHART[tostring(key)] and tonumber(key) then
                sets[key] = sets[key] or {}
                who[key] = who[key] or { names = {}, classes = {}, profs = {} }
                for _, id in ipairs(p.ids or {}) do sets[key][id] = true end
                table.insert(who[key].names, c.name)
                table.insert(who[key].classes, c.class or "")
                -- how many recipes this character knows in this profession (each only once)
                local own, n = {}, 0
                for _, id in ipairs(p.ids or {}) do if not own[id] then own[id] = true n = n + 1 end end
                table.insert(who[key].profs, tostring(n))
            end
        end
    end
    local list, total, biggest = {}, 0, 0
    for _, id in ipairs(ns.PROFESSION_ORDER) do
        local key = tostring(id)
        if not NO_RECIPE_CHART[key] then
            local n = 0
            for _ in pairs(sets[key] or {}) do n = n + 1 end
            local w = who[key] or { names = {}, classes = {}, profs = {} }
            -- the characters with the most recipes first
            do
                local idx = {}
                for i = 1, #w.names do idx[i] = i end
                table.sort(idx, function(x, y)
                    local nx, ny = tonumber(w.profs[x]) or 0, tonumber(w.profs[y]) or 0
                    if nx ~= ny then return nx > ny end
                    return w.names[x] < w.names[y]
                end)
                local nn, cc, pp = {}, {}, {}
                for i, j in ipairs(idx) do nn[i], cc[i], pp[i] = w.names[j], w.classes[j], w.profs[j] end
                w = { names = nn, classes = cc, profs = pp }
            end
            list[#list + 1] = { key = key, name = ns.PROFESSIONS[id] or key, icon = ns.PROFESSION_ICONS[id], count = n, names = w.names, classes = w.classes, levels = w.profs or {} }
            total = total + n
            if n > biggest then biggest = n end
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return list, total, biggest
end

-- How many characters have each profession specialization: { { id, key, name, short, icon, count, names, classes } ... } grouped by profession
function ns.GetSpecializationDistribution()
    local out, biggest, total = {}, 0, 0
    if not ns.Specs then return out, 0, 0 end
    local demo = ns.DB and ns.DB.demo
    for _, key in ipairs(ns.Specs.ORDER) do
        for _, id in ipairs(ns.Specs.SpecsOf(key)) do
            local names, classes = {}, {}
            for _, h in ipairs(ns.Specs.Holders(id)) do
                local entry = ns.GetRoster().byGUID[h.guid]
                table.insert(names, ns.DisplayName(h.member.name or "?"))
                table.insert(classes, entry and entry.class or "")
            end
            local n = #names
            if demo then n = (id % 7) + 1 end
            out[#out + 1] = { id = id, key = key, name = (ns.Specs.SpecName(id)), short = ns.Specs.ShortName(id), icon = ns.Specs.SpecIcon(id), count = n, names = names, classes = classes }
            total = total + n
            if n > biggest then biggest = n end
        end
    end
return out, total, biggest
end

-- How many guild members are at which levels: { { from, to, count }, ... } in steps of ten, total, largest count
function ns.GetLevelDistribution()
    local counts, top, total = {}, 0, 0
    local members = {}        -- [bucket] = { { name, class, level } }
    if ns.DB and ns.DB.demo then
        counts = { 2, 3, 4, 6, 5, 9 }
        top = 60
    elseif IsInGuild() then
        for _, e in ipairs(ns.GetRoster().list) do
            local level = tonumber(e.level) or 0
            if level > 1 then   -- level 1s (fresh characters) are left out of the chart
                local bucket = math.ceil(level / 10)
                counts[bucket] = (counts[bucket] or 0) + 1
                members[bucket] = members[bucket] or {}
                table.insert(members[bucket], { name = ns.DisplayName(e.name), class = e.class, level = level })
                if level > top then top = level end
            end
        end
    end
    local buckets, biggest = {}, 0
    for b = 1, math.max(6, math.ceil(top / 10)) do
        local n = counts[b] or 0
        local list = members[b] or {}
        table.sort(list, function(x, y)
            if x.level ~= y.level then return x.level > y.level end
            return x.name < y.name
        end)
        local names, classes, levels = {}, {}, {}
        for i, m in ipairs(list) do names[i], classes[i], levels[i] = m.name, m.class or "", m.level end
        buckets[b] = { from = (b - 1) * 10 + 1, to = b * 10, count = n, names = names, classes = classes, levels = levels }
        total = total + n
        if n > biggest then biggest = n end
    end
    return buckets, total, biggest
end

---------------------------------------------------------------------------
-- FetaFondue Forever: totals
---------------------------------------------------------------------------
-- dungeons, bosses, crafts, gold (in copper), number of characters reporting
function ns.GetForeverStats()
    if ns.DB and ns.DB.demo then return 47, 47, 283, 123456700, 24, 17 end
    local d, b, c, g, n = 0, 0, 0, 0, 0
    local clients, users = {}, 0
    local members = ns.GetMembers()
    if members then
        for guid, m in pairs(members) do
            local st = m.stats
            if st then
                -- crafts without smelting where the character reports them (0.30 and newer), else the old total
                d, b, c, g, n = d + st.d, b + st.b, c + (st.cx or st.c), g + st.g, n + 1
                -- characters of the same installation count as one user (unknown: every character is a user)
                local client = m.client or (ns.IsMine(guid) and ns.DB.clientID) or ("c:" .. tostring(guid))
                if not clients[client] then
                    clients[client] = true
                    users = users + 1
                end
            end
        end
    end
    -- what people who have left the guild contributed stays in the totals
    local gname = ns.guildName
    local archived = gname and ns.DB.guilds[gname] and ns.DB.guilds[gname].archived
    if archived then d, b, c, g = d + archived.d, b + archived.b, c + archived.c, g + archived.g end
    return d, b, c, g, n, users
end

local function Credit(field, amount)
    local own = ns.GetOwn()
    if not (own and own.stats) then return end
    own.stats[field] = own.stats[field] + (amount or 1)
    own.stats.rev = math.max(ns.Time(), (own.stats.rev or 0) + 1)   -- strictly newer, even within the same second
    if ns.Sync then ns.Sync.OnStatsChanged() end
    if ns.RefreshUI then ns.RefreshUI() end
end

local HookMail   -- defined with the mail code below

function T.Init()
    T.ResetMoney()
    ns.After(10, T.LocalizeZones)
    local own = ns.GetOwn()
    if not own then return end
    own.stats = own.stats or { d = 0, b = 0, c = 0, g = 0, rev = 0 }
    -- crafts without smelting (the Crafts tile of the dashboard and the "sweatiest crafter"). Crafts counted before this existed cannot be split into
    -- smelting and the rest: a character without Mining has no smelting, so its total is exact; with Mining it starts at 0.
    if own.stats.cx == nil then
        local hasMining = false
        for key in pairs(own.profs or {}) do if tostring(key) == "186" then hasMining = true end end
        own.stats.cx = hasMining and 0 or (own.stats.c or 0)
    end
    if (own.stats.rev or 0) == 0 then own.stats.rev = ns.Time() end
    T.RebuildRecipes()
    T.UpdateRun()
    HookMail()
    T.StartGameStats()
end

---------------------------------------------------------------------------
-- Dungeon runs: 5-man instances with 2 or more guildies in the group
---------------------------------------------------------------------------
local run = { id = nil, killed = {}, cleared = false }
local encounterSeen = false -- true once the client has fired a real boss/encounter event
local BaselineScenario

function T.UpdateRun()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "party" then
        local instanceID = select(8, GetInstanceInfo())
        if run.id ~= instanceID then
            run = { id = instanceID, killed = {}, cleared = false }
            ns.After(3, BaselineScenario)
        end
    else
        run = { id = nil, killed = {}, cleared = false }
    end
end

-- Returns: number of guildies in the group (me included), and whether *I* am the one who records this
-- kill for the guild. So the same kill is not counted once per guildie, the guildie with the lowest
-- character GUID (among those running the addon) records it.
local function GroupInfo()
    local me = ns.myGUID
    local members = ns.GetMembers() or {}
    local guildies, eligible = 1, { me }
    local prefix, n
    if IsInRaid() then
        prefix, n = "raid", GetNumGroupMembers()
    else
        prefix, n = "party", GetNumSubgroupMembers()
    end
    for i = 1, n do
        local unit = prefix .. i
        pcall(function()
            if UnitExists(unit) and not UnitIsUnit(unit, "player")
                and UnitIsInMyGuild and UnitIsInMyGuild(unit) then
                guildies = guildies + 1
                local guid = UnitGUID(unit)
                local st = guid and members[guid] and members[guid].stats
                if st and (ns.Time() - (st.seen or 0)) < PEER_TTL then
                    eligible[#eligible + 1] = guid
                end
            end
        end)
    end
    table.sort(eligible)
    return guildies, eligible[1] == me
end

local function IsFinalBoss(key)
    if ns.FINAL_BOSSES[key] or ns.DB.extraFinalBosses[key] then return true end
    for final in pairs(ns.FINAL_BOSSES) do
        if key:find(final, 1, true) then return true end
    end
    for final in pairs(ns.DB.extraFinalBosses) do
        if key:find(final, 1, true) then return true end
    end
    return false
end

-- Raids: the guild clears one when its last boss dies with enough guildies in the group (RAID_MIN, see Achievements.lua).
-- What the game says in a raid is remembered (for /ff raids) so that the details can be filled in.
local raidSeen = {}
local function Lc(text) return ns.Lower and ns.Lower(text) or tostring(text or ""):lower() end

local function RaidFor(instanceName, instanceID)
    local lname = Lc(instanceName)
    for _, raid in ipairs(ns.RAID_CLEARS or {}) do
        for _, id in ipairs(raid.ids) do if instanceID and id == instanceID then return raid end end
        for _, id in ipairs((ns.DB.extraRaidIDs[raid.key] or {})) do if instanceID and id == instanceID then return raid end end
        for _, n in ipairs(raid.names) do if lname == n or (lname ~= "" and lname:find(n, 1, true)) then return raid end end
    end
    return nil
end

local function IsRaidFinal(raid, key, encounterID)
    local extra = ns.DB.extraRaidFinal and ns.DB.extraRaidFinal[raid.key] or {}
    if encounterID and encounterID ~= 0 then
        for _, id in ipairs(raid.finalIDs) do if id == encounterID then return true end end
        for _, id in ipairs(extra.ids or {}) do if id == encounterID then return true end end
    end
    -- (the whole name: "Onyxia" is the last boss, not everything that has her name in it)
    for _, n in ipairs(raid.final) do if key == n then return true end end
    for _, n in ipairs(extra.names or {}) do if key == n then return true end end
    return false
end

-- returns true when we are in a raid (the kill is not a dungeon boss then)
local function OnRaidBossDown(name, encounterID)
    local inInstance, instanceType = IsInInstance()
    if not (inInstance and instanceType == "raid") then return false end
    local iname, _, _, _, _, _, _, iid = GetInstanceInfo()
    table.insert(raidSeen, { instance = iname, id = iid, boss = name, encounterID = encounterID, at = ns.Time() })
    while #raidSeen > 30 do table.remove(raidSeen, 1) end
    local raid = RaidFor(iname, iid)
    if not raid or not name then return true end
    local A = ns.Achievements
    if not A then return true end
    if not A.criteriaRead then A.ScanRaidCriteria() end                   -- (the game's steps, if they were not asked yet)
    local guildies = GroupInfo()
    if guildies < A.RAID_MIN then return true end
    -- Both ways together: when the game lists the steps of the raid achievement, a step is done by the death of its boss
    -- (only with enough guildies in the group) and the guild has it when all steps are done. Without steps from the game
    -- the death of the last boss is enough. Every addon in the group that knows the raid records it (a client on another language
    -- may not know the raid by its name: the others still do); the same from several of them is one.
    if #A.TrackedCriteria(raid.key) > 0 then
        A.RecordBossKill(raid.key, name, encounterID)
    elseif IsRaidFinal(raid, Lc(name), encounterID) then
        A.RecordRaidClear(raid.key)
    end
    return true
end

function T.RaidSeen() return raidSeen end

-- /ff raids
function T.PrintRaids()
    ns.Print("Raids that count for the guild's raid achievements (a clear = the last boss dies with 5 or more guildies in the group):")
    for _, raid in ipairs(ns.RAID_CLEARS) do
        local extra = ns.DB.extraRaidFinal[raid.key] or {}
        local ids, names = {}, {}
        for _, v in ipairs(raid.ids) do ids[#ids + 1] = tostring(v) end
        for _, v in ipairs(ns.DB.extraRaidIDs[raid.key] or {}) do ids[#ids + 1] = tostring(v) .. " (added)" end
        for _, v in ipairs(raid.final) do names[#names + 1] = v end
        for _, v in ipairs(raid.finalIDs) do names[#names + 1] = "#" .. v end
        for _, v in ipairs(extra.names or {}) do names[#names + 1] = v .. " (added)" end
        for _, v in ipairs(extra.ids or {}) do names[#names + 1] = "#" .. v .. " (added)" end
        ns.Print(("  %s: instance ids [%s], last boss [%s]"):format(raid.short, table.concat(ids, ","), #names > 0 and table.concat(names, ", ") or "not known yet"))
    end
    local A = ns.Achievements
    if A then
        if A.criteriaRead == nil then A.ScanRaidCriteria() end
        ns.Print(("Steps of the game's raid achievements (read from the game: %s):"):format(tostring(A.criteriaRead ~= false and A.criteriaRead ~= nil)))
        for _, raid in ipairs(ns.RAID_CLEARS) do
            local list = A.criteria[raid.key] or {}
            if #list == 0 then
                ns.Print(("  %s: no steps from the game: the last boss counts"):format(raid.short))
            else
                local done, total = A.RaidProgress(raid.key)
                ns.Print(("  %s (achievement %s): %d steps, %d tracked, guild has %d of them"):format(raid.short, tostring(A.achievementID[raid.key]), #list, total, done))
                local tracked = {}
                for _, c in ipairs(A.TrackedCriteria(raid.key)) do tracked[c.id] = true end
                for _, c in ipairs(list) do
                    ns.Print(("    #%s %s (type %s, boss number %s)%s"):format(tostring(c.id), tostring(c.name), tostring(c.type), tostring(c.asset), tracked[c.id] and "" or " - set aside"))
                end
            end
        end
    end
    if #raidSeen == 0 then
        ns.Print("Nothing seen yet: kill a boss in a raid and type /ff raids again to see what the game reports.")
    else
        ns.Print("What the game reported for boss kills in raids (newest last):")
        for _, e in ipairs(raidSeen) do
            ns.Print(("  %s (instance id %s): %s (encounter id %s)"):format(tostring(e.instance), tostring(e.id), tostring(e.boss), tostring(e.encounterID)))
        end
    end
end

-- /ff raidcrit hyjal ignore 12345  (or use): set a step of a raid achievement aside (it is not a boss kill) or take it back.
-- This is saved on this computer only: when it is known which steps are no bosses, it belongs in the code (ignoreCriteria in Data.lua).
function T.RaidCrit(input)
    local word, action, id = tostring(input or ""):match("^%s*%S+%s+(%S+)%s+(%S+)%s+(%d+)%s*$")
    local raid
    for _, r in ipairs(ns.RAID_CLEARS) do if r.short == (word or ""):lower() then raid = r end end
    if not (raid and (action == "ignore" or action == "use")) then
        ns.Print("Usage: /ff raidcrit <onyxia|hyjal|barrow> <ignore|use> <step number> (the numbers are shown by /ff raids)")
        return
    end
    ns.DB.ignoredCriteria[raid.key] = ns.DB.ignoredCriteria[raid.key] or {}
    ns.DB.ignoredCriteria[raid.key][tonumber(id)] = (action == "ignore") or nil
    ns.Print(("Step %s of %s is %s."):format(id, raid.short, action == "ignore" and "set aside" or "counted again"))
    if ns.Achievements then ns.Achievements.EvaluateRaid(raid.key) end
end

-- /ff addraidid barrow 1234: the id of the instance (shown by /ff raids), the same in every language
function T.AddRaidID(input)
    local word, rest = tostring(input or ""):match("^%s*%S+%s+(%S+)%s+(%d+)%s*$")
    local raid
    for _, r in ipairs(ns.RAID_CLEARS) do if r.short == (word or ""):lower() then raid = r end end
    if not (raid and rest) then
        ns.Print("Usage: /ff addraidid <onyxia|hyjal|barrow> <instance id> (the id is shown by /ff raids after you killed a boss in the raid)")
        return
    end
    ns.DB.extraRaidIDs[raid.key] = ns.DB.extraRaidIDs[raid.key] or {}
    table.insert(ns.DB.extraRaidIDs[raid.key], tonumber(rest))
    ns.Print(("Added: instance %s is the raid %s."):format(rest, raid.short))
end

-- /ff addraidboss onyxia Onyxia   or   /ff addraidboss barrow 1234
function T.AddRaidBoss(input)
    local word, rest = tostring(input or ""):match("^%s*%S+%s+(%S+)%s+(.-)%s*$")
    local raid
    for _, r in ipairs(ns.RAID_CLEARS) do if r.short == (word or ""):lower() then raid = r end end
    if not (raid and rest and rest ~= "") then
        ns.Print("Usage: /ff addraidboss <onyxia|hyjal|barrow> <name of the last boss, or its encounter id>")
        return
    end
    ns.DB.extraRaidFinal[raid.key] = ns.DB.extraRaidFinal[raid.key] or { names = {}, ids = {} }
    local entry = ns.DB.extraRaidFinal[raid.key]
    local id = tonumber(rest)
    if id then table.insert(entry.ids, id) else table.insert(entry.names, rest:lower()) end
    ns.Print(("Added: %s counts as the last boss of %s."):format(rest, raid.short))
end

local function OnBossDown(name, source, encounterID)
    ns.Debug(("boss down via %s: %s"):format(source, tostring(name)))
    if OnRaidBossDown(name, encounterID) then return end
    T.UpdateRun()
    if not run.id or not name then return end

    local key = tostring(name):lower()
    if run.killed[key] then return end
    run.killed[key] = true

    local guildies, iRecord = GroupInfo()
    local isFinal = IsFinalBoss(key)
    -- Names are language dependent, ids are not: a client that knows the name teaches the id to everybody
    if encounterID and encounterID ~= 0 and ns.NOT_FINAL_BOSSES[key] then
        ns.DB.finalBossIDs[encounterID] = nil          -- (an id that older versions taught as a final boss, but is not)
        isFinal = false
    elseif encounterID and encounterID ~= 0 then
        if isFinal and not ns.DB.finalBossIDs[encounterID] then
            ns.DB.finalBossIDs[encounterID] = true
            if ns.Sync and ns.Sync.AdvertiseBossIDs then ns.After(5, ns.Sync.AdvertiseBossIDs) end
        elseif ns.DB.finalBossIDs[encounterID] then
            isFinal = true
        end
    end
    if guildies >= 2 and iRecord then
        Credit("b")
        if isFinal and not run.cleared then Credit("d") end
    end
    if isFinal then run.cleared = true end
end

-- Backup: the instance's own objectives (scenario criteria), used only if the client never fires
-- ENCOUNTER_END / BOSS_KILL for old dungeons.
local scenarioDone = {}

local function ScenarioCriteria()
    local list = {}
    if not (C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo and C_ScenarioInfo.GetCriteriaInfo) then
        return list
    end
    pcall(function()
        local step = C_ScenarioInfo.GetScenarioStepInfo()
        local num = step and step.numCriteria or 0
        for i = 1, num do
            local c = C_ScenarioInfo.GetCriteriaInfo(i)
            if c and c.description then list[#list + 1] = c end
        end
    end)
    return list
end

BaselineScenario = function()
    scenarioDone = {}
    for _, c in ipairs(ScenarioCriteria()) do
        if c.completed then scenarioDone[c.description] = true end
    end
end

local function ScanScenario()
    if encounterSeen then return end
    T.UpdateRun()
    if not run.id then return end
    for _, c in ipairs(ScenarioCriteria()) do
        if c.completed and not scenarioDone[c.description] then
            scenarioDone[c.description] = true
            local desc = c.description
            -- wait a moment: if a real encounter event follows, that one wins
            ns.After(5, function()
                if not encounterSeen then OnBossDown(desc, "SCENARIO") end
            end)
        end
    end
end

function ns.ENCOUNTER_END(id, name, difficulty, size, success)
    encounterSeen = true
    ns.Debug(("ENCOUNTER_END id=%s name=%s success=%s"):format(tostring(id), tostring(name), tostring(success)))
    if success == 1 then OnBossDown(name, "ENCOUNTER_END", tonumber(id)) end
end

function ns.BOSS_KILL(id, name)
    encounterSeen = true
    ns.Debug(("BOSS_KILL id=%s name=%s"):format(tostring(id), tostring(name)))
    OnBossDown(name, "BOSS_KILL", tonumber(id))
end

-- Dungeon Finder completion: backup for when the final boss name is not in our list.
function ns.LFG_COMPLETION_REWARD()
    ns.Debug("LFG_COMPLETION_REWARD")
    T.UpdateRun()
    if not run.id or run.cleared then return end
    local guildies, iRecord = GroupInfo()
    if guildies >= 2 and iRecord then Credit("d") end
    run.cleared = true
end

function ns.SCENARIO_CRITERIA_UPDATE() ScanScenario() end
function ns.SCENARIO_UPDATE() ScanScenario() end
function ns.ZONE_CHANGED_NEW_AREA() T.UpdateRun() end

---------------------------------------------------------------------------
-- Crafts: a cast of one of my own profession recipes counts (so mage conjures, healthstones and the like
-- do not). The recipe list comes from what the profession windows showed (Professions.lua).
---------------------------------------------------------------------------
local recipeSet = {}
local smeltSet = {}      -- the recipes of the Mining window (Smelting): they do not count for the "sweatiest crafter"

function T.RebuildRecipes()
    recipeSet, smeltSet = {}, {}
    local own = ns.GetOwn()
    if not own then return end
    for key, p in pairs(own.profs) do
        for _, id in ipairs(p.ids) do
            recipeSet[id] = true
            if tostring(key) == "186" then smeltSet[id] = true end
        end
    end
end

-- Bolts of cloth and cured hides are only steps on the way to something else: they do not count as crafts (for the Crafts tile
-- and the sweatiest crafter). Known by the recipe's spell id and by the item it makes (ids, not names: the game may be in any language).
-- Crafts counted before this version stay counted.
local UNCOUNTED_SPELLS = {
    [2963] = true, [2964] = true, [3839] = true, [3865] = true, [18401] = true,        -- bolts: linen, woolen, silk, mageweave, runecloth
    [3816] = true, [3817] = true, [3818] = true, [10482] = true, [19047] = true,       -- cured hides: light, medium, heavy, thick, rugged
}
local UNCOUNTED_ITEMS = {
    [2996] = true, [2997] = true, [4305] = true, [4339] = true, [14048] = true,        -- the bolts
    [4231] = true, [4233] = true, [4236] = true, [8172] = true, [15564] = true,        -- the cured hides
}
function T.IsUncountedCraft(spellID)
    if UNCOUNTED_SPELLS[spellID] then return true end
    local info = ns.DB and ns.DB.recipeInfo and ns.DB.recipeInfo[spellID]
    return info ~= nil and info.item ~= nil and UNCOUNTED_ITEMS[info.item] == true
end

local lastCastGUID
function ns.UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
    if unit ~= "player" or not spellID then return end
    if ns.DB.debug then
        ns.Debug(("cast %s recipe=%s%s"):format(tostring(spellID), tostring(recipeSet[spellID] == true), T.IsUncountedCraft(spellID) and " (bolt or hide: not counted)" or ""))
    end
    if ns.Specs then ns.Specs.OnCast(spellID) end
    if not recipeSet[spellID] or T.IsUncountedCraft(spellID) then return end
    if castGUID and castGUID == lastCastGUID then return end
    lastCastGUID = castGUID
    local own = ns.GetOwn()
    if own and own.stats and not smeltSet[spellID] then own.stats.cx = (own.stats.cx or 0) + 1 end
    Credit("c")
end

-- Gold plundered = every copper that comes in, wherever it comes from: coins looted, your share of a group
-- loot, vendor sales, quest rewards... The game tells us when the money changes (PLAYER_MONEY); the change
-- is counted unless it happens while the mailbox, a trade or the guild bank is open: gold sent between your
-- own characters would be counted twice. (Auction house sales arrive by mail: they are counted separately
-- below, when you take the money from a "your auction sold" mail.)
local lastMoney = nil
local noCount = { mail = false, trade = false, guildBank = false }

local function Money()
    local ok, m = pcall(GetMoney)
    return ok and tonumber(m) or nil
end

function T.ResetMoney() lastMoney = Money() end

function ns.PLAYER_MONEY()
    local now = Money()
    if not now then return end
    if not lastMoney then lastMoney = now return end
    local delta = now - lastMoney
    lastMoney = now
    if delta > 0 and not (noCount.mail or noCount.trade or noCount.guildBank) then
        ns.Debug("gold in: " .. delta .. " copper")
        Credit("g", delta)
    end
end

local function Window(name, open)
    return function()
        noCount[name] = open
        lastMoney = Money()      -- whatever changed meanwhile is not counted
    end
end
ns.MAIL_SHOW, ns.MAIL_CLOSED = Window("mail", true), Window("mail", false)
ns.TRADE_SHOW, ns.TRADE_CLOSED = Window("trade", true), Window("trade", false)
local OpenBankWindow, CloseBankWindow = Window("guildBank", true), Window("guildBank", false)

---------------------------------------------------------------------------
-- Gold from auction house sales: counted when you take the money from a "your auction sold" mail.
-- Only mails with an auction invoice count; mail from other players, refunds and COD are ignored.
---------------------------------------------------------------------------
local pendingMail = {}   -- key -> { money, before, t }   (waiting for the inbox to confirm the money was taken)
local PENDING_TTL = 30

local function MailAPI(name)
    if type(_G[name]) == "function" then return _G[name] end
    if C_Mail and type(C_Mail[name]) == "function" then return C_Mail[name] end
    return nil
end

-- subject, money (copper), daysLeft of one inbox mail (works with positional or table results)
local function ReadMailHeader(index)
    local header = MailAPI("GetInboxHeaderInfo")
    if not header then return nil end
    local r1, _, _, subject, money, _, daysLeft = header(index)
    if type(r1) == "table" then
        return r1.subject, r1.money or 0, r1.daysLeft or 0
    end
    if subject == nil then return nil end
    return subject, money or 0, daysLeft or 0
end

local function MailKey(subject, money, daysLeft)
    return ("%s|%d|%.3f"):format(tostring(subject), money, daysLeft or 0)
end

local function IsAuctionSale(index)
    local invoice = MailAPI("GetInboxInvoiceInfo")
    if not invoice then return false end
    local r1 = invoice(index)
    if type(r1) == "table" then r1 = r1.invoiceType end
    return r1 == "seller"
end

local function CountMailsWithKey(key)
    local numItems = MailAPI("GetInboxNumItems")
    local n = numItems and numItems() or 0
    local found = 0
    for i = 1, n do
        local subject, money, daysLeft = ReadMailHeader(i)
        if subject and money > 0 and MailKey(subject, money, daysLeft) == key then found = found + 1 end
    end
    return found
end

-- the player took the money from mail #index (hooked below)
local function OnTakeMail(index)
    local ok = pcall(function()
        local subject, money, daysLeft = ReadMailHeader(index)
        if not subject or money <= 0 or not IsAuctionSale(index) then return end
        local key = MailKey(subject, money, daysLeft)
        local p = pendingMail[key]
        if p then
            p.t = ns.Now()
        else
            pendingMail[key] = { money = money, before = CountMailsWithKey(key), t = ns.Now() }
        end
    end)
    if not ok then ns.Debug("mail hook failed") end
end

-- The inbox changed: whatever sale mails lost their money since we looked, count them.
function ns.MAIL_INBOX_UPDATE()
    for key, p in pairs(pendingMail) do
        local ok, remaining = pcall(CountMailsWithKey, key)
        if ok and remaining < p.before then
            local taken = (p.before - remaining) * p.money
            ns.Debug(("auction sale mail: +%d copper"):format(taken))
            p.before = remaining
            Credit("g", taken)
        end
        if ns.Now() - p.t > PENDING_TTL then pendingMail[key] = nil end
    end
end

local mailHooked = false
HookMail = function()
    if mailHooked then return end
    mailHooked = true
    for _, fname in ipairs({ "TakeInboxMoney", "AutoLootMailItem" }) do
        if type(_G[fname]) == "function" then
            pcall(hooksecurefunc, fname, OnTakeMail)
        elseif C_Mail and type(C_Mail[fname]) == "function" then
            pcall(hooksecurefunc, C_Mail, fname, OnTakeMail)
        end
    end
end

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------
function T.Probe()
    local inInstance, itype = IsInInstance()
    local iname, _, _, _, _, _, _, iid = GetInstanceInfo()
    ns.Print(("In instance: %s (%s) name=%s id=%s"):format(tostring(inInstance), tostring(itype), tostring(iname), tostring(iid)))
    ns.Print(("Boss/encounter events seen this session: %s"):format(tostring(encounterSeen)))
    ns.Print(("Guild membership check (UnitIsInMyGuild): %s"):format(UnitIsInMyGuild and "available" or "MISSING"))
    local count = 0
    for _ in pairs(recipeSet) do count = count + 1 end
    ns.Print(("Recipes counted as crafts: %d"):format(count))
    local crit = ScenarioCriteria()
    ns.Print(("Instance objectives visible: %d"):format(#crit))
    local pm = _G.ProfessionMasterApi ~= nil
    local lcl = false
    if _G.LibStub then
        local ok, lib = pcall(_G.LibStub, "LibCraftLevels-1.0", true)
        lcl = ok and lib ~= nil
    end
    ns.Print(("Skill-needed data sources: Profession Master %s, LibCraftLevels %s"):format(pm and "found" or "not found", lcl and "found" or "not found"))
    local own = ns.GetOwn()
    if own and own.stats then
        local st = own.stats
        ns.Print(("Your counters: %d dungeons, %d bosses, %d crafts (smelting not counted), %d copper looted or sold"):format(st.d, st.b, st.cx or st.c, st.g))
    end
    local d, b, c, g, n = ns.GetForeverStats()
    ns.Print(("Guild totals: %d dungeons, %d bosses, %d crafts, %d copper looted or sold (%d characters reporting)"):format(d, b, c, g, n))
end

---------------------------------------------------------------------------
-- Records: who is best at something (Analytics). The same walk for every record: the characters we know that are still in
-- the guild, the highest number wins, a tie goes to the name that comes first.
---------------------------------------------------------------------------
-- valueOf(member) gives the number of a character; returns { amount, name, class } or nil when nobody has one
local function BestMember(valueOf)
    local best
    local roster = ns.GetRoster()
    for guid, m in pairs(ns.GetMembers() or {}) do
        local n = valueOf(m) or 0
        if n > 0 then
            local entry = ns.FindRosterEntry(roster, guid, m.name)
            if roster.total == 0 or entry then
                local name = ns.DisplayName(entry and entry.name or m.name)
                if not best or n > best.amount or (n == best.amount and name < best.name) then
                    best = { amount = n, name = name, class = entry and entry.class }
                end
            end
        end
    end
    return best
end

-- The guild member who has crafted the most (all professions together, smelting, bolts and cured hides not counted)
function ns.GetSweatiest()
    if ns.DB and ns.DB.demo then return { amount = 1284, name = "Garrosh", class = "WARRIOR" } end
    return BestMember(function(m) return m.stats and m.stats.cx end)
end

-- how many characters of each class the guild has (from the roster: also members without the addon)
function ns.GetClassDistribution()
    local counts, names = {}, {}
    if ns.DB and ns.DB.demo then
        counts = { WARRIOR = 5, HUNTER = 4, MAGE = 6, PRIEST = 3, ROGUE = 4, DRUID = 2, SHAMAN = 2, PALADIN = 1, WARLOCK = 3 }
        for k in pairs(counts) do names[k] = {} end
    elseif IsInGuild() then
        for _, e in ipairs(ns.GetRoster().list) do
            if e.class and e.class ~= "" then
                counts[e.class] = (counts[e.class] or 0) + 1
                names[e.class] = names[e.class] or {}
                table.insert(names[e.class], ns.DisplayName(e.name))
            end
        end
    end
    local list, total, biggest = {}, 0, 0
    for class, n in pairs(counts) do
        table.sort(names[class])
        local label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or (class:sub(1, 1) .. class:sub(2):lower())
        list[#list + 1] = { class = class, name = label, count = n, names = names[class] }
        total = total + n
        if n > biggest then biggest = n end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return list, total, biggest
end

-- The guild member who knows the most different recipes (all professions together; the recipes of the Mining window, smelting,
-- are not counted). { amount, name, class } or nil.
function ns.GetMostKnowledgeable()
    if ns.DB and ns.DB.demo then return { amount = 342, name = "Thrall", class = "SHAMAN" } end
    return BestMember(function(m)
        local known, count = {}, 0
        for key, p in pairs(m.profs or {}) do
            if tostring(key) ~= "186" then
                for _, id in ipairs(p.ids or {}) do
                    if not known[id] then known[id] = true count = count + 1 end
                end
            end
        end
        return count
    end)
end

---------------------------------------------------------------------------
-- The game's own statistics: fish caught. Read from the game's Statistics (by id: the same on
-- every client language), kept in the character's counters and shared like the others (the highest number wins).
---------------------------------------------------------------------------
T.GAME_STATS = { fish = 1518 }
local GAME_STAT_DEMO = { fish = { amount = 4821, name = "Brasco", class = "HUNTER" } }

-- the game gives a number as text: "493", "1,234", "2729 (Humanoid)" or "--" when there is nothing yet: the first number, or nil
function T.ParseStat(text)
    if type(text) ~= "string" then return nil end
    local lead = text:match("^%s*(%d[%d%.,%s\194\160]*)")
    if not lead then return nil end
    local digits = lead:gsub("%D", "")
    return tonumber(digits)
end

-- reads my own numbers (not before the world is ready, like talents and gear); true when the game could be asked
function T.ReadGameStats()
    if not ns.worldReady or type(GetStatistic) ~= "function" then return false end
    local own = ns.GetOwn()
    if not (own and own.stats) then return false end
    local changed = false
    for field, id in pairs(T.GAME_STATS) do
        local ok, text = pcall(GetStatistic, id)
        local n = ok and T.ParseStat(text) or nil
        if n and n > (own.stats[field] or 0) then
            own.stats[field] = n
            changed = true
        end
    end
    if changed then
        own.stats.rev = math.max(ns.Time(), (own.stats.rev or 0) + 1)
        if ns.Sync then ns.Sync.OnStatsChanged() end
        if ns.RefreshUI then ns.RefreshUI() end
    end
    return true
end

-- once the world is ready, then every ten minutes
function T.StartGameStats()
    local function Tick()
        ns.After(T.ReadGameStats() and 600 or 15, Tick)
    end
    ns.After(30, Tick)
end

-- who has the most of one of them: field is "fish"
function ns.GetGameRecord(field)
    if ns.DB and ns.DB.demo then return GAME_STAT_DEMO[field] end
    return BestMember(function(m) return m.stats and m.stats[field] end)
end

---------------------------------------------------------------------------
-- The gold in the guild bank. The game only tells it while somebody has the bank open, so it is remembered (with the time and who
-- looked) in the data of the guild and shared: the newest sighting wins. It can go up and down, unlike the counters.
---------------------------------------------------------------------------
local function GuildData()
    return ns.guildName and ns.DB and ns.DB.guilds and ns.DB.guilds[ns.guildName] or nil
end

-- copper, when it was seen (unix time), who saw it: nil when nobody has looked yet
function ns.GetGuildBank()
    if ns.DB and ns.DB.demo then return 4321000000, ns.Time() - 7200, "Garrosh" end
    local gd = GuildData()
    local bank = gd and gd.bank
    if not bank then return nil end
    return bank.money, bank.ts, bank.by
end

-- a sighting (mine or from a guildmate); true when it is newer than what we have
function T.NoteGuildBank(money, ts, by)
    local gd = GuildData()
    money, ts = tonumber(money), tonumber(ts)
    if not (gd and money and ts) or money < 0 then return false end
    if gd.bank and (gd.bank.ts or 0) > ts then return false end
    gd.bank = { money = math.min(money, 1e13), ts = ts, by = by or "" }
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

-- What the game told us about the bank (for /ff bank): the last events and what each way of reading the money returned.
local bankLog = {}
local function BankNote(text)
    bankLog[#bankLog + 1] = ("%s %s"):format(date and date("%H:%M:%S") or "", text)
    while #bankLog > 14 do table.remove(bankLog, 1) end
end

-- The money in the bank, tried in the ways this client might offer it. Returns the number and the name of the way that gave it.
local function BankMoney()
    local ways = {
        { "GetGuildBankMoney", function() return GetGuildBankMoney() end, type(GetGuildBankMoney) == "function" },
        { "C_GuildBank.GetMoney", function() return C_GuildBank.GetMoney() end, C_GuildBank and type(C_GuildBank.GetMoney) == "function" },
        { "C_GuildBank.FetchMoney", function() return C_GuildBank.FetchMoney() end, C_GuildBank and type(C_GuildBank.FetchMoney) == "function" },
    }
    local first
    for _, w in ipairs(ways) do
        if w[3] then
            local ok, v = pcall(w[2])
            local n = ok and tonumber(v) or nil
            BankNote(("%s -> %s"):format(w[1], ok and tostring(v) or ("error: " .. tostring(v))))
            if n and n > 0 then return n, w[1] end
            if n and not first then first = n end
        end
    end
    return first, first and "zero" or nil
end

-- the bank is open: read the money (a zero only counts when the game says the money changed: it can be zero while the bank loads)
local function ReadGuildBank(certain)
    local money = BankMoney()
    if not money or (money <= 0 and not certain) then return end
    local fresh = T.NoteGuildBank(money, ns.Time(), ns.me or "")
    BankNote(("seen %d copper, %s"):format(money, fresh and "stored and shared" or "not stored (guild not known yet, or an older reading)"))
    if fresh and ns.Sync and ns.Sync.OnGuildBankChanged then ns.Sync.OnGuildBankChanged() end
end
function T.ReadGuildBank(certain) ReadGuildBank(certain) end

local function BankOpened(how)
    BankNote("bank opened (" .. how .. ")")
    OpenBankWindow()
    -- the money can arrive a moment after the window opens: look again a few times
    for _, delay in ipairs({ 0.5, 2, 5 }) do ns.After(delay, function() ReadGuildBank(false) end) end
end
local function BankClosed(how)
    BankNote("bank closed (" .. how .. ")")
    ReadGuildBank(false)
    CloseBankWindow()
end
function ns.GUILDBANK_UPDATE_MONEY() BankNote("money changed") ReadGuildBank(true) end
function ns.GUILDBANKFRAME_OPENED() BankOpened("GUILDBANKFRAME_OPENED") end
function ns.GUILDBANKFRAME_CLOSED() BankClosed("GUILDBANKFRAME_CLOSED") end
-- clients built like the modern game announce every NPC window this way (the guild banker is one of them)
local function IsBanker(kind) return Enum and Enum.PlayerInteractionType and kind ~= nil and kind == Enum.PlayerInteractionType.GuildBanker end
function ns.PLAYER_INTERACTION_MANAGER_FRAME_SHOW(kind) if IsBanker(kind) then BankOpened("interaction") end end
function ns.PLAYER_INTERACTION_MANAGER_FRAME_HIDE(kind) if IsBanker(kind) then BankClosed("interaction") end end

-- /ff bank: what the addon knows about the guild bank and what the game has said so far
function T.BankProbe()
    ns.Print(("Guild known: %s. GetGuildBankMoney: %s. C_GuildBank: %s. Bank window: %s."):format(
        tostring(ns.guildName), type(GetGuildBankMoney) == "function" and "available" or "MISSING",
        C_GuildBank and "available" or "missing", (_G.GuildBankFrame and _G.GuildBankFrame:IsShown()) and "open" or "not open / not found"))
    local money, ts, by = ns.GetGuildBank()
    if money then
        ns.Print(("Stored amount: %d copper (%s), seen by %s, %s."):format(money, GetCoinTextureString and GetCoinTextureString(money) or "", tostring(by), ("%d s ago"):format(math.max(0, ns.Time() - (ts or 0)))))
    else
        ns.Print("Nothing stored yet.")
    end
    if #bankLog == 0 then ns.Print("The game has sent no bank event since login (open the bank, then type /ff bank again).") end
    for _, line in ipairs(bankLog) do ns.Print("  " .. line) end
    if type(GetGuildBankMoney) == "function" then BankMoney() ns.Print("Read right now: " .. tostring(bankLog[#bankLog])) end
end

