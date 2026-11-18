---@class ns
local ns = select(2, ...)
local K = ns.K
local NewWindow, Gray = K.NewWindow, K.Gray

---------------------------------------------------------------------------
-- The warning: a small window in the middle of the screen when somebody on the shitlist is in your party or
-- raid. It shows when they were added and the reason. (Not who added them. It is not opened during combat or
-- loading screens: Blacklist.lua waits for a quiet moment.)
---------------------------------------------------------------------------
local BLOCK_H = 112
local MAX_SHOWN = 3

local warn = NewWindow("FetaFondueBlacklistWarning", 440, 200)
warn:SetFrameStrata("FULLSCREEN_DIALOG")
warn:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
warn:SetMovable(true)
warn:RegisterForDrag("LeftButton")
warn:SetScript("OnDragStart", warn.StartMoving)
warn:SetScript("OnDragStop", warn.StopMovingOrSizing)
warn:SetTitle("Shitlist warning")
warn.solid:SetColorTexture(0.1, 0.03, 0.03, 1)

local head = warn:Text("GameFontNormalLarge", 20, -44, 400)
local blocks = {}
local function GetBlock(i)
    local b = blocks[i]
    if not b then
        b = {}
        b.name = warn:Text("GameFontNormalLarge", 20, 0, 400)
        b.added = warn:Text("GameFontHighlightSmall", 20, 0, 400)
        b.reason = warn:Text("GameFontHighlight", 20, 0, 400)
        b.reason:SetWordWrap(true)
        b.reason:SetJustifyV("TOP")
        b.line = warn:CreateTexture(nil, "ARTWORK")
        b.line:SetColorTexture(0.35, 0.12, 0.12, 1)
        b.line:SetSize(400, 1)
        blocks[i] = b
    end
    return b
end

local function Stamp(t) return t and t > 0 and date("%Y-%m-%d %H:%M", t) or "unknown" end
ns.UI.StampText = Stamp

local ok = K.NewButton(warn, "OK")
ok:SetSize(110, 26)
ok:SetScript("OnClick", function() warn:Hide() end)

