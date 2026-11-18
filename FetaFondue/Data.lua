---@class ns
local ns = select(2, ...)

-- Shown when you are not in a guild (or the game has not told us the name yet).
ns.GUILD_FALLBACK = "FetaFondue"

-- Profession skill line IDs -> English display names. Skill line IDs do not depend on the
-- game language, so guildies on different language clients still agree on the profession.
ns.PROFESSIONS = {
    [129] = "First Aid",
    [164] = "Blacksmithing",
    [165] = "Leatherworking",
    [171] = "Alchemy",
    [182] = "Herbalism",
    [185] = "Cooking",
    [186] = "Mining",
    [197] = "Tailoring",
    [202] = "Engineering",
    [333] = "Enchanting",
    [356] = "Fishing",
    [393] = "Skinning",
    [755] = "Jewelcrafting",
    [773] = "Inscription",
}

-- Window titles that differ from the profession name.
ns.PROFESSION_ALIASES = {
    smelting = 186, -- the Mining profession window is called Smelting
}

ns.PROFESSION_BY_NAME = {}
for id, name in pairs(ns.PROFESSIONS) do
    ns.PROFESSION_BY_NAME[name:lower()] = id
end
for name, id in pairs(ns.PROFESSION_ALIASES) do
    ns.PROFESSION_BY_NAME[name] = id
end

-- Where is a guildie? The guild roster tells us the zone name (English client). A zone matches if its
-- name CONTAINS one of these. Add more in-game: /ff addzone dungeon|raid|capital <zone name>
ns.ZONES = {
    raid = {
        "molten core", "onyxia's lair", "blackwing lair", "zul'gurub", "ruins of ahn'qiraj",
        "temple of ahn'qiraj", "naxxramas", "barrow deeps", "hyjal summit",
    },
    dungeon = {
        "ragefire chasm", "the deadmines", "deadmines", "wailing caverns", "shadowfang keep",
        "blackfathom deeps", "the stockade", "stormwind stockade", "gnomeregan",
        "razorfen kraul", "scarlet monastery", "razorfen downs", "uldaman", "zul'farrak",
        "maraudon", "temple of atal'hakkar", "sunken temple", "blackrock depths",
        "blackrock spire", "dire maul", "scholomance", "stratholme",
        "ruins of lordaeron", "hall of thanes",
    },
    capital = {
        "stormwind city", "ironforge", "darnassus", "orgrimmar", "thunder bluff", "undercity",
    },
}

