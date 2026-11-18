---@class ns
local ns = select(2, ...)
local K = ns.K
local NewWindow, ItemData, QUALITY_HEX, Shifted, SendToChat, Gold, Gray, QUESTION, BOX_BACKDROP, AgeText =
    K.NewWindow, K.ItemData, K.QUALITY_HEX, K.Shifted, K.SendToChat, K.Gold, K.Gray, K.QUESTION, K.BOX_BACKDROP, K.AgeText

---------------------------------------------------------------------------
-- Inspect window. On top, for both tabs: name and level, class, race, and the role (tank, healer or damage)
-- worked out from where the talent points are. Gear tab: a paper doll like the character panel.
-- Talents tab: the class's talent trees, laid out by the game's own data, with the points picked.
---------------------------------------------------------------------------
local WIN_W, WIN_H = 770, 750
local win = NewWindow("FetaFondueInspect", WIN_W, WIN_H)
win:SetFrameStrata("FULLSCREEN")
win:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
win:SetMovable(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)

local insp = { guid = nil, member = nil, fresh = false, waiting = false, tab = "gear", specIndex = nil }

-- header --------------------------------------------------------------------------------
local nameText = win:Text("GameFontNormalLarge", 28, -44, 480)
local classText = win:Text("GameFontHighlight", 28, -70, 700)
local raceText = win:Text("GameFontHighlight", 28, -88, 700)
local roleText = win:Text("GameFontNormalLarge", 28, -108, 300)
pcall(roleText.SetFont, roleText, "Fonts\\MORPHEUS.TTF", 22, "OUTLINE")   -- a different font for the role
-- right side: online (green glow) or last seen (gray), and the day the member joined the guild
local presenceText = win:Text("GameFontNormal", 520, -48, 220, "RIGHT")
pcall(presenceText.SetFont, presenceText, "Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
local joinedText = win:Text("GameFontDisable", 520, -70, 220, "RIGHT")
local altsText = win:Text("GameFontDisableSmall", 440, -88, 300, "RIGHT")
local roleTree = win:Text("GameFontDisable", 330, -114, 360)      -- (the other spec, when there are two)
local statusText = win:Text("GameFontDisableSmall", 28, -140, 700)

-- tabs ---------------------------------------------------------------------------------
local PANE_W, PANE_H = 722, 490
local function NewTab(x, label)
    local b = K.NewButton(win, label)
    b:SetSize(110, 24)
    b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -160)
    return b
end
local gearTab = NewTab(28, "Gear")
local talentTab = NewTab(144, "Talents")

local function NewPane()
    local pane = CreateFrame("Frame", nil, win, "BackdropTemplate")
    pane:SetBackdrop(BOX_BACKDROP)
    pane:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    pane:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    pane:SetPoint("TOPLEFT", win, "TOPLEFT", 24, -190)
    pane:SetSize(PANE_W, PANE_H)
    return pane
end
local gearPane = NewPane()
local talentPane = NewPane()

local function HexToRGB(hex)
    local r, g, b = hex:match("^(%x%x)(%x%x)(%x%x)$")
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

---------------------------------------------------------------------------
-- Gear: slots left and right of the crest, weapons underneath
---------------------------------------------------------------------------
local SLOT = 46
local LEFT_SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT_SLOTS = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM_SLOTS = { 16, 17, 18 }
local slotInfo = {}
for _, s in ipairs(ns.Inspect.SLOTS) do slotInfo[s[1]] = { label = s[2], pic = s[3] } end

