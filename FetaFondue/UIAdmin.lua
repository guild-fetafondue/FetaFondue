---@class ns
local ns = select(2, ...)
local K = ns.K
local Gray, BOX_BACKDROP, NewWindow = K.Gray, K.BOX_BACKDROP, K.NewWindow

---------------------------------------------------------------------------
-- Admin: only for the admin character (see ns.ADMIN_NAMES). Shows who has installed which version, when
-- each addon was last heard from, message counts, errors and what data it holds, and who in the guild has
-- not been seen running the addon.
---------------------------------------------------------------------------
local panel = K.adminPanel

local header = panel:Text("GameFontNormalLarge", 0, -4, 500)
header:SetText("Admin")
local only = panel:Text("GameFontDisableSmall", 400, -10, 400, "RIGHT")
only:SetText("Only you see this tab")

local function NewBox(x, y, w, h)
    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetBackdrop(BOX_BACKDROP)
    box:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    box:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    box:SetSize(w, h)
    return box
end

---------------------------------------------------------------------------
-- the data
---------------------------------------------------------------------------
local function VersionKey(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)$")
    if not a then return nil end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + (tonumber(c) or 0)
end

local function AgeText(at)
    if not at or at == 0 then return "never" end
    local secs = math.max(0, ns.Time() - at)
    if secs < 90 then return "now" end
    if secs < 5400 then return math.floor(secs / 60 + 0.5) .. " min ago" end
    if secs < 129600 then return math.floor(secs / 3600 + 0.5) .. " h ago" end
    return math.floor(secs / 86400 + 0.5) .. " days ago"
end

local function Minutes(m)
    if not m then return "?" end
    if m < 60 then return m .. " min" end
    return ("%dh %02dm"):format(math.floor(m / 60), m % 60)
end

