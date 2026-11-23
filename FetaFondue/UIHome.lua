---@class ns
local ns = select(2, ...)
local K = ns.K
local Gold, Gray, Commas, Plural, GuildTitle, CreateScrollList, BOX_BACKDROP =
    K.Gold, K.Gray, K.Commas, K.Plural, K.GuildTitle, K.CreateScrollList, K.BOX_BACKDROP
local OpenMemberMenu = K.OpenMemberMenu

---------------------------------------------------------------------------
-- Dashboard: Forever stats as tiles on top; below them a spot reserved for the upcoming calendar events (left)
-- and the requests (right); at the bottom, full width, who is online (Now).
---------------------------------------------------------------------------
local home = K.homePanel   -- the page inside the main window (created in UIMain.lua)
local COIN = "|TInterface\\MoneyFrame\\UI-GoldIcon:11:11:2:0|t"

local function NewBox(x, y, w, h)
    local box = CreateFrame("Frame", nil, home, "BackdropTemplate")
    box:SetBackdrop(BOX_BACKDROP)
    box:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    box:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    box:SetPoint("TOPLEFT", home, "TOPLEFT", x, y)
    box:SetSize(w, h)
    return box
end

-- FetaFondue Forever: five stat tiles ------------------------------------
local foreverHeader = home:Text("GameFontNormalLarge", 0, -4, 400)

