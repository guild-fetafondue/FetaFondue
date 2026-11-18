---@class ns
local ns = select(2, ...)
local K = ns.K
local Gray, BOX_BACKDROP = K.Gray, K.BOX_BACKDROP

---------------------------------------------------------------------------
-- Management: only shown to officers and the guild master.
--   Notes:      several notes shared between all officers who use the addon (one big note, a list of notes on the right)
--   Shitlist:   characters the guild warns about
--   Scheduling: the raid calendar
---------------------------------------------------------------------------
local panel = K.managementPanel

local header = panel:Text("GameFontNormalLarge", 0, -4, 500)
header:SetText("Management")

---------------------------------------------------------------------------
-- Invite to guild (top right, on every page of Management). Opens a small window with the name of the player you target (or
-- empty to type one). A name on the shitlist shows a warning and cannot be invited from here.
---------------------------------------------------------------------------
local inviteWin = K.NewWindow("FetaFondueGuildInvite", 400, 214)
inviteWin:SetFrameStrata("FULLSCREEN_DIALOG")
inviteWin:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
inviteWin:SetMovable(true)
inviteWin:RegisterForDrag("LeftButton")
inviteWin:SetScript("OnDragStart", inviteWin.StartMoving)
inviteWin:SetScript("OnDragStop", inviteWin.StopMovingOrSizing)
inviteWin:SetTitle("Invite to guild")
local inviteLabel = inviteWin:Text("GameFontNormal", 20, -46, 360)
inviteLabel:SetText("Character name")
local inviteBox = K.NewEditBox("FetaFondueGuildInviteName", inviteWin)
inviteBox:SetSize(360, 26)
inviteBox:SetPoint("TOPLEFT", inviteWin, "TOPLEFT", 20, -68)
inviteBox:SetMaxLetters(40)
local inviteWarn = inviteWin:Text("GameFontHighlight", 20, -104, 360)
inviteWarn:SetWordWrap(true)
inviteWarn:SetJustifyV("TOP")
local inviteGo = K.NewButton(inviteWin, "Invite")
inviteGo:SetSize(110, 26)
inviteGo:SetPoint("BOTTOMRIGHT", inviteWin, "BOTTOM", -6, 14)
local inviteCancel = K.NewButton(inviteWin, "Cancel")
inviteCancel:SetSize(110, 26)
inviteCancel:SetPoint("BOTTOMLEFT", inviteWin, "BOTTOM", 6, 14)

-- the name of the player in the target (a first and a last name the game keeps apart are joined by a space)
function ns.TargetName()
    local name
    pcall(function()
        if UnitExists("target") and UnitIsPlayer("target") then
            local n, realm = UnitName("target")
            if n and realm and realm ~= "" then n = n .. " " .. realm end
            name = n
        end
    end)
    return name
end

local function CanInviteNow() return ns.CanInviteToGuild() end