-- list: entries { name, reason, addedAt }
function ns.UI.ShowBlacklistWarning(list, kind)
    if not list or #list == 0 then return end
    if kind == "invite" then
        head:SetText("|cffff5050You invited a shitlisted player to the guild|r")
    elseif kind == "scan" then
        head:SetText("|cffff5050" .. (#list == 1 and "A shitlisted player is in the guild" or "Shitlisted players are in the guild") .. "|r")
    else
        head:SetText("|cffff5050A shitlisted player is in your group|r")
    end
    local n = math.min(#list, MAX_SHOWN)
    local y = -76
    for i = 1, n do
        local e = list[i]
        local b = GetBlock(i)
        for _, region in ipairs({ b.name, b.added, b.reason }) do region:Show() end
        b.name:ClearAllPoints()
        b.name:SetPoint("TOPLEFT", warn, "TOPLEFT", 20, y)
        b.name:SetText("|cffffffff" .. e.name .. "|r")
        b.added:ClearAllPoints()
        b.added:SetPoint("TOPLEFT", warn, "TOPLEFT", 20, y - 24)
        b.added:SetText("Added " .. Stamp(e.addedAt))
        b.reason:ClearAllPoints()
        b.reason:SetPoint("TOPLEFT", warn, "TOPLEFT", 20, y - 42)
        b.reason:SetWidth(400)
        b.reason:SetText("|cffffd100Reason:|r " .. (e.reason or ""))
        b.line:ClearAllPoints()
        b.line:SetPoint("TOPLEFT", warn, "TOPLEFT", 20, y - BLOCK_H + 8)
        b.line:Show()
        y = y - BLOCK_H
    end
    for i = n + 1, #blocks do
        for _, region in ipairs({ blocks[i].name, blocks[i].added, blocks[i].reason }) do region:Hide() end
        blocks[i].line:Hide()
    end
    if #list > n then
        local more = GetBlock(n + 1)
        more.name:Show()
        more.name:ClearAllPoints()
        more.name:SetPoint("TOPLEFT", warn, "TOPLEFT", 20, y)
        more.name:SetText(Gray(("and %d more on the list"):format(#list - n)))
        more.added:Hide() more.reason:Hide() more.line:Hide()
        y = y - 28
    end
    warn:SetSize(440, -y + 48)
    ok:ClearAllPoints()
    ok:SetPoint("BOTTOM", warn, "BOTTOM", 0, 14)
    warn:Show()
end

---------------------------------------------------------------------------
-- Add / change an entry (officers and the guild master)
---------------------------------------------------------------------------
local edit = NewWindow("FetaFondueBlacklistEdit", 480, 262)
edit:SetFrameStrata("FULLSCREEN_DIALOG")
edit:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
edit:SetMovable(true)
edit:RegisterForDrag("LeftButton")
edit:SetScript("OnDragStart", edit.StartMoving)
edit:SetScript("OnDragStop", edit.StopMovingOrSizing)

local nameLabel = edit:Text("GameFontNormal", 24, -48, 300)
nameLabel:SetText("Character name")
local nameBox = K.NewEditBox("FetaFondueBlacklistName", edit)
nameBox:SetSize(430, 24)
nameBox:SetPoint("TOPLEFT", edit, "TOPLEFT", 24, -68)
nameBox:SetMaxLetters(40)

local reasonLabel = edit:Text("GameFontNormal", 24, -108, 300)
reasonLabel:SetText("Reason (everybody in a group with them will see it)")
local reasonBox = K.NewEditBox("FetaFondueBlacklistReason", edit)
reasonBox:SetSize(430, 24)
reasonBox:SetPoint("TOPLEFT", edit, "TOPLEFT", 24, -128)
reasonBox:SetMaxLetters(200)

local errorText = edit:Text("GameFontNormal", 24, -164, 430)
local editing = nil     -- the entry being changed, nil when adding

local save = K.NewButton(edit, "Save")
save:SetSize(110, 26)
save:SetPoint("BOTTOMLEFT", edit, "BOTTOMLEFT", 24, 18)
local cancel = K.NewButton(edit, "Cancel")
cancel:SetSize(110, 26)
cancel:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", -24, 18)
cancel:SetScript("OnClick", function() edit:Hide() end)

local function Save()
    local okay, err
    if editing then
        okay, err = ns.Blacklist.EditReason(editing.name, reasonBox:GetText())
    else
        okay, err = ns.Blacklist.Add(nameBox:GetText(), reasonBox:GetText())
    end
    if okay then
        edit:Hide()
        if ns.UI.RefreshBlacklist then ns.UI.RefreshBlacklist() end
    else
        errorText:SetText("|cffff5050" .. tostring(err or "Could not save.") .. "|r")
    end
end
save:SetScript("OnClick", Save)
nameBox:SetScript("OnEnterPressed", function() reasonBox:SetFocus() end)
reasonBox:SetScript("OnEnterPressed", Save)

-- entry: an existing entry to change (its reason), or nil to add a new one
function ns.UI.OpenBlacklistEditor(entry)
    if not ns.CanModerate() then return end
    editing = entry
    errorText:SetText("")
    if entry then
        edit:SetTitle("Change the reason")
        nameBox:SetText(entry.name)
        nameBox:EnableMouse(false)
        nameBox:SetTextColor(0.6, 0.6, 0.6)
        reasonBox:SetText(entry.reason or "")
    else
        edit:SetTitle("Add to the shitlist")
        nameBox:SetText("")
        nameBox:EnableMouse(true)
        nameBox:SetTextColor(1, 1, 1)
        reasonBox:SetText("")
    end
    edit:Show()
    if entry then reasonBox:SetFocus() else nameBox:SetFocus() end
end

K.RegisterCloser(function() edit:Hide() end)