-- the game's own name for each slot: GetInventorySlotInfo gives the art of an empty slot for exactly this client
local SLOT_NAMES = {
    [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [4] = "ShirtSlot", [5] = "ChestSlot", [6] = "WaistSlot",
    [7] = "LegsSlot", [8] = "FeetSlot", [9] = "WristSlot", [10] = "HandsSlot", [11] = "Finger0Slot", [12] = "Finger1Slot",
    [13] = "Trinket0Slot", [14] = "Trinket1Slot", [15] = "BackSlot", [16] = "MainHandSlot", [17] = "SecondaryHandSlot",
    [18] = "RangedSlot", [19] = "TabardSlot",
}
-- The game may give the picture as a path or as a file number. A slot that gets nothing from the game borrows the picture of
-- its twin (trinket 2 from trinket 1, ring 2 from ring 1, off hand from main hand) so it never stays a black square.
local TWIN = { [12] = 11, [14] = 13, [17] = 16 }
local function GameSlotArt(id)
    local art
    pcall(function()
        if GetInventorySlotInfo and SLOT_NAMES[id] then
            local _, tex = GetInventorySlotInfo(SLOT_NAMES[id])
            if (type(tex) == "string" and tex ~= "") or (type(tex) == "number" and tex > 0) then art = tex end
        end
    end)
    return art
end
local function EmptySlotArt(id)
    return GameSlotArt(id) or (TWIN[id] and GameSlotArt(TWIN[id])) or ("Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. slotInfo[id].pic)
end

-- The ranged slot holds different things for different classes: bows, guns, crossbows and thrown weapons (hunter, warrior, rogue),
-- wands (mage, priest, warlock) and relics (paladin librams, shaman totems, druid idols).
local RANGED = {
    HUNTER = { "Ranged (bow, crossbow or gun)" }, WARRIOR = { "Ranged (bow, crossbow, gun or thrown)" }, ROGUE = { "Ranged (bow, crossbow, gun or thrown)" },
    MAGE = { "Wand" }, PRIEST = { "Wand" }, WARLOCK = { "Wand" },
    PALADIN = { "Relic (libram)", true }, SHAMAN = { "Relic (totem)", true }, DRUID = { "Relic (idol)", true },
}
local function RangedInfo(classFile)
    local r = RANGED[classFile or ""]
    if not r then return slotInfo[18].label, nil end
    return r[1], r[2] and "Interface\\PaperDoll\\UI-PaperDoll-Slot-Relic" or nil
end

local slots = {}
local function NewSlot(id, x, y)
    local b = CreateFrame("Button", nil, gearPane, "BackdropTemplate")
    b:SetSize(SLOT, SLOT)
    b:SetPoint("TOPLEFT", gearPane, "TOPLEFT", x, y)
    b:SetBackdrop(BOX_BACKDROP)
    b:SetBackdropColor(0.03, 0.03, 0.035, 1)
    b:SetBackdropBorderColor(0.3, 0.3, 0.33, 1)
    b.empty = b:CreateTexture(nil, "BACKGROUND")
    b.empty:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -5)
    b.empty:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -5, 5)
    b.empty:SetTexture(EmptySlotArt(id))
    b.empty:SetAlpha(0.65)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.icon:Hide()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.12)
    b.slotID = id
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemString then
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.itemString)
            if (GameTooltip:NumLines() or 0) == 0 then GameTooltip:SetText(self.itemName or self.label or slotInfo[id].label, 1, 1, 1) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(K.Key("Shift-click") .. ": link it in chat", 0.6, 0.6, 0.6)
        else
            GameTooltip:SetText(self.label or slotInfo[id].label, 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Empty", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if not (self.itemString and Shifted()) then return end
        local link = ("|cffffffff|Hitem:%s|h[%s]|h|r"):format(self.itemString, self.itemName or "item")
        SendToChat(link, link)
    end)
    slots[id] = b
    return b
end

local COL_PAD, STEP = 44, 54
local rightX = PANE_W - COL_PAD - SLOT
for i, id in ipairs(LEFT_SLOTS) do NewSlot(id, COL_PAD, -20 - (i - 1) * STEP) end
for i, id in ipairs(RIGHT_SLOTS) do NewSlot(id, rightX, -20 - (i - 1) * STEP) end
for i, id in ipairs(BOTTOM_SLOTS) do NewSlot(id, PANE_W / 2 - SLOT / 2 + (i - 2) * 72, -20 - 8 * STEP - 6) end

