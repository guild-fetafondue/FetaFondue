---@class ns
local ns = select(2, ...)
local K = ns.K
local Gray, BOX_BACKDROP, QUESTION = K.Gray, K.BOX_BACKDROP, K.QUESTION

---------------------------------------------------------------------------
-- Analytics: guild-wide charts on two tabs.
--   Makeup:      level, class, race, specialization, role, main/alt
--   Professions: professions, profession specializations, recipes known together; the sweatiest crafter, the most
--                knowledgeable crafter and the luckiest angler
-- Hovering a bar shows the characters in it.
---------------------------------------------------------------------------
local root = K.analyticsPanel

local strip = K.NewTabStrip(root, 0)
local tabMakeup = strip:AddTab(0, "Makeup", 112)
local tabProfessions = strip:AddTab(116, "Professions", 112)

local hint = root:Text("GameFontDisableSmall", 450, -10, 350, "RIGHT")
hint:SetText("Hover a bar for the characters")

local function NewPage()
    local page = CreateFrame("Frame", nil, root)
    page:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -34)
    page:SetSize(800, 586)
    page:Hide()
    return page
end
local makeupPage, profPage = NewPage(), NewPage()

local function NewBox(parent, x, y, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetBackdrop(BOX_BACKDROP)
    box:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    box:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(w, h)
    return box
end

local function BoxTitle(box, text)
    local t = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    t:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -12)
    t:SetText(text)
    return t
end
local function BoxNote(box)
    local t = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    t:SetPoint("TOPRIGHT", box, "TOPRIGHT", -14, -14)
    return t
end