local TILE_W, TILE_GAP = 152, 10      -- (five tiles and four gaps are the 800 of the page)
local function NewTile(index, label)
    local tile = CreateFrame("Frame", nil, home, "BackdropTemplate")
    tile:SetBackdrop(BOX_BACKDROP)
    tile:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    tile:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    tile:SetPoint("TOPLEFT", home, "TOPLEFT", (index - 1) * (TILE_W + TILE_GAP), -30)
    tile:SetSize(TILE_W, 68)
    tile.number = tile:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    tile.number:SetPoint("TOP", tile, "TOP", 0, -12)
    pcall(tile.number.SetFont, tile.number, "Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
    tile.number:SetTextColor(1, 0.82, 0)
    tile.label = tile:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tile.label:SetPoint("BOTTOM", tile, "BOTTOM", 0, 10)
    tile.label:SetText(label)
    return tile
end
local tileDungeons = NewTile(1, "Dungeons cleared")
local tileBosses = NewTile(2, "Dungeon bosses killed")
local tileCrafts = NewTile(3, "Crafts")
local tileGold = NewTile(4, "Total plundered")
local tileBank = NewTile(5, "Guild bank")

-- the game only tells the gold in the guild bank while somebody has it open: the number is what a guildie last saw
tileBank:EnableMouse(true)
tileBank:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Guild bank", 1, 1, 1)
    local money, seen, by = ns.GetGuildBank()
    if money then
        local who = (by and by ~= "") and (" by " .. ns.DisplayName(by)) or ""
        GameTooltip:AddLine(("Last seen %s%s"):format(K.AgeText(seen), who), 0.8, 0.8, 0.8, true)
    else
        GameTooltip:AddLine("Nobody has looked into the guild bank yet.", 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine("The game only tells the gold while the bank is open: open it to update the number for everybody.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end)
tileBank:SetScript("OnLeave", function() GameTooltip:Hide() end)

home:Divider(-112, 0, 800)

-- right: the requests --------------------------------------------------------
local workHeader = home:Text("GameFontNormalLarge", 408, -122, 392)
local workSummary = home:Text("GameFontHighlight", 408, -146, 392)
-- (officers and the guild master) all requests of the guild, not only mine and the ones I can fulfil
local allRequestsCheck = K.NewCheck(home, "All requests", function(checked)
    ns.DB.showAllRequests = checked
    ns.UI.RefreshHome()
    if ns.UI.RefreshRequests then ns.UI.RefreshRequests() end
end)
allRequestsCheck:SetPoint("LEFT", workSummary, "LEFT", 230, 0)
local requestBox = NewBox(408, -166, 392, 176)
local dashList = CreateScrollList(requestBox, 392 - 8 - 28, 176 - 16, 22,
    K.RequestRowRenderer({ onOpen = function(r) ns.UI.OpenSweatshopRecipe(r.id, r.qty) end }), { stripes = true })
dashList.frame:SetPoint("TOPLEFT", requestBox, "TOPLEFT", 6, -8)

-- left: the upcoming raids, one at a time; the arrows go through them --------------------
local R = ns.Raids
local eventsHeader = home:Text("GameFontNormalLarge", 0, -122, 230)
eventsHeader:SetText("Upcoming raids")
local eventsBox = NewBox(0, -166, 392, 176)
local eventIndex = 1

local evCount = home:Text("GameFontDisableSmall", 236, -128, 90, "RIGHT")
local evPrev = K.NewButton(home, "<")
evPrev:SetSize(28, 22)
evPrev:SetPoint("TOPLEFT", home, "TOPLEFT", 332, -124)
local evNext = K.NewButton(home, ">")
evNext:SetSize(28, 22)
evNext:SetPoint("TOPLEFT", home, "TOPLEFT", 364, -124)

local measure = eventsBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
measure:SetAlpha(0)
measure:SetPoint("TOPLEFT", eventsBox, "TOPLEFT", 0, 0)

local evTitle = eventsBox:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
evTitle:SetPoint("TOPLEFT", eventsBox, "TOPLEFT", 12, -10)
evTitle:SetWidth(368)
evTitle:SetJustifyH("LEFT")
evTitle:SetWordWrap(false)

-- the lines under the title are reused: description, when, organizer, the sign-ups by state, my own state
local evLines = {}
for i = 1, 9 do
    local fs = eventsBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetWidth(368)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    evLines[i] = fs
end
local evNone = eventsBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
evNone:SetPoint("CENTER", eventsBox, "CENTER", 0, 0)
evNone:SetWidth(320)

-- 15 minutes before a raid that I (or an alt) signed up for, the box gets a highlighted border (and a warmer background)
local highlighted = false

eventsBox:EnableMouse(true)
eventsBox:SetScript("OnEnter", function(self)
    local rec = R.Upcoming()[eventIndex]
    if rec then
        ns.UI.RaidTooltip(self, rec)
        GameTooltip:AddLine(K.Key("Click") .. ": all the details", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end
end)
eventsBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
eventsBox:SetScript("OnMouseUp", function()
    local rec = R.Upcoming()[eventIndex]
    if rec and ns.UI.OpenRaidInfo then ns.UI.OpenRaidInfo(rec) end
end)

-- a description cut to one line
local function OneLine(text, width)
    measure:SetText(text)
    if (measure:GetStringWidth() or 0) <= width then return text end
    local cut = text
    while #cut > 4 do
        cut = cut:sub(1, #cut - 3)
        measure:SetText(cut .. "...")
        if (measure:GetStringWidth() or 0) <= width then return cut .. "..." end
    end
    return cut
end

local function RefreshEvents()
    local list = R.Upcoming()
    if eventIndex > #list then eventIndex = #list end
    if eventIndex < 1 then eventIndex = 1 end
    local rec = list[eventIndex]
    evPrev:SetEnabled(#list > 1)
    evNext:SetEnabled(#list > 1)
    evCount:SetText(#list > 0 and Gray(("%d / %d"):format(eventIndex, #list)) or "")
    for _, fs in ipairs(evLines) do fs:SetText("") end
    highlighted = false
    if not rec then
        evTitle:SetText("")
        evNone:SetText(ns.CanModerate() and "No raids scheduled yet. Add one in Management, under Scheduling." or "No raids scheduled yet.")
    else
        evNone:SetText("")
        local s = R.Summary(rec)
        evTitle:SetText(s.title)
        evTitle:SetTextColor(1, 0.6, 0.24)
        local lines = {}
        if s.desc then lines[#lines + 1] = Gray(OneLine(s.desc, 368)) end
        lines[#lines + 1] = ("%s   %s"):format(s.when, Gray(s.left))
        if s.organizer then lines[#lines + 1] = Gray("organized by " .. s.organizer) end
        -- the counts only (the names are in the raid window): "Signed up (6): 1 tank, 2 healers, 3 dps"
        if s.signed > 0 then lines[#lines + 1] = ("|cffffd100Signed up (%d):|r %s"):format(s.signed, s.roles) end
        if s.others ~= "" then lines[#lines + 1] = Gray(s.others) end
        if s.mine then lines[#lines + 1] = "|cff66ff66You: " .. R.StateText(s.mine) .. "|r" end
        local y = 36
        for i, text in ipairs(lines) do
            local fs = evLines[i]
            if not fs then break end
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", eventsBox, "TOPLEFT", 12, -y)
            fs:SetText(text)
            y = y + 19
        end
        highlighted = R.IsSoon(rec) and R.MyActiveEntry(rec) ~= nil
    end
    if highlighted then
        eventsBox:SetBackdropBorderColor(1, 0.65, 0.2, 1)
        eventsBox:SetBackdropColor(0.14, 0.095, 0.04, 0.95)
    else
        eventsBox:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
        eventsBox:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    end
end

-- keeps the time left right, and starts the highlight when the 15 minutes begin
eventsBox:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t >= 5 then
        self.t = 0
        RefreshEvents()
    end
end)

-- the arrows go round: after the last one comes the first
evPrev:SetScript("OnClick", function()
    local n = #R.Upcoming()
    if n > 0 then eventIndex = (eventIndex - 2) % n + 1 end
    RefreshEvents()
end)
evNext:SetScript("OnClick", function()
    local n = #R.Upcoming()
    if n > 0 then eventIndex = eventIndex % n + 1 end
    RefreshEvents()
end)

-- bottom: FetaFondue Now ----------------------------------------------------------------
local nowHeader = home:Text("GameFontNormalLarge", 0, -352, 392)
local nowMembers = home:Text("GameFontHighlight", 0, -378, 392)
local nowLine = home:Text("GameFontHighlight", 300, -378, 500, "RIGHT")
local onlineBox = NewBox(0, -400, 800, 188)

-- also show the guildies who are offline? (right next to "26 members · 12 online", above the list)
local offlineCheck = K.NewCheck(home, "Show offline members", function(checked)
    ns.DB.showOffline = checked
    ns.UI.RefreshHome()
end)
offlineCheck:SetPoint("LEFT", nowMembers, "LEFT", 170, 0)

local function ClassColored(name, classFile)
    local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
    if c then
        local function Byte(x) return math.floor(x * 255 + 0.5) end
        return ("|cff%02x%02x%02x%s|r"):format(Byte(c.r), Byte(c.g), Byte(c.b), name)
    end
    return name
end

K.ClassColored = ClassColored

local KIND_LABEL = { raid = "raid", dungeon = "dungeon", capital = "capital city" }

-- what the guild roster (and synced profession data) tells us about a guildie
local function ShowMemberTooltip(row, m)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(ClassColored(m.name, m.class), 1, 1, 1)
    GameTooltip:AddLine(("Level %s %s"):format(tostring(m.level or "?"), m.classDisplay or ""), 1, 1, 1)
    if m.rank and m.rank ~= "" then GameTooltip:AddLine("Rank: " .. m.rank, 0.8, 0.8, 0.8) end
    local where = (m.zone and m.zone ~= "") and m.zone or "unknown"
    if m.online == false then
        GameTooltip:AddLine("Offline", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Zone: " .. where .. (m.kind and (" (" .. KIND_LABEL[m.kind] .. ")") or " (open world)"), 0.8, 0.8, 0.8)
    end
    if m.afk then GameTooltip:AddLine("Away from keyboard", 1, 0.5, 0.5) end
    if m.note and m.note ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("\"" .. m.note .. "\"", 0.6, 0.8, 1, true)
    end
    if m.profs and #m.profs > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Professions", 1, 0.82, 0)
        for _, p in ipairs(m.profs) do
            GameTooltip:AddLine(p.rank > 0 and ("%s (%d)"):format(p.name, p.rank) or p.name, 1, 1, 1)
        end
    end
    if m.altOfFull then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Alt of " .. m.altOfFull, 0.56, 0.78, 1)
        GameTooltip:AddLine(m.altSource == "set" and "Set by an officer" or "Guessed from the shared data", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(K.Key("Click") .. ": inspect gear and talents", 0.6, 0.6, 0.6)
    if not m.mine then GameTooltip:AddLine(K.Key("Right-click") .. ": options", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function RenderOnlineRow(row, item)
    if item.kind == "note" then
        row:EnableMouse(false)
        row.text:SetFontObject("GameFontDisable")
        row.text:SetText(item.text)
        return
    end
    local m = item.member
    row:EnableMouse(true)
    row.text:SetFontObject("GameFontHighlight")
    local where = (m.zone and m.zone ~= "") and m.zone or "?"
    local afk = m.afk and " |cffff8080<AFK>|r" or ""
    local colored = ClassColored(m.name, m.class)
    -- an alt says whose: the first name of the original character of the same person
    local alt = m.altOfFull and ("  |cff8fc7ffalt of " .. m.altOfFull .. "|r") or ""
    if m.online == false then
        -- offline: all grey
        row.text:SetText(("%s  %s%s"):format(Gray(m.name), Gray(("Lv %s · offline"):format(tostring(m.level or "?"))), m.altOfFull and Gray("  alt of " .. m.altOfFull) or ""))
    else
        row.text:SetText(("%s  %s%s%s"):format(colored, Gray(("Lv %s · %s"):format(tostring(m.level or "?"), where)), alt, afk))
    end
    row.onEnter = function(r) ShowMemberTooltip(r, m) end
    row.onClick = function() ns.UI.OpenInspect(m) end
    row.onRightClick = function() OpenMemberMenu(m, colored) end
end

local onlineList = CreateScrollList(onlineBox, 800 - 8 - 28, 188 - 16, 20, RenderOnlineRow, { stripes = true })
onlineList.frame:SetPoint("TOPLEFT", onlineBox, "TOPLEFT", 6, -8)

-- open the window at login? (off unless turned on here)
local loginCheck = K.NewCheck(home, "Open this window when I log in", function(checked) ns.DB.openOnLogin = checked end)
loginCheck:SetPoint("TOPLEFT", home, "TOPLEFT", 0, -596)

local function RefreshHome()
    RefreshEvents()
    local guild = GuildTitle()
    loginCheck:SetChecked(ns.DB.openOnLogin == true)
    offlineCheck:SetChecked(ns.DB.showOffline == true)

    -- Now
    nowHeader:SetText(guild .. " Now")
    local items = {}
    if not IsInGuild() and not (ns.DB and ns.DB.demo) then
        nowMembers:SetText("You are not in a guild")
        nowLine:SetText("")
    else
        local s = ns.GetNowStats()
        nowMembers:SetText(("%s %s · %s online"):format(Gold(s.members), Plural(s.members, "member", "members"), Gold(s.online)))
        -- the toggle sits right of that text, wherever it ends
        local w = nowMembers.GetStringWidth and nowMembers:GetStringWidth() or 0
        if type(w) ~= "number" or w <= 0 then w = 150 end
        offlineCheck:ClearAllPoints()
        offlineCheck:SetPoint("LEFT", nowMembers, "LEFT", w + 18, 0)
        nowLine:SetText(("%s in dungeons · %s raiding · %s in the open world · %s in capitals · %s AFK"):format(
            Gold(s.dungeon), Gold(s.raid), Gold(s.world), Gold(s.capital), Gold(s.afk)))
        for _, m in ipairs(ns.GetOnlineMembers(ns.DB.showOffline == true)) do items[#items + 1] = { kind = "member", member = m } end
    end
    if #items == 0 then
        items[1] = { kind = "note", text = (ns.DB and ns.DB.demo) and "Demo numbers are on (/ff demo)." or "Nobody is online." }
    end
    onlineList:Render(items, true)

    -- Forever
    foreverHeader:SetText(guild .. " Forever")
    local d, b, c, g, n, users = ns.GetForeverStats()
    tileDungeons.number:SetText(K.Short(d))
    tileBosses.number:SetText(K.Short(b))
    tileCrafts.number:SetText(K.Short(c))
    tileGold.number:SetText(K.Short(g / 10000) .. COIN)
    local bank = ns.GetGuildBank()
    tileBank.number:SetText(bank and (K.Short(bank / 10000) .. COIN) or "-")
    if bank then tileBank.number:SetTextColor(1, 0.82, 0) else tileBank.number:SetTextColor(0.5, 0.5, 0.5) end


    -- requests (the ones this character can craft first)
    workHeader:SetText(guild .. " Sweatshop")
    local allItems = K.GatherRequests()
    -- everybody sees their own requests and the ones they can fulfil; officers and the guild master can switch to all of them
    local showAll = ns.DB.showAllRequests == true and ns.CanModerate()
    local reqItems, mine, can = {}, 0, 0
    for _, item in ipairs(allItems) do
        if item.req and item.req.mine then mine = mine + 1 end
        if item.canFulfill or item.altCanFulfill then can = can + 1 end
        if showAll or (item.req and item.req.mine) or item.canFulfill or item.altCanFulfill then reqItems[#reqItems + 1] = item end
    end
    workSummary:SetText(("%s %s by you, %s that you can fulfill"):format(Gold(mine), Plural(mine, "request", "requests"), Gold(can)))
    local canAll = ns.CanModerate()
    allRequestsCheck:SetShown(canAll)
    allRequestsCheck:SetChecked(ns.DB.showAllRequests == true)
    if canAll then
        local w = workSummary.GetStringWidth and workSummary:GetStringWidth() or 0
        if type(w) ~= "number" or w <= 0 then w = 200 end
        allRequestsCheck:ClearAllPoints()
        allRequestsCheck:SetPoint("LEFT", workSummary, "LEFT", w + 18, 0)
    end
    if #reqItems == 0 then
        if showAll then
            reqItems[1] = { kind = "note", text = "Nobody has requested anything yet." }
        else
            reqItems[1] = { kind = "note", text = "No requests by you, and none that you can fulfill." }
        end
        reqItems[2] = { kind = "note", text = "Use the Sweatshop tab to request an item." }
    end
    dashList:Render(reqItems, true)
end

function ns.UI.RefreshHome()
    if home:IsShown() then RefreshHome() end
end

-- the dashboard always starts with the first raid to come
function ns.UI.ResetEventsCycle() eventIndex = 1 end

home:SetScript("OnShow", function()
    eventIndex = 1
    ns.RequestRoster()
    RefreshHome()
end)

-- keep "Now" fresh while the page is open
home:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t >= 30 then
        self.t = 0
        ns.RequestRoster()
    end
end)