-- one entry per character that runs the addon (or ran it: seen at some time)
function ns.AdminData()
    local roster = ns.GetRoster()
    local members = ns.GetMembers() or {}
    local rows, silent = {}, {}
    local latest
    for guid, m in pairs(members) do
        local diag = m.diag
        if ns.IsMine(guid) then diag = ns.Sync.OwnDiag() end
        if diag or m.seen then
            local entry = ns.FindRosterEntry(roster, guid, m.name)
            rows[#rows + 1] = {
                guid = guid, name = ns.DisplayName(entry and entry.name or m.name), class = entry and entry.class, online = entry and entry.online or false,
                inGuild = entry ~= nil, version = diag and diag.version or nil, diag = diag, seen = ns.IsMine(guid) and ns.Time() or m.seen, mine = ns.IsMine(guid),
            }
            local key = diag and VersionKey(diag.version)
            if key and (not latest or key > latest) then latest = key end
        end
    end
    local seenGUID = {}
    for _, r in ipairs(rows) do seenGUID[r.guid] = true end
    for _, e in ipairs(roster.list) do
        if e.guid and not seenGUID[e.guid] then
            silent[#silent + 1] = { name = ns.DisplayName(e.name), online = e.online, level = e.level, class = e.class }
        end
    end
    table.sort(rows, function(a, b)
        if (a.seen or 0) ~= (b.seen or 0) then return (a.seen or 0) > (b.seen or 0) end
        return a.name < b.name
    end)
    table.sort(silent, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    -- versions: how many characters run each
    local versions, unknown = {}, 0
    for _, r in ipairs(rows) do
        if r.version and r.version ~= "?" then versions[r.version] = (versions[r.version] or 0) + 1 else unknown = unknown + 1 end
    end
    local list = {}
    for v, n in pairs(versions) do list[#list + 1] = { version = v, count = n, key = VersionKey(v) or 0 } end
    table.sort(list, function(a, b) return a.key > b.key end)
    return rows, silent, list, unknown, latest
end

-- all of it as text, for pasting somewhere
function ns.AdminReport()
    local rows, silent, versions, unknown = ns.AdminData()
    local lines = { ("FetaFondue report %s (this client: version %s)"):format(date("%Y-%m-%d %H:%M"), ns.Version()) }
    local vs = {}
    for _, v in ipairs(versions) do vs[#vs + 1] = ("%s x%d"):format(v.version, v.count) end
    if unknown > 0 then vs[#vs + 1] = ("no version info x%d"):format(unknown) end
    lines[#lines + 1] = "Versions: " .. (#vs > 0 and table.concat(vs, ", ") or "none")
    lines[#lines + 1] = ("Running the addon: %d characters. Not seen: %d."):format(#rows, #silent)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Character | Version | Build | Last seen | Session | Msgs in/out | Errors | Professions/Recipes | Last error"
    for _, r in ipairs(rows) do
        local d = r.diag
        lines[#lines + 1] = ("%s%s | %s | %s | %s | %s | %s | %s | %s | %s"):format(
            r.name, r.inGuild and "" or " (left the guild)", d and d.version or "no info", d and d.build or "-", AgeText(r.seen),
            d and Minutes(d.session) or "-", d and (d.inN .. "/" .. d.outN) or "-", d and d.errors or "-",
            d and (d.profs .. "/" .. d.recipes) or "-", (d and d.lastError ~= "" and d.lastError) or "")
    end
    if #silent > 0 then
        lines[#lines + 1] = ""
        local names = {}
        for _, s in ipairs(silent) do names[#names + 1] = s.name end
        lines[#lines + 1] = "Not seen running the addon: " .. table.concat(names, ", ")
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- the summary
---------------------------------------------------------------------------
local summaryBox = NewBox(0, -34, 800, 84)
local sumLine1 = summaryBox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
sumLine1:SetPoint("TOPLEFT", summaryBox, "TOPLEFT", 14, -12)
local sumLine2 = summaryBox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
sumLine2:SetPoint("TOPLEFT", summaryBox, "TOPLEFT", 14, -32)
local sumLine3 = summaryBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
sumLine3:SetPoint("TOPLEFT", summaryBox, "TOPLEFT", 14, -56)

---------------------------------------------------------------------------
-- the table
---------------------------------------------------------------------------
local COLS = {
    { "Character", 8, 160 }, { "Version", 176, 70 }, { "Last seen", 252, 100 }, { "Session", 356, 70 },
    { "Msgs in / out", 430, 100 }, { "Errors", 536, 50 }, { "Prof. / recipes", 592, 90 }, { "Build", 690, 80 },
}
for _, c in ipairs(COLS) do
    local t = panel:Text("GameFontNormalSmall", c[2] + 6, -126, c[3])
    t:SetText(c[1])
end
local tableBox = NewBox(0, -144, 800, 290)

local function RenderRow(row, item)
    if not row.cols then
        row.cols = {}
        for i, c in ipairs(COLS) do
            local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", c[2], 0)
            fs:SetWidth(c[3])
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.cols[i] = fs
        end
    end
    row.text:SetText("")
    if item.note then
        for i = 1, #COLS do row.cols[i]:SetText("") end
        row.cols[1]:SetWidth(700)
        row.cols[1]:SetText(Gray(item.note))
        row.onEnter = nil
        return
    end
    row.cols[1]:SetWidth(COLS[1][3])
    local r, d = item.row, item.row.diag
    local outdated = item.latest and d and VersionKey(d.version) and VersionKey(d.version) < item.latest
    row.cols[1]:SetText((r.online and "|cff40ff40•|r " or "|cff666666•|r ") .. K.ClassColored(r.name, r.class) .. (r.mine and Gray(" (you)") or "") .. (r.inGuild and "" or Gray(" left")))
    row.cols[2]:SetText(d and ((outdated and "|cffffa040" or "|cffffffff") .. d.version .. "|r") or Gray("unknown"))
    row.cols[3]:SetText(AgeText(r.seen))
    row.cols[4]:SetText(d and Minutes(d.session) or Gray("-"))
    row.cols[5]:SetText(d and (d.inN .. " / " .. d.outN) or Gray("-"))
    row.cols[6]:SetText(d and (d.errors > 0 and ("|cffff5050" .. d.errors .. "|r") or "0") or Gray("-"))
    row.cols[7]:SetText(d and (d.profs .. " / " .. d.recipes) or Gray("-"))
    row.cols[8]:SetText(d and d.build or Gray("-"))
    row.onEnter = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(r.name, 1, 1, 1)
        GameTooltip:AddLine(r.guid, 0.5, 0.5, 0.5)
        if d then
            GameTooltip:AddLine(("Version %s, game build %s"):format(d.version, d.build), 1, 0.82, 0)
            GameTooltip:AddLine(("This session: %s, %d messages in, %d out"):format(Minutes(d.session), d.inN, d.outN), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(("Holds data about %d characters; shares %d professions with %d recipes"):format(d.members, d.profs, d.recipes), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(("Report from %s"):format(AgeText(d.at)), 0.6, 0.6, 0.6)
            if d.errors > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(("%d errors this session. The last one:"):format(d.errors), 1, 0.4, 0.4)
                GameTooltip:AddLine(d.lastError ~= "" and d.lastError or "(no text)", 0.9, 0.9, 0.9, true)
            end
        else
            GameTooltip:AddLine("Heard from, but no version information (an older version).", 1, 0.65, 0.25, true)
        end
        GameTooltip:Show()
    end
end
local list = K.CreateScrollList(tableBox, 800 - 8 - 28, 290 - 16, 22, RenderRow, { stripes = true })
list.frame:SetPoint("TOPLEFT", tableBox, "TOPLEFT", 6, -8)

---------------------------------------------------------------------------
-- who is missing
---------------------------------------------------------------------------
local missTitle = panel:Text("GameFontNormal", 0, -452, 500)
local missBox = NewBox(0, -472, 800, 96)
local missText = missBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
missText:SetPoint("TOPLEFT", missBox, "TOPLEFT", 12, -10)
missText:SetWidth(776)
missText:SetJustifyH("LEFT")
missText:SetJustifyV("TOP")
missText:SetWordWrap(true)

---------------------------------------------------------------------------
-- buttons and the report window
---------------------------------------------------------------------------
local ask = K.NewButton(panel, "Ask everybody to report now")
ask:SetSize(210, 26)
ask:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -586)
local copy = K.NewButton(panel, "Copy report")
copy:SetSize(130, 26)
copy:SetPoint("LEFT", ask, "RIGHT", 8, 0)
local askNote = panel:Text("GameFontDisableSmall", 360, -592, 440)
-- tell everybody that the version of this client is out (upload the file to the Discord channel first)
local announce = K.NewButton(panel, "Announce this version")
announce:SetSize(170, 26)
announce:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -586)
announce:SetScript("OnClick", function()
    local v = ns.Version()
    K.Confirm("Announce version " .. v, ("Is version %s already uploaded in the fetafondue-addon channel? Everybody who runs an older version will get a window telling them to download it."):format(v), function()
        if ns.Sync.AnnounceRelease() then
            askNote:SetText(("Announced version %s. Players who are online get the window now, the others when they log in."):format(v))
        else
            askNote:SetText("Could not announce (not in the guild yet, or the version is unknown).")
        end
    end, "Yes, it is uploaded", "No")
end)

local report = NewWindow("FetaFondueReport", 700, 520)
report:SetFrameStrata("FULLSCREEN_DIALOG")
report:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
report:SetTitle("Report: select all with Ctrl+A, copy with Ctrl+C")
local rscroll = CreateFrame("ScrollFrame", "FetaFondueReportScroll", report)
rscroll:SetPoint("TOPLEFT", report, "TOPLEFT", 20, -48)
rscroll:SetPoint("BOTTOMRIGHT", report, "BOTTOMRIGHT", -20, 56)
rscroll:EnableMouseWheel(true)
rscroll:SetScript("OnMouseWheel", function(self, delta)
    local cur, max = tonumber(self:GetVerticalScroll()) or 0, tonumber(self:GetVerticalScrollRange()) or 0
    self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 40)))
end)
local redit = CreateFrame("EditBox", "FetaFondueReportText", rscroll)
redit:SetMultiLine(true)
redit:SetAutoFocus(false)
redit:SetFontObject("ChatFontNormal")
redit:SetSize(640, 400)
redit:SetMaxLetters(0)
rscroll:SetScrollChild(redit)
rscroll:EnableMouse(true)
rscroll:SetScript("OnMouseDown", function() redit:SetFocus() end)
redit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
local rclose = K.NewButton(report, "Close")
rclose:SetSize(110, 26)
rclose:SetPoint("BOTTOMRIGHT", report, "BOTTOMRIGHT", -20, 16)
rclose:SetScript("OnClick", function() report:Hide() end)

copy:SetScript("OnClick", function()
    local text = ns.AdminReport()
    redit:SetText(text)
    local lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end
    redit:SetHeight(math.max(400, lines * 14 + 20))
    report:Show()
    redit:SetFocus()
    redit:HighlightText()
end)
ask:SetScript("OnClick", function()
    if ns.Sync.RequestStatus() then
        askNote:SetText("Asked. The answers arrive over the next minute.")
    else
        askNote:SetText("Wait a couple of minutes between requests.")
    end
end)
K.RegisterCloser(function() report:Hide() end)

---------------------------------------------------------------------------
function ns.UI.RefreshAdmin()
    if not panel:IsShown() then return end
    local rows, silent, versions, unknown, latest = ns.AdminData()
    local vs = {}
    for _, v in ipairs(versions) do vs[#vs + 1] = ("|cffffffff%s|r x%d"):format(v.version, v.count) end
    if unknown > 0 then vs[#vs + 1] = Gray(("no version info x%d"):format(unknown)) end
    local online = 0
    for _, r in ipairs(rows) do if r.online then online = online + 1 end end
    sumLine1:SetText(("%d characters run the addon (%d online now). %d guild members not seen with it."):format(#rows, online, #silent))
    sumLine2:SetText("Versions: " .. (#vs > 0 and table.concat(vs, "   ") or Gray("none yet")))
    sumLine3:SetText(("This client: version %s, session %s, %d errors. Orange = older than the newest version seen."):format(ns.Version(), Minutes(ns.SessionMinutes()), ns.errors.count))

    local items = {}
    for _, r in ipairs(rows) do items[#items + 1] = { row = r, latest = latest } end
    if #items == 0 then items = { { note = "Nobody has reported yet." } } end
    list:Render(items)

    missTitle:SetText(("Not seen running the addon (%d)"):format(#silent))
    if #silent == 0 then
        missText:SetText(Gray("Everybody in the guild has been seen."))
    else
        local names = {}
        for i, s in ipairs(silent) do
            if i > 60 then names[#names + 1] = Gray(("and %d more"):format(#silent - 60)) break end
            names[#names + 1] = (s.online and "|cff40ff40" or "|cff999999") .. s.name .. "|r"
        end
        missText:SetText(table.concat(names, ", "))
    end
end
