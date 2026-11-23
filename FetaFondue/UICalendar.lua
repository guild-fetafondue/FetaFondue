---@class ns
local ns = select(2, ...)
local K = ns.K
local Gold, Gray, BOX_BACKDROP, CreateScrollList = K.Gold, K.Gray, K.BOX_BACKDROP, K.CreateScrollList
local R = ns.Raids

---------------------------------------------------------------------------
-- Events: the raid calendar of the addon, a month view. Officers and the guild master add raids in Management
-- (from the JSON of a Raid-Helper event); everybody who uses the addon sees them. The game's own calendar is not
-- used at all.
---------------------------------------------------------------------------
local root = K.calendarPanel

-- two tabs on top (as in the Sweatshop and Management): Calendar (the month and the raids of the day) and the Planner
local strip = K.NewTabStrip(root, 0)
local calTab = strip:AddTab(0, "Calendar", 112)
local planTab = strip:AddTab(116, "Planner", 112)
local panel = K.NewPanel("FetaFondueCalendarPage", root, 800, 586)       -- (the calendar itself; "panel" is what the code below draws on)
panel:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -34)
-- the Planner is laid out for a page that starts 66 below its top: this page starts 24 above the area, so its content begins right under the tabs
local planPage = K.NewPanel("FetaFondueCompositionPage", root, 800, 590)
planPage:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 24)
ns.UI.BuildComposition(planPage)

local MONTHS = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}
local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local RAID_COLOR = "ff9a3c"        -- not the gold of the headers, so it does not blend with the day numbers

local CELL_W, CELL_H = 110, 62
local GRID_X, GRID_Y = 15, -64
local LABEL_Y = -446          -- the "Month day" label above the list of the selected day

local view = { year = nil, month = nil, selected = nil, days = {}, numDays = 0, firstWeekday = 1 }

local function Today()
    local d = R.DateTable(ns.Time())
    return d.year, d.month, d.day
end

