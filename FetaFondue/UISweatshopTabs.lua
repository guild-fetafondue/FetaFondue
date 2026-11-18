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
    for _, key in ipairs(S.ORDER) do
        local specs = S.SpecsOf(key)
        if #specs > 0 then
            items[#items + 1] = { height = 30, font = "GameFontNormalLarge", indent = 6,
                text = ("|T%s:20|t  %s"):format(ProfIcon(key), ns.Professions.ProfessionName(key)) }
            for _, id in ipairs(specs) do
                local holders = S.Holders(id)
                local icon = S.SpecIcon(id)
                items[#items + 1] = { height = 24, font = "GameFontNormal", indent = 22,
                    text = ("%s%s  %s"):format(icon and ("|T" .. icon .. ":16|t  ") or "", (S.SpecName(id)),
                        Gray("(" .. #holders .. ")")) }
                if #holders == 0 then
                    items[#items + 1] = { text = Gray("Nobody yet"), font = "GameFontDisableSmall", indent = 44 }
                end
                for _, h in ipairs(holders) do
                    local _, online, level = ClassOf(h.guid)
                    local extra = {}
                    if level then extra[#extra + 1] = "level " .. level end
                    if online then extra[#extra + 1] = "online" end
                    items[#items + 1] = { text = CharName(h.guid, h.member) .. (#extra > 0 and ("  " .. Gray(table.concat(extra, ", "))) or ""), indent = 44 }
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
local cdTitle = cdPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
cdTitle:SetPoint("TOPLEFT", cdPage, "TOPLEFT", 0, -2)
cdTitle:SetText("Profession cooldowns, the shortest wait first")

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
local cdList = K.CreateScrollList(cdPage.box, 800 - 12, 562 - 16, 22, CooldownRow, { stripes = true, insideTrack = true })
cdList.frame:SetPoint("TOPLEFT", cdPage.box, "TOPLEFT", 6, -8)

local function BuildCooldownItems()
    local S = ns.Specs
    local items = {}
    for _, g in ipairs(S.ListByProfession()) do
        items[#items + 1] = { height = 30, font = "GameFontNormalLarge", indent = 6,
            text = ("|T%s:20|t  %s  %s"):format(ProfIcon(g.key), g.name, Gray("(" .. #g.rows .. ")")) }
        for _, r in ipairs(g.rows) do
            items[#items + 1] = { kind = "cd", guid = r.guid, member = r.member, left = r.left, spellName = S.CooldownName(r.spell) }
        end
    end
    if #items == 0 then
        items[1] = { text = Gray("No profession cooldowns known yet. They show up once a character has used one or a guildmate shares his."), font = "GameFontDisable" }
    end
    return items
end

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