-- Every dungeon of Forever with its bosses in the order of the dungeon. A boss written "Name (rare)" is a rare: it counts as a boss
-- kill but is never the last boss. "A or B" means the dungeon has one of the two. The LAST boss that is not a rare is the final
-- boss: killing it is "dungeon cleared" (ns.FINAL_BOSSES is built from this list below). `zone` is the name of the zone (any
-- part of it, lowercase) as the guild roster shows it. Names must match what the game reports for the encounter; add missing
-- ones in-game with /ff addboss <name>.
ns.DUNGEONS = {
    { name = "Hall of Thanes", zone = "hall of thanes", bosses = { "Faldrim Anvilmar", "Magmatus", "Plunder", "Durgen Dirgehammer" } },
    { name = "Wailing Caverns", zone = "wailing caverns", bosses = { "Lord Cobrahn", "Lady Anacondra", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis", "Verdan the Everliving", "Mutanus the Devourer", "Deviate Faerie Dragon (rare)" } },
    { name = "Ruins of Lordaeron", zone = "ruins of lordaeron", bosses = { "The Baron", "Witherfang", "The Abandoned", "Bjork", "Rath'mael", "Viktor the Vile", "Lordaeron Captain (rare)" } },
    { name = "The Deadmines", zone = "deadmines", bosses = { "Rhahk'Zor", "Miner Johnson (rare)", "Sneed's Shredder", "Sneed", "Gilnid", "Mr. Smite", "Captain Greenskin", "Edwin VanCleef", "Cookie" } },
    { name = "Blackfathom Deeps", zone = "blackfathom deeps", bosses = { "Ghamoo-ra", "Lady Sarevess", "Gelihast", "Lorgus Jett", "Old Serra'kis", "Twilight Lord Kelris", "Aku'mai" } },
    { name = "Ragefire Chasm", zone = "ragefire chasm", bosses = { "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" } },
    { name = "Shadowfang Keep", zone = "shadowfang keep", bosses = { "Rethilgore", "Fel Steed or Shadow Charger", "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher", "Deathsworn Captain (rare)", "Arugal's Voidwalker", "Fenrus the Devourer", "Wolf Master Nandos", "Archmage Arugal" } },
    { name = "The Stockade", zone = "stockade", bosses = { "Targorr the Dread", "Kam Deepfury", "Hamhock", "Dextren Ward", "Bazil Thredd", "Bruegal Ironknuckle (rare)" } },
    { name = "Excavation Site: Wetlands", zone = "excavation site", bosses = { "Saltspine", "Shadetooth", "Relic Guardian" } },
    { name = "City of Dalaran", zone = "city of dalaran", bosses = { "Atrexis the Grave Knight", "Arcane Anomaly", "Fel Ancient", "Unstable Sentinel", "Mana Devourer", "Arcanic Enigma", "Lyn the Ignored (rare)", "Shade of the Archmage" } },
    { name = "Gnomeregan", zone = "gnomeregan", bosses = { "Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60", "Mekgineer Thermaplugg", "Dark Iron Ambassador (rare)" } },
    { name = "Razorfen Kraul", zone = "razorfen kraul", bosses = { "Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk", "Agathelos the Raging", "Charlga Razorflank", "Blind Hunter (rare)", "Earthcaller Halmgar (rare)" } },
    { name = "Scarlet Monastery: Graveyard", zone = "scarlet monastery", bosses = { "Interrogator Vishas", "Azshir the Sleepless (rare)", "Fallen Champion (rare)", "Ironspine (rare)", "Bloodmage Thalnos" } },
    { name = "Scarlet Monastery: Library", zone = "scarlet monastery", bosses = { "Houndmaster Loksey", "Arcanist Doan" } },
    { name = "Scarlet Monastery: Armory", zone = "scarlet monastery", bosses = { "Herod" } },
    { name = "Scarlet Monastery: Cathedral", zone = "scarlet monastery", bosses = { "High Inquisitor Fairbanks", "Scarlet Commander Mograine", "High Inquisitor Whitemane" } },
    { name = "Razorfen Downs", zone = "razorfen downs", bosses = { "Tuten'kash", "Plaguemaw the Rotting", "Mordresh Fire Eye", "Glutton", "Ragglesnout (rare)", "Amnennar the Coldbringer" } },
    { name = "Uldaman", zone = "uldaman", bosses = { "Revelosh", "The Lost Dwarves", "Ironaya", "Obsidian Sentinel", "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas" } },
    { name = "Zul'Farrak", zone = "zul'farrak", bosses = { "Theka the Martyr", "Antu'sul", "Witch Doctor Zum'rah", "Nekrum Gutchewer", "Shadowpriest Sezz'ziz", "Sergeant Bly", "Hydromancer Velratha", "Gahz'rilla", "Zerillis (rare)", "Sandarr Dunereaver (rare)", "Dustwraith (rare)", "Ruuzlu", "Chief Ukorz Sandscalp" } },
    { name = "The Drowned City", zone = "drowned city", bosses = { "Zul'Alai", "Var'Taka", "Captain Dreadrise", "Deathless Marrow", "Gill (rare)", "Umbra (rare)", "\"Pyromancer\" Braxton (rare)", "Min'loth the Serpent" } },
    { name = "Krol'dok Stronghold", zone = "krol'dok", bosses = { "Slavecrusher Grox", "Twilight Commander Zarmok", "War Handler Ashka", "Nar'gurk", "Bossman Toof", "Kroog (rare)", "Overlord Mugg" } },
    { name = "Alcaz Prison", zone = "alcaz prison", bosses = { "Overseer Wrex", "The Questioner", "Tidemistress Ca'zass", "Katerina the Cleaner", "Blazeroar" } },
    { name = "Blackmaw Hold", zone = "blackmaw hold", bosses = { "Impaan the Imprisoner", "Bonesnout the Unbroken", "Moontouched Wanderer (rare)", "Gortek the Apprentice (rare)", "Tunnelweb Matriarch (rare)", "Withermaw", "Elder Shaman Bloodmane", "Blackmaw Behemoth", "Unbound Spirit", "Varrox Bleakhoof" } },
    { name = "Shaper's Terrace", zone = "shaper's terrace", bosses = { "Titanosaur", "Venomridge", "Thunderhoof", "Direhorn Matriarch", "Cinder", "Bolt", "Snowtalon", "Vitrix", "Izha'Rel and Tor'Rel", "Nanaya" } },
    { name = "Sunken Temple", zone = "sunken temple", bosses = { "Altar Bosses", "Gasher", "Hukku", "Loro", "Mijan", "Zolo", "Zul'Lor", "Atal'alarion", "Morphaz & Hazzas", "Jammal'an the Prophet", "Ogom the Wretched", "Dreamscythe & Weaver", "Shade of Eranikus", "Avatar of Hakkar" } },
    { name = "Scholomance", zone = "scholomance", bosses = { "Kirtonos the Herald", "Jandice Barov", "Rattlegore", "Marduk Blackpool", "Vectus", "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov", "Lorekeeper Polkelt", "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov", "Darkmaster Gandling" } },
    { name = "Maraudon", zone = "maraudon", bosses = { "Noxxion", "Razorlash", "Lord Vyletongue", "Meshlok the Harvester (rare)", "Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras" } },
    { name = "Dire Maul: East", zone = "dire maul", bosses = { "Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper" } },
    { name = "Dire Maul: West", zone = "dire maul", bosses = { "Tendris Warpwood", "Tsu'zee (rare)", "Magister Kalendris", "Illyanna Ravenoak", "Immol'thar", "Lord Hel'nurath", "Prince Tortheldrin" } },
    { name = "Dire Maul: North", zone = "dire maul", bosses = { "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush", "Cho'Rush the Observer", "King Gordok" } },
    { name = "Stratholme: Living", zone = "stratholme", bosses = { "Skul (rare)", "Hearthsinger Forresten (rare)", "The Unforgiven", "Timmy the Cruel", "Malor the Zealous", "Postmaster Malown", "Cannon Master Willey", "Archivist Galford", "Balnazzar" } },
    { name = "Stratholme: Undead", zone = "stratholme", bosses = { "Stonespine (rare)", "Nerub'enkan", "Baroness Anastari", "Maleki the Pallid", "Magistrate Barthilas", "Ramstein the Gorger", "Baron Rivendare" } },
    { name = "Blackrock Depths", zone = "blackrock depths", bosses = { "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Gorosh the Dervish", "Grizzle", "Eviscerator", "Ok'thor the Breaker", "Anub'shiah", "Hedrum the Creeper", "Theldren (rare)", "Pyromancer Loregrain", "Fineous Darkvire", "Warder Stilgiss", "Lord Incendius", "Bael'Gar", "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx", "Ribbly Screwspigot", "Plugger Spazzring", "Ambassador Flamelash", "Panzor the Invincible (rare)", "The Seven", "Magmus", "Princess Moira Bronzebeard", "Emperor Dagran Thaurissan" } },
    { name = "Upper Blackrock Spire", zone = "blackrock spire", bosses = { "Pyroguard Emberseer", "Solakar Flamewreath", "Jed Runewatcher (rare)", "Goraluk Anvilcrack", "Gyth", "Warchief Rend Blackhand", "The Beast", "Lord Valthalak (rare)", "General Drakkisath" } },
    { name = "Lower Blackrock Spire", zone = "blackrock spire", bosses = { "Spirestone Butcher (rare)", "Spirestone Battle Lord (rare)", "Spirestone Lord Magus (rare)", "Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb", "Crystal Fang (rare)", "Urok Doomhowl", "Bannok Grimaxe (rare)", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener", "Ghok Bashguud (rare)", "Overlord Wyrmthalak" } },
}

-- One entry per boss, in the order of the dungeon: { name = lowercase name, rare = bool, alt = the other name of an "A or B" boss }
-- and the final boss (the last boss that is not a rare) as a lowercase name. Built once from ns.DUNGEONS.
ns.FINAL_BOSSES = {}
ns.DUNGEON_BOSSES = {}
for _, d in ipairs(ns.DUNGEONS) do
    d.list = {}
    for _, raw in ipairs(d.bosses) do
        local name, rare = raw, false
        local base = raw:match("^(.-)%s*%(rare%)$")
        if base then name, rare = base, true end
        local first, second = name:match("^(.-) or (.+)$")
        local entry = { name = (first or name):lower(), rare = rare, alt = second and second:lower() or nil }
        d.list[#d.list + 1] = entry
        ns.DUNGEON_BOSSES[entry.name] = true
        if entry.alt then ns.DUNGEON_BOSSES[entry.alt] = true end
    end
    for i = #d.list, 1, -1 do
        if not d.list[i].rare then
            d.final = d.list[i].name
            ns.FINAL_BOSSES[d.final] = d.name
            break
        end
    end
end

-- Bosses that were once taken for a final boss but are not (the last boss of the dungeon comes after them). Older versions
-- shared their encounter ids with everybody; those are ignored again when the name is known.
ns.NOT_FINAL_BOSSES = { ["edwin vancleef"] = true, ["shade of eranikus"] = true, ["immol'thar"] = true }

-- the zone names of the dungeons above join the list the roster uses (a zone matches when its name contains one of these)
do
    local have = {}
    for _, z in ipairs(ns.ZONES.dungeon) do have[z] = true end
    for _, d in ipairs(ns.DUNGEONS) do
        if not have[d.zone] then have[d.zone] = true ns.ZONES.dungeon[#ns.ZONES.dungeon + 1] = d.zone end
    end
end

-- Profession filter buttons in the Guild Workshop (skill line IDs, in button order) and their icons.
ns.PROFESSION_ORDER = { 171, 164, 333, 202, 182, 165, 186, 393, 197, 185, 129, 356 }
ns.PROFESSION_ICONS = {
    [171] = "Interface\\Icons\\Trade_Alchemy",
    [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [333] = "Interface\\Icons\\Trade_Engraving",
    [202] = "Interface\\Icons\\Trade_Engineering",
    [182] = "Interface\\Icons\\Trade_Herbalism",
    [165] = "Interface\\Icons\\INV_Misc_ArmorKit_17",
    [186] = "Interface\\Icons\\Trade_Mining",
    [393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    [197] = "Interface\\Icons\\Trade_Tailoring",
    [185] = "Interface\\Icons\\INV_Misc_Food_15",
    [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    [356] = "Interface\\Icons\\Trade_Fishing",
}

-- The Admin tab (who runs which version, sync state, errors) is for the characters below: a name (compared
-- without case, spaces, dashes and realm part) or a character GUID (/ff whoami shows yours).
-- This is a convenience, not a lock: anybody can edit the Lua files of their own copy, but everything the tab shows
-- is already sent between everybody's addons anyway.
ns.ADMIN_NAMES = { ["purple xtazy"] = true }
ns.ADMIN_GUIDS = { ["Player-6841-0005D871"] = true }

-- the invite of the guild's Discord server (the "Advertise Discord" button on the Events tab puts it into the chat box)
ns.DISCORD_INVITE = "https://discord.gg/bTdTCajssb"

-- Races travel between clients as the game's language independent token ("NightElf"), and are shown in
-- English. Older versions sent the localized name: anything unknown is shown as it came.
ns.RACE_NAMES = {
    Human = "Human", Dwarf = "Dwarf", NightElf = "Night Elf", Gnome = "Gnome", Draenei = "Draenei", Worgen = "Worgen",
    Orc = "Orc", Scourge = "Undead", Tauren = "Tauren", Troll = "Troll", BloodElf = "Blood Elf", Goblin = "Goblin",
    Pandaren = "Pandaren", Dracthyr = "Dracthyr", VoidElf = "Void Elf", LightforgedDraenei = "Lightforged Draenei",
    DarkIronDwarf = "Dark Iron Dwarf", KulTiran = "Kul Tiran", Mechagnome = "Mechagnome", Nightborne = "Nightborne",
    HighmountainTauren = "Highmountain Tauren", MagharOrc = "Mag'har Orc", ZandalariTroll = "Zandalari Troll", Vulpera = "Vulpera",
}
function ns.RaceName(r)
    r = tostring(r or "")
    return ns.RACE_NAMES[r] or r
end

-- The raids of the guild's raid achievements (Achievements.lua). The guild has cleared a raid when its last boss dies
-- with 5 or more guildies in the group. The details of the raids on WoW Forever are not all known yet, so this table
-- says how to recognise each raid (the instance name in English, or the instance id) and which boss is the last
-- (English name, or encounter id: ids are the same in every language). `/ff raids` shows what the game reports in a
-- raid, `/ff addraidboss <onyxia|hyjal|barrow> <name or id>` adds a last boss without a new version of the addon.
-- `ignoreCriteria` = numbers of steps of the game's raid achievement that are no boss kill (set aside for everybody; see /ff raids).
ns.RAID_CLEARS = {
    { key = "R:ONYXIA", short = "onyxia", names = { "onyxia's lair" }, ids = { 249 }, final = { "onyxia" }, finalIDs = {} },
    { key = "R:HYJAL", short = "hyjal", names = { "hyjal summit", "the battle for mount hyjal", "mount hyjal" }, ids = { 534 }, final = { "archimonde" }, finalIDs = {} },
    { key = "R:BARROW", short = "barrow", names = { "barrow deeps", "the barrow deeps" }, ids = {}, final = {}, finalIDs = {} },
}

-- The officer who is the master looter of the guild's raids (when he is in the raid and is not the one who invites everybody).
-- The name as it is in the guild roster. Set to nil for "the leader".
ns.MASTER_LOOTER = "Johnny Kashor"

---------------------------------------------------------------------------
-- Guild join dates the game does not give. Everybody who was already in the guild when the addon first looked is dated
-- 5 November 2026 (not exact). New members after that are dated by the addon the day it first sees them, and exact dates are
-- shared between the addons (a date before JOIN_DEFAULT is not believed: the addon did not exist yet).
-- (Until 1.0.0 a hand-made list of exact dates for 15 members lived here; every client has copied it into its saved data,
-- and the addons now share it with each other.)
ns.JOIN_DEFAULT = { 2026, 11, 5 }