-- the tooltip of a raid: everything about it (also used by the Management list)
function ns.UI.RaidTooltip(owner, rec)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(rec.title, 1, 0.6, 0.24)
    GameTooltip:AddLine(("%s  (%s)"):format(R.WhenText(rec.start), R.Relative(rec.start)), 1, 1, 1)
    local organizer = (rec.org and rec.org ~= "" and rec.org) or (rec.leader ~= "" and rec.leader) or nil
    if organizer then GameTooltip:AddLine("Organized by " .. organizer, 0.8, 0.8, 0.8) end
    if rec.desc and rec.desc ~= "" then GameTooltip:AddLine(rec.desc, 0.9, 0.9, 0.9, true) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(R.SignedText(rec, true, "|cffffd100"), 1, 0.82, 0)
    local others = R.OthersText(rec)
    if others ~= "" then GameTooltip:AddLine((others:gsub("^%l", string.upper)), 0.7, 0.7, 0.7) end
    -- melee, ranged and the rest of the damage dealers are all DPS; the characters are shown, not the Discord names
    local byRole = { T = {}, H = {}, D = {}, O = {} }
    local roleOf = { T = "T", H = "H", M = "D", R = "D", D = "D" }
    local roster = ns.GetRoster()
    for _, s in ipairs(rec.signups or {}) do
        if s.st == "signed" then
            local list = byRole[roleOf[s.r] or "O"]
            -- class colors; my own character is green
            local entry = R.CharEntry(s.n, roster)
            local name = R.CharName(s.n, roster)
            if entry and entry.guid and ns.IsMine(entry.guid) then
                name = "|cff66ff66" .. name .. "|r"
            elseif entry and entry.class then
                name = K.ClassColored(name, entry.class)
            end
            list[#list + 1] = name
        end
    end
    for _, role in ipairs({ { "T", "Tanks" }, { "H", "Healers" }, { "D", "DPS" }, { "O", "Other" } }) do
        local names = byRole[role[1]]
        if #names > 0 then
            local shown = {}
            for i = 1, math.min(#names, 30) do shown[i] = names[i] end
            GameTooltip:AddLine(("%s: %s%s"):format(role[2], table.concat(shown, ", "), #names > 30 and (" +" .. (#names - 30)) or ""), 0.85, 0.85, 0.85, true)
        end
    end
    local me = R.MyEntry(rec)
    if me then GameTooltip:AddLine("You: " .. R.StateText(me), 0.4, 1, 0.4) end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- header: month title and navigation
---------------------------------------------------------------------------
local Refresh

local title = panel:Text("GameFontNormalLarge", 160, -8, 320)

local function NavButton(x, text, width)
    local b = K.NewButton(panel)
    b:SetSize(width or 30, 24)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -6)
    b:SetText(text)
    return b
end
local prevButton = NavButton(15, "<")
local nextButton = NavButton(49, ">")
local todayButton = NavButton(83, "Today", 60)

for i, name in ipairs(WEEKDAYS) do
    local fs = panel:Text("GameFontNormal", GRID_X + (i - 1) * CELL_W, -42, CELL_W, "CENTER")
    fs:SetText(name)
end

---------------------------------------------------------------------------
-- the grid
---------------------------------------------------------------------------
local cells = {}
local Refresh

local function NewCell(i)
    local col, row = (i - 1) % 7, math.floor((i - 1) / 7)
    local c = CreateFrame("Button", nil, panel)
    c:SetSize(CELL_W - 3, CELL_H - 3)
    c:SetPoint("TOPLEFT", panel, "TOPLEFT", GRID_X + col * CELL_W, GRID_Y - row * CELL_H)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0.09, 0.09, 0.1, 1)
    c.sel = c:CreateTexture(nil, "BORDER")
    c.sel:SetAllPoints()
    c.sel:SetColorTexture(1, 0.82, 0, 0.22)
    c.sel:Hide()
    c.today = c:CreateTexture(nil, "ARTWORK")
    c.today:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.today:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
    c.today:SetHeight(3)
    c.today:SetColorTexture(1, 0.82, 0, 1)
    c.today:Hide()
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints()
    c.hl:SetColorTexture(1, 1, 1, 0.07)
    c.day = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")   -- white, not gold
    c.day:SetPoint("TOPLEFT", c, "TOPLEFT", 5, -4)
    c.lines = {}
    for k = 1, 3 do
        local fs = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", c, "TOPLEFT", 5, -4 - 13 * k - 3)
        fs:SetWidth(CELL_W - 12)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        c.lines[k] = fs
    end
    c:SetScript("OnClick", function(self)
        if self.dayNumber then
            view.selected = self.dayNumber
            Refresh()
        end
    end)
    c:SetScript("OnEnter", function(self)
        local list = self.dayNumber and view.days[self.dayNumber]
        if not list or #list == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(("%s %d"):format(MONTHS[view.month], self.dayNumber), 1, 1, 1)
        for _, ev in ipairs(list) do
            GameTooltip:AddLine(("%s  |cff%s%s|r"):format(ev.time, RAID_COLOR, ev.title), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end
for i = 1, 42 do cells[i] = NewCell(i) end

---------------------------------------------------------------------------
-- the selected day
---------------------------------------------------------------------------
local detailLabel = panel:Text("GameFontNormal", 15, LABEL_Y, 620)

local detailBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
detailBox:SetBackdrop(BOX_BACKDROP)
detailBox:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
detailBox:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
detailBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 15, -466)
detailBox:SetSize(770, 98)

local function RenderEventRow(row, item)
    if item.kind == "note" then
        row:EnableMouse(false)
        row.text:SetFontObject("GameFontDisable")
        row.text:SetText(item.text)
        return
    end
    row:EnableMouse(true)
    row.text:SetFontObject("GameFontHighlight")
    local ev = item.ev
    local rec = ev.rec
    -- "20:00  Onyxia  organized by Emiron, 8 signed up (3 tanks, 3 healers, 2 damage)"
    local organizer = (rec.org and rec.org ~= "" and rec.org) or (rec.leader ~= "" and rec.leader) or nil
    local signed = R.Counts(rec).signed
    local breakdown = R.SignedText(rec, true, "|cff999999"):match("%((.*)%)$")
    local people = signed > 0 and ("%d signed up%s"):format(signed, breakdown and (" (" .. breakdown .. ")") or "") or "nobody signed up yet"
    row.text:SetText(("%s  |cff%s%s|r  %s"):format(Gray(ev.time), RAID_COLOR, rec.title,
        Gray((organizer and ("organized by " .. organizer .. ", ") or "") .. people)))
    row.onEnter = function(r) ns.UI.RaidTooltip(r, rec) end
    row.onClick = function() ns.UI.OpenRaidInfo(rec) end          -- the same window as on the dashboard
end
local eventList = CreateScrollList(detailBox, 770 - 8 - 28, 98 - 16, 20, RenderEventRow, { stripes = true })
eventList.frame:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 6, -8)

---------------------------------------------------------------------------
-- the month: raids by day
---------------------------------------------------------------------------
local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local SAKAMOTO = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
-- days in a month and the weekday of its first day (1 = Sunday), from plain arithmetic
local function MonthShape(year, month)
    local days = MONTH_DAYS[month]
    if month == 2 and ((year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0) then days = 29 end
    local y = (month < 3) and (year - 1) or year
    local weekday = (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + SAKAMOTO[month] + 1) % 7
    return days, weekday + 1
end

local function LoadMonth(year, month)
    view.numDays, view.firstWeekday = MonthShape(year, month)
    view.days = {}
    for _, rec in ipairs(R.List()) do
        local d = R.DateTable(rec.start)
        if d.year == year and d.month == month then
            local list = view.days[d.day] or {}
            view.days[d.day] = list
            list[#list + 1] = { rec = rec, title = rec.title, time = ("%02d:%02d"):format(d.hour, d.min), sort = d.hour * 60 + d.min }
        end
    end
    for _, list in pairs(view.days) do table.sort(list, function(a, b) return a.sort < b.sort end) end
end

Refresh = function()
    if not panel:IsShown() then return end
    local ty, tm, td = Today()
    if not view.year then
        view.year, view.month, view.selected = ty, tm, td
    end
    title:SetText(("%s %d"):format(MONTHS[view.month] or "?", view.year))
    LoadMonth(view.year, view.month)

    for i, c in ipairs(cells) do
        local day = i - (view.firstWeekday - 1)
        if day >= 1 and day <= view.numDays then
            c.dayNumber = day
            c:Show()
            c.day:SetText(day)
            local isToday = (view.year == ty and view.month == tm and day == td)
            c.today:SetShown(isToday)
            c.sel:SetShown(view.selected == day)
            local list = view.days[day] or {}
            for k = 1, 3 do
                local ev = list[k]
                if k == 3 and #list > 3 then
                    c.lines[k]:SetText(Gray("+" .. (#list - 2) .. " more"))
                elseif ev then
                    c.lines[k]:SetText(("%s |cff%s%s|r"):format(Gray(ev.time), RAID_COLOR, ev.title))
                else
                    c.lines[k]:SetText("")
                end
            end
        else
            c.dayNumber = nil
            c:Hide()
        end
    end

    local sel = view.selected
    local list = sel and view.days[sel] or nil
    detailLabel:SetText(sel and ("%s %d"):format(MONTHS[view.month] or "?", sel) or "Pick a day")
    local rows = {}
    for _, ev in ipairs(list or {}) do rows[#rows + 1] = { kind = "event", ev = ev } end
    if #rows == 0 then
        rows[1] = { kind = "note", text = (#R.List() == 0) and "No raids have been added yet." or "No raid on this day." }
    end
    eventList:Render(rows)
end

local function Shift(delta)
    local month = view.month + delta
    local year = view.year
    if month < 1 then month, year = 12, year - 1 end
    if month > 12 then month, year = 1, year + 1 end
    view.month, view.year, view.selected = month, year, nil
    Refresh()
end
prevButton:SetScript("OnClick", function() Shift(-1) end)
nextButton:SetScript("OnClick", function() Shift(1) end)
todayButton:SetScript("OnClick", function()
    local y, m, d = Today()
    view.year, view.month, view.selected = y, m, d
    Refresh()
end)

-- the tab was selected
local currentSub = "calendar"
local function ShowSub(id)
    currentSub = id
    panel:SetShown(id == "calendar")
    planPage:SetShown(id == "planner")
    calTab:UnlockHighlight() planTab:UnlockHighlight()
    if id == "planner" then planTab:LockHighlight() else calTab:LockHighlight() end
    if id == "planner" then
        if ns.UI.RefreshComposition then ns.UI.RefreshComposition() end
    else
        Refresh()
    end
end
calTab:SetScript("OnClick", function() ShowSub("calendar") end)
planTab:SetScript("OnClick", function() ShowSub("planner") end)

function ns.UI.OnCalendarShown()
    ShowSub(currentSub)
end
panel:Show()                 -- (the Calendar page is the one shown when the tab opens)
calTab:LockHighlight()

function ns.UI.RefreshCalendar()
    if panel:IsShown() then Refresh() end
end
