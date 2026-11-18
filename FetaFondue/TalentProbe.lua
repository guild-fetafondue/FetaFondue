---@class ns
local ns = select(2, ...)

---------------------------------------------------------------------------
-- /ff talentprobe        what the game offers for talents, and what MY active talent tree looks like
-- /ff talentprobe view   also borrows the game's "view" config to load a whole spec tree (default: my spec)
-- /ff talentprobe view <specID>   the same for another spec, for example 253 (Beast Mastery Hunter)
-- Nothing here changes anything; it only reads and prints. (The view test borrows the config the game's
-- own inspect window uses, so close any talent window first.)
---------------------------------------------------------------------------
local function Say(text) ns.Print(text) end

local function Has(tbl, name)
    return tbl ~= nil and type(tbl[name]) == "function"
end

local function Names(tbl, label, names)
    local have, missing = {}, {}
    for _, n in ipairs(names) do
        if Has(tbl, n) then have[#have + 1] = n else missing[#missing + 1] = n end
    end
    Say(("%s: have %s%s"):format(label, #have > 0 and table.concat(have, ", ") or "none",
        #missing > 0 and ("  |  missing: " .. table.concat(missing, ", ")) or ""))
end

local function SpellName(id)
    local name
    pcall(function()
        if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id)
        elseif GetSpellInfo then name = (GetSpellInfo(id)) end
    end)
    return name or "?"
end

-- what one trait config contains
local function Analyze(configID, label)
    local ok, err = pcall(function()
        local cfg = C_Traits.GetConfigInfo(configID)
        if not cfg then Say(label .. ": no config info for id " .. tostring(configID)) return end
        local treeIDs = cfg.treeIDs or {}
        Say(("%s (config %s): %d tree(s)"):format(label, tostring(configID), #treeIDs))
        for _, treeID in ipairs(treeIDs) do
            local ids = C_Traits.GetTreeNodes(treeID) or {}
            local visible, ranked, edges, choice, withSub = 0, 0, 0, 0, 0
            local subs = {}
            local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
            local xs, noPos = {}, 0
            local sample = {}
            for _, nodeID in ipairs(ids) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                if node and node.isVisible ~= false and (node.maxRanks or 0) > 0 then
                    visible = visible + 1
                    if (node.activeRank or 0) > 0 then ranked = ranked + 1 end
                    edges = edges + #(node.visibleEdges or {})
                    if node.entryIDs and #node.entryIDs > 1 then choice = choice + 1 end
                    if (node.subTreeID or 0) > 0 then withSub = withSub + 1 subs[node.subTreeID] = true end
                    if node.posX and node.posY then
                        minX, maxX = math.min(minX, node.posX), math.max(maxX, node.posX)
                        minY, maxY = math.min(minY, node.posY), math.max(maxY, node.posY)
                        xs[node.posX] = true
                    else
                        noPos = noPos + 1
                    end
                    if #sample < 3 then
                        local spell
                        local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
                        if entryID then
                            local entry = C_Traits.GetEntryInfo(configID, entryID)
                            local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                            spell = def and def.spellID
                        end
                        sample[#sample + 1] = ("node %s at %s,%s rank %s/%s spell %s (%s)"):format(
                            tostring(node.ID), tostring(node.posX), tostring(node.posY), tostring(node.activeRank), tostring(node.maxRanks),
                            tostring(spell), spell and SpellName(spell) or "-")
                    end
                end
            end
            -- talents that sit outside the usual grid (more than 8 rows or 5 columns away from the others)
            local strays = {}
            for _, nodeID in ipairs(ids) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                if node and node.isVisible ~= false and (node.maxRanks or 0) > 0 and node.posY and node.posY > 2130 + 8 * 600 then
                    local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
                    local spell
                    if entryID then
                        local entry = C_Traits.GetEntryInfo(configID, entryID)
                        local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                        spell = def and def.spellID
                    end
                    strays[#strays + 1] = ("%s at %s,%s"):format(spell and SpellName(spell) or tostring(node.ID), tostring(node.posX), tostring(node.posY))
                end
            end
            if #strays > 0 then Say("  talents far below the grid: " .. table.concat(strays, "; ")) end
            local distinctX = 0
            for _ in pairs(xs) do distinctX = distinctX + 1 end
            local subList = {}
            for id in pairs(subs) do subList[#subList + 1] = tostring(id) end
            Say(("  tree %s: %d nodes, %d visible, %d with ranks, %d choice nodes, %d lines"):format(
                tostring(treeID), #ids, visible, ranked, choice, edges))
            if visible > 0 then
                Say(("  positions: x %s..%s (%d different), y %s..%s, nodes without position: %d"):format(
                    tostring(minX), tostring(maxX), distinctX, tostring(minY), tostring(maxY), noPos))
                Say(("  hero sub trees: %d nodes in %d sub tree(s) %s"):format(withSub, #subList, #subList > 0 and ("[" .. table.concat(subList, ",") .. "]") or ""))
                for _, line in ipairs(sample) do Say("  " .. line) end
            end
            -- where the sub trees sit (the game centres their nodes on this point)
            if #subList > 0 and Has(C_Traits, "GetSubTreeInfo") then
                local sid = tonumber(subList[1])
                local info = C_Traits.GetSubTreeInfo(configID, sid)
                if info then Say(("  sub tree %s: at %s,%s name %s"):format(subList[1], tostring(info.posX), tostring(info.posY), tostring(info.name))) end
            end
        end
    end)
    if not ok then Say(label .. ": reading failed: " .. tostring(err)) end
end

local function CurrentSpecID()
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

-- how many talents have points in a config
local function CountRanks(configID)
    local n, points = 0, 0
    pcall(function()
        local cfg = C_Traits.GetConfigInfo(configID)
        for _, treeID in ipairs(cfg and cfg.treeIDs or {}) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                local r = node and (node.activeRank or node.ranksPurchased) or 0
                if r > 0 then n = n + 1 points = points + r end
            end
        end
    end)
    return n, points
end

-- dual specialization: what the game offers for a second talent setup
local function DualSpec(specID)
    Say(("dual spec calls: GetNumTalentGroups=%s, GetActiveTalentGroup=%s, GetNumSpecGroups=%s, GetActiveSpecGroup=%s"):format(
        tostring(GetNumTalentGroups ~= nil and GetNumTalentGroups()), tostring(GetActiveTalentGroup ~= nil and GetActiveTalentGroup()),
        tostring(C_SpecializationInfo and C_SpecializationInfo.GetNumSpecGroups and C_SpecializationInfo.GetNumSpecGroups()),
        tostring(C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup())))
    local active
    pcall(function() active = C_ClassTalents.GetActiveConfigID() end)
    local function ListConfigs(label, sid)
        pcall(function()
            local ids = C_ClassTalents.GetConfigIDsBySpecID(sid) or {}
            Say(("saved configs of specialization %s (%s): %d"):format(tostring(sid), label, #ids))
            for _, id in ipairs(ids) do
                local info = C_Traits.GetConfigInfo(id)
                local nodes, points = CountRanks(id)
                Say(("  config %s '%s'%s: %d talents with %d points"):format(tostring(id), tostring(info and info.name), id == active and " (ACTIVE)" or "", nodes, points))
            end
        end)
    end
    if Has(C_ClassTalents, "GetConfigIDsBySpecID") then
        ListConfigs("mine", specID)
        pcall(function()
            local info = C_SpecializationInfo
            local _, _, classID = UnitClass("player")
            local n = info and info.GetNumSpecializationsForClassID and info.GetNumSpecializationsForClassID(classID) or 0
            Say(("specializations of my class: %s"):format(tostring(n)))
            for i = 1, n do
                local sid = info.GetSpecializationInfoForClassID and (info.GetSpecializationInfoForClassID(classID, i))
                if sid and sid ~= specID then ListConfigs("other specialization of my class", sid) end
            end
        end)
    else
        Say("C_ClassTalents.GetConfigIDsBySpecID is missing: no saved configs to read")
    end
    pcall(function()
        if Has(C_ClassTalents, "GetLastSelectedSavedConfigID") then
            Say("last selected saved config of my spec: " .. tostring(C_ClassTalents.GetLastSelectedSavedConfigID(specID)))
        end
    end)
end

function ns.TalentProbe(args)
    Say("Talent probe (read-only)")
    Say(("tables: C_ClassTalents=%s, C_Traits=%s, C_SpecializationInfo=%s, Constants.TraitConsts=%s, PlayerUtil=%s"):format(
        tostring(C_ClassTalents ~= nil), tostring(C_Traits ~= nil), tostring(C_SpecializationInfo ~= nil),
        tostring(Constants ~= nil and Constants.TraitConsts ~= nil), tostring(PlayerUtil ~= nil)))
    Names(C_ClassTalents, "C_ClassTalents", { "GetActiveConfigID", "InitializeViewLoadout", "ViewLoadout", "GetLoadoutExportString" })
    Names(C_Traits, "C_Traits", { "GetConfigInfo", "GetTreeNodes", "GetNodeInfo", "GetEntryInfo", "GetDefinitionInfo", "GetSubTreeInfo",
        "GenerateImportString", "GenerateInspectImportString", "HasValidInspectData" })
    Names(C_SpecializationInfo, "C_SpecializationInfo", { "GetSpecialization", "GetSpecializationInfo", "GetInspectSpecialization", "GetSpecializationInfoByID" })
    local tc = Constants and Constants.TraitConsts
    Say(("config ids: VIEW=%s, INSPECT=%s"):format(tostring(tc and tc.VIEW_TRAIT_CONFIG_ID), tostring(tc and tc.INSPECT_TRAIT_CONFIG_ID)))
    local lineOK = false
    pcall(function()
        local f = CreateFrame("Frame")
        lineOK = f.CreateLine ~= nil and f:CreateLine() ~= nil
    end)
    Say(("drawing: lines between talents %s, spell textures %s"):format(
        lineOK and "supported" or "NOT supported", (C_Spell and C_Spell.GetSpellTexture) and "C_Spell.GetSpellTexture" or (GetSpellTexture and "GetSpellTexture" or "none")))

    local specID = CurrentSpecID()
    Say("my specialization id: " .. tostring(specID) .. ", level " .. tostring(UnitLevel("player")))

    -- my own tree
    local configID
    pcall(function() configID = C_ClassTalents.GetActiveConfigID() end)
    if configID then
        Analyze(configID, "my active talents")
        pcall(function()
            if Has(C_Traits, "GenerateImportString") then
                local s = C_Traits.GenerateImportString(configID)
                Say("my loadout string: " .. (type(s) == "string" and (#s .. " characters") or tostring(s)))
            end
        end)
    else
        Say("no active talent config: the game has no talents for this character (yet)")
    end

    DualSpec(specID)

    -- a whole spec tree through the view config
    local word, want = (args or ""):match("^%s*(%S*)%s*(%S*)")
    if (word or ""):lower() == "view" then
        local spec = tonumber(want) or specID
        if not spec then
            Say("view test: no specialization id (pass one: /ff talentprobe view 253)")
        elseif not (Has(C_ClassTalents, "InitializeViewLoadout") and Has(C_ClassTalents, "ViewLoadout") and tc and tc.VIEW_TRAIT_CONFIG_ID) then
            Say("view test: the game does not offer the view-config calls here")
        else
            Say(("view test: loading the tree of specialization %s into the game's view config"):format(tostring(spec)))
            local ok, err = pcall(function()
                C_ClassTalents.InitializeViewLoadout(spec, UnitLevel("player") or 10)
                C_ClassTalents.ViewLoadout({})
            end)
            if not ok then
                Say("view test failed: " .. tostring(err))
            else
                Analyze(tc.VIEW_TRAIT_CONFIG_ID, "spec " .. tostring(spec) .. " from the view config")
            end
        end
    else
        Say("(add 'view' to also load a whole spec tree: /ff talentprobe view  or  /ff talentprobe view 253)")
    end
end