-- what the window shows for the typed name
function ns.UI.RefreshGuildInvite()
    local name = (inviteBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local listed = name ~= "" and ns.Blacklist.Find(name) or nil
    if listed then
        inviteWarn:SetText("|cffff5050" .. listed.name .. " is on the Shitlist and cannot be invited from here.|r\n|cffffd100Reason:|r " .. (listed.reason or ""))
    elseif not CanInviteNow() then
        inviteWarn:SetText("|cffff5050Your guild rank cannot invite.|r")
    else
        inviteWarn:SetText("")
    end
    inviteGo:SetEnabled(name ~= "" and not listed and CanInviteNow())
end
function ns.UI.OpenGuildInvite()
    inviteBox:SetText(ns.TargetName() or "")
    inviteWin:Show()
    ns.UI.RefreshGuildInvite()
    inviteBox:SetFocus()
end
inviteBox:SetScript("OnTextChanged", function() ns.UI.RefreshGuildInvite() end)
inviteBox:SetScript("OnEscapePressed", function() inviteWin:Hide() end)
inviteBox:SetScript("OnEnterPressed", function() if inviteGo:IsEnabled() then inviteGo:Click() end end)
inviteCancel:SetScript("OnClick", function() inviteWin:Hide() end)
inviteGo:SetScript("OnClick", function()
    local name = (inviteBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or ns.Blacklist.Find(name) or not CanInviteNow() then return end      -- (checked again: never invite a listed name)
    pcall(function()
        if C_GuildInfo and C_GuildInfo.Invite then C_GuildInfo.Invite(name) elseif GuildInvite then GuildInvite(name) end
    end)
    ns.Print("Guild invite sent to " .. name .. ".")
    inviteWin:Hide()
end)
local function NewBox(parent, x, y, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetBackdrop(BOX_BACKDROP)
    box:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    box:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(w, h)
    return box
end

-- pages under small tabs: the notes, the shitlist and the scheduling
local page = K.NewPanel("FetaFondueNotesPage", panel, 800, 590)
page:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
page:Show()
local blPage = K.NewPanel("FetaFondueBlacklistPage", panel, 800, 590)
blPage:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
blPage:Hide()
local schedPage = K.NewPanel("FetaFondueSchedulingPage", panel, 800, 590)
schedPage:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
schedPage:Hide()

---------------------------------------------------------------------------
-- Notes: one big note on the left; on the right the list of notes (click one to open it). The note "Important!" is always
-- there and always the one that opens: it cannot be renamed or deleted. Everything is saved by itself a moment after the
-- typing stops and shared with the other officers.
---------------------------------------------------------------------------
local O = ns.Officer
local openID = O.DEFAULT_ID
local dirty, conflictFrom, loading, saveToken = false, nil, false, 0

local titleBox = K.NewEditBox("FetaFondueNoteTitle", page)
titleBox:SetSize(590, 26)
titleBox:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -66)
titleBox:SetMaxLetters(O.MAX_TITLE)
titleBox:SetFontObject("GameFontNormal")
titleBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
local protectedHint = titleBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
protectedHint:SetPoint("RIGHT", titleBox, "RIGHT", -8, 0)
protectedHint:SetText("protected: it cannot be renamed or deleted")

local noteBox = NewBox(page, 0, -98, 590, 440)
local scroll = CreateFrame("ScrollFrame", "FetaFondueNoteScroll", noteBox)
scroll:SetPoint("TOPLEFT", noteBox, "TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", noteBox, "BOTTOMRIGHT", -20, 8)
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(self, delta)
    local cur, max = tonumber(self:GetVerticalScroll()) or 0, tonumber(self:GetVerticalScrollRange()) or 0
    self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 36)))