-- the crest in the middle
local crest = gearPane:CreateTexture(nil, "ARTWORK")
crest:SetSize(128, 128)
crest:SetPoint("TOP", gearPane, "TOP", 0, -90)
crest:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
local crestName = gearPane:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
crestName:SetPoint("TOP", crest, "BOTTOM", 0, -12)
local crestInfo = gearPane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
crestInfo:SetPoint("TOP", crestName, "BOTTOM", 0, -6)

-- the professions under it, a little further down, one per line: "Cooking (200)"
local profNames = gearPane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
profNames:SetPoint("TOP", crestInfo, "BOTTOM", 0, -22)
profNames:SetWidth(260)
profNames:SetJustifyH("CENTER")
profNames:SetSpacing(3)
local profNone = gearPane:CreateFontString(nil, "ARTWORK", "GameFontDisable")
profNone:SetPoint("TOP", crestInfo, "BOTTOM", 0, -22)

---------------------------------------------------------------------------
-- Talents: the trees side by side in their own panels; every talent an icon in a square frame with its
-- rank in the corner (gold when maxed, green when partly spent, grey when nothing is spent), lines between
-- connected talents.
---------------------------------------------------------------------------
local talentSummary = talentPane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
talentSummary:SetPoint("TOPLEFT", talentPane, "TOPLEFT", 14, -10)
local talentNote = talentPane:CreateFontString(nil, "ARTWORK", "GameFontDisable")
talentNote:SetPoint("CENTER", talentPane, "CENTER", 0, 0)
talentNote:SetWidth(520)
talentNote:SetJustifyH("CENTER")

-- dual specialization: one button per talent setup, the active one is marked
local specButtons = {}
local function SpecButton(i)
    local b = specButtons[i]
    if not b then
        b = K.NewButton(talentPane, "")
        b:SetSize(250, 22)
        b:SetPoint("TOPRIGHT", talentPane, "TOPRIGHT", -14 - (2 - i) * 258, -8)
        b.setupIndex = i
        b:SetScript("OnClick", function(self)
            insp.specIndex = self.setupIndex
            ns.UI.RefreshInspect()
        end)
        specButtons[i] = b
    end
    return b
end

local NODE = 30
local panels, nodes, lines = {}, {}, {}

-- Layers: the tree panels at the bottom, the connecting lines above them, the talent icons on top.
-- (Lines that belong to the page itself would be hidden behind the panels.)
local baseLevel = tonumber(talentPane:GetFrameLevel()) or 1
local lineLayer = CreateFrame("Frame", nil, talentPane)
lineLayer:SetAllPoints(talentPane)
lineLayer:SetFrameLevel(baseLevel + 3)
local TREE_TINTS = { { 0.06, 0.05, 0.04 }, { 0.04, 0.05, 0.07 }, { 0.05, 0.07, 0.05 } }

local function GetPanel(i)
    local p = panels[i]
    if not p then
        p = CreateFrame("Frame", nil, talentPane, "BackdropTemplate")
        p:SetFrameLevel(baseLevel + 1)
        p:SetBackdrop(BOX_BACKDROP)
        local t = TREE_TINTS[(i - 1) % #TREE_TINTS + 1]
        p:SetBackdropColor(t[1], t[2], t[3], 1)
        p:SetBackdropBorderColor(0.3, 0.27, 0.15, 1)
        p.title = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        p.title:SetPoint("TOP", p, "TOP", 0, -8)
        panels[i] = p
    end
    return p
end

local function GetNode(i)
    local n = nodes[i]
    if not n then
        n = CreateFrame("Button", nil, talentPane, "BackdropTemplate")
        n:SetFrameLevel(baseLevel + 6)
        n:SetSize(NODE, NODE)
        n:SetBackdrop(BOX_BACKDROP)
        n:SetBackdropColor(0.02, 0.02, 0.025, 1)
        n.icon = n:CreateTexture(nil, "ARTWORK")
        n.icon:SetPoint("TOPLEFT", n, "TOPLEFT", 2, -2)
        n.icon:SetPoint("BOTTOMRIGHT", n, "BOTTOMRIGHT", -2, 2)
        n.badge = n:CreateTexture(nil, "OVERLAY")
        n.badge:SetSize(14, 13)
        n.badge:SetPoint("BOTTOMRIGHT", n, "BOTTOMRIGHT", 3, -3)
        n.badge:SetColorTexture(0, 0, 0, 0.85)
        n.rank = n:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        n.rank:SetPoint("CENTER", n.badge, "CENTER", 0, 0)
        n.hl = n:CreateTexture(nil, "HIGHLIGHT")
        n.hl:SetAllPoints()
        n.hl:SetColorTexture(1, 1, 1, 0.2)
        n:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.spell and self.spell > 0 then pcall(GameTooltip.SetSpellByID, GameTooltip, self.spell) end
            if (GameTooltip:NumLines() or 0) == 0 then GameTooltip:SetText("Talent", 1, 1, 1) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(("Rank %d / %d"):format(self.rankNow or 0, self.rankMax or 0), 1, 0.82, 0)
            GameTooltip:Show()
        end)
        n:SetScript("OnLeave", function() GameTooltip:Hide() end)
        nodes[i] = n
    end
    return n
