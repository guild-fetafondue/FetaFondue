---@class ns
local ns = select(2, ...)
local K = ns.K
local Gold, Gray, Shifted, OpenChatWith, LinkRecipe, ShowRecipeHover, BOX_BACKDROP =
    K.Gold, K.Gray, K.Shifted, K.OpenChatWith, K.LinkRecipe, K.ShowRecipeHover, K.BOX_BACKDROP

---------------------------------------------------------------------------
-- Right-click menu for a guildie: whisper, invite and (with the guild rank for it) guild kick
---------------------------------------------------------------------------
local menuCatcher = CreateFrame("Button", nil, UIParent)
menuCatcher:SetAllPoints(UIParent)
menuCatcher:SetFrameStrata("TOOLTIP")          -- above every window (the raid window too), below the menu itself
menuCatcher:SetFrameLevel(1)
menuCatcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
menuCatcher:Hide()

local menu = CreateFrame("Frame", "FetaFondueMemberMenu", UIParent, "BackdropTemplate")
menu:SetFrameStrata("TOOLTIP")
menu:SetFrameLevel(20)
menu:SetBackdrop(BOX_BACKDROP)
menu:SetBackdropColor(0.07, 0.07, 0.075, 0.98)
menu:SetBackdropBorderColor(0.3, 0.3, 0.33, 1)
menu:Hide()
tinsert(UISpecialFrames, "FetaFondueMemberMenu")

local menuTitle = menu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
menuTitle:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, -10)
local menuButtons = {}

local function CloseMenu()
    menu:Hide()
    menuCatcher:Hide()
end
menuCatcher:SetScript("OnClick", CloseMenu)
menu:SetScript("OnHide", function() menuCatcher:Hide() end)

local function GetMenuButton(i)
    local b = menuButtons[i]
    if not b then
        b = CreateFrame("Button", nil, menu)
        b:SetHeight(20)
        b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 0.82, 0, 0.2)
        b:SetScript("OnClick", function(self)
            local action = self.action
            CloseMenu()
            if action then action() end
        end)
        menuButtons[i] = b
    end
    return b
end

local function SendTell(name)
    if ChatFrame_SendTell then
        ChatFrame_SendTell(name)
    elseif ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(name)
    else
        OpenChatWith("/w " .. name .. " ")
    end
end

