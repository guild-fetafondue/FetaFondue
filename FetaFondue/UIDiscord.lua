---@class ns
local ns = select(2, ...)
local K = ns.K
local NewWindow, CreateScrollList, Gray = K.NewWindow, K.CreateScrollList, K.Gray
local R = ns.Raids

---------------------------------------------------------------------------
-- Discord names: the sign-ups of a Raid-Helper event carry Discord names. Officers (and the guild master) match a
-- Discord name to the guild character it belongs to: pick the name on the left, then the character on the right.
-- The match is shared with everybody. A name that is the name of exactly one guild character is matched by itself.
---------------------------------------------------------------------------
local win = NewWindow("FetaFondueDiscordNames", 660, 530)
win:SetFrameStrata("FULLSCREEN_DIALOG")
win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
win:SetMovable(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:SetTitle("Link names")

local selected = nil        -- the key of the Discord name picked on the left

local function NewBox(x, y, w, h)
    local box = CreateFrame("Frame", nil, win, "BackdropTemplate")
    box:SetBackdrop(K.BOX_BACKDROP)
    box:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    box:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    box:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
    box:SetSize(w, h)
    return box
end

---------------------------------------------------------------------------
-- left: the Discord names
---------------------------------------------------------------------------
local leftLabel = win:Text("GameFontNormal", 20, -50, 280)
leftLabel:SetText("Discord names")
local leftBox = NewBox(20, -72, 300, 380)

local function RenderName(row, item)
    if item.note then
        row:EnableMouse(false)
        row.text:SetFontObject("GameFontDisable")
        row.text:SetText(item.note)
        row.onClick = nil
        if row.sel then row.sel:Hide() end
        return
    end
    if not row.sel then
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.18)
    end
    row:EnableMouse(true)
    row.text:SetFontObject("GameFontHighlight")
    local right
    if item.entry then
        local shown = {}
        for i, e in ipairs(item.entries) do
            if i > 3 then shown[#shown + 1] = Gray(("+%d"):format(#item.entries - 3)) break end
            shown[#shown + 1] = K.ClassColored(ns.DisplayName(e.name or "?"), e.class)
        end
        right = table.concat(shown, ", ") .. (item.how == "auto" and (" " .. Gray("(automatic)")) or "")
    elseif item.suggest then
        right = "|cffff9a3cnot matched|r " .. Gray("(has alts: pick them)")
    else
        right = "|cffff9a3cnot matched|r"
    end
    local classes = {}
    for _, token in ipairs(item.classes or {}) do classes[#classes + 1] = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or (token:sub(1, 1) .. token:sub(2):lower()) end
    row.text:SetText(("%s%s  >  %s"):format(item.name, #classes > 0 and ("  " .. Gray(table.concat(classes, ", "))) or "", right))
    row.sel:SetShown(selected == item.key)
    row.onClick = function()
        selected = item.key
        ns.UI.RefreshDiscordNames()
    end
end
local nameList = CreateScrollList(leftBox, 300 - 8 - 28, 380 - 16, 24, RenderName)
nameList.frame:SetPoint("TOPLEFT", leftBox, "TOPLEFT", 6, -8)

---------------------------------------------------------------------------
-- right: the guild characters
---------------------------------------------------------------------------
local rightLabel = win:Text("GameFontNormal", 340, -50, 300)
local search = K.NewEditBox("FetaFondueDiscordSearch", win)
search:SetSize(250, 22)
search:SetPoint("TOPLEFT", win, "TOPLEFT", 340, -72)
search:SetMaxLetters(30)
local clear = K.NewButton(win, "x")
clear:SetSize(24, 22)
clear:SetPoint("LEFT", search, "RIGHT", 6, 0)
local rightBox = NewBox(340, -102, 300, 350)

local function KnownItem(key)
    for _, n in ipairs(R.KnownNames(ns.UI.PendingSignups and ns.UI.PendingSignups() or nil)) do
        if n.key == key then return n end
    end
    return nil
end

local function Candidates()
    local roster = ns.GetRoster()
    local words = {}
    for w in (search:GetText() or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    local items = {}
    for _, e in ipairs(roster.list) do
        if e.guid then
            local lname = (e.name or ""):lower()
            local ok = true
            for _, w in ipairs(words) do if not lname:find(w, 1, true) then ok = false end end
            if ok then items[#items + 1] = { entry = e, lname = lname } end
        end
    end
    table.sort(items, function(a, b)
        if a.entry.online ~= b.entry.online then return a.entry.online end
        return a.lname < b.lname
    end)
    return items
end

local function RenderCharacter(row, item)
    if item.note then
        row:EnableMouse(false)
        row.text:SetFontObject("GameFontDisable")
        row.text:SetText(item.note)
        row.onClick = nil
        return
    end
    local e = item.entry
    row:EnableMouse(true)
    row.text:SetFontObject("GameFontHighlight")
    row.text:SetText(("%s%s  %s  %s"):format(item.linked and "|cff40ff40+|r " or (item.related and "|cffff9a3c*|r " or "    "), K.ClassColored(ns.DisplayName(e.name), e.class),
        Gray("Lv " .. tostring(e.level or "?")), e.online and "|cff40ff40online|r" or Gray("offline")))
    row.onClick = function()
        local known = selected and KnownItem(selected)
        if not known then return end
        -- a click adds the character to the Discord name, or takes it off again
        local changed
        if item.linked then
            changed = R.RemoveLink(known.name, e.guid, ns.DisplayName(ns.me))
        else
            changed = R.AddLink(known.name, e.guid, ns.DisplayName(e.name), ns.DisplayName(ns.me))
        end
        if changed then ns.UI.RefreshDiscordNames() end
    end
end
local charList = CreateScrollList(rightBox, 300 - 8 - 28, 350 - 16, 22, RenderCharacter)
charList.frame:SetPoint("TOPLEFT", rightBox, "TOPLEFT", 6, -8)

local removeButton = K.NewButton(win, "Remove all matches")
removeButton:SetSize(160, 26)
removeButton:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -462)
local closeButton = K.NewButton(win, "Close")
closeButton:SetSize(110, 26)
closeButton:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -20, 16)
closeButton:SetScript("OnClick", function() win:Hide() end)
local status = win:Text("GameFontDisableSmall", 20, -496, 480)

function ns.UI.RefreshDiscordNames()
    if not win:IsShown() then return end
    local names = R.KnownNames(ns.UI.PendingSignups and ns.UI.PendingSignups() or nil)
    local items = {}
    for _, n in ipairs(names) do items[#items + 1] = n end
    if #items == 0 then items = { { note = "No sign-ups yet. Add a raid first." } } end
    nameList:Render(items, true)
    local chosen
    for _, n in ipairs(names) do if n.key == selected then chosen = n end end
    if not chosen then selected = nil end
    rightLabel:SetText(chosen and ("Characters of %s"):format(chosen.name) or "Pick a Discord name first")
    local cands = Candidates()
    local linked, related = {}, {}
    if chosen then
        for _, l in ipairs(R.Links(chosen.name)) do linked[l.guid] = true end
        related = R.RelatedToName(chosen.name)
    end
    for _, cand in ipairs(cands) do
        cand.linked = linked[cand.entry.guid] == true
        cand.related = not cand.linked and related[cand.entry.guid] ~= nil
    end
    -- the characters of this Discord name first, then the related ones
    table.sort(cands, function(a, b)
        if a.linked ~= b.linked then return a.linked end
        if a.related ~= b.related then return a.related end
        if a.entry.online ~= b.entry.online then return a.entry.online end
        return a.lname < b.lname
    end)

    if #cands == 0 then cands = { { note = "Nobody matches." } } end
    charList:Render(cands, true)
    removeButton:SetEnabled(chosen ~= nil and chosen.how == "mapped")
    local open = 0
    for _, n in ipairs(names) do if not n.entry then open = open + 1 end end
    status:SetText(open == 0 and Gray("Every Discord name is matched to a character.") or ("|cffff9a3c" .. open .. (open == 1 and " name is" or " names are") .. " not matched yet.|r"))
end

removeButton:SetScript("OnClick", function()
    if not selected then return end
    local known = KnownItem(selected)
    if known and known.how == "mapped" then R.ClearLinks(known.name, ns.DisplayName(ns.me)) end
    ns.UI.RefreshDiscordNames()
end)
search:SetScript("OnTextChanged", function() if win:IsShown() then ns.UI.RefreshDiscordNames() end end)
search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
clear:SetScript("OnClick", function() search:SetText("") search:ClearFocus() end)

function ns.UI.OpenDiscordNames()
    if not ns.CanModerate() then return end
    win:Show()
    ns.UI.RefreshDiscordNames()
end

K.RegisterCloser(function() win:Hide() end)