end

local function SpellIcon(spell)
    local icon
    pcall(function()
        if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(spell)
        elseif GetSpellTexture then icon = GetSpellTexture(spell) end
    end)
    return icon
end

local function GetLine(i)
    local l = lines[i]
    if l == nil then
        local ok, line = pcall(function() return lineLayer:CreateLine() end)
        l = ok and line or false
        lines[i] = l
    end
    return l or nil
end

-- everything about somebody's talents: nil when we have none, else { groups, total, points = {p1,p2,p3} }
local function TalentView(profile, sp)
    if not profile or not sp or (sp.spec or 0) <= 0 then return nil, "none" end
    local layout = ns.Inspect.GetLayout(sp.spec, profile.level)
    if not layout then
        -- nobody on this computer has seen this class's tree yet: a guildmate who has will share it
        if ns.Sync and ns.Sync.RequestLayout then ns.Sync.RequestLayout(sp.spec) end
        return nil, "layout"
    end
    local all, total = {}, 0
    for _, n in ipairs(layout.nodes) do
        local rank = math.min((sp.ranks or {})[n.id] or 0, n.max)
        all[#all + 1] = { id = n.id, x = n.x, y = n.y, max = n.max, spell = n.spell, edges = n.edges, rank = rank }
        total = total + rank
    end
    local groups = ns.Inspect.GroupNodes(all)
    local points = {}
    for i, g in ipairs(groups) do points[i] = g.points end
    return { groups = groups, total = total, points = points }
end

local function RenderTalents(view, why, classFile)
    for _, p in ipairs(panels) do p:Hide() end
    for _, n in ipairs(nodes) do n:Hide() end
    for _, l in ipairs(lines) do if l then l:Hide() end end
    if not view then
        talentSummary:SetText("")
        if why == "layout" then
            talentNote:SetText("The layout of this class's talent tree is not known here yet.\nIt is asked from the guild: a guildmate who plays this class shares it.")
        else
            talentNote:SetText("No talents yet.\nThe game hands them out after inspecting a player close enough, otherwise they come from the guildie's own FetaFondue (0.26 or newer).")
        end
        return
    end
    talentNote:SetText("")
    talentSummary:SetText(("%s points spent"):format(Gold(view.total)))

    local groups = view.groups
    -- one grid for all three trees: the same rows everywhere, the same icon size everywhere
    local rows = ns.Inspect.PlaceOnGrid(groups)
    local sumW = 0
    for _, g in ipairs(groups) do
        g.weight = math.max(2, g.cols)
        sumW = sumW + g.weight
    end

    -- panel widths: a minimum each, the rest shared by the number of columns of the tree
    local gap, n = 10, #groups
    local usable = PANE_W - 28 - gap * (n - 1)
    local minW = math.min(170, usable / n)
    local extra = math.max(0, usable - minW * n)
    local PANEL_H = PANE_H - 40
    local x0 = 14
    local byID, ni = {}, 0
    local names = ns.Inspect.TREES[classFile] or {}

    local cell = math.min((PANEL_H - 50) / rows, 54)
    for _, g in ipairs(groups) do
        local w = minW + extra * g.weight / sumW
        g.width = w
        cell = math.min(cell, (w - 16) / g.cols)
    end
    local size = math.max(22, math.min(38, math.floor(cell - 8)))
    cell = math.max(cell, size + 2)

    for gi, g in ipairs(groups) do
        local w = g.width
        local panel = GetPanel(gi)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", talentPane, "TOPLEFT", x0, -30)
        panel:SetSize(w, PANEL_H)
        panel.title:SetText(("%s  %s"):format(names[gi] or ("Tree " .. gi), Gray("(" .. g.points .. ")")))
        panel:Show()

        -- one square cell per grid position, the same cell for every tree
        local offX = x0 + (w - g.cols * cell) / 2
        for i, node in ipairs(g.nodes) do
            ni = ni + 1
            local b = GetNode(ni)
            local px = offX + node.gc * cell + (cell - size) / 2
            local py = 30 + 34 + node.gr * cell + (cell - size) / 2
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", talentPane, "TOPLEFT", px, -py)
            b.icon:SetTexture(SpellIcon(node.spell) or QUESTION)
            b.icon:SetDesaturated(node.rank == 0)
            b.rankNow, b.rankMax, b.spell = node.rank, node.max, node.spell
            if node.rank >= node.max then
                b:SetBackdropBorderColor(1, 0.82, 0, 1)         -- maxed: gold
            elseif node.rank > 0 then
                b:SetBackdropBorderColor(0.25, 0.9, 0.25, 1)    -- some points: green
            else
                b:SetBackdropBorderColor(0.3, 0.3, 0.33, 1)     -- nothing: dull
            end
            b.rank:SetText(node.rank > 0 and tostring(node.rank) or "")
            if node.rank >= node.max then b.rank:SetTextColor(1, 0.82, 0) else b.rank:SetTextColor(0.25, 0.9, 0.25) end
            b.badge:SetShown(node.rank > 0)
            b:Show()
            byID[node.id] = { frame = b, node = node }
        end
        x0 = x0 + w + gap
    end

    -- the lines between a talent and the talent it needs
    local li = 0
    for _, g in ipairs(groups) do
        for _, node in ipairs(g.nodes) do
            local from = byID[node.id]
            for _, target in ipairs(node.edges) do
                local to = byID[target]
                if to then
                    li = li + 1
                    local line = GetLine(li)
                    if line then
                        line:SetThickness(3)
                        if node.rank > 0 and to.node.rank > 0 then line:SetColorTexture(1, 0.82, 0, 0.95) else line:SetColorTexture(0.55, 0.52, 0.45, 0.9) end
                        line:SetStartPoint("CENTER", from.frame)
                        line:SetEndPoint("CENTER", to.frame)
                        line:Show()
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Showing what we have
---------------------------------------------------------------------------
local function ClassName(classFile)
    if not classFile or classFile == "" then return "" end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile])
        or (classFile:sub(1, 1) .. classFile:sub(2):lower())