end)
-- a scroll bar on the right of the note (it appears when the text is longer than the box)
K.AttachScrollbar(scroll, noteBox, 424, -7, -8)
local NOTE_MIN_H = 424
local note = CreateFrame("EditBox", "FetaFondueNote", scroll)
note:SetMultiLine(true)
note:SetAutoFocus(false)
note:SetFontObject("ChatFontNormal")
-- a multi-line box in a scroll frame has no height of its own: without one there is nothing to click on
note:SetSize(546, NOTE_MIN_H)
note:SetMaxLetters(O.MAX_TEXT)
note:EnableMouse(true)
scroll:SetScrollChild(note)
note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Clicking in the empty part below the text (or around it) puts the cursor at the end of the text and gives the note the keyboard
-- (the arrows then move in it, not in another box that still had the focus). Clicks on the text itself are the box's own.
local function FocusNoteAtEnd()
    titleBox:ClearFocus()
    note:SetFocus()
    note:SetCursorPosition(#(note:GetText() or ""))
end
scroll:EnableMouse(true)
scroll:SetScript("OnMouseDown", FocusNoteAtEnd)
noteBox:EnableMouse(true)
noteBox:SetScript("OnMouseDown", FocusNoteAtEnd)

-- the box grows with the text, so the scroll frame can scroll
local function FitNote()
    local text = note:GetText() or ""
    local lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end
    lines = lines + math.floor(#text / 76)
    note:SetHeight(math.max(NOTE_MIN_H, lines * 14 + 12))
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
end

-- keep the line being typed in view
note:SetScript("OnCursorChanged", function(self, x, y, w, h)
    y, h = tonumber(y), tonumber(h)
    if not (y and h) then return end
    local cur, view = tonumber(scroll:GetVerticalScroll()) or 0, tonumber(scroll:GetHeight()) or NOTE_MIN_H
    local top = -y
    if top < cur then scroll:SetVerticalScroll(top)
    elseif top + h > cur + view then scroll:SetVerticalScroll(top + h - view) end
end)
-- a cursor you can see (and a gold frame while the box has the focus)
K.AttachCaret(note, noteBox)         -- (the title box keeps the game's own cursor)

local status = page:Text("GameFontDisableSmall", 0, -546, 590)

-- the list of notes on the right
local listLabel = page:Text("GameFontNormal", 606, -70, 90)
listLabel:SetText("Notes")
local newButton = K.NewButton(page, "New note")
newButton:SetSize(96, 24)
newButton:SetPoint("TOPLEFT", page, "TOPLEFT", 704, -64)
local listBox = NewBox(page, 606, -98, 194, 400)
local deleteButton = K.NewButton(page, "Delete note")
deleteButton:SetSize(126, 28)
deleteButton:SetPoint("TOPLEFT", page, "TOPLEFT", 606, -506)
local upButton = K.NewButton(page, "")
upButton:SetSize(28, 28)
upButton:SetPoint("TOPLEFT", page, "TOPLEFT", 744, -506)
local downButton = K.NewButton(page, "")
downButton:SetSize(28, 28)
downButton:SetPoint("TOPLEFT", page, "TOPLEFT", 772, -506)
-- (drawn arrows: no font has to contain them)
local function Arrow(button, up)
    for i = 0, 3 do
        local bar = button:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(1, 0.82, 0, 1)
        bar:SetSize(2 + i * 4, 2)
        bar:SetPoint("CENTER", button, "CENTER", 0, (up and 1 or -1) * (5 - i * 3))
        button["arrow" .. i] = bar
    end
end
Arrow(upButton, true)
Arrow(downButton, false)
local sharedHint = page:Text("GameFontDisableSmall", 606, -542, 194)
sharedHint:SetWordWrap(true)
sharedHint:SetText("Shared with all officers who use the addon")

local SelectNote   -- (below)
local RefreshList   -- (below)

local function RenderNoteRow(row, item)
    row.text:SetFontObject(item.protected and "GameFontNormal" or "GameFontHighlight")
    row.text:SetText(item.title)
    row.onClick = function() SelectNote(item.id) end
    row.onRightClick = function()
        if item.protected then return end
        K.OpenMenu(item.title, {
            { text = "Move up", action = function() ns.Officer.Move(item.id, -1) RefreshList() end },
            { text = "Move down", action = function() ns.Officer.Move(item.id, 1) RefreshList() end },
        })
    end
end
-- (the rows run to the end of the box: the scroll bar, when needed, sits on top of their end)
local noteList = K.CreateScrollList(listBox, 194 - 2 - 2, 400 - 16, 26, RenderNoteRow, { stripes = true, insideTrack = true })
noteList.frame:SetPoint("TOPLEFT", listBox, "TOPLEFT", 2, -8)

function RefreshList()
    local items = {}
    for _, n in ipairs(O.List()) do
        items[#items + 1] = { id = n.id, title = n.title, protected = n.id == O.DEFAULT_ID, selected = n.id == openID }
    end
    noteList:Render(items, true)
end

local function Age(at)
    if not at or at == 0 then return "" end
    local secs = math.max(0, ns.Time() - at)
    if secs < 60 then return "just now" end
    if secs < 3600 then return math.floor(secs / 60 + 0.5) .. " minutes ago" end
    if secs < 86400 then return math.floor(secs / 3600 + 0.5) .. " hours ago" end
    return math.floor(secs / 86400 + 0.5) .. " days ago"
end

local function RefreshStatus()
    local n = O.GetNote(openID)
    if conflictFrom then
        status:SetText("|cffffd100" .. conflictFrom .. " changed this note too. Your next save replaces their version.|r")
    elseif dirty then
        status:SetText(Gray("Saving..."))
    elseif n and (n.rev or 0) > 0 then
        status:SetText(("Saved by %s, %s"):format(n.by ~= "" and n.by or "?", Age(n.rev)))
    else
        status:SetText(Gray("Nothing written yet"))
    end
end

-- save what is in the boxes (a moment after the typing stopped, when another note is opened, and when the tab is left)
local function FlushSave()
    if not dirty then return end
    dirty = false
    local n = O.GetNote(openID)
    if n and not n.deleted then
        O.Save(openID, titleBox:GetText(), note:GetText())
        conflictFrom = nil
    end
end
local function ScheduleSave()
    saveToken = saveToken + 1
    local token = saveToken
    ns.After(1.5, function()
        if token == saveToken and dirty then
            FlushSave()
            RefreshStatus()
            RefreshList()
        end
    end)
end

SelectNote = function(id)
    FlushSave()
    titleBox:ClearFocus()           -- (a click on the list does not move the keyboard by itself: no box keeps it by mistake)
    note:ClearFocus()
    local n = O.GetNote(id)
    if not n or n.deleted then n = O.GetNote(O.DEFAULT_ID) end
    openID = n.id
    loading = true
    titleBox:SetText(n.title or "")
    note:SetText(n.text or "")
    loading = false
    dirty, conflictFrom = false, nil
    local protected = n.id == O.DEFAULT_ID
    titleBox:SetEnabled(not protected)
    titleBox:SetAlpha(protected and 0.8 or 1)
    protectedHint:SetShown(protected)
    deleteButton:SetEnabled(not protected)
    upButton:SetEnabled(not protected)
    downButton:SetEnabled(not protected)
    RefreshList()
    RefreshStatus()
end

note:SetScript("OnTextChanged", function(self, user)
    FitNote()
    if user and not loading then
        dirty = true
        RefreshStatus()
        ScheduleSave()
    end
end)
titleBox:SetScript("OnTextChanged", function(self, user)
    if loading or not user then return end
    if openID == O.DEFAULT_ID then            -- the protected note keeps its name
        loading = true
        self:SetText(O.DEFAULT_TITLE)
        loading = false
        return
    end
    dirty = true
    RefreshStatus()
    ScheduleSave()
end)
titleBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    note:SetFocus()
end)

newButton:SetScript("OnClick", function()
    FlushSave()
    local id, why = O.Create("New note")
    if not id then
        status:SetText("|cffffd100" .. (why or "The note could not be made.") .. "|r")
        return
    end
    SelectNote(id)
    titleBox:SetFocus()
    titleBox:HighlightText()
end)

deleteButton:SetScript("OnClick", function()
    local n = O.GetNote(openID)
    if not n or openID == O.DEFAULT_ID then return end
    K.Confirm("Delete note", ('Delete "%s"? This cannot be undone.'):format(n.title), function()
        dirty = false
        O.Delete(n.id)
        SelectNote(O.DEFAULT_ID)
    end)
end)

upButton:SetScript("OnClick", function() if openID and O.Move(openID, -1) then RefreshList() end end)
downButton:SetScript("OnClick", function() if openID and O.Move(openID, 1) then RefreshList() end end)

-- another officer moved a note
function ns.Officer.OnOrder()
    if panel:IsShown() and page:IsShown() then RefreshList() end
end

-- another officer saved or deleted a note
function ns.Officer.OnNote(n)
    if not (panel:IsShown() and page:IsShown()) then return end
    RefreshList()
    if n.id ~= openID then return end
    if n.deleted then
        SelectNote(O.DEFAULT_ID)
    elseif dirty and n.by ~= ns.DisplayName(ns.me) then
        conflictFrom = n.by ~= "" and n.by or "An officer"
        RefreshStatus()
    else
        loading = true
        titleBox:SetText(n.title or "")
        note:SetText(n.text or "")
        loading = false
        dirty, conflictFrom = false, nil
        RefreshStatus()
    end
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- the Shitlist page
---------------------------------------------------------------------------
local B = ns.Blacklist
local blIntro = blPage:Text("GameFontDisableSmall", 0, -66, 800)
blIntro:SetWordWrap(true)
blIntro:SetText("Everybody who uses the addon gets a warning when one of these characters is in their party or raid. The warning shows the date and the reason. Who added an entry is only visible here, to officers.")
local colDate = blPage:Text("GameFontNormalSmall", 12, -98, 130)
colDate:SetText("Added")
local colName = blPage:Text("GameFontNormalSmall", 148, -98, 140)
colName:SetText("Character")
local colBy = blPage:Text("GameFontNormalSmall", 294, -98, 130)
colBy:SetText("Added by")
local colReason = blPage:Text("GameFontNormalSmall", 430, -98, 330)
colReason:SetText("Reason")
local blBox = NewBox(blPage, 0, -116, 800, 408)
local blCount = blPage:Text("GameFontDisableSmall", 0, -566, 300)

local selected = nil     -- normalized name of the selected row

local function RenderBlacklistRow(row, item)
    if not row.cDate then
        row.cDate = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.cDate:SetPoint("LEFT", row, "LEFT", 12, 0)
        row.cDate:SetWidth(130)
        row.cDate:SetJustifyH("LEFT")
        row.cName = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.cName:SetPoint("LEFT", row, "LEFT", 148, 0)
        row.cName:SetWidth(140)
        row.cName:SetJustifyH("LEFT")
        row.cName:SetWordWrap(false)
        row.cBy = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.cBy:SetPoint("LEFT", row, "LEFT", 294, 0)
        row.cBy:SetWidth(130)
        row.cBy:SetJustifyH("LEFT")
        row.cBy:SetWordWrap(false)
        row.cReason = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.cReason:SetPoint("LEFT", row, "LEFT", 430, 0)
        row.cReason:SetWidth(330)
        row.cReason:SetJustifyH("LEFT")
        row.cReason:SetWordWrap(false)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.18)
    end
    row.text:SetText("")
    if item.note then
        row.cDate:SetText("") row.cName:SetText("") row.cBy:SetText("") row.cReason:SetText(Gray(item.note))
        row.sel:Hide()
        row.onClick, row.onEnter = nil, nil
        return
    end
    local e = item.entry
    row.cDate:SetText(Gray(ns.UI.StampText(e.addedAt)))
    row.cName:SetText(e.name)
    row.cBy:SetText(e.by and e.by ~= "" and e.by or Gray("unknown"))
    row.cReason:SetText(e.reason or "")
    row.sel:SetShown(selected == B.Normalize(e.name))
    row.onClick = function()
        selected = B.Normalize(e.name)
        ns.UI.RefreshBlacklist()
    end
    row.onEnter = function(r)
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.name, 1, 1, 1)
        GameTooltip:AddLine("Added " .. ns.UI.StampText(e.addedAt) .. (e.by and e.by ~= "" and (" by " .. e.by) or ""), 0.6, 0.6, 0.6)
        GameTooltip:AddLine(e.reason or "", 1, 0.82, 0, true)
        GameTooltip:Show()
    end
end
local blList = K.CreateScrollList(blBox, 800 - 8 - 28, 408 - 16, 26, RenderBlacklistRow, { stripes = true })
blList.frame:SetPoint("TOPLEFT", blBox, "TOPLEFT", 6, -8)

local addButton = K.NewButton(blPage, "Add")
addButton:SetSize(110, 26)
addButton:SetPoint("TOPLEFT", blPage, "TOPLEFT", 0, -540)
local changeButton = K.NewButton(blPage, "Change reason")
changeButton:SetSize(130, 26)
changeButton:SetPoint("LEFT", addButton, "RIGHT", 8, 0)
local removeButton = K.NewButton(blPage, "Remove")
removeButton:SetSize(150, 26)
removeButton:SetPoint("LEFT", changeButton, "RIGHT", 8, 0)
local previewButton = K.NewButton(blPage, "Preview the warning")
previewButton:SetSize(160, 26)
previewButton:SetPoint("TOPRIGHT", blPage, "TOPRIGHT", 0, -540)

local function SelectedEntry()
    if not selected then return nil end
    for _, e in ipairs(B.List()) do
        if B.Normalize(e.name) == selected then return e end
    end
    selected = nil
    return nil
end

local confirmUntil = 0
local function ResetRemove()
    confirmUntil = 0
    removeButton:SetText("Remove")
end

function ns.UI.RefreshBlacklist()
    local entries = B.List()
    local items = {}
    for _, e in ipairs(entries) do items[#items + 1] = { entry = e } end
    if #items == 0 then items = { { note = "Nobody is on the shitlist." } } end
    blList:Render(items)
    blCount:SetText(#entries == 1 and "1 character on the list" or (#entries .. " characters on the list"))
    local has = SelectedEntry() ~= nil
    changeButton:SetEnabled(has)
    removeButton:SetEnabled(has)
    previewButton:SetEnabled(has)
end
function B.OnChanged() if blPage:IsShown() then ns.UI.RefreshBlacklist() end end

addButton:SetScript("OnClick", function() ns.UI.OpenBlacklistEditor(nil) end)
changeButton:SetScript("OnClick", function()
    local e = SelectedEntry()
    if e then ns.UI.OpenBlacklistEditor(e) end
end)
removeButton:SetScript("OnClick", function()
    local e = SelectedEntry()
    if not e then return end
    if ns.Now() < confirmUntil then
        B.Remove(e.name)
        selected = nil
        ResetRemove()
        ns.UI.RefreshBlacklist()
    else
        confirmUntil = ns.Now() + 4
        removeButton:SetText("Click again to remove")
        ns.After(4.2, function() if ns.Now() >= confirmUntil then ResetRemove() end end)
    end
end)
previewButton:SetScript("OnClick", function()
    local e = SelectedEntry()
    if e then ns.UI.ShowBlacklistWarning({ e }) end
end)

---------------------------------------------------------------------------
-- the Scheduling page: add raids to the raid calendar from the JSON of a Raid-Helper event
---------------------------------------------------------------------------
local R = ns.Raids
local RAID_COLOR = "|cffff9a3c"

local sIntro = schedPage:Text("GameFontDisableSmall", 0, -64, 800)
sIntro:SetWordWrap(true)
sIntro:SetText("Go to an event in Discord, click Web View, then JSON on the opened web page. Copy the JSON string into the box below.")

local jsonBox = NewBox(schedPage, 0, -98, 520, 150)
local jsonScroll = CreateFrame("ScrollFrame", "FetaFondueRaidScroll", jsonBox)
jsonScroll:SetPoint("TOPLEFT", jsonBox, "TOPLEFT", 8, -8)
jsonScroll:SetPoint("BOTTOMRIGHT", jsonBox, "BOTTOMRIGHT", -8, 8)
jsonScroll:EnableMouseWheel(true)
jsonScroll:SetScript("OnMouseWheel", function(self, delta)
    local cur, max = tonumber(self:GetVerticalScroll()) or 0, tonumber(self:GetVerticalScrollRange()) or 0
    self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 36)))
end)
local JSON_MIN_H = 134
local jsonEdit = CreateFrame("EditBox", "FetaFondueRaidJSON", jsonScroll)
jsonEdit:SetMultiLine(true)
jsonEdit:SetAutoFocus(false)
jsonEdit:SetFontObject("ChatFontNormal")
jsonEdit:SetSize(496, JSON_MIN_H)
jsonEdit:SetMaxLetters(0)
jsonEdit:EnableMouse(true)
jsonScroll:SetScrollChild(jsonEdit)
jsonEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
jsonScroll:EnableMouse(true)
jsonScroll:SetScript("OnMouseDown", function() jsonEdit:SetFocus() end)
jsonBox:EnableMouse(true)
jsonBox:SetScript("OnMouseDown", function() jsonEdit:SetFocus() end)
K.AttachCaret(jsonEdit, jsonBox)
local jsonHint = jsonBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
jsonHint:SetPoint("CENTER", jsonBox, "CENTER", 0, 0)
jsonHint:SetWidth(400)
jsonHint:SetText("Click here and paste the event (Ctrl+V)")

