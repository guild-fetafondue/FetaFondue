---@class ns
local ns = select(2, ...)
local K = ns.K
local Gray, QUESTION = K.Gray, K.QUESTION

---------------------------------------------------------------------------
-- Sweatshop tabs: Requests (the page built in UISweatshop.lua), Specialization and Cooldowns.
---------------------------------------------------------------------------
local root = K.sweatshopPanel
local requestsPage = K.sweatshopRequestsPage

local strip = K.NewTabStrip(root, 0)
local tabRequests = strip:AddTab(0, "Requests", 112)
local tabSpec = strip:AddTab(116, "Specializations", 132)
local tabCooldowns = strip:AddTab(252, "Cooldowns", 112)

local function NewPage()
    local page = CreateFrame("Frame", nil, root)
    page:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -34)
    page:SetSize(800, 586)
    page:Hide()
    local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
    box:SetBackdrop(K.BOX_BACKDROP)
    box:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    box:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    box:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -24)
    box:SetSize(800, 562)
    page.box = box
    return page
end

local function ClassOf(guid)
    local roster = ns.GetRoster and ns.GetRoster()
    local e = roster and roster.byGUID and roster.byGUID[guid]
    return e and e.class, e and e.online, e and e.level
end

local function CharName(guid, m)
    local class = ClassOf(guid)
    return K.ClassColored(ns.DisplayName(m.name or "?"), class)
end

local function ProfIcon(key)
    return ns.PROFESSION_ICONS and ns.PROFESSION_ICONS[tonumber(key) or 0] or QUESTION
end

-- a second text on the left of a row (the time left); made once per row
local function LeftText(row)
    if not row.leftText then
        row.leftText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.leftText:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.leftText:SetWidth(90)
        row.leftText:SetJustifyH("LEFT")
    end
    return row.leftText
end

local function PlainRow(row, item)
    row:EnableMouse(false)
    if row.leftText then row.leftText:SetText("") end
    row.text:SetFontObject(item.font or "GameFontHighlight")
    row.text:SetText(item.text or "")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", item.indent or 8, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
end

---------------------------------------------------------------------------
-- Specialization
---------------------------------------------------------------------------
local specPage = NewPage()
K.sweatshopSpecPage = specPage
local specTitle = specPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
specTitle:SetPoint("TOPLEFT", specPage, "TOPLEFT", 0, -2)
specTitle:SetText("Professions with specializations, and who has which")

local function SpecRow(row, item)
    PlainRow(row, item)
end
local specList = K.CreateScrollList(specPage.box, 800 - 12, 562 - 16, 22, SpecRow, { stripes = true, insideTrack = true })
specList.frame:SetPoint("TOPLEFT", specPage.box, "TOPLEFT", 6, -8)