-- hover: a title, a count and the characters (as many as fit); the names in the colour of their class unless it is the class chart
local function ShowNames(owner, title, count, names, classes, levels, colored, extra, noCount)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if extra then GameTooltip:AddLine(extra, 0.8, 0.8, 0.8) end
    if not noCount then GameTooltip:AddLine(("%d %s"):format(count, count == 1 and "character" or "characters"), 1, 0.82, 0) end
    local MAX = 30
    for i, name in ipairs(names or {}) do
        if i > MAX then
            GameTooltip:AddLine(("+%d more"):format(#names - MAX), 0.6, 0.6, 0.6)
            break
        end
        local text = name
        if colored and classes and classes[i] and classes[i] ~= "" then text = K.ClassColored(name, classes[i]) end
        if levels and levels[i] then text = text .. Gray("  " .. levels[i]) end
        GameTooltip:AddLine(text, 0.85, 0.85, 0.85)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- horizontal bars: [picture] label, a track with the bar, the number
---------------------------------------------------------------------------
local function NewHBar(box, i, topY, color, geo)
    local bar = CreateFrame("Button", nil, box)
    bar:SetSize(geo.width, geo.row - 2)
    bar:SetPoint("TOPLEFT", box, "TOPLEFT", 14, topY - (i - 1) * geo.row)
    bar.geo = geo
    local labelX = 0
    if geo.icon then
        bar.icon = bar:CreateTexture(nil, "ARTWORK")
        bar.icon:SetSize(geo.icon, geo.icon)
        bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
        labelX = geo.icon + 4
    end
    bar.label = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    bar.label:SetPoint("LEFT", bar, "LEFT", labelX, 0)
    bar.label:SetWidth(geo.label)
    bar.label:SetJustifyH("LEFT")
    bar.label:SetWordWrap(false)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetPoint("LEFT", bar, "LEFT", labelX + geo.label + 6, 0)
    -- the row is exactly geo.width wide: [picture] label, gap, track, gap, number (right-aligned to the row's end), so the space left of
    -- the first thing and right of the number is the same
    local valueW = geo.valueW or 40
    bar.trackW = geo.width - labelX - geo.label - 12 - valueW
    bar.track:SetSize(bar.trackW, geo.barH or 13)
    bar.track:SetColorTexture(0.09, 0.09, 0.1, 1)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("LEFT", bar.track, "LEFT", 0, 0)
    bar.fill:SetHeight(geo.barH or 13)
    bar.fill:SetColorTexture(color[1], color[2], color[3], 1)
    bar.value = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    bar.value:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    bar.value:SetWidth(valueW)
    bar.value:SetJustifyH("RIGHT")
    bar.hl = bar:CreateTexture(nil, "HIGHLIGHT")
    bar.hl:SetAllPoints()
    bar.hl:SetColorTexture(1, 1, 1, 0.06)
    bar:SetScript("OnEnter", function(self)
        if self.isHeader then return end
        ShowNames(self, self.barTitle or "", self.barCount or 0, self.barNames, self.barClasses, self.barLevels, self.barColored, self.barExtra, self.barNoCount)
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return bar
end

-- opts: color (the bar), icon (a picture), noPercent (just the number), levels, extra (a line in the tooltip)
local function FillHBar(bar, title, label, count, total, biggest, names, classes, colored, opts)
    opts = opts or {}
    bar.barTitle, bar.barCount, bar.barNames, bar.barClasses, bar.barColored = title, count, names, classes, colored
    bar.barLevels, bar.barExtra, bar.barNoCount = opts.levels, opts.extra, opts.noCount
    bar.isHeader = opts.header == true
    bar.label:SetText(label)
    if bar.isHeader then
        -- a line that names a group (the bars below belong to it): no bar, no number
        bar.track:Hide(); bar.fill:Hide(); bar.value:SetText("")
        if bar.icon then bar.icon:Hide() end
        bar:Show()
        return
    end
    bar.track:Show()
    if bar.icon then bar.icon:Show() end
    bar.fill:SetWidth(biggest > 0 and math.max(1, bar.trackW * count / biggest) or 1)
    if opts.color then bar.fill:SetColorTexture(opts.color[1], opts.color[2], opts.color[3], 1) end
    if bar.icon then
        bar.icon:SetTexture(opts.icon or QUESTION)
        bar.icon:SetDesaturated(count == 0)
    end
    bar.fill:SetShown(count > 0)
    if opts.noPercent then
        bar.value:SetText(tostring(count))
    else
        local pct = total > 0 and math.floor(count * 100 / total + 0.5) or 0
        bar.value:SetText(("%d %s"):format(count, Gray("(" .. pct .. "%)")))
    end
    bar:Show()
end

-- a box of horizontal bars. chart:Set(rows, total, biggest) with rows = { { title, label, count, names, classes, colored, color, icon,
-- noPercent, levels, extra } }; the rows are put in the middle of the box
local function NewHChart(box, title, maxRows, geo, colors, top)
    top = top or 38
    local chart = { box = box, bars = {}, geo = geo }
    BoxTitle(box, title)
    chart.note = BoxNote(box)
    function chart:Set(rows, total, biggest)
        local shown = math.min(#rows, maxRows)
        local height = tonumber(box:GetHeight()) or 0
        local y0 = top + math.max(0, (height - top - 10 - shown * geo.row) / 2)
        for i = 1, maxRows do
            local r = rows[i]
            local c = (r and r.color) or colors[(i - 1) % #colors + 1]
            local bar = self.bars[i]
            if not bar then bar = NewHBar(box, i, -top, c, geo) self.bars[i] = bar end
            if r then
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -(y0 + (i - 1) * geo.row))
                FillHBar(bar, r.title or r.label, r.label, r.count, total, biggest, r.names, r.classes, r.colored ~= false, r)
            else
                bar:Hide()
            end
        end
        return #rows > maxRows
    end
    return chart
end

local MIXED = {
    { 0.45, 0.8, 0.45 }, { 0.5, 0.8, 0.35 }, { 0.65, 0.8, 0.3 }, { 0.85, 0.75, 0.25 }, { 0.9, 0.6, 0.2 }, { 0.95, 0.45, 0.2 },
    { 0.9, 0.35, 0.35 }, { 0.8, 0.35, 0.6 }, { 0.6, 0.4, 0.8 }, { 0.4, 0.5, 0.9 },
}
-- vertical bars in a box: chart:Set(rows, biggest), rows = { { title, label, count, names, classes, color, extra, colored } }
local V_TOP, V_LABEL_H, V_BAR_MAX = 40, 34, 170
local function NewVChart(box, title, maxCols)
    local chart = { box = box, cols = {} }
    BoxTitle(box, title)
    function chart:Set(rows, biggest)
        local n = math.min(#rows, maxCols)
        local step = n > 0 and math.min(64, 234 / n) or 64
        local colW = math.min(40, step - 8)
        local x0 = 14 + (234 - n * step) / 2
        local height = (tonumber(box:GetHeight()) or 288) - V_TOP - 12
        for i = 1, maxCols do
            local r = rows[i]
            local b = self.cols[i]
            if not b then
                b = CreateFrame("Button", nil, box)
                b.fill = b:CreateTexture(nil, "ARTWORK")
                b.count = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                b.label:SetJustifyH("CENTER")
                b.label:SetJustifyV("TOP")
                b.hl = b:CreateTexture(nil, "HIGHLIGHT")
                b.hl:SetAllPoints()
                b.hl:SetColorTexture(1, 1, 1, 0.07)
                b:SetScript("OnEnter", function(self2)
                    ShowNames(self2, self2.barTitle or "", self2.barCount or 0, self2.barNames, self2.barClasses, nil, self2.barColored, self2.barExtra)
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                self.cols[i] = b
            end
            if r then
                b:SetSize(step - 2, height)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", box, "TOPLEFT", x0 + (i - 1) * step, -V_TOP)
                b.fill:SetWidth(colW)
                b.fill:ClearAllPoints()
                b.fill:SetPoint("BOTTOM", b, "BOTTOM", 0, V_LABEL_H)
                b.fill:SetHeight(math.max(1, biggest > 0 and (V_BAR_MAX * r.count / biggest) or 1))
                local c = r.color or MIXED[(i - 1) % #MIXED + 1]
                b.fill:SetColorTexture(c[1], c[2], c[3], 1)
                b.fill:SetShown(r.count > 0)
                b.count:ClearAllPoints()
                b.count:SetPoint("BOTTOM", b.fill, "TOP", 0, 3)
                b.count:SetText(tostring(r.count))
                if r.count == 0 then b.count:ClearAllPoints() b.count:SetPoint("BOTTOM", b, "BOTTOM", 0, V_LABEL_H + 3) end
                b.label:ClearAllPoints()
                b.label:SetPoint("TOP", b, "BOTTOM", 0, V_LABEL_H - 4)
                b.label:SetWidth(step)
                b.label:SetText(r.label)
                b.barTitle, b.barCount, b.barNames, b.barClasses, b.barColored, b.barExtra = r.title or r.label, r.count, r.names, r.classes, r.colored ~= false, r.extra
                b:Show()
            else
                b:Hide()
            end
        end
    end
    return chart
end

local PROF_COLORS = {
    { 0.9, 0.35, 0.35 }, { 0.9, 0.6, 0.25 }, { 0.9, 0.82, 0.3 }, { 0.6, 0.85, 0.35 },
    { 0.3, 0.8, 0.5 }, { 0.3, 0.8, 0.8 }, { 0.35, 0.6, 0.95 }, { 0.55, 0.45, 0.95 },
    { 0.8, 0.45, 0.9 }, { 0.9, 0.4, 0.65 }, { 0.7, 0.7, 0.75 }, { 0.6, 0.5, 0.4 },
}
local RACE_COLORS = {
    { 0.35, 0.65, 0.95 }, { 0.95, 0.6, 0.25 }, { 0.5, 0.85, 0.4 }, { 0.85, 0.4, 0.55 },
    { 0.7, 0.55, 0.95 }, { 0.95, 0.85, 0.3 }, { 0.35, 0.8, 0.8 }, { 0.8, 0.5, 0.4 },
}
local ROLE_COLORS = { TANK = { 0.29, 0.62, 1 }, HEALER = { 0.25, 1, 0.25 }, DPS = { 1, 0.31, 0.31 } }
local UNKNOWN_COLOR = { 0.5, 0.5, 0.55 }

local function Count(n) return n .. (n == 1 and " character" or " characters") end

---------------------------------------------------------------------------
-- Makeup tab: a grid of six boxes, three in a row
---------------------------------------------------------------------------
local BW, BH = 262, 288
local COLX = { 0, 269, 538 }
local ROWY = { 0, -298 }

-- levels (horizontal): one bar per ten levels
local levelBox = NewBox(makeupPage, COLX[1], ROWY[1], BW, BH)
local levelChart = NewHChart(levelBox, "Level distribution", 8, { width = 234, label = 46, valueW = 66, row = 28, barH = 18 }, MIXED)
local function RefreshLevels()
    local buckets, total, biggest = ns.GetLevelDistribution()
    local rows = {}
    for i, b in ipairs(buckets) do
        rows[i] = { title = ("Level %d-%d"):format(b.from, b.to), label = ("%d-%d"):format(b.from, b.to), count = b.count, names = b.names, classes = b.classes, levels = b.levels }
    end
    levelChart:Set(rows, total, biggest)
end

-- classes (horizontal): the colour and the picture of the class, the most common first
local classBox = NewBox(makeupPage, COLX[2], ROWY[1], BW, BH)
local CLASS_ICON = {
    WARRIOR = 626008, PALADIN = 626003, HUNTER = 626000, ROGUE = 626005, PRIEST = 626004, SHAMAN = 626006, MAGE = 626001,
    WARLOCK = 626007, DRUID = 625999,
}
local classChart = NewHChart(classBox, "Class distribution", 9, { width = 234, icon = 18, label = 72, valueW = 24, row = 26, barH = 14 }, MIXED)
local function RefreshClasses()
    local list, total, biggest = ns.GetClassDistribution()
    local rows = {}
    for i, e in ipairs(list) do
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
        -- (the names of a class are not coloured: the bar already is)
        rows[i] = { title = e.name, label = K.ClassColored(e.name, e.class), count = e.count, names = e.names, colored = false, noPercent = true, icon = CLASS_ICON[e.class],
            color = c and { c.r, c.g, c.b } or nil }
    end
    classChart:Set(rows, total, biggest)
end

-- races (vertical)
local raceBox = NewBox(makeupPage, COLX[3], ROWY[1], BW, BH)
local raceChart = NewVChart(raceBox, "Race distribution", 6)
local function RefreshRaces()
    local list, total, biggest = ns.GetRaceDistribution()
    local rows = {}
    for i, e in ipairs(list) do rows[i] = { label = e.name, count = e.count, names = e.names, classes = e.classes, color = RACE_COLORS[(i - 1) % #RACE_COLORS + 1] } end
    raceChart:Set(rows, biggest)
end

-- talent trees (horizontal), the label carries the class: "Enhancement Shaman"
local specBox = NewBox(makeupPage, COLX[1], ROWY[2], BW, BH)
local specChart = NewHChart(specBox, "Spec distribution", 11, { width = 234, label = 128, valueW = 24, row = 22, barH = 11 }, MIXED)
local function RefreshSpecs()
    local list, known, unknown, biggest, unkNames, unkClasses = ns.GetSpecDistribution()
    local rows = {}
    for i, e in ipairs(list) do
        rows[i] = { title = e.label, label = K.ClassColored(e.label, e.class), count = e.count, names = e.names, classes = e.classes, noPercent = true, color = MIXED[(i - 1) % #MIXED + 1] }
    end
    local keep = {}
    for i = 1, math.min(#rows, 10) do keep[i] = rows[i] end
    keep[#keep + 1] = { title = "Unknown spec", label = Gray("Unknown"), count = unknown, names = unkNames, classes = unkClasses, noPercent = true, color = UNKNOWN_COLOR,
        extra = "No talent data shared yet" }
    specChart:Set(keep, known + unknown, math.max(biggest, unknown))
end

-- roles (vertical)
local roleBox = NewBox(makeupPage, COLX[2], ROWY[2], BW, BH)
local roleChart = NewVChart(roleBox, "Role distribution", 4)
local function RefreshRoles()
    local list, known, unknown, biggest, unkNames, unkClasses = ns.GetRoleDistribution()
    local rows = {}
    for i, e in ipairs(list) do
        rows[i] = { title = e.label, label = e.label, count = e.count, names = e.names, classes = e.classes, color = ROLE_COLORS[e.key] }
    end
    rows[#rows + 1] = { title = "Unknown role", label = Gray("Unknown"), count = unknown, names = unkNames, classes = unkClasses, color = UNKNOWN_COLOR, extra = "No talent data shared yet" }
    roleChart:Set(rows, math.max(biggest, unknown))
end

-- mains and alts (vertical)
local mainBox = NewBox(makeupPage, COLX[3], ROWY[2], BW, BH)
local mainChart = NewVChart(mainBox, "Mains and alts", 2)
local MAIN_COLORS = { MAIN = { 1, 0.82, 0 }, ALT = { 0.56, 0.78, 1 } }
local function RefreshMains()
    local list, total, biggest = ns.GetMainAltDistribution()
    local rows = {}
    for i, e in ipairs(list) do
        rows[i] = { title = e.label, label = e.label, count = e.count, names = e.names, classes = e.classes, color = MAIN_COLORS[e.key] }
    end
    mainChart:Set(rows, biggest)
end

---------------------------------------------------------------------------
-- Professions tab
---------------------------------------------------------------------------
local profBox = NewBox(profPage, COLX[1], 0, BW, 362)
local profChart = NewHChart(profBox, "Profession distribution", 12, { width = 234, icon = 18, label = 96, valueW = 26, row = 26, barH = 14 }, PROF_COLORS)
local function RefreshProfessions()
    local list, biggest = ns.GetProfessionDistribution()
    local total = 0
    for _, e in ipairs(list) do total = total + e.count end
    local rows = {}
    for i, e in ipairs(list) do
        -- (the skill of each character is shown next to the name on hover)
        rows[i] = { title = e.name, label = e.name, count = e.count, names = e.names, classes = e.classes, levels = e.levels, icon = e.icon, noPercent = true, color = PROF_COLORS[(i - 1) % #PROF_COLORS + 1] }
    end
    profChart:Set(rows, total, biggest)
    profChart.note:SetText(total == 0 and "No profession data yet" or "")
end

-- profession specializations: an icon and one word, grouped by profession
local specializationBox = NewBox(profPage, COLX[2], 0, BW, 362)
local specializationChart = NewHChart(specializationBox, "Specializations", 13, { width = 234, icon = 16, label = 100, valueW = 26, row = 24, barH = 12 }, PROF_COLORS)
local function RefreshSpecializations()
    local list, total, biggest = ns.GetSpecializationDistribution()
    local rows, lastKey = {}, nil
    for _, e in ipairs(list) do
        if e.key ~= lastKey then
            lastKey = e.key
            rows[#rows + 1] = { header = true, label = "|cffffd100" .. ns.Professions.ProfessionName(e.key) .. "|r" }
        end
        local color = PROF_COLORS[((tonumber(e.key) or 0) % #PROF_COLORS) + 1]
        rows[#rows + 1] = { title = e.name, label = e.short or e.name, count = e.count, names = e.names, classes = e.classes, icon = e.icon, noPercent = true, color = color }
    end
    specializationChart:Set(rows, total, biggest)
end

-- recipes the guild knows together per profession; hovering lists the characters with all of their professions
local recipeBox = NewBox(profPage, COLX[3], 0, BW, 362)
local recipeChart = NewHChart(recipeBox, "Recipes known", 9, { width = 234, icon = 18, label = 96, valueW = 34, row = 28, barH = 14 }, PROF_COLORS)
local function RefreshRecipes()
    local list, total, biggest = ns.GetRecipeDistribution()
    local rows = {}
    for i, e in ipairs(list) do
        rows[i] = { title = e.name, label = e.name, count = e.count, names = e.names, classes = e.classes, levels = e.levels, icon = e.icon, noPercent = true, noCount = true, color = PROF_COLORS[(i - 1) % #PROF_COLORS + 1],
            extra = ("%d different %s known by the guild together"):format(e.count, e.count == 1 and "recipe" or "recipes") }
    end
    recipeChart:Set(rows, total, biggest)
end

-- the records below the charts: three boxes with a big number and the name
local TILE_Y = -372
local tiles = {}
local function NewTile(x, label, color)
    local box = NewBox(profPage, x, TILE_Y, BW, 214)
    local t = { box = box, color = color }
    t.label = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    t.label:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -12)
    t.label:SetText(label)
    t.value = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t.value:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -52)
    pcall(t.value.SetFont, t.value, "Fonts\\FRIZQT__.TTF", 34, "OUTLINE")
    t.value:SetTextColor(color[1], color[2], color[3])
    t.name = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    t.name:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -108)
    t.what = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    t.what:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -134)
    tiles[#tiles + 1] = t
    return t
end
local sweatTile = NewTile(COLX[1], "Sweatiest crafter", { 1, 0.56, 0.2 })
local knowTile = NewTile(COLX[2], "Most knowledgeable crafter", { 0.45, 0.8, 1 })
local fishTile = NewTile(COLX[3], "Luckiest angler", { 0.3, 0.85, 0.7 })

local function FillTile(tile, r, what)
    if not r then
        tile.value:SetText("-")
        tile.value:SetTextColor(0.5, 0.5, 0.5)
        tile.name:SetText(Gray("Nobody yet"))
        tile.what:SetText("")
        return
    end
    tile.value:SetText(K.Commas(r.amount))
    tile.value:SetTextColor(tile.color[1], tile.color[2], tile.color[3])
    tile.name:SetText(K.ClassColored(r.name, r.class))
    tile.what:SetText(what)
end
local function RefreshRecords()
    FillTile(sweatTile, ns.GetSweatiest(), "crafts in total")
    FillTile(knowTile, ns.GetMostKnowledgeable(), "recipes known")
    FillTile(fishTile, ns.GetGameRecord("fish"), "fishes caught")
end

---------------------------------------------------------------------------
-- switching tabs and refreshing
---------------------------------------------------------------------------
local current = "makeup"

local function RefreshPage()
    if current == "makeup" then
        RefreshLevels()
        RefreshClasses()
        RefreshRaces()
        RefreshSpecs()
        RefreshRoles()
        RefreshMains()
    else
        RefreshProfessions()
        RefreshSpecializations()
        RefreshRecipes()
        RefreshRecords()
    end
end

function ns.UI.AnalyticsSelectTab(id)
    current = id
    makeupPage:SetShown(id == "makeup")
    profPage:SetShown(id == "professions")
    for tab, which in pairs({ [tabMakeup] = "makeup", [tabProfessions] = "professions" }) do
        if which == id then tab:LockHighlight() else tab:UnlockHighlight() end
    end
    if root:IsShown() then RefreshPage() end
end

tabMakeup:SetScript("OnClick", function() ns.UI.AnalyticsSelectTab("makeup") end)
tabProfessions:SetScript("OnClick", function() ns.UI.AnalyticsSelectTab("professions") end)
K.analyticsMakeupPage, K.analyticsProfessionsPage = makeupPage, profPage

function ns.UI.RefreshAnalytics()
    if root:IsShown() then RefreshPage() end
end

root:SetScript("OnShow", function()
    ns.RequestRoster()
    ns.UI.AnalyticsSelectTab(current)
end)
tabMakeup:LockHighlight()
makeupPage:Show()
