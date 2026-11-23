---@class ns
local ns = select(2, ...)

local P = {}
ns.Professions = P

---------------------------------------------------------------------------
-- Recipe names
---------------------------------------------------------------------------
local nameCache, lowerCache = {}, {}

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and info.name then return info.name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and type(name) == "string" then return name end
    end
    return nil
end

-- Names we saw in our own profession windows first, then the game's spell data.
function ns.RecipeName(id)
    local cached = nameCache[id]
    if cached then return cached end
    local name = (ns.DB and ns.DB.recipeNames[id]) or SpellName(id)
    if name then
        nameCache[id] = name
        return name
    end
    return "Recipe #" .. tostring(id)
end

function ns.RecipeLower(id)
    local cached = lowerCache[id]
    if cached then return cached end
    local lower = ns.RecipeName(id):lower()
    if nameCache[id] then lowerCache[id] = lower end
    return lower
end

function ns.RecipeInfo(id)
    return ns.DB and ns.DB.recipeInfo[id] or nil
end

function P.ProfessionName(key, fallback)
    local id = tonumber(key)
    if id and ns.PROFESSIONS[id] then return ns.PROFESSIONS[id] end
    return fallback or tostring(key)
end

---------------------------------------------------------------------------
-- Which professions does this character have? (works without opening any window)
---------------------------------------------------------------------------
function P.ReadKnownProfessions()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local ok, list = pcall(function()
        local out = {}
        local packed = { GetProfessions() }
        for i = 1, 6 do
            local index = packed[i]
            if index then
                local name, _, rank, max, _, _, skillLine = GetProfessionInfo(index)
                if name and skillLine then
                    out[#out + 1] = { key = tostring(skillLine), name = P.ProfessionName(skillLine, name), raw = name, rank = rank or 0, max = max or 0 }
                end
            end
        end
        return out
    end)
    if ok then return list end
    return nil
end

local function Changed()
    if ns.Stats then ns.Stats.RebuildRecipes() end
    if ns.Specs and ns.Specs.OnProfessionsChanged then ns.Specs.OnProfessionsChanged() end      -- (specializations and cooldowns of a profession that is gone)
    if ns.Sync then ns.Sync.OnLocalChange() end
    if ns.RefreshUI then ns.RefreshUI() end
end

-- The names of the skills the game's skills tab lists right now (a set), or nil when that cannot be read (functions missing or an empty
-- answer). A second source next to GetProfessions: it can only ever VETO a removal ("the tab still lists it"), never cause one, so a
-- name that does not match, or a collapsed header, can never make a profession disappear.
local function SkillsTabNames()
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
    local ok, set, n = pcall(function()
        local names, count = {}, GetNumSkillLines() or 0
        for i = 1, count do
            local name, header = GetSkillLineInfo(i)
            if name and not header then names[name] = true end
        end
        return names, count
    end)
    if ok and set and n and n > 0 then return set end
    return nil
end