end
K.ClassName = ClassName

-- "Enhancement Shaman" in the colour of the class (the spec is the talent tree with the most points)
local function SpecAndClass(tree, role, classFile)
    local class = ClassName(classFile)
    local text = tree and (tree .. " " .. class) or class
    return K.ClassColored(text, classFile)
end

-- one profession per line, the skill in brackets next to the name
local function ShowProfessions(guid)
    local list = ns.GetProfessionList(guid)
    local names = {}
    for i, p in ipairs(list) do
        names[i] = p.rank > 0 and ("%s %s"):format(p.name, Gold("(" .. p.rank .. ")")) or p.name
    end
    profNames:SetText(table.concat(names, "\n"))
    profNone:SetText(#list == 0 and "No profession data" or "")
end

local function ShowTab(tab)
    insp.tab = tab
    gearPane:SetShown(tab == "gear")
    talentPane:SetShown(tab == "talents")
    if tab == "gear" then gearTab:LockHighlight() talentTab:UnlockHighlight()
    else talentTab:LockHighlight() gearTab:UnlockHighlight() end
end
gearTab:SetScript("OnClick", function() ShowTab("gear") end)
talentTab:SetScript("OnClick", function() ShowTab("talents") end)

local function Render()
    local m = insp.member
    if not m then return end
    local profile = ns.DB.inspect[insp.guid]
    local classFile = (profile and profile.class ~= "" and profile.class) or m.class
    local level = (profile and profile.level and profile.level > 0 and profile.level) or m.level
    local race = profile and profile.race ~= "" and ns.RaceName(profile.race) or nil

    -- header (the same above both tabs): name and level, class, race, role
    win:SetTitle(m.name)
    nameText:SetText(("|cffffd100%s|r  |cffffffffLevel %s|r"):format(m.name, tostring(level or "?")))
    raceText:SetText(race or Gray("Race unknown"))

    local entry = ns.FindRosterEntry(ns.GetRoster(), insp.guid, m.name)
    if entry and entry.online then
        presenceText:SetText("|cff4cff4cOnline|r")
        pcall(presenceText.SetShadowColor, presenceText, 0.2, 1, 0.2, 0.9)
        pcall(presenceText.SetShadowOffset, presenceText, 0, 0)
    else
        pcall(presenceText.SetShadowColor, presenceText, 0, 0, 0, 0)
        presenceText:SetText(Gray(ns.LastSeenText(entry)))
    end
    local joined = ns.GetJoined(insp.guid)
    joinedText:SetText(joined and ("Joined " .. ns.DateText(joined.ts)) or "")
    local _, mainName = ns.GetOriginalOf(insp.guid)
    if mainName then
        altsText:SetText("Alt of " .. ns.DisplayName(mainName))
    else
        local alts = ns.GetAltsOf(insp.guid)
        altsText:SetText(#alts > 0 and ("Known alts: " .. table.concat(alts, ", ")) or "")
    end

    -- the talent setups (dual specialization: up to two): the active one decides the role in the header
    local setups = {}
    if profile then ns.Inspect.Normalize(profile) setups = profile.specs end
    local activeIndex = 1
    for n, sp in ipairs(setups) do if sp.active then activeIndex = n end end
    if not insp.specIndex or insp.specIndex > #setups then insp.specIndex = activeIndex end

    local views, trees, roles = {}, {}, {}
    for n, sp in ipairs(setups) do
        views[n] = TalentView(profile, sp)
        if views[n] then trees[n], roles[n] = ns.Inspect.RoleFor(classFile, views[n].points) end
    end
    local view, why = views[insp.specIndex], (#setups == 0) and "none" or ((not views[insp.specIndex]) and "layout" or nil)
    local tree, role = trees[activeIndex], roles[activeIndex]
    local specClass = SpecAndClass(tree, role, classFile)
    classText:SetText(specClass)
    if role then
        roleText:SetText(("|c%s%s|r"):format(ns.Inspect.ROLE_COLOR[role], ns.Inspect.ROLE_LABEL[role]))
    else
        roleText:SetText(Gray(views[activeIndex] and "No role yet" or "Role unknown"))
    end
    local other = ""
    if #setups >= 2 then
        local o = (activeIndex == 1) and 2 or 1
        if roles[o] then other = ("Other spec: %s%s"):format(ns.Inspect.ROLE_LABEL[roles[o]], trees[o] and (" (" .. trees[o] .. ")") or "") end
    end
    roleTree:SetText(other)

    -- spec buttons
    for n = 1, 2 do
        local b = specButtons[n]
        local sp = setups[n]
        if #setups >= 2 and sp then
            b = SpecButton(n)
            b:SetText(("%s%s%s"):format(trees[n] or ("Spec " .. n), roles[n] and (" · " .. ns.Inspect.ROLE_LABEL[roles[n]]) or "", sp.active and "  (active)" or ""))
            if n == insp.specIndex then b:LockHighlight() else b:UnlockHighlight() end
            b:Show()
        elseif b then
            b:Hide()
        end
    end

    -- status
    if insp.fresh then
        local how = profile and profile.src == "scan" and "Scanned in the game by a guildie " or "From their own addon "
        statusText:SetText(how .. AgeText(profile and profile.at))
    elseif profile then
        local how = profile.src == "scan" and "Scanned in the game by a guildie" or "Saved copy"
        statusText:SetText(("%s %s%s"):format(how, AgeText(profile.at), insp.waiting and "  -  asking for a fresh one" or ""))
    elseif insp.waiting then
        statusText:SetText(insp.native and ("Inspecting %s"):format(m.name) or ("Asking %s's addon"):format(m.name))
    else
        statusText:SetText(("No answer from %s: out of inspect range, offline, or not running a FetaFondue version with Inspect."):format(m.name))
    end

    -- the crest
    pcall(function()
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then crest:SetTexCoord(unpack(coords)) end
    end)
    crestName:SetText(("|cffffd100%s|r"):format(m.name))
    crestInfo:SetText(("Level %s %s"):format(tostring(level or "?"), specClass))
    ShowProfessions(insp.guid)

    -- the slots
    for id, b in pairs(slots) do
        local itemString = profile and profile.items[id] or nil
        -- an item id of 0 (or none) is an empty slot
        if itemString and (tonumber(tostring(itemString):match("^(%d+)")) or 0) == 0 then itemString = nil end
        b.itemString = itemString
        if id == 18 then
            local label, art = RangedInfo(classFile)
            b.label = label
            b.empty:SetTexture(art or EmptySlotArt(18))
        end
        if itemString then
            local itemID = tonumber(itemString:match("^(%d+)"))
            local name, icon, quality = ItemData(itemID)
            b.itemName = name or ("item " .. tostring(itemID))
            b.icon:SetTexture(icon or QUESTION)
            b.icon:Show()
            b.empty:Hide()
            local hex = quality and QUALITY_HEX[quality]
            if hex then b:SetBackdropBorderColor(HexToRGB(hex)) else b:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end
        else
            b.itemName = nil
            b.icon:Hide()
            b.empty:Show()
            b:SetBackdropBorderColor(0.3, 0.3, 0.33, 1)
        end
    end

    RenderTalents(view, why, classFile)
end

local function Ask()
    local m = insp.member
    if not m then return end
    insp.fresh = false
    if insp.guid == ns.myGUID then
        -- my own character: read it directly
        local profile = ns.Inspect.CaptureSelf()
        profile.at = ns.Time()
        ns.DB.inspect[insp.guid] = profile
        insp.fresh, insp.waiting = true, false
        return
    end
    insp.waiting = true
    local guid, token = insp.guid, ns.Now()
    insp.token = token
    -- the game's own inspect gives the gear and, when available, the talents (no addon needed on their
    -- side); their addon is asked as well, it can answer from any distance
    insp.native = ns.Inspect.StartNative(guid)
    ns.Sync.RequestInspect(guid)
    ns.After(8, function()
        if insp.guid == guid and insp.token == token and not insp.fresh then
            insp.waiting = false
            Render()
        end
    end)
end

-- m: { guid, name, class, level, ... } from the online list
function ns.UI.OpenInspect(m)
    if not (m and m.guid) then return end
    insp.guid, insp.member = m.guid, m
    insp.specIndex = nil
    Ask()
    win:Show()
    ShowTab("gear")
    Render()
end

function ns.UI.RefreshInspect()
    if win:IsShown() then Render() end
end

-- gear (the game's inspect) or gear and talents (their addon) arrived
function ns.OnInspectData(guid)
    if insp.guid == guid then
        insp.fresh, insp.waiting = true, false
        Render()
    end
end

-- buttons --------------------------------------------------------------------------------------
local refresh = K.NewButton(win, "Refresh")
refresh:SetSize(110, 26)
refresh:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 24, 22)
refresh:SetScript("OnClick", function()
    Ask()
    Render()
end)

local close = K.NewButton(win, "Close")
close:SetSize(110, 26)
close:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -24, 22)
close:SetScript("OnClick", function() win:Hide() end)

K.RegisterCloser(function() win:Hide() end)

-- a talent tree layout arrived from a guildmate
function ns.OnLayoutData(spec)
    if win:IsShown() then Render() end
end
