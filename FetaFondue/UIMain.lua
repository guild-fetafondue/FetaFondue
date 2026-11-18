---@class ns
local ns = select(2, ...)
local K = ns.K

---------------------------------------------------------------------------
-- The main window: tabs on the left (Dashboard, Sweatshop, Analytics, Events), the page of the selected tab on the right.
-- Dashboard = stats, who is online, open requests. Sweatshop = who can craft what, and requests.
---------------------------------------------------------------------------
local MAIN_W, MAIN_H = 1012, 704
local main = K.NewWindow("FetaFondueMain", MAIN_W, MAIN_H)
main:SetPoint("CENTER", 0, 0)
main:SetMovable(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", main.StartMoving)
main:SetScript("OnDragStop", main.StopMovingOrSizing)
K.main = main

-- where the pages live
local content = CreateFrame("Frame", nil, main)
content:SetSize(800, 620)
content:SetPoint("TOPLEFT", main, "TOPLEFT", 192, -56)
K.content = content
K.homePanel = K.NewPanel("FetaFondueDashboard", content, 800, 620)
K.homePanel:SetAllPoints(content)
K.sweatshopPanel = K.NewPanel("FetaFondueWorkshop", content, 800, 620)
K.sweatshopPanel:SetAllPoints(content)
K.analyticsPanel = K.NewPanel("FetaFondueAnalytics", content, 800, 620)
K.analyticsPanel:SetAllPoints(content)
K.achievementsPanel = K.NewPanel("FetaFondueAchievements", content, 800, 620)
K.achievementsPanel:SetAllPoints(content)
K.calendarPanel = K.NewPanel("FetaFondueCalendar", content, 800, 620)
K.calendarPanel:SetAllPoints(content)
K.managementPanel = K.NewPanel("FetaFondueManagement", content, 800, 620)
K.managementPanel:SetAllPoints(content)
K.adminPanel = K.NewPanel("FetaFondueAdmin", content, 800, 620)
K.adminPanel:SetAllPoints(content)

-- thin line between the tabs and the page
local columnLine = main:CreateTexture(nil, "ARTWORK")
columnLine:SetColorTexture(1, 0.82, 0, 0.35)
columnLine:SetWidth(1)
columnLine:SetPoint("TOPLEFT", main, "TOPLEFT", 180, -56)
columnLine:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 180, 24)

-- the FetaFondue logo (it carries the name) in the left column
local LOGO_PATH = "Interface\\AddOns\\FetaFondue\\Media\\logo.tga"
local logo = main:CreateTexture(nil, "ARTWORK")
logo:SetTexture(LOGO_PATH)
logo:SetSize(168, 168)
logo:SetPoint("TOP", main, "TOPLEFT", 96, -40)

-- tabs: the Dashboard is always the top one
local TAB_W, TAB_H = 156, 42
local tabs = {
    { id = "home", label = "Dashboard", icon = "Interface\\Icons\\INV_Misc_Bag_08", panel = K.homePanel },
    { id = "sweatshop", label = "Sweatshop", icon = "Interface\\Icons\\Trade_BlackSmithing", panel = K.sweatshopPanel },
    { id = "analytics", label = "Analytics", icon = "Interface\\Icons\\INV_Misc_Book_09", panel = K.analyticsPanel },
    { id = "achievements", label = "Achievements", icon = "Interface\\Icons\\Achievement_Level_60", panel = K.achievementsPanel },
    { id = "calendar", label = "Events", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", panel = K.calendarPanel },
    -- only for officers and the guild master
    { id = "management", label = "Management", icon = "Interface\\Icons\\INV_Misc_Note_06", panel = K.managementPanel,
      visible = function() return ns.CanModerate() end },
    -- only for the admin character
    { id = "admin", label = "Admin", icon = "Interface\\Icons\\INV_Misc_Gear_01", panel = K.adminPanel,
      visible = function() return ns.IsAdmin() end },
}
for i, def in ipairs(tabs) do
    local b = CreateFrame("Button", nil, main)
    b:SetSize(TAB_W, TAB_H)
    b:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -(222 + (i - 1) * (TAB_H + 6)))   -- (UpdateTabs puts it in place)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.11, 0.11, 0.12, 1)
    b.sel = b:CreateTexture(nil, "BORDER")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(1, 0.82, 0, 0.2)
    b.sel:Hide()
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.bar:SetWidth(3)
    b.bar:SetColorTexture(1, 0.82, 0, 1)
    b.bar:Hide()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.08)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(28, 28)
    b.icon:SetPoint("LEFT", b, "LEFT", 12, 0)
    b.icon:SetTexture(def.icon)
    b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    b.text:SetText(def.label)
    b.tabID = def.id
    b:SetScript("OnClick", function() ns.UI.SelectTab(def.id) end)
    def.button = b
end

local version = main:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
version:SetPoint("BOTTOM", main, "BOTTOMLEFT", 98, 28)
local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local okV, ver = pcall(function() return meta and meta("FetaFondue", "Version") end)
version:SetText(okV and ver and ("v" .. ver) or "")