-- My professions come straight from the character's own skill lines (GetProfessions), no profession window needed. What the game
-- lists is what I have. A profession it does not list any more is removed (with its recipes: they live inside the profession; the
-- other characters who know it keep theirs), but only when
--   1. the game's skills tab does not list it either (when that tab can be read), and
--   2. it has been missing on two looks at least REMOVE_WAIT seconds apart (a profession that shows up in between starts over).
-- Wrongly keeping one for half a minute costs nothing; wrongly dropping one loses its recipes until the window is scanned again.
-- nil from the game = it could not be read: nothing is touched. Before the world is ready an empty list may just not be loaded yet.
-- profsRev = when the list of my professions last changed: it travels with my advert so that the others drop what I dropped.
local REMOVE_WAIT = 30
local missingSince = {}          -- [profession key] = when it was first missing (this session only)
function P.RefreshKnown()
    local own = ns.GetOwn()
    local known = P.ReadKnownProfessions()
    if not own or not known then return end
    if #known == 0 and not ns.worldReady then return end

    local seen = {}
    for _, k in ipairs(known) do seen[k.key] = true end
    local tab
    local now = ns.Now()
    local drop, wait = {}, false
    for key, p in pairs(own.profs) do
        if tonumber(key) then
            if seen[key] then
                missingSince[key] = nil
            else
                tab = tab or SkillsTabNames() or false
                if tab and p.raw and tab[p.raw] then
                    missingSince[key] = nil          -- the skills tab still lists it: not gone
                elseif not missingSince[key] then
                    missingSince[key] = now          -- first look
                    wait = true
                elseif now - missingSince[key] >= REMOVE_WAIT then
                    drop[#drop + 1] = key
                else
                    wait = true
                end
            end
        end
    end
    if wait then ns.After(REMOVE_WAIT + 5, P.ScheduleKnownRefresh) end

    local changed, listChanged = false, false
    for _, k in ipairs(known) do
        local p = own.profs[k.key]
        if not p then
            own.profs[k.key] = { name = k.name, raw = k.raw, rank = k.rank, max = k.max, rev = ns.Time(), ids = {} }
            changed, listChanged = true, true
        else
            p.raw = k.raw or p.raw          -- (the game's own spelling of the name, for the skills tab check)
            if p.rank ~= k.rank or p.max ~= k.max then
                p.name, p.rank, p.max, p.rev = k.name, k.rank, k.max, ns.Time()
                changed = true
            end
        end
    end
    for _, key in ipairs(drop) do
        own.profs[key] = nil
        missingSince[key] = nil
        changed, listChanged = true, true
    end
    if listChanged or not own.profsRev then own.profsRev = ns.Time() end
    if changed then Changed() end
    if ns.Achievements then ns.Achievements.CheckOwn() end      -- 300 skill = maxed out (guild firsts)
end

local knownQueued = false
function P.ScheduleKnownRefresh()
    if knownQueued then return end
    knownQueued = true
    ns.After(2, function()
        knownQueued = false
        P.RefreshKnown()
    end)
end

---------------------------------------------------------------------------
-- Reading the open profession window
---------------------------------------------------------------------------
local function ParseSpellLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
end

local function ItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function KeepInfo(infos, id, item, reagents, made, icon)
    made = tonumber(made)
    if item or #reagents > 0 then
        infos[id] = { item = item, reagents = reagents, made = (made and made > 1) and made or nil, icon = icon }
    end
end

-- What a recipe makes and needs, from the game's own recipe data (works for a recipe that is not open in a window too, where
-- the game has it). Only reagents count: a half answer without them is not kept.
local function SchematicInfo(id, icon)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return nil end
    local okS, schem = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
    if not (okS and type(schem) == "table") then return nil end
    local reagents = {}
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, slot in ipairs(schem.reagentSlotSchematics or {}) do
        local need = slot.quantityRequired or 0
        local first = slot.reagents and slot.reagents[1]
        if need > 0 and first and first.itemID and (slot.reagentType == nil or basic == nil or slot.reagentType == basic) then
            reagents[#reagents + 1] = { id = first.itemID, count = need }
        end
    end
    local made = tonumber(schem.quantityMin)
    if schem.outputItemID or #reagents > 0 then
        return { item = schem.outputItemID, reagents = reagents, made = (made and made > 1) and made or nil, icon = icon }
    end
    return nil
end

-- A recipe we have no details for (a freshly synced one): ask the game; saves and returns the details when they came with reagents.
function P.LearnInfoFromGame(id)
    local have = ns.DB.recipeInfo[id]
    if have then return have end
    local info = SchematicInfo(id)
    if info and #info.reagents > 0 then
        ns.DB.recipeInfo[id] = info
        return info
    end
    return nil
end

-- Returns name, rank, max, ids, names, infos (names[id] = recipe name, infos[id] = what it makes and
-- what it needs), or nil when no window is open. Details are only read for recipes we have none for yet.
local function ReadWindow()
    local pname, rank, max, pid
    local ids, names, infos = {}, {}, {}
    local known = ns.DB.recipeInfo

    -- Modern profession window
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and type(info) == "table" and type(info.professionName) == "string" and info.professionName ~= "" then
            pname, rank, max = info.professionName, info.skillLevel, info.maxSkillLevel
            pid = info.professionID or info.parentProfessionID
            if C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
                pcall(function()
                    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
                        local r = C_TradeSkillUI.GetRecipeInfo(id)
                        if type(r) == "table" and r.learned then
                            ids[#ids + 1] = id
                            names[id] = r.name
                            if not (known[id] and known[id].icon) and C_TradeSkillUI.GetRecipeSchematic then
                                local okS, schem = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
                                if okS and type(schem) == "table" then
                                    local reagents = {}
                                    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
                                    for _, slot in ipairs(schem.reagentSlotSchematics or {}) do
                                        local need = slot.quantityRequired or 0
                                        local first = slot.reagents and slot.reagents[1]
                                        if need > 0 and first and first.itemID
                                            and (slot.reagentType == nil or basic == nil or slot.reagentType == basic) then
                                            reagents[#reagents + 1] = { id = first.itemID, count = need }
                                        end
                                    end
                                    KeepInfo(infos, id, schem.outputItemID, reagents, schem.quantityMin, r.icon)
                                end
                            end
                        end
                    end
                end)
            end
        end
    end

    -- Classic profession window
    if #ids == 0 and GetNumTradeSkills and GetTradeSkillLine then
        pcall(function()
            local n, r, m = GetTradeSkillLine()
            if n and n ~= "UNKNOWN" and (GetNumTradeSkills() or 0) > 0 then
                pname, rank, max = pname or n, rank or r, max or m
                for i = 1, GetNumTradeSkills() do
                    local rname, skillType = GetTradeSkillInfo(i)
                    if rname and skillType ~= "header" then
                        local id = GetTradeSkillRecipeLink and ParseSpellLink(GetTradeSkillRecipeLink(i))
                        if id then
                            ids[#ids + 1] = id
                            names[id] = rname
                            if not (known[id] and known[id].icon) then
                                local reagents = {}
                                for j = 1, (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) or 0) do
                                    local _, _, count = GetTradeSkillReagentInfo(i, j)
                                    local rid = GetTradeSkillReagentItemLink and ItemIDFromLink(GetTradeSkillReagentItemLink(i, j))
                                    if rid and count then reagents[#reagents + 1] = { id = rid, count = count } end
                                end
                                KeepInfo(infos, id, GetTradeSkillItemLink and ItemIDFromLink(GetTradeSkillItemLink(i)), reagents,
                                    GetTradeSkillNumMade and (GetTradeSkillNumMade(i)),
                                    GetTradeSkillIcon and GetTradeSkillIcon(i))
                            end
                        end
                    end
                end
            end
        end)
    end

    -- Classic Enchanting window
    if #ids == 0 and GetNumCrafts and GetCraftDisplaySkillLine then
        pcall(function()
            local n, r, m = GetCraftDisplaySkillLine()
            if n and (GetNumCrafts() or 0) > 0 then
                pname, rank, max = pname or n, rank or r, max or m
                for i = 1, GetNumCrafts() do
                    local rname, _, craftType = GetCraftInfo(i)
                    if rname and craftType ~= "header" then
                        local id = GetCraftRecipeLink and ParseSpellLink(GetCraftRecipeLink(i))
                        if id then
                            ids[#ids + 1] = id
                            names[id] = rname
                            if not (known[id] and known[id].icon) then
                                local reagents = {}
                                for j = 1, (GetCraftNumReagents and GetCraftNumReagents(i) or 0) do
                                    local _, _, count = GetCraftReagentInfo(i, j)
                                    local rid = GetCraftReagentItemLink and ItemIDFromLink(GetCraftReagentItemLink(i, j))
                                    if rid and count then reagents[#reagents + 1] = { id = rid, count = count } end
                                end
                                KeepInfo(infos, id, nil, reagents, nil, GetCraftIcon and GetCraftIcon(i))
                            end
                        end
                    end
                end
            end
        end)
    end

    if not pname or #ids == 0 then return nil end
    return pname, rank or 0, max or 0, ids, names, infos, pid
end

local function ResolveKey(pname, pid)
    -- 0) the profession id the game gives for the open window: language independent (and Smelting is Mining)
    if pid and ns.PROFESSIONS[tonumber(pid)] then return tostring(tonumber(pid)), ns.PROFESSIONS[tonumber(pid)] end
    -- 1) the character's own profession list: language independent
    local known = P.ReadKnownProfessions()
    if known then
        for _, k in ipairs(known) do
            if k.name == pname or ns.PROFESSIONS[tonumber(k.key)] == pname then return k.key, k.name end
        end
    end
    -- 2) English profession / window names
    local sl = ns.PROFESSION_BY_NAME[pname:lower()]
    if sl then return tostring(sl), ns.PROFESSIONS[sl] end
    -- 3) anything else: a key made from the name
    local slug = pname:lower():gsub("[^%w]", function(c) return ("%02x"):format(c:byte()) end)
    return "n_" .. slug:sub(1, 24), pname
end

local function SortedUnique(ids)
    table.sort(ids)
    local out, prev = {}, nil
    for _, id in ipairs(ids) do
        if id ~= prev then out[#out + 1] = id end
        prev = id
    end
    return out
end

-- a short fingerprint of a list of recipe ids (the count and the ids themselves)
local function IdSignature(list)
    local s = 0
    for _, id in ipairs(list) do s = (s * 31 + id) % 2147483647 end
    return #list .. ":" .. s
end

local SHRINK_WAIT = 20          -- seconds between the two looks that must agree on a shorter recipe list
local pendingShrink = {}        -- [profession key] = { sig, t } (this session only)

-- Scans the profession window that is open right now.
-- Returns true/false plus a message for /ff scan.
function P.ScanOpen()
    local own = ns.GetOwn()
    if not own then return false, "Not ready yet." end

    local pname, rank, max, ids, names, infos, pid = ReadWindow()
    if not pname then
        return false, "No profession window with recipes is open (or this client's profession API is not supported yet)."
    end

    local key, display = ResolveKey(pname, pid)
    ids = SortedUnique(ids)

    for id, rname in pairs(names) do
        if rname and ns.DB.recipeNames[id] ~= rname then ns.DB.recipeNames[id] = rname end
    end

    local newDetails = 0
    for id, info in pairs(infos or {}) do
        if not ns.DB.recipeInfo[id] then
            ns.DB.recipeInfo[id] = info
            newDetails = newDetails + 1
        end
    end

    local p = own.profs[key]
    if not p then
        p = { name = display, rank = rank, max = max, rev = 0, ids = {} }
        own.profs[key] = p
    end

    -- A shorter list than the one we hold is usually a window that is not fully loaded yet, so the first one is ignored. But recipes are
    -- really lost when a specialization is unlearned: the same shorter list seen again at least SHRINK_WAIT seconds later (the window
    -- has long finished loading by then) is believed and replaces the old one.
    if #ids < #p.ids then
        local sig = IdSignature(ids)
        local now = ns.Now()
        local pending = pendingShrink[key]
        if pending and pending.sig == sig and now - pending.t >= SHRINK_WAIT then
            pendingShrink[key] = nil
        else
            if not (pending and pending.sig == sig) then pendingShrink[key] = { sig = sig, t = now } end
            return false, ("Ignored a partial list for %s (%d of %d recipes)."):format(display, #ids, #p.ids)
        end
    else
        pendingShrink[key] = nil
    end

    local changed = IdSignature(ids) ~= IdSignature(p.ids) or p.rank ~= rank or p.max ~= max or p.rev == 0
    local summary = ("%s (key %s): skill %d/%d, %d recipes%s, %d new recipe details."):format(display, key, rank, max, #ids, changed and ", updated" or ", unchanged", newDetails)
    if changed then
        p.name, p.rank, p.max, p.ids, p.rev = display, rank, max, ids, ns.Time()
        Changed()
    end
    ns.Debug("scan: " .. summary)
    return true, summary
end

local scanQueued = false
function P.ScheduleScan()
    if scanQueued then return end
    scanQueued = true
    ns.After(1, function()
        scanQueued = false
        P.ScanOpen()
    end)
end

-- A recipe learned at a trainer: refresh the profession list now and read the window if it is open.
function P.OnRecipeLearned(recipeID)
    ns.Debug("recipe learned: " .. tostring(recipeID))
    P.ScheduleKnownRefresh()
    P.ScheduleScan()
end

---------------------------------------------------------------------------
-- Looking things up across the guild
---------------------------------------------------------------------------
-- Everybody (that we know about) who can craft this recipe: { { guid, name, online }, ... }
function P.FindCrafters(recipeID)
    local out = {}
    local members = ns.GetMembers() or {}
    local roster = ns.GetRoster()
    for guid, m in pairs(members) do
        local entry = ns.FindRosterEntry(roster, guid, m.name)
        if roster.total == 0 or entry then
            for key, p in pairs(m.profs) do
                local found = false
                for _, id in ipairs(p.ids) do
                    if id == recipeID then found = true break end
                end
                if found then
                    out[#out + 1] = { guid = guid, name = ns.DisplayName(entry and entry.name or m.name), online = entry and entry.online or false, key = key, rank = p.rank }
                    break
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return out
end

-- The exact skill a recipe needs, if any addon on this client knows it:
--  * Profession Master (every recipe), or LibCraftLevels (the skill a craft is learned at);
--  * what we saved earlier (recipeReq / recipeInfo.req), including what guildies sent us.
-- Profession Master (optional helper addon): its read-only API answers about recipes of the game.
-- ProfessionMasterApi: IsReady, GetRecipeInfo(itemId), GetRecipeInfoBySpell(spellId) -> { spellId,
-- professionId, professionName, requiredSkill, difficulty = { orange, yellow, green, grey }, craftedItemId },
-- IsRecipeKnown(itemId), IsRecipeKnownBySpell(spellId), GetProfessionLevel(professionId).
function P.PMApi()
    local api = _G.ProfessionMasterApi
    if api and (api.Version or 0) >= 1 and api.IsReady and api.IsReady() then return api end
    return nil
end

local pmCache = {}
function P.PMRecipeInfo(id)
    local cached = pmCache[id]
    if cached ~= nil then return cached or nil end
    local api = P.PMApi()
    if not (api and api.GetRecipeInfoBySpell) then return nil end   -- not ready yet: ask again later
    local ok, info = pcall(api.GetRecipeInfoBySpell, id)
    pmCache[id] = (ok and type(info) == "table") and info or false
    return pmCache[id] or nil
end

-- the skill needed to learn a recipe: what we already know, else Profession Master, else LibCraftLevels
function P.ExactSkill(id)
    local saved = ns.DB.recipeReq[id] or (ns.DB.recipeInfo[id] and ns.DB.recipeInfo[id].req)
    if saved then return saved end

    local skill
    local info = P.PMRecipeInfo(id)
    if info and tonumber(info.requiredSkill) then skill = tonumber(info.requiredSkill) end
    if not skill and _G.LibStub then
        local ok, lib = pcall(_G.LibStub, "LibCraftLevels-1.0", true)
        if ok and lib and lib.GetCraftLearnedAtLevel then
            local ok2, learned = pcall(lib.GetCraftLearnedAtLevel, lib, id)
            if ok2 and tonumber(learned) and tonumber(learned) > 0 then skill = tonumber(learned) end
        end
    end
    if skill then
        ns.DB.recipeReq[id] = skill
        local ri = ns.DB.recipeInfo[id]
        if ri then ri.req = skill end
    end
    return skill
end

-- which profession a recipe belongs to and the skill it needs: { key, name, skill }
function P.RecipeRequirements(ids)
    local want, out = {}, {}
    for _, id in ipairs(ids) do want[id] = true end

    local members = ns.GetMembers() or {}
    for _, m in pairs(members) do
        for key, p in pairs(m.profs) do
            for _, id in ipairs(p.ids) do
                if want[id] and not out[id] then
                    out[id] = { key = key, name = P.ProfessionName(key, p.name) }
                end
            end
        end
    end

    for _, id in ipairs(ids) do
        local o = out[id]
        if not o then
            local info = P.PMRecipeInfo(id)
            if info and (info.professionName or info.professionId) then
                o = { key = info.professionId and tostring(info.professionId) or nil,
                      name = info.professionName or P.ProfessionName(info.professionId) }
                out[id] = o
            end
        end
        if o then o.skill = P.ExactSkill(id) end
    end
    return out
end

-- Can THIS character craft the recipe right now: does it know it (from the windows we scanned, or from
-- Profession Master) and is its skill high enough?
function P.CanCraft(id)
    local known, skillNow = false, nil
    local own = ns.GetOwn()
    if own then
        for _, p in pairs(own.profs) do
            for _, rid in ipairs(p.ids) do
                if rid == id then known, skillNow = true, p.rank break end
            end
            if known then break end
        end
    end
    local api = P.PMApi()
    if not known and api and api.IsRecipeKnownBySpell then
        local ok, res = pcall(api.IsRecipeKnownBySpell, id)
        if ok and res == true then known = true end
    end
    if not known then return false end

    local need = P.ExactSkill(id)
    if need and not skillNow and api and api.GetProfessionLevel then
        local info = P.PMRecipeInfo(id)
        if info and info.professionId then
            local ok, level = pcall(api.GetProfessionLevel, info.professionId)
            if ok and tonumber(level) then skillNow = tonumber(level) end
        end
    end
    if need and skillNow and skillNow < need then return false end
    return true
end

-- Can one of my known alts craft the recipe (knows it and has the skill it needs, when that is known)?
function P.AltsCanCraft(id)
    local members = ns.GetMembers() or {}
    local need = P.ExactSkill(id)
    for guid in pairs(ns.GetMyFamilyGUIDs()) do
        local m = members[guid]
        if m and m.profs then
            for _, p in pairs(m.profs) do
                for _, rid in ipairs(p.ids) do
                    if rid == id then
                        if not (need and p.rank and p.rank < need) then return true end
                        break
                    end
                end
            end
        end
    end
    return false
end

-- every recipe that anybody in the guild (me included) can craft, by profession:
-- { [key] = { key, name, ids = { recipeID... } } }
function P.GuildRecipes()
    local out = {}
    for _, m in pairs(ns.GetMembers() or {}) do
        for key, p in pairs(m.profs) do
            local e = out[key]
            if not e then
                e = { key = key, name = P.ProfessionName(key, p.name), ids = {}, seen = {} }
                out[key] = e
            end
            for _, id in ipairs(p.ids) do
                if not e.seen[id] then
                    e.seen[id] = true
                    e.ids[#e.ids + 1] = id
                end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- "Craft this" for a request (1.0.21): open my profession window on the recipe and put the quantity in, the player presses the game's own
-- Create button. Nothing is crafted by us. Opening needs a click of the player (it comes from one); the quantity box is filled a moment later
-- because the game resets it to 1 when it selects a recipe.
---------------------------------------------------------------------------
local function QuantityBoxes()
    local boxes = {}
    local function Add(f) if type(f) == "table" then boxes[#boxes + 1] = f end end
    pcall(function() Add(ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.CreateMultipleInputBox) end)
    pcall(function() Add(TradeSkillFrame and TradeSkillFrame.DetailsFrame and TradeSkillFrame.DetailsFrame.CreateMultipleInputBox) end)
    pcall(function() Add(_G.TradeSkillInputBox) end)
    pcall(function() Add(_G.CraftInputBox) end)
    return boxes
end

-- puts the number in the first quantity box this client has; true when one took it
function P.FillQuantity(qty)
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    for _, box in ipairs(QuantityBoxes()) do
        if box.SetValue then
            if pcall(box.SetValue, box, qty) then return true end
        elseif box.SetNumber then
            if pcall(box.SetNumber, box, qty) then return true end
        end
    end
    return false
end

-- returns false when it could not even open the recipe
function P.OpenToCraft(id, qty, name)
    local inCombat = false
    pcall(function() inCombat = InCombatLockdown and InCombatLockdown() or false end)
    if inCombat then ns.Print("You cannot open your profession in combat.") return false end
    local opened = false
    pcall(function()
        if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then opened = C_TradeSkillUI.OpenRecipe(id) ~= false end
    end)
    if not opened then
        ns.Print("Open your profession window to craft this.")
        return false
    end
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local label = ("%d× %s"):format(qty, name or ("#" .. id))
    -- a few tries: the window loads its recipe a moment after it opens, and selecting a recipe resets the amount
    local tries, done = { 0.2, 0.6, 1.2, 2.5 }, false
    for i, delay in ipairs(tries) do
        ns.After(delay, function()
            if P.FillQuantity(qty) then done = true end
            if i == #tries then
                if done then ns.Print(("Ready to craft %s: press Create."):format(label))
                else ns.Print(("Craft %s: set the amount to %d and press Create."):format(label, qty)) end
            end
        end)
    end
    return true
end