local previewBox = NewBox(schedPage, 532, -98, 268, 150)
local preview = previewBox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
preview:SetPoint("TOPLEFT", previewBox, "TOPLEFT", 10, -10)
preview:SetPoint("BOTTOMRIGHT", previewBox, "BOTTOMRIGHT", -10, 10)
preview:SetJustifyH("LEFT")
preview:SetJustifyV("TOP")
preview:SetSpacing(3)

local addRaidButton = K.NewButton(schedPage, "Add to raid calendar")
addRaidButton:SetSize(170, 26)
addRaidButton:SetPoint("TOPLEFT", schedPage, "TOPLEFT", 0, -256)
local clearRaidButton = K.NewButton(schedPage, "Clear")
clearRaidButton:SetSize(80, 26)
clearRaidButton:SetPoint("LEFT", addRaidButton, "RIGHT", 8, 0)
local discordButton = K.NewButton(schedPage, "Link names")
discordButton:SetSize(140, 26)
discordButton:SetPoint("LEFT", clearRaidButton, "RIGHT", 8, 0)
discordButton:SetScript("OnClick", function() ns.UI.OpenDiscordNames() end)
local sStatus = schedPage:Text("GameFontHighlightSmall", 400, -262, 400, "RIGHT")

local parsed = nil          -- the event in the box, when it can be read