-- show only the tabs this person may use, one under the other
local function UpdateTabs()
    local row = 0
    for _, def in ipairs(tabs) do
        local visible = (not def.visible) or def.visible()
        def.shown = visible and true or false
        def.button:SetShown(visible)
        if visible then
            def.button:ClearAllPoints()
            def.button:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -(222 + row * (TAB_H + 6)))
            row = row + 1
        end
    end
end
ns.UI.UpdateTabs = UpdateTabs

function ns.UI.SelectTab(id)
    UpdateTabs()
    for _, def in ipairs(tabs) do
        if def.id == id and def.shown == false then id = "home" end   -- a tab this person may not see
    end
    main.currentTab = id
    for _, def in ipairs(tabs) do
        local on = def.id == id
        def.panel:SetShown(on)
        def.button.sel:SetShown(on)
        def.button.bar:SetShown(on)
        def.button.text:SetFontObject(on and "GameFontHighlight" or "GameFontNormal")
    end
    if main:IsShown() then
        ns.RefreshUI()
        if id == "calendar" and ns.UI.OnCalendarShown then ns.UI.OnCalendarShown() end
        if id == "management" and ns.UI.OnManagementShown then ns.UI.OnManagementShown() end
        if id == "admin" and ns.UI.RefreshAdmin then ns.UI.RefreshAdmin() end
        if id == "achievements" and ns.UI.RefreshAchievements then ns.UI.RefreshAchievements() end
    end
end

main:SetScript("OnShow", function(self)
    self:SetTitle(K.GuildTitle())
    ns.RequestRoster()
    ns.UI.SelectTab(self.currentTab or "home")
end)
main:SetScript("OnHide", function() K.CloseAll() end)

---------------------------------------------------------------------------
-- Showing and hiding
---------------------------------------------------------------------------
function ns.ShowDashboard()
    main.currentTab = "home"
    main:Show()
    ns.UI.SelectTab("home")
end

function ns.ShowWorkshop()
    main.currentTab = "sweatshop"
    main:Show()
    ns.UI.SelectTab("sweatshop")
end

function ns.ToggleDashboard()
    if main:IsShown() then main:Hide() else main:Show() end
end

-- refresh whatever is on screen (called when roster / guild data / requests change)
function ns.RefreshUI()
    if main:IsShown() then
        UpdateTabs()
        if main.currentTab == "management" and not ns.CanModerate() then ns.UI.SelectTab("home") end
        if main.currentTab == "admin" and not ns.IsAdmin() then ns.UI.SelectTab("home") end
        main:SetTitle(K.GuildTitle())
        ns.UI.RefreshHome()
        ns.UI.RefreshSweatshop(true)
        if ns.UI.RefreshAnalytics then ns.UI.RefreshAnalytics() end
        if ns.UI.RefreshAdmin then ns.UI.RefreshAdmin() end
        if ns.UI.RefreshAchievements then ns.UI.RefreshAchievements() end
    end
    if ns.UI.RefreshWelcome then ns.UI.RefreshWelcome() end
    ns.UI.RefreshProfessionView(true)
    if ns.UI.RefreshInspect then ns.UI.RefreshInspect() end
end

---------------------------------------------------------------------------
-- Details arriving later (from a guildmate, or the game finishing loading an item or spell)
---------------------------------------------------------------------------
local function RefreshDetailViews(id)
    ns.UI.RefreshProfessionDetail()
    ns.UI.RefreshSweatshop(true)                 -- item colors and icons in the lists
    ns.UI.RefreshProfessionView(true)
    if ns.UI.RefreshInspect then ns.UI.RefreshInspect() end
    K.RefreshHover(id)
    ns.UI.RefreshHome()
end

function ns.OnRecipeInfo(id) RefreshDetailViews(id) end

local itemRefreshQueued = false
function ns.UI.OnItemData()
    if itemRefreshQueued then return end
    itemRefreshQueued = true
    ns.After(0.3, function()
        itemRefreshQueued = false
        RefreshDetailViews(nil)
    end)
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
function ns.InitUI()
    -- in the background: ask the game for the items of known recipes, so their icons are ready
    ns.After(25, function() K.PreloadItems() end)
    local b = CreateFrame("Button", "FetaFondueMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(22, 22)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Food_07")          -- (the game's own cheese wedge: Dwarven Mild; fallback INV_Misc_Food_37 = Alterac Swiss)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)          -- (without the icon's dark edge)
    icon:SetPoint("CENTER", 0, 1)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    local function UpdatePosition()
        local angle = math.rad(ns.DB.minimap.angle or 215)
        local radius = (Minimap:GetWidth() / 2) + 5
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local atan = math.atan2 or math.atan
            ns.DB.minimap.angle = math.deg(atan(py - my, px - mx))
            UpdatePosition()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function() ns.ToggleDashboard() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("FetaFondue", 1, 0.82, 0)
        GameTooltip:AddLine("Click to open", 1, 1, 1)
        GameTooltip:AddLine("Drag to move this button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
end

-- the raid calendar changed (an officer added or removed a raid): everything that shows it
ns.Raids.OnChanged = function()
    if ns.UI.RefreshHome then ns.UI.RefreshHome() end
    if ns.UI.RefreshCalendar then ns.UI.RefreshCalendar() end
    if ns.UI.RefreshScheduling then ns.UI.RefreshScheduling() end
    if ns.UI.RefreshDiscordNames then ns.UI.RefreshDiscordNames() end
end
