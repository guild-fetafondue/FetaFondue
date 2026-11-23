---@class ns
local ns = select(2, ...)

---------------------------------------------------------------------------
-- /ff statprobe: which character-stat functions exist on this client and what they return for MY character
-- (read-only; only out of combat and once the world is ready). The result is printed and kept in the saved
-- variables (FetaFondueDB.statProbe) so it can be sent from the SavedVariables file as well.
---------------------------------------------------------------------------
local unpack = unpack or table.unpack

local function Say(text, lines)
    ns.Print(text)
    lines[#lines + 1] = text
end

local function Show(v)
    local secret = false
    pcall(function() if issecretvalue and issecretvalue(v) then secret = true end end)
    if secret then return "<secret>" end
    local ok, s = pcall(function()
        if type(v) == "number" then return ("%.2f"):format(v) end
        return tostring(v)
    end)
    return ok and s or "<unreadable>"
end

local function Find(path)
    local obj = _G
    for part in path:gmatch("[^%.]+") do
        if type(obj) ~= "table" then return nil end
        obj = obj[part]
    end
    return obj
end

-- name, then the arguments to call it with
local CALLS = {
    { "UnitHealthMax", "player" }, { "UnitPowerMax", "player" }, { "UnitPowerType", "player" }, { "GetUnitSpeed", "player" },
    { "UnitStat", "player", 1 }, { "UnitStat", "player", 2 }, { "UnitStat", "player", 3 }, { "UnitStat", "player", 4 }, { "UnitStat", "player", 5 },
    { "UnitArmor", "player" }, { "UnitDefense", "player" }, { "GetDodgeChance" }, { "GetParryChance" }, { "GetBlockChance" },
    { "GetCritChance" }, { "GetSpellCritChance", 2 }, { "GetRangedCritChance" }, { "GetHaste" }, { "GetMeleeHaste" }, { "GetRangedHaste" },
    { "GetSpellHaste" }, { "GetMastery" }, { "GetVersatilityBonus", 29 }, { "GetCombatRating", 9 }, { "GetCombatRatingBonus", 9 },
    { "UnitAttackPower", "player" }, { "UnitRangedAttackPower", "player" }, { "GetSpellBonusDamage", 2 }, { "GetSpellBonusHealing" },
    { "GetManaRegen" }, { "GetPowerRegen" }, { "GetShieldBlock" }, { "GetLifesteal" }, { "GetAvoidance" }, { "GetSpeed" },
    { "C_PaperDollInfo.GetStaggerPercentage", "player" }, { "GetAverageItemLevel" },
    { "GetArmorPenetration" }, { "GetSpellPenetration" }, { "GetNumSkillLines" },
}

function ns.StatProbe()
    local lines = {}
    if not ns.worldReady then ns.Print("Not ready yet: try again in a few seconds.") return end
    local inCombat = false
    pcall(function() inCombat = InCombatLockdown and InCombatLockdown() or false end)
    if inCombat then ns.Print("Not in combat, please.") return end
    local _, classFile = UnitClass("player")
    Say(("Stat probe (read-only): %s, level %s"):format(tostring(classFile), tostring(UnitLevel("player"))), lines)
    for _, c in ipairs(CALLS) do
        local name = c[1]
        local fn = Find(name)
        local arg = ""
        for i = 2, #c do arg = arg .. (i > 2 and "," or "") .. tostring(c[i]) end
        if type(fn) ~= "function" then
            Say(("%s(%s): not there"):format(name, arg), lines)
        else
            local res = { pcall(fn, unpack(c, 2)) }
            if not res[1] then
                Say(("%s(%s): error"):format(name, arg), lines)
            else
                local out = {}
                for i = 2, math.min(#res, 6) do out[#out + 1] = Show(res[i]) end
                Say(("%s(%s) = %s"):format(name, arg, #out > 0 and table.concat(out, ", ") or "nothing"), lines)
            end
        end
    end
    -- where the game gets the Defense number from: the stat functions with "defense" or "armor" in their name, and the skill line
    local found = {}
    for name, value in pairs(_G) do
        if type(name) == "string" and type(value) == "function" and (name:lower():find("defense", 1, true) or name:lower():find("defence", 1, true)) then
            found[#found + 1] = name
        end
    end
    table.sort(found)
    Say("functions with defense in the name: " .. (#found > 0 and table.concat(found, ", ", 1, math.min(#found, 12)) or "none"), lines)
    pcall(function()
        for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
            local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
            if not header and name and (name:lower():find("def", 1, true) or name:lower():find("verteid", 1, true)) then
                Say(("skill line %s: %s / %s"):format(name, Show(rank), Show(max)), lines)
            end
        end
    end)
    -- what the game's own character panel lists, if the tables exist
    local cats = _G.PAPERDOLL_STATCATEGORIES
    if type(cats) == "table" then
        local order = _G.PAPERDOLL_STATCATEGORY_ORDER
        for key, cat in pairs(cats) do
            local ids = {}
            for _, st in ipairs(cat.stats or {}) do ids[#ids + 1] = tostring(st.stat or st) end
            Say(("panel category %s: %s"):format(tostring(cat.id or key), table.concat(ids, ", ")), lines)
        end
        if type(order) == "table" then
            local names = {}
            for _, o in ipairs(order) do names[#names + 1] = tostring(o.categoryFrame or o.category or o) end
            Say("panel order: " .. table.concat(names, ", "), lines)
        end
    else
        Say("panel tables (PAPERDOLL_STATCATEGORIES): not there", lines)
    end
    if ns.DB then ns.DB.statProbe = lines end
    ns.Print("Done. Please paste these lines (or send them from the SavedVariables file) for both characters.")
end
