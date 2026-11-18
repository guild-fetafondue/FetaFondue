---@class ns
local ns = select(2, ...)
local K = ns.K
local NewWindow, CreateScrollList, Gray = K.NewWindow, K.CreateScrollList, K.Gray

---------------------------------------------------------------------------
-- "Set as alt of...": officers (and the guild master) pick the main of a character from the guild roster.
-- The setting is shared with the whole guild (only officers' settings are accepted) and wins over the
-- automatic guess.
---------------------------------------------------------------------------
local win = NewWindow("FetaFondueAltPicker", 380, 500)
win:SetFrameStrata("FULLSCREEN_DIALOG")
win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
win:SetMovable(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:SetTitle("Set as alt of")

local target = nil   -- the member being edited

local heading = win:Text("GameFontHighlight", 20, -46, 340)
local hint = win:Text("GameFontDisableSmall", 20, -68, 340)
hint:SetText("Pick the main character. Everybody in the guild will see it.")

local search = K.NewEditBox("FetaFondueAltSearch", win)
search:SetSize(300, 22)
search:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -92)
search:SetMaxLetters(30)
local clear = K.NewButton(win, "x")
clear:SetSize(24, 22)
clear:SetPoint("LEFT", search, "RIGHT", 6, 0)

local box = CreateFrame("Frame", nil, win, "BackdropTemplate")
box:SetBackdrop(K.BOX_BACKDROP)
box:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
box:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
box:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -124)
box:SetSize(340, 316)

local function Candidates()
    local roster = ns.GetRoster()
    local words = {}
    for w in (search:GetText() or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    local items = {}
    for _, e in ipairs(roster.list) do
        if e.guid and (not target or e.guid ~= target.guid) then
            local lname = (e.name or ""):lower()
            local ok = true
            for _, w in ipairs(words) do if not lname:find(w, 1, true) then ok = false end end
            if ok then items[#items + 1] = { kind = "who", entry = e, lname = lname } end
        end
    end
    table.sort(items, function(a, b)
        if a.entry.online ~= b.entry.online then return a.entry.online end
        return a.lname < b.lname
    end)
    return items
end

local function RenderRow(row, item)
    if item.kind == "note" then
        row:EnableMouse(false)
        row.text:SetFontObject("GameFontDisable")
        row.text:SetText(item.text)
        return
    end
    local e = item.entry
    row:EnableMouse(true)
    row.text:SetFontObject("GameFontHighlight")
    row.text:SetText(("%s  %s  %s"):format(K.ClassColored(ns.DisplayName(e.name), e.class), Gray("Lv " .. tostring(e.level or "?")),
        e.online and "|cff40ff40online|r" or Gray("offline")))
    row.onClick = function()
        if target and ns.Sync.SetAltLink(target.guid, e.guid) then
            ns.Print(("%s is now an alt of %s."):format(target.name or "?", ns.DisplayName(e.name)))
            win:Hide()
            ns.RefreshUI()
        end
    end
end
local list = CreateScrollList(box, 340 - 8 - 28, 316 - 16, 22, RenderRow)
list.frame:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -8)

local function Refresh()
    local items = Candidates()
    if #items == 0 then items = { { kind = "note", text = "Nobody matches." } } end
    list:Render(items)
end

search:SetScript("OnTextChanged", function() if win:IsShown() then Refresh() end end)
search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
clear:SetScript("OnClick", function() search:SetText("") search:ClearFocus() end)

local cancel = K.NewButton(win, "Cancel")
cancel:SetSize(110, 26)
cancel:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -20, 16)
cancel:SetScript("OnClick", function() win:Hide() end)

-- m: the member being edited ({ guid, name, ... } from the online list)
function ns.UI.OpenAltPicker(m)
    if not (m and m.guid and ns.CanModerate()) then return end
    target = m
    heading:SetText(("%s is an alt of:"):format(m.name or "?"))
    search:SetText("")
    win:Show()
    Refresh()
end

K.RegisterCloser(function() win:Hide() end)