-- the Discord names window also lists the names of the event that is in the box
function ns.UI.PendingSignups() return parsed and parsed.signups or nil end

local function FitJSON()
    local text = jsonEdit:GetText() or ""
    local lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end
    lines = lines + math.floor(#text / 70)
    jsonEdit:SetHeight(math.max(JSON_MIN_H, math.min(lines, 400) * 14 + 12))
end

local function ShowPreview()
    local text = jsonEdit:GetText() or ""
    jsonHint:SetShown(text == "")
    parsed = nil
    if text:find("^%s*$") then
        preview:SetText(Gray("The event will be shown here when you have pasted it."))
        addRaidButton:SetEnabled(false)
        return
    end
    local ev, err = R.ParseEvent(text)
    if not ev then
        preview:SetText("|cffff6060That cannot be used:|r " .. tostring(err))
        addRaidButton:SetEnabled(false)
        return
    end
    parsed = ev
    local rec = { signups = ev.signups }
    local lines = {
        RAID_COLOR .. ev.title .. "|r",
        R.WhenText(ev.start) .. "  " .. Gray(R.Relative(ev.start)),
        ev.leader ~= "" and Gray("Led by " .. ev.leader) or nil,
        R.SignedText(rec),
        (R.OthersText(rec) ~= "") and Gray((R.OthersText(rec):gsub("^%l", string.upper))) or nil,
        R.Get(ev.id) and "|cffffd100This raid is already in the calendar: adding it again updates it.|r" or nil,
        (function()
            local open = R.UnmatchedCount(ev.signups)
            return open > 0 and ("|cffff9a3c" .. open .. (open == 1 and " name is" or " names are") .. " not matched to a guild character (see Link names).|r") or nil
        end)(),
    }
    local out = {}
    for i = 1, 7 do if lines[i] then out[#out + 1] = lines[i] end end
    preview:SetText(table.concat(out, "\n"))
    addRaidButton:SetEnabled(true)
end

jsonEdit:SetScript("OnTextChanged", function(self)
    FitJSON()
    ShowPreview()
end)

addRaidButton:SetScript("OnClick", function()
    if not parsed then return end
    local rec, updated = R.Add(parsed, ns.DisplayName(ns.me))
    if rec then
        sStatus:SetText(("|cff66ff66%s \"%s\".|r"):format(updated and "Updated" or "Added", rec.title))
        jsonEdit:SetText("")
        jsonEdit:ClearFocus()
    else
        sStatus:SetText("|cffff6060" .. tostring(updated) .. "|r")
    end
end)
clearRaidButton:SetScript("OnClick", function()
    jsonEdit:SetText("")
    sStatus:SetText("")
end)

-- the list of what has been added
local sListLabel = schedPage:Text("GameFontNormal", 0, -296, 400)
sListLabel:SetText("Raids in the calendar")
local sCols = {
    { "Raid", 12, 150 }, { "Title", 166, 220 }, { "Added", 392, 130 }, { "By", 528, 130 }, { "Signed up", 664, 100 },
}
for _, c in ipairs(sCols) do
    local fs = schedPage:Text("GameFontNormalSmall", c[2], -318, c[3])
    fs:SetText(c[1])
end
local sBox = NewBox(schedPage, 0, -336, 800, 188)
local sCount = schedPage:Text("GameFontDisableSmall", 0, -552, 300)
local selectedRaid = nil

local function PastRaid(rec) return rec.start + 3 * 3600 < ns.Time() end

local function RenderRaidRow(row, item)
    if not row.cols then
        row.cols = {}
        for i, c in ipairs(sCols) do
            local fs = row:CreateFontString(nil, "ARTWORK", i == 2 and "GameFontHighlight" or "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", c[2], 0)
            fs:SetWidth(c[3] - 6)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.cols[i] = fs
        end
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.18)
    end
    row.text:SetText("")
    if item.note then
        for i = 1, #sCols do row.cols[i]:SetText("") end
        row.cols[2]:SetText(Gray(item.note))
        row.sel:Hide()
        row.onClick, row.onEnter = nil, nil
        return
    end
    local rec = item.rec
    local past = PastRaid(rec)
    local function Tone(text) return past and Gray(text) or text end
    row.cols[1]:SetText(Tone(date("%Y-%m-%d %H:%M", rec.start)))
    row.cols[2]:SetText(past and Gray(rec.title) or (RAID_COLOR .. rec.title .. "|r"))
    row.cols[3]:SetText(Gray(ns.UI.StampText(rec.addedAt)))
    row.cols[4]:SetText(rec.by ~= "" and rec.by or Gray("unknown"))
    row.cols[5]:SetText(Tone(tostring(R.Counts(rec).signed)))
    row.sel:SetShown(selectedRaid == rec.id)
    row.onClick = function()
        selectedRaid = rec.id
        ns.UI.RefreshScheduling()
    end
    row.onEnter = function(r) ns.UI.RaidTooltip(r, rec) end
end
local sList = K.CreateScrollList(sBox, 800 - 8 - 28, 188 - 16, 24, RenderRaidRow, { stripes = true })
sList.frame:SetPoint("TOPLEFT", sBox, "TOPLEFT", 6, -8)

local removeRaidButton = K.NewButton(schedPage, "Remove from the calendar")
removeRaidButton:SetSize(190, 26)
removeRaidButton:SetPoint("TOPRIGHT", schedPage, "TOPRIGHT", 0, -548)
local raidConfirmUntil = 0
local function ResetRaidRemove()
    raidConfirmUntil = 0
    removeRaidButton:SetText("Remove from the calendar")
end

function ns.UI.RefreshScheduling()
    if not schedPage:IsShown() then return end
    local list = R.List()
    local items = {}
    for _, rec in ipairs(list) do items[#items + 1] = { rec = rec } end
    if #items == 0 then items = { { note = "No raids have been added yet." } } end
    if selectedRaid and not R.Get(selectedRaid) then selectedRaid = nil end
    sList:Render(items, true)
    sCount:SetText(#list == 1 and "1 raid in the calendar" or (#list .. " raids in the calendar"))
    removeRaidButton:SetEnabled(selectedRaid ~= nil)
end

removeRaidButton:SetScript("OnClick", function()
    if not selectedRaid then return end
    if ns.Now() < raidConfirmUntil then
        local rec = R.Get(selectedRaid)
        if R.Remove(selectedRaid, ns.DisplayName(ns.me)) then
            sStatus:SetText(("Removed \"%s\" from the calendar."):format(rec and rec.title or "?"))
        end
        selectedRaid = nil
        ResetRaidRemove()
        ns.UI.RefreshScheduling()
    else
        raidConfirmUntil = ns.Now() + 4
        removeRaidButton:SetText("Click again to remove")
        ns.After(4.2, function() if ns.Now() >= raidConfirmUntil then ResetRaidRemove() end end)
    end
end)

---------------------------------------------------------------------------
-- the two small tabs on top
---------------------------------------------------------------------------
-- real tabs: each one has its own outline (left, top, right) standing on a thin line; the open tab is lighter and has the
-- gold line below it, on the base line
local tabStrip = K.NewTabStrip(panel, -30)
local chatTab = tabStrip:AddTab(0, "Notes")
local blTab = tabStrip:AddTab(116, "Shitlist")
local schedTab = tabStrip:AddTab(232, "Scheduling")
local currentSub = "notes"

local function ShowSub(id)
    if currentSub == "notes" and id ~= "notes" then FlushSave() end     -- (what was typed is saved before the page is left)
    currentSub = id
    page:SetShown(id == "notes")
    blPage:SetShown(id == "blacklist")
    schedPage:SetShown(id == "scheduling")
    for tab, which in pairs({ [chatTab] = "notes", [blTab] = "blacklist", [schedTab] = "scheduling" }) do
        if which == id then tab:LockHighlight() else tab:UnlockHighlight() end
    end
    if id == "notes" then
        SelectNote(O.DEFAULT_ID)                -- always opens on the protected note
    elseif id == "blacklist" then
        ResetRemove()
        ns.UI.RefreshBlacklist()
    else
        ResetRaidRemove()
        ShowPreview()
        ns.UI.RefreshScheduling()
    end
end
chatTab:SetScript("OnClick", function() ShowSub("notes") end)
blTab:SetScript("OnClick", function() ShowSub("blacklist") end)
schedTab:SetScript("OnClick", function() ShowSub("scheduling") end)

-- the tab was selected
function ns.UI.OnManagementShown()
    ShowSub(currentSub)
end

