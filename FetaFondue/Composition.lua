---@class ns
local ns = select(2, ...)

---------------------------------------------------------------------------
-- Composition planner (Management > Planner): the people of my group plus placeholder characters ("Enha Shaman") are put into
-- raid groups, and the planner shows which raid buffs, party buffs and debuffs the composition brings (green) and which are missing (red).
-- Everything is based on the SPECIALIZATION, not only the class. The plan is mine only: it is saved on this installation, never shared.
--
-- This file: the specializations, the table of effects (CompData below), the plan and the maths. The window is UIComposition.lua.
-- NOTE: the table of effects (names, icons, texts, who provides what, the three groups) was read from oxm.gg/forever/comp on 2026-11-21:
-- the texts are its tooltips and "who provides it" was read by putting every one of the 28 specs into an empty raid. If the site changes, edit the lines
-- of the table (one line per effect).
---------------------------------------------------------------------------
local C = {}
ns.Composition = C

local ICON = "Interface\\Icons\\"

---------------------------------------------------------------------------
-- Specializations
---------------------------------------------------------------------------
-- key, class, tree (the name of the talent tree it is recognised by, nil = never recognised by itself), role, name, generic name, icon
local SPEC_LIST = {
    { "WARRIOR_ARMS", "WARRIOR", "Arms", "DPS", "Arms Warrior", "Arms War", "Ability_Rogue_Eviscerate" },
    { "WARRIOR_FURY", "WARRIOR", "Fury", "DPS", "Fury Warrior", "Fury War", "Ability_Warrior_InnerRage" },
    { "WARRIOR_PROT", "WARRIOR", "Protection", "TANK", "Protection Warrior", "Prot War", "INV_Shield_06" },
    { "PALADIN_HOLY", "PALADIN", "Holy", "HEALER", "Holy Paladin", "Holy Pala", "Spell_Holy_HolyBolt" },
    { "PALADIN_PROT", "PALADIN", "Protection", "TANK", "Protection Paladin", "Prot Pala", "Spell_Holy_DevotionAura" },
    { "PALADIN_RET", "PALADIN", "Retribution", "DPS", "Retribution Paladin", "Ret Pala", "Spell_Holy_AuraOfLight" },
    { "HUNTER_BM", "HUNTER", "Beast Mastery", "DPS", "Beast Mastery Hunter", "BM Hunter", "Ability_Hunter_BeastTaming" },
    { "HUNTER_MM", "HUNTER", "Marksmanship", "DPS", "Marksmanship Hunter", "MM Hunter", "Ability_Marksmanship" },
    { "HUNTER_SURV", "HUNTER", "Survival", "DPS", "Survival Hunter", "Surv Hunter", "Ability_Hunter_SwiftStrike" },
    { "ROGUE_ASSA", "ROGUE", "Assassination", "DPS", "Assassination Rogue", "Assa Rogue", "Ability_Rogue_Eviscerate" },
    { "ROGUE_COMBAT", "ROGUE", "Combat", "DPS", "Combat Rogue", "Combat Rogue", "Ability_BackStab" },
    { "ROGUE_SUB", "ROGUE", "Subtlety", "DPS", "Subtlety Rogue", "Sub Rogue", "Ability_Stealth" },
    { "PRIEST_DISC", "PRIEST", "Discipline", "HEALER", "Discipline Priest", "Disc Priest", "Spell_Holy_WordFortitude" },
    { "PRIEST_HOLY", "PRIEST", "Holy", "HEALER", "Holy Priest", "Holy Priest", "Spell_Holy_GuardianSpirit" },
    { "PRIEST_SHADOW", "PRIEST", "Shadow", "DPS", "Shadow Priest", "Shadow Priest", "Spell_Shadow_ShadowWordPain" },
    { "SHAMAN_ELE", "SHAMAN", "Elemental", "DPS", "Elemental Shaman", "Ele Shaman", "Spell_Nature_Lightning" },
    { "SHAMAN_ENH", "SHAMAN", "Enhancement", "DPS", "Enhancement Shaman", "Enha Shaman", "Spell_Nature_LightningShield" },
    { "SHAMAN_RESTO", "SHAMAN", "Restoration", "HEALER", "Restoration Shaman", "Resto Shaman", "Spell_Nature_MagicImmunity" },
    { "MAGE_ARCANE", "MAGE", "Arcane", "DPS", "Arcane Mage", "Arcane Mage", "Spell_Holy_MagicalSentry" },
    { "MAGE_FIRE", "MAGE", "Fire", "DPS", "Fire Mage", "Fire Mage", "Spell_Fire_FireBolt02" },
    { "MAGE_FROST", "MAGE", "Frost", "DPS", "Frost Mage", "Frost Mage", "Spell_Frost_FrostBolt02" },
    { "WARLOCK_AFF", "WARLOCK", "Affliction", "DPS", "Affliction Warlock", "Aff Warlock", "Spell_Shadow_DeathCoil" },
    { "WARLOCK_DEMO", "WARLOCK", "Demonology", "DPS", "Demonology Warlock", "Demo Warlock", "Spell_Shadow_Metamorphosis" },
    { "WARLOCK_DESTRO", "WARLOCK", "Destruction", "DPS", "Destruction Warlock", "Destro Warlock", "Spell_Shadow_RainOfFire" },
    { "DRUID_BALANCE", "DRUID", "Balance", "DPS", "Balance Druid", "Boomkin", "Spell_Nature_StarFall" },
    { "DRUID_BEAR", "DRUID", nil, "TANK", "Feral Druid (tank)", "Feral Tank", "Ability_Racial_BearForm" },
    { "DRUID_CAT", "DRUID", "Feral", "DPS", "Feral Druid (cat)", "Feral Cat", "Ability_Druid_CatForm" },
    { "DRUID_RESTO", "DRUID", "Restoration", "HEALER", "Restoration Druid", "Resto Druid", "Spell_Nature_HealingTouch" },
}
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
C.CLASS_ORDER = CLASS_ORDER