local function InviteToGroup(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end

-- Addons are not allowed to remove guildies themselves, so "Guild kick" opens the chat box with the
-- command typed in: you only have to press Enter.
local function OpenMenu(titleText, entries)
    entries[#entries + 1] = { text = "Cancel" }
    GameTooltip:Hide()
    menuTitle:SetText(titleText)
    for i, e in ipairs(entries) do
        local b = GetMenuButton(i)
        b.text:SetText(e.text)
        b.action = e.action
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -(32 + (i - 1) * 20))
        b:SetWidth(200)
        b:Show()
    end
    for i = #entries + 1, #menuButtons do menuButtons[i]:Hide() end
    menu:SetSize(216, 32 + #entries * 20 + 10)

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    menuCatcher:Show()
    menu:Show()
end

-- main / alt settings, for officers (and the guild master): who is an alt of whom
local function AltEntries(m)
    local entries = {}
    if not (m.guid and ns.CanModerate()) then return entries end
    entries[#entries + 1] = { text = "|cff8fc7ffSet as alt of...|r", action = function() ns.UI.OpenAltPicker(m) end }
    local links = ns.GetAltLinks() or {}
    local link = links[m.guid]
    if m.altOf then
        entries[#entries + 1] = { text = "|cff8fc7ffThis is a main, not an alt|r", action = function() ns.Sync.SetAltLink(m.guid, "-") end }
    end
    if link and link.main ~= "x" then
        entries[#entries + 1] = { text = "|cff8fc7ffAlt setting: back to automatic|r", action = function() ns.Sync.SetAltLink(m.guid, nil) end }
    end
    return entries
end

local function OpenMemberMenu(m, classColoredName)
    if not m.fullName then return end
    local entries = {}
    if m.mine then
        -- nothing to whisper to yourself; officers can still set their own alt / main
        entries = AltEntries(m)
        if #entries == 0 then return end
        OpenMenu(classColoredName, entries)
        return
    end
    entries = {
        { text = "Inspect", action = function() ns.UI.OpenInspect(m) end },
        { text = "Whisper", action = function() SendTell(m.fullName) end },
        { text = "Invite to group", action = function() InviteToGroup(m.fullName) end },
    }
    for _, e in ipairs(AltEntries(m)) do entries[#entries + 1] = e end
    if CanGuildRemove and CanGuildRemove() then
        entries[#entries + 1] = { text = "|cffff5050Guild kick|r", action = function() OpenChatWith("/gkick " .. m.fullName) end }
    end
    OpenMenu(classColoredName, entries)
end

local function CanDeleteRequest(r) return r.mine or ns.CanModerate() end

local function OpenRequestMenu(r)
    if not CanDeleteRequest(r) then return end
    local entries = {
        { text = r.mine and "Delete request" or "|cffff5050Delete request (officer)|r",
          action = function() ns.DeleteGuildRequest(r) end },
    }
    OpenMenu(("%s × %s"):format(r.qty, r.name), entries)
end

K.OpenMenu, K.CloseMenu, K.OpenMemberMenu = OpenMenu, CloseMenu, OpenMemberMenu
K.InviteToGroup = InviteToGroup
K.OpenRequestMenu, K.CanDeleteRequest = OpenRequestMenu, CanDeleteRequest
K.RegisterCloser(CloseMenu)

---------------------------------------------------------------------------
-- Requests as list rows (Home and Sweatshop show the same rows)
---------------------------------------------------------------------------

-- All open requests as list items, the ones this character can craft first.
-- Returns items, how many requests there are, how many this character can craft.
function K.GatherRequests()
    local requests = ns.GetGuildRequests()
    local ids = {}
    for _, r in ipairs(requests) do ids[#ids + 1] = r.id end
    local reqs = ns.Professions.RecipeRequirements(ids)
    local can, altCan, rest = {}, {}, {}
    for _, r in ipairs(requests) do
        local prof = reqs[r.id]
        local item = { kind = "request", req = r, prof = prof }
        -- only requests of others, for a recipe this character knows AND has the skill for
        item.canFulfill = (not r.mine) and ns.Professions.CanCraft(r.id) or false
        -- (a character of mine can do it, or one of my known alts: shown by default too, but only this character's own ones glow)
        item.altCanFulfill = (not r.mine) and not item.canFulfill and ns.Professions.AltsCanCraft(r.id) or false
        if item.canFulfill then can[#can + 1] = item elseif item.altCanFulfill then altCan[#altCan + 1] = item else rest[#rest + 1] = item end
        -- the skill is not known yet: ask the guild (somebody with Profession Master may answer)
        if prof and prof.name and not prof.skill and ns.Sync then ns.Sync.RequestRecipeInfo(r.id) end
    end
    local items = {}
    for _, item in ipairs(can) do items[#items + 1] = item end
    for _, item in ipairs(altCan) do items[#items + 1] = item end
    for _, item in ipairs(rest) do items[#items + 1] = item end
    return items, #requests, #can, #altCan
end

-- a soft pulsing glow behind requests the player can craft
local function PulseGlow(self, elapsed)
    self.glowT = (self.glowT or 0) + elapsed
    self.glow:SetAlpha(0.12 + 0.16 * (0.5 + 0.5 * math.sin(self.glowT * 3)))
end

-- opts.onOpen(request, item): left click (a fulfillable or any request)
-- opts.withDelete: little X on my own requests
function K.RequestRowRenderer(opts)
    opts = opts or {}
    return function(row, item)
        if not row.glow then
            row.glow = row:CreateTexture(nil, "BACKGROUND")
            row.glow:SetAllPoints()
            row.glow:SetColorTexture(1, 0.82, 0.1, 1)
            row.glowBar = row:CreateTexture(nil, "ARTWORK")
            row.glowBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.glowBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.glowBar:SetWidth(3)
            row.glowBar:SetColorTexture(1, 0.85, 0.2, 1)
        end
        row.glow:Hide()
        row.glowBar:Hide()
        row:SetScript("OnUpdate", nil)

        if item.kind == "note" then
            row:EnableMouse(false)
            row.text:SetFontObject("GameFontDisable")
            row.text:SetText(item.text)
            return
        end
        local r, prof = item.req, item.prof
        if item.canFulfill then
            row.glow:Show()
            row.glow:SetAlpha(0.2)
            row.glowBar:Show()
            row:SetScript("OnUpdate", PulseGlow)
        end
        row:EnableMouse(true)
        row.text:SetFontObject("GameFontHighlight")
        local who = r.mine and "you" or r.who

        -- "Leatherworking 150": the profession and the skill it needs (when known)
        local profText, profHint = "", ""
        if prof and prof.name then
            local skill = prof.skill and (" " .. prof.skill) or ""
            profText = "  |cff8fc7ff" .. prof.name .. skill .. "|r"
            profHint = prof.name .. (prof.skill and (", skill " .. prof.skill) or "") .. ". "
        end
        local ready = item.canFulfill and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t " or ""
        row.text:SetText(("%s%s × %s%s  %s"):format(ready, Gold(r.qty), r.name, profText, Gray("- " .. who)))

        if opts.withDelete then
            if not row.remove then
                local x = CreateFrame("Button", nil, row)
                x:SetSize(16, 16)
                x:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                x.t = x:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                x.t:SetPoint("CENTER", x, "CENTER", 0, 0)
                x.t:SetText("x")
                x.t:SetTextColor(1, 0.3, 0.3)
                x.hl = x:CreateTexture(nil, "HIGHLIGHT")
                x.hl:SetAllPoints()
                x.hl:SetColorTexture(1, 0.3, 0.3, 0.25)
                x:SetScript("OnClick", function(self) if self.request then ns.DeleteGuildRequest(self.request) end end)
                x:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Remove this request", 1, 1, 1)
                    GameTooltip:Show()
                end)
                x:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row.remove = x
            end
            if r.mine then
                row.remove.request = r
                row.remove:Show()
                row.text:SetPoint("RIGHT", row, "RIGHT", -24, 0)
            end
        end

        row.onClick = function()
            if Shifted() then
                LinkRecipe(r.id, r.name, r.qty)
            elseif item.canFulfill and not (IsControlKeyDown and IsControlKeyDown()) then
                -- a request I can craft: the profession window opens on it with the amount in, I press Create
                ns.Professions.OpenToCraft(r.id, r.qty, r.name)
            elseif opts.onOpen then
                opts.onOpen(r, item)
            end
        end
        row.onRightClick = function() OpenRequestMenu(r) end
        row.onEnter = function(rw)
            local hint = {}
            if item.canFulfill then hint[#hint + 1] = "|cff40ff40You can craft this!|r" end
            if prof and prof.name then hint[#hint + 1] = prof.name .. (prof.skill and (", skill " .. prof.skill) or "") end
            hint[#hint + 1] = "Requested by " .. who
            if item.canFulfill then
                hint[#hint + 1] = K.Key("Click") .. ": open it in your profession"
                hint[#hint + 1] = K.Key("Ctrl-click") .. ": show it in the Sweatshop"
            else
                hint[#hint + 1] = K.Key("Click") .. ": show it in the Sweatshop"
            end
            hint[#hint + 1] = K.Key("Shift-click") .. ": link in chat"
            if CanDeleteRequest(r) then hint[#hint + 1] = K.Key("Right-click") .. ": delete" end
            ShowRecipeHover(rw, r.id, r.name, hint, r.qty)
        end
    end
end