local function BuildSpecItems()
    local S = ns.Specs
    local items = {}
    -- only what somebody in the guild has: a profession, a specialization or a character without one is not shown at all
    for _, key in ipairs(S.ORDER) do
        local sections = {}
        for _, id in ipairs(S.SpecsOf(key)) do
            local holders = S.Holders(id)
            if #holders > 0 then sections[#sections + 1] = { id = id, holders = holders } end
        end
        if #sections > 0 then
            items[#items + 1] = { height = 30, font = "GameFontNormalLarge", indent = 6,
                text = ("|T%s:20|t  %s"):format(ProfIcon(key), ns.Professions.ProfessionName(key)) }
            for _, sec in ipairs(sections) do
                local icon = S.SpecIcon(sec.id)
                items[#items + 1] = { height = 24, font = "GameFontNormal", indent = 22,
                    text = ("%s%s  %s"):format(icon and ("|T" .. icon .. ":16|t  ") or "", (S.SpecName(sec.id)),
                        Gray("(" .. #sec.holders .. ")")) }
                for _, h in ipairs(sec.holders) do
                    local _, online, level = ClassOf(h.guid)
                    local text = CharName(h.guid, h.member)
                    if level then text = text .. "  " .. Gray("level " .. level) end
                    text = text .. "  " .. (online and "|cff4cff4conline|r" or Gray("offline"))
                    items[#items + 1] = { text = text, indent = 44 }
                end
            end
        end
    end
    if #items == 0 then items[1] = { text = Gray("No specialization data yet."), font = "GameFontDisable" } end
    return items
end

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
local cdPage = NewPage()
K.sweatshopCooldownPage = cdPage
-- (no heading above the list: the box takes the whole page)
cdPage.box:ClearAllPoints()
cdPage.box:SetPoint("TOPLEFT", cdPage, "TOPLEFT", 0, 0)
cdPage.box:SetSize(800, 586)

local function CooldownRow(row, item)
    if item.kind ~= "cd" then
        PlainRow(row, item)
        return
    end
    row:EnableMouse(false)
    local timeText = ns.Specs.TimeText(item.left)
    local lt = LeftText(row)
    lt:SetText(item.left <= 0 and ("|cff55dd55" .. timeText .. "|r") or ("|cffffd100" .. timeText .. "|r"))
    row.text:SetFontObject("GameFontHighlight")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 110, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.text:SetText(CharName(item.guid, item.member) .. "  " .. Gray(item.spellName))
end
local cdList = K.CreateScrollList(cdPage.box, 800 - 12, 586 - 16, 22, CooldownRow, { stripes = true, insideTrack = true })
cdList.frame:SetPoint("TOPLEFT", cdPage.box, "TOPLEFT", 6, -8)

-- the icon of a spell (the game's own picture of it), nil when the game does not give one
local function SpellIcon(id)
    local tex
    pcall(function()
        if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(id)
        elseif GetSpellTexture then tex = GetSpellTexture(id) end
    end)
    return tex
end

-- the font of the Alchemy groups: a size between the profession title (16) and the rows (12); if the game refuses, the large white one
local subheadFont
local function SubheadFont()
    if subheadFont == nil then
        subheadFont = "GameFontHighlightLarge"
        if CreateFont then
            local ok, obj = pcall(function()
                local f = CreateFont("FetaFondueSubheadFont")
                f:CopyFontObject("GameFontHighlight")
                local path, _, flags = f:GetFont()
                if not path then error("no font") end
                f:SetFont(path, 14, flags or "")
                return f
            end)
            if ok and obj then subheadFont = obj end
        end
    end
    return subheadFont
end

-- the icon of an item, nil when the game does not give one
local function ItemIcon(id)
    local tex
    pcall(function()
        if C_Item and C_Item.GetItemIconByID then tex = C_Item.GetItemIconByID(id)
        elseif GetItemIcon then tex = GetItemIcon(id) end
    end)
    return tex
end

local function BuildCooldownItems()
    local S = ns.Specs
    local items = {}
    local function Add(r) items[#items + 1] = { kind = "cd", guid = r.guid, member = r.member, left = r.left, spellName = S.CooldownName(r.spell) } end
    for _, g in ipairs(S.ListByProfession()) do
        items[#items + 1] = { height = 30, font = "GameFontNormalLarge", indent = 6,
            text = ("|T%s:20|t  %s  %s"):format(ProfIcon(g.key), g.name, Gray("(" .. #g.rows .. ")")) }
        if g.key == "171" then
            -- Alchemy: one group per kind of transmute (a group with nobody ready or waiting is simply not there), the groups in alphabetical
            -- order, inside a group the shortest wait first
            local cats, order = {}, {}
            for _, r in ipairs(g.rows) do
                local name = S.TransmuteGroup(r.spell, S.CooldownName(r.spell))
                if not cats[name] then cats[name] = {} order[#order + 1] = name end
                cats[name][#cats[name] + 1] = r
            end
            table.sort(order)
            for _, name in ipairs(order) do
                local rows = cats[name]
                table.sort(rows, function(a, b)
                    if a.left ~= b.left then return a.left < b.left end
                    if a.spell ~= b.spell then return a.spell < b.spell end
                    return (a.member.name or "") < (b.member.name or "")
                end)
                local iconSpell = S.TRANSMUTE_ICON[name]
                local itemId = S.TRANSMUTE_ITEM_ICON[name]
                local icon = (itemId and ItemIcon(itemId)) or (iconSpell and SpellIcon(iconSpell)) or ProfIcon(g.key)
                items[#items + 1] = { height = 24, font = SubheadFont(), indent = 22,
                    text = ("|T%s:16|t  %s  %s"):format(icon, name, Gray("(" .. #rows .. ")")) }
                for _, r in ipairs(rows) do Add(r) end
            end
        else
            for _, r in ipairs(g.rows) do Add(r) end
        end
    end
    if #items == 0 then
        items[1] = { text = Gray("No profession cooldowns known yet. They show up once a character has used one or a guildmate shares his."), font = "GameFontDisable" }
    end
    return items
end

ns.UI.CooldownItems = BuildCooldownItems       -- (for the tests)

---------------------------------------------------------------------------
-- switching
---------------------------------------------------------------------------
local current = "requests"
local loopToken = 0

local function RefreshPages(keepScroll)
    if not root:IsShown() then return end
    if current == "specialization" then specList:Render(BuildSpecItems(), keepScroll) end
    if current == "cooldowns" then cdList:Render(BuildCooldownItems(), keepScroll) end
end

local loopRunning = false
local function CooldownLoop(token)
    if token ~= loopToken or current ~= "cooldowns" or not root:IsShown() then loopRunning = false return end
    RefreshPages(true)
    ns.After(30, function() CooldownLoop(token) end)
end
local function StartLoop()
    if loopRunning then return end
    loopRunning = true
    local token = loopToken
    ns.After(30, function() CooldownLoop(token) end)
end

function ns.UI.SweatshopSelectTab(id)
    current = id
    requestsPage:SetShown(id == "requests")
    specPage:SetShown(id == "specialization")
    cdPage:SetShown(id == "cooldowns")
    for tab, which in pairs({ [tabRequests] = "requests", [tabSpec] = "specialization", [tabCooldowns] = "cooldowns" }) do
        if which == id then tab:LockHighlight() else tab:UnlockHighlight() end
    end
    loopToken = loopToken + 1
    loopRunning = false
    if id == "requests" then
        ns.UI.RefreshSweatshop()
    else
        RefreshPages(false)
        if id == "cooldowns" then StartLoop() end
    end
end

function ns.UI.RefreshSweatshopTabs()
    RefreshPages(true)
    if current == "cooldowns" then StartLoop() end     -- (the window was closed and opened again)
end

tabRequests:SetScript("OnClick", function() ns.UI.SweatshopSelectTab("requests") end)
tabSpec:SetScript("OnClick", function() ns.UI.SweatshopSelectTab("specialization") end)
tabCooldowns:SetScript("OnClick", function() ns.UI.SweatshopSelectTab("cooldowns") end)

-- (the page that was open stays open when the window is closed and opened again)
tabRequests:LockHighlight()
requestsPage:Show()

K.sweatshopSelect = ns.UI.SweatshopSelectTab