C.SPECS, C.BY_KEY, C.BY_CLASS = {}, {}, {}
for _, s in ipairs(SPEC_LIST) do
    local spec = { key = s[1], class = s[2], tree = s[3], role = s[4], name = s[5], gen = s[6], icon = ICON .. s[7] }
    C.SPECS[#C.SPECS + 1] = spec
    C.BY_KEY[spec.key] = spec
    C.BY_CLASS[spec.class] = C.BY_CLASS[spec.class] or {}
    table.insert(C.BY_CLASS[spec.class], spec)
end

function C.Spec(key) return key and C.BY_KEY[key] or nil end

-- the spec of a class for the name of a talent tree (Feral is the cat; DetectSpec makes it the bear for a Feral Tank)
function C.SpecFor(class, tree)
    for _, s in ipairs(C.BY_CLASS[class or ""] or {}) do
        if s.tree and tree and s.tree == tree then return s end
    end
    return nil
end

---------------------------------------------------------------------------
-- The table of effects
--   scope "raid":   one in the raid is enough, the whole raid gets it
--   scope "party":  only the group of the provider gets it (so who stands in which group matters)
--   scope "debuff": put on the enemy by one in the raid, helps everybody
-- who: "CLASS" (every spec of the class) or a spec key
---------------------------------------------------------------------------
C.BUFFS = {}
local function B(scope, cat, id, name, icon, who, desc, extra)
    C.BUFFS[#C.BUFFS + 1] = { id = id, scope = scope, cat = cat, name = name, icon = ICON .. icon, who = who, desc = desc, extra = extra or {} }
end

-- raid buffs (19)
B("raid", "Stats", "kings", "Blessing of Kings", "spell_magic_greaterblessingofkings", { "PALADIN" }, "Increases total stats by 10% for 1 hour; every Paladin trains it at level 20, and the Greater version covers a whole class.", nil)
B("raid", "Stats", "fort", "Power Word: Fortitude", "spell_holy_wordfortitude", { "PRIEST" }, "Increases Stamina by 70 for 1 hour, and Prayer of Fortitude now reaches every party and raid member.", nil)
B("raid", "Stats", "motw", "Mark of the Wild", "spell_nature_regeneration", { "DRUID" }, "Grants 385 armor, 16 to all stats and 27 to all resistances for 1 hour, and Gift of the Wild now reaches the whole raid.", nil)
B("raid", "Stats", "strength", "Strength of Earth Totem", "spell_nature_earthbindtotem", { "SHAMAN" }, "Increases party or raid members' Strength by 53; totems last 5 minutes with a 30 yard radius.", nil)
B("raid", "Stats", "grace", "Grace of Air Totem", "spell_nature_invisibilitytotem", { "SHAMAN" }, "Increases party or raid members' Agility by 89; totems last 5 minutes with a 30 yard radius.", { "Does not stack with Windfury or Tranquil Air Totem, even from different Shamans." })
B("raid", "Stats", "crit", "Moonkin Aura / Leader of the Pack", "spell_nature_moonglow", { "DRUID_BALANCE", "DRUID_CAT", "DRUID_BEAR" }, "Grants 3% critical strike chance to party or raid members within 45 yards; the two auras do not stack with each other (Leader of the Pack works only while in Cat, Bear or Dire Bear Form).", { "Talent: Moonkin Form (Balance), Leader of the Pack (Feral)." })
B("raid", "Attack power", "might", "Blessing of Might", "spell_holy_fistofjustice", { "PALADIN" }, "Increases melee attack power by 133 for 1 hour, per class with the Greater version.", nil)
B("raid", "Attack power", "battleshout", "Battle Shout", "ability_warrior_battleshout", { "WARRIOR" }, "Increases melee attack power of party or raid members within 20 yards by 140 for 3 minutes.", nil)
B("raid", "Attack power", "trueshot", "Trueshot Aura", "ability_trueshot", { "HUNTER_MM" }, "Increases ranged attack power of party or raid members within 45 yards by 100 at rank 5 (level 60, from the trainer); the talent grants rank 1, worth 20.", { "Talent: Trueshot Aura (Marksmanship)." })
B("raid", "Attack power", "windfury", "Windfury Totem", "spell_nature_windfury", { "SHAMAN" }, "Gives each main-hand hit of party or raid members a 20% chance of an extra attack with 246 bonus attack power; totems last 5 minutes with a 30 yard radius.", { "Does not stack with Grace of Air or Tranquil Air Totem, even from different Shamans, nor with Flametongue Totem." })
B("raid", "Attack power", "flametongue", "Flametongue Totem", "spell_nature_guardianward", { "SHAMAN" }, "Adds Fire damage to party or raid members' main-hand weapon attacks within 30 yards; the buff has no duration and is replaced by the next totem placed.", { "Does not stack with itself, with Flametongue Weapon or with Windfury Totem." })
B("raid", "Attack power", "howl", "Furious Howl", "ability_hunter_pet_wolf", { "HUNTER" }, "The Hunter's wolf increases the melee attack power of party or raid members within 15 yards by 84 for 1 minute.", nil)
B("raid", "Mana and spell", "wisdom", "Blessing of Wisdom", "spell_holy_sealofwisdom", { "PALADIN" }, "Restores 40 mana every 5 seconds for 1 hour, per class with the Greater version.", nil)
B("raid", "Mana and spell", "spirit", "Divine Spirit", "spell_holy_divinespirit", { "PRIEST" }, "Increases Spirit by 40 for 1 hour; baseline for every Priest, and Prayer of Spirit reaches the whole raid.", nil)
B("raid", "Mana and spell", "int", "Arcane Intellect", "spell_holy_magicalsentry", { "MAGE" }, "Increases Intellect by 31 for 1 hour, and Arcane Brilliance reaches the whole party and raid.", nil)
B("raid", "Resistances", "fireres", "Fire Resistance", "spell_fire_sealoffire", { "PALADIN", "SHAMAN" }, "Grants 60 Fire resistance to every party and raid member within 30 yards.", nil)
B("raid", "Resistances", "frostres", "Frost Resistance", "spell_frost_wizardmark", { "PALADIN", "SHAMAN" }, "Grants 60 Frost resistance to every party and raid member within 30 yards.", nil)
B("raid", "Resistances", "shadowres", "Shadow Resistance", "spell_shadow_sealofkings", { "PALADIN", "PRIEST" }, "Grants 60 Shadow resistance to every party and raid member, from the aura or from Prayer of Shadow Protection.", nil)
B("raid", "Resistances", "natureres", "Nature Resistance", "spell_nature_protectionformnature", { "HUNTER", "SHAMAN" }, "Grants 60 Nature resistance to every party and raid member within 30 yards.", nil)

-- party buffs (14): only the group of the one who brings it
B("party", "Stats", "darkinsp", "Dark Inspiration", "spell_warlock_demonsoul", { "PRIEST_SHADOW" }, "Mind Blast and fully channeled Mind Flay increase the Priest's and party members' Spirit by 15% for 10 seconds at 5 ranks.", { "Talent: Dark Inspiration (Shadow)." })
B("party", "Stats", "devotion", "Devotion Aura", "spell_holy_devotionaura", { "PALADIN" }, "Grants 735 armor to party members within 30 yards; one aura per Paladin.", nil)
B("party", "Stats", "bloodpact", "Blood Pact", "spell_shadow_bloodboil", { "WARLOCK" }, "Increases party members' Stamina by 54 while the Warlock's Imp is out.", { "Provided by the Warlock's Imp." })
B("party", "Mana and spell", "manaspring", "Mana Spring Totem", "spell_nature_manaregentotem", { "SHAMAN" }, "Restores 10 mana every 2 seconds to party members; totems last 5 minutes with a 30 yard radius.", nil)
B("party", "Mana and spell", "manatide", "Mana Tide Totem", "spell_frost_summonwaterelemental", { "SHAMAN_RESTO" }, "Restores 197 mana every 3 seconds for 12 seconds to party members.", { "Talent: Mana Tide Totem (Restoration)." })
B("party", "Utility", "tremor", "Tremor Totem", "spell_nature_tremortotem", { "SHAMAN" }, "Removes Fear, Charm and Sleep effects from nearby party members; totems last 5 minutes with a 30 yard radius.", nil)
B("party", "Utility", "grounding", "Grounding Totem", "spell_nature_groundingtotem", { "SHAMAN" }, "Redirects one harmful spell cast on a nearby party member to the totem.", nil)
B("party", "Utility", "stoneskin", "Stoneskin / Windwall Totem", "spell_nature_stoneskintotem", { "SHAMAN" }, "Reduces Physical damage taken by 30 (Stoneskin) or ranged damage taken by 64 (Windwall) for party members.", nil)
B("party", "Utility", "healstream", "Healing Stream Totem", "inv_spear_04", { "SHAMAN" }, "Restores 11 health every 2 seconds to party members; totems last 5 minutes with a 30 yard radius.", nil)
B("party", "Utility", "cleansing", "Poison / Disease Cleansing Totem", "spell_nature_poisoncleansingtotem", { "SHAMAN" }, "Periodically removes one poison or one disease from nearby party members.", nil)
B("party", "Utility", "retaura", "Retribution Aura", "spell_holy_auraoflight", { "PALADIN" }, "Deals 20 Holy damage to anything that strikes a party member in melee.", nil)
B("party", "Utility", "concentration", "Concentration Aura", "spell_holy_mindsooth", { "PALADIN" }, "Gives a 35% chance of ignoring spell interruption when damaged to all party members within 30 yards.", nil)
B("party", "Utility", "vampiric", "Vampiric Embrace", "spell_shadow_unsummonbuilding", { "PRIEST_SHADOW" }, "Heals party members for 20% of the Priest's Shadow damage, lasting 30 seconds on a 1 minute cooldown.", { "Talent: Vampiric Embrace (Shadow)." })
B("party", "Utility", "packaspect", "Aspect of the Pack", "ability_mount_whitetiger", { "HUNTER" }, "Increases the movement speed of party members within 30 yards by 30%; a pack member who takes damage is dazed for 4 seconds.", nil)

-- debuffs and single target (20)
B("debuff", "Armor", "sunder", "Sunder Armor", "ability_warrior_sunder", { "WARRIOR" }, "Reduces the target's armor by 450 per application, up to 5 applications (2,250).", nil)
B("debuff", "Armor", "expose", "Expose Armor", "ability_warrior_riposte", { "ROGUE" }, "Reduces the target's armor by 450 per combo point, 2,250 at 5 combo points.", { "Forever has not confirmed whether Expose Armor and Sunder Armor stack." })
B("debuff", "Armor", "faerie", "Faerie Fire", "spell_nature_faeriefire", { "DRUID" }, "Reduces the target's armor by 505 for 40 seconds; cannot be cast while shapeshifted.", nil)
B("debuff", "Armor", "reckless", "Curse of Recklessness", "spell_shadow_unholystrength", { "WARLOCK" }, "Reduces the target's armor by 505 for 2 minutes and no longer raises its attack power.", { "One Curse per Warlock, so it competes with Curse of the Elements; Banes are separate." })
B("debuff", "Spell damage", "elements", "Curse of the Elements", "warlock_curse_shadow", { "WARLOCK" }, "Reduces the resistance of all magic schools by 75 and increases magic damage taken by 10% for 5 minutes.", { "One Curse per Warlock; Banes are a separate category and stack beside it." })
B("debuff", "Spell damage", "jotc", "Judgement of the Crusader", "spell_holy_holysmite", { "PALADIN" }, "Increases Holy damage taken by 161 for 40 seconds, refreshed by the Paladin's melee attacks.", nil)
B("debuff", "Spell damage", "tongues", "Curse of Tongues", "spell_shadow_curseoftounges", { "WARLOCK" }, "Increases the target's casting time by 60%.", nil)
B("debuff", "Enemy melee", "aprd", "Attack Power reduction", "ability_warrior_warcry", { "WARRIOR", "DRUID", "HUNTER", "PALADIN_RET" }, "Reduces the target's melee attack power by about 200 (Demoralizing Shout 210, Demoralizing Roar 207, Hex of Weakness and Demoralizing Screech 204).", { "Talent: Vindication (Retribution).", "Forever has not announced whether these stack with each other." })
B("debuff", "Enemy melee", "thunderclap", "Thunder Clap", "spell_nature_thunderclap", { "WARRIOR" }, "Slows the attack speed of nearby enemies by 20%, usable in Battle or Defensive Stance.", nil)
B("debuff", "Enemy melee", "weakness", "Curse of Weakness", "spell_shadow_curseofmannoroth", { "WARLOCK" }, "Reduces physical damage dealt by the target by 37.", nil)
B("debuff", "Enemy melee", "swarm", "Insect Swarm", "spell_nature_insectswarm", { "DRUID_BALANCE" }, "Reduces the target's chance to hit by 2%.", { "Talent: Insect Swarm (Balance)." })
B("debuff", "Single target", "mark", "Hunter's Mark", "ability_hunter_snipershot", { "HUNTER" }, "Increases ranged attack power against the marked target by 143 for every attacker.", nil)
B("debuff", "Single target", "powerinf", "Power Infusion", "spell_holy_powerinfusion", { "PRIEST_DISC" }, "Increases one target's spell damage and healing by 20% for 15 seconds, on a 3 minute cooldown.", { "Talent: Power Infusion (Discipline)." })
B("debuff", "Single target", "innervate", "Innervate", "spell_nature_lightning", { "DRUID" }, "Increases the target's mana regeneration by 400% and lets 100% of it continue while casting, for 20 seconds on a 6 minute cooldown.", nil)
B("debuff", "Single target", "fearward", "Fear Ward", "spell_holy_excorcism", { "PRIEST" }, "Absorbs the next Fear on one target for 3 minutes, on a 3 minute cooldown; every Priest race has it.", nil)
B("debuff", "Single target", "amplify", "Amplify / Dampen Magic", "spell_holy_flashheal", { "MAGE" }, "Amplify raises spell damage taken by 113 and healing received by 225; Dampen lowers them by 135 and 270.", nil)
B("debuff", "Single target", "thorns", "Thorns", "spell_nature_thorns", { "DRUID" }, "Deals 18 Nature damage to anything that strikes the target in melee.", nil)
B("debuff", "Single target", "soulstone", "Soulstone", "spell_shadow_soulgem", { "WARLOCK" }, "Stores the target's soul so they can resurrect themselves after dying.", nil)
B("debuff", "Single target", "jow", "Judgement of Wisdom", "spell_holy_righteousnessaura", { "PALADIN" }, "Attacks on the judged target can restore mana to the attacker for 40 seconds, refreshed by the Paladin's melee attacks.", nil)
B("debuff", "Single target", "jol", "Judgement of Light", "spell_holy_healingaura", { "PALADIN" }, "Attacks on the judged target can heal the attacker for 40 seconds, refreshed by the Paladin's melee attacks.", nil)

C.BUFF_BY_ID = {}
for _, b in ipairs(C.BUFFS) do C.BUFF_BY_ID[b.id] = b end

-- does somebody of this spec provide the effect?
function C.Provides(buff, specKey)
    local spec = C.BY_KEY[specKey or ""]
    if not spec then return false end
    for _, w in ipairs(buff.who) do
        if w == spec.class or w == spec.key then return true end
    end
    return false
end

-- "Any Shaman, Restoration Shaman" for the tooltip: the specs that can provide it
function C.WhoText(buff)
    local out = {}
    for _, w in ipairs(buff.who) do
        local spec = C.BY_KEY[w]
        if spec then out[#out + 1] = spec.name
        else out[#out + 1] = "Any " .. (w:sub(1, 1) .. w:sub(2):lower()) end
    end
    return table.concat(out, ", ")
end

---------------------------------------------------------------------------
-- The plan (saved in my own data)
---------------------------------------------------------------------------
-- plan.size: 10, 20 or 40. plan.slots[i] (i = 1..40, group = ceil(i / 5)): nil, { gen = specKey } or { key = guid or name, name, class }
-- plan.specs[key] = specKey: what I assigned to a character whose spec is not known (or that I changed)
local function Plan()
    local db = ns.DB
    if not db then return { size = 40, slots = {}, specs = {} } end
    db.composition = db.composition or {}
    local p = db.composition
    p.size = (p.size == 10 or p.size == 20) and p.size or 40
    p.slots = p.slots or {}
    p.specs = p.specs or {}
    return p
end
C.Plan = Plan

function C.Size() return Plan().size end
function C.Groups() return Plan().size / 5 end
function C.Slot(i) return Plan().slots[i] end
function C.GroupOf(i) return math.ceil(i / 5) end

-- the size changed: what stood in groups that are gone is taken out (the real ones are back in the list)
function C.SetSize(n)
    if n ~= 10 and n ~= 20 and n ~= 40 then return end
    local p = Plan()
    p.size = n
    for i = n + 1, 40 do p.slots[i] = nil end
end

function C.Reset()
    local p = Plan()
    p.slots = {}
end

---------------------------------------------------------------------------
-- My group
---------------------------------------------------------------------------
C.members = {}          -- the people of my group now: { key, guid, name, class, spec = specKey or nil, unit }
C.byKey = {}

local function InRaid() local ok, v = pcall(IsInRaid) return ok and v == true end

-- the specialization of a character, from what we know: what I set, a guildmate's shared talents, my own, an inspect of somebody else
local function DetectSpec(m)
    local p = Plan()
    local set = p.specs[m.key]
    if set and C.BY_KEY[set] and C.BY_KEY[set].class == m.class then return set end
    local tree, code
    pcall(function()
        local own = ns.IsMine and m.guid and ns.IsMine(m.guid) and ns.GetOwn()
        local data = own or (m.guid and ns.GetMembers()[m.guid])
        if data then
            tree = data.setups and data.setups[1] and data.setups[1].tree
            code = data.setups and data.setups[1] and data.setups[1].role
            if not tree or tree == "" then tree = data.tree code = data.role end
        end
        if (not tree or tree == "") and m.guid and ns.DB.inspect and ns.DB.inspect[m.guid] and ns.Inspect then
            local role
            tree, role = ns.Inspect.RoleOfProfile(ns.DB.inspect[m.guid])
            code = role and ns.Inspect.ROLE_CODE[role]
        end
    end)
    -- a Feral druid who has Primal Bite (and not Shifting Power) is the bear; every other Feral (cat, hybrid, plain) is the cat
    if m.class == "DRUID" and tree == "Feral" and code == "B" then return "DRUID_BEAR" end
    local spec = C.SpecFor(m.class, tree)
    return spec and spec.key or nil
end
C.DetectSpec = DetectSpec

-- Read the group (me included, also when I am alone) and keep the plan in step: somebody who left is taken out of the groups.
-- Returns true when the plan changed because somebody left.
function C.Refresh()
    local list, seen = {}, {}
    local function Add(unit)
        pcall(function()
            if not UnitExists(unit) then return end
            local name, last = UnitName(unit)
            local _, class = UnitClass(unit)
            local guid = UnitGUID(unit)
            if not name or not class then return end
            -- the full name: as the guild roster spells it, else the first and the last name the game keeps apart
            local rosterEntry
            pcall(function()
                local roster = guid and ns.GetRoster and ns.GetRoster()
                rosterEntry = roster and roster.byGUID and roster.byGUID[guid]
            end)
            if rosterEntry and rosterEntry.name and rosterEntry.name ~= "" then name = ns.DisplayName(rosterEntry.name)
            elseif type(last) == "string" and last ~= "" then name = name .. " " .. last end
            local key = guid or name
            if seen[key] then return end
            seen[key] = true
            list[#list + 1] = { key = key, guid = guid, name = name, class = class, unit = unit }
        end)
    end
    Add("player")
    if InRaid() then
        local n = 0
        pcall(function() n = GetNumGroupMembers() or 0 end)
        for i = 1, n do Add("raid" .. i) end
    else
        local n = 0
        pcall(function() n = GetNumSubgroupMembers() or 0 end)
        for i = 1, n do Add("party" .. i) end
    end
    C.byKey = {}
    for _, m in ipairs(list) do
        m.spec = DetectSpec(m)
        C.byKey[m.key] = m
    end
    C.members = list

    local p, changed = Plan(), false
    for i = 1, 40 do
        local e = p.slots[i]
        if e and e.key and not C.byKey[e.key] then p.slots[i] = nil changed = true end
    end
    -- what I assigned to somebody who is gone is forgotten
    for key in pairs(p.specs) do
        if not C.byKey[key] then p.specs[key] = nil end
    end
    return changed
end

-- the people of my group that are not in a planned group (the list on the left): by class, then name
function C.Unplaced()
    local placed = {}
    for i = 1, 40 do
        local e = Plan().slots[i]
        if e and e.key then placed[e.key] = true end
    end
    local out = {}
    for _, m in ipairs(C.members) do
        if not placed[m.key] then out[#out + 1] = m end
    end
    local order = {}
    for i, c in ipairs(CLASS_ORDER) do order[c] = i end
    table.sort(out, function(a, b)
        local oa, ob = order[a.class] or 99, order[b.class] or 99
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
    return out
end

-- what a slot holds, with its specialization: { spec = specKey or nil, name, class, real = bool, key } or nil
function C.Entry(i)
    local e = Plan().slots[i]
    if not e then return nil end
    if e.gen then
        local spec = C.BY_KEY[e.gen]
        if not spec then return nil end
        return { spec = spec.key, name = spec.gen, class = spec.class, real = false }
    end
    local m = C.byKey[e.key]
    if not m then return nil end
    return { spec = m.spec, name = m.name, class = m.class, real = true, key = m.key }
end

---------------------------------------------------------------------------
-- Moving things around
---------------------------------------------------------------------------
-- source: { kind = "player", key } (from the list), { kind = "spec", spec = specKey } (from the top), { kind = "slot", index } (from a group)
-- Dropped onto a slot: the one standing there is replaced (a real character is back in the list), or swapped for a slot that is moved.
function C.Drop(source, i)
    local p = Plan()
    if not i or i < 1 or i > p.size then return false end
    if source.kind == "slot" then
        local j = source.index
        if j == i or not p.slots[j] then return false end
        p.slots[i], p.slots[j] = p.slots[j], p.slots[i]
        return true
    elseif source.kind == "spec" then
        if not C.BY_KEY[source.spec or ""] then return false end
        p.slots[i] = { gen = source.spec }
        return true
    elseif source.kind == "player" then
        local m = C.byKey[source.key]
        if not m then return false end
        for j = 1, 40 do
            if p.slots[j] and p.slots[j].key == m.key then p.slots[j] = nil end     -- (never in two places)
        end
        p.slots[i] = { key = m.key }
        return true
    end
    return false
end

-- take it out of the groups: a generic one is gone, a real one is back in the list
function C.Remove(i)
    local p = Plan()
    if not p.slots[i] then return false end
    p.slots[i] = nil
    return true
end

-- the spec of a real character (nil = what we detect)
function C.SetSpec(key, specKey)
    local p = Plan()
    local m = C.byKey[key]
    if specKey == nil then
        p.specs[key] = nil
    elseif m and C.BY_KEY[specKey] and C.BY_KEY[specKey].class == m.class then
        p.specs[key] = specKey
    else
        return false
    end
    if m then m.spec = DetectSpec(m) end
    return true
end

---------------------------------------------------------------------------
-- The maths
---------------------------------------------------------------------------
-- Everything about the composition now.
--   roles:  { TANK, HEALER, DPS, unknown } (placed characters; unknown = a real one without a spec)
--   groups: [g] = { count, party = { [buffId] = { slots } } }
--   raid[id], debuff[id]: { slots = the slots of those who provide it }
--   party[id]: { groups = number of populated groups that have it, of = populated groups, status }
--   status (all of them): "ok" (green), "partial" (yellow, party buffs only), "missing" (red)
--   counts: { raid = {ok, total}, party = {ok, total}, debuff = {ok, total} }
function C.Analyze()
    local p = Plan()
    local res = { roles = { TANK = 0, HEALER = 0, DPS = 0, unknown = 0 }, groups = {}, raid = {}, party = {}, debuff = {},
                  counts = { raid = { 0, 0 }, party = { 0, 0 }, debuff = { 0, 0 } }, placed = 0 }
    for g = 1, p.size / 5 do res.groups[g] = { count = 0, party = {} } end
    local entries = {}
    for i = 1, p.size do
        local e = C.Entry(i)
        if e then
            entries[#entries + 1] = { slot = i, group = C.GroupOf(i), spec = e.spec }
            res.placed = res.placed + 1
            res.groups[C.GroupOf(i)].count = res.groups[C.GroupOf(i)].count + 1
            local spec = C.BY_KEY[e.spec or ""]
            if spec then res.roles[spec.role] = res.roles[spec.role] + 1 else res.roles.unknown = res.roles.unknown + 1 end
        end
    end
    local populated = 0
    for _, g in ipairs(res.groups) do if g.count > 0 then populated = populated + 1 end end

    for _, b in ipairs(C.BUFFS) do
        local slots, perGroup = {}, {}
        for _, en in ipairs(entries) do
            if C.Provides(b, en.spec) then
                slots[#slots + 1] = en.slot
                perGroup[en.group] = perGroup[en.group] or {}
                table.insert(perGroup[en.group], en.slot)
            end
        end
        local counts = res.counts[b.scope]
        counts[2] = counts[2] + 1
        if b.scope == "party" then
            local have = 0
            for g, list in pairs(perGroup) do
                have = have + 1
                res.groups[g].party[b.id] = list
            end
            local status = (populated > 0 and have == populated) and "ok" or (have > 0 and "partial" or "missing")
            if status == "ok" then counts[1] = counts[1] + 1 end
            res.party[b.id] = { groups = have, of = populated, status = status, slots = slots }
        else
            local status = #slots > 0 and "ok" or "missing"
            if status == "ok" then counts[1] = counts[1] + 1 end
            res[b.scope][b.id] = { slots = slots, status = status }
        end
    end
    return res
end

---------------------------------------------------------------------------
-- The group changed: look again a moment later (the window refreshes itself)
---------------------------------------------------------------------------
local queued = false
function C.OnRoster()
    if queued then return end
    queued = true
    ns.After(0.5, function()
        queued = false
        if ns.UI and ns.UI.RefreshComposition then ns.UI.RefreshComposition() end
    end)
end
