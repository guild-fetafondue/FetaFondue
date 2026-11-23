---@class ns
local ns = select(2, ...)
local K = ns.K
local C = ns.Composition
local Gray = K.Gray
local unpack = unpack or table.unpack

---------------------------------------------------------------------------
-- Management > Planner: put the people of my group (and placeholder characters) into raid groups and see what the composition brings.
-- Layout: size buttons and the roles on top, the specialization icons to drag, the people of my group on the left, the groups, and
-- under them the raid buffs, the party buffs and the debuffs (green = covered, yellow = some groups, red = missing).
-- Left button: drag. Right button on a person: assign a specialization. The small x takes somebody out of a group.
---------------------------------------------------------------------------
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local FLAT = "Interface\\Buttons\\WHITE8X8"
local STATUS_COLOR = { ok = { 0.2, 0.85, 0.3 }, partial = { 0.95, 0.75, 0.15 }, missing = { 0.8, 0.22, 0.22 } }
local ROLE_COLOR = { TANK = "ff4a9fff", HEALER = "ff40ff40", DPS = "ffff5050" }
local ROLE_NAME = { TANK = "Tank", HEALER = "Healer", DPS = "DPS" }

local GROUP_W, GROUP_H, GROUP_GAP_X, GROUP_GAP_Y = 156, 130, 4, 6
local GRID_X, GRID_Y = 158, -128
local HEAD_H, SLOT_H = 22, 21

-- "Any Shaman, Restoration Shaman" with every name in the color of its class (for the tooltips)
local function WhoColored(buff)
    local out = {}
    for _, w in ipairs(buff.who) do
        local spec = C.BY_KEY[w]
        if spec then out[#out + 1] = K.ClassColored(spec.name, spec.class)
        else out[#out + 1] = K.ClassColored("Any " .. w:sub(1, 1) .. w:sub(2):lower(), w) end
    end
    return table.concat(out, ", ")
end

local function NewBox(parent, x, y, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetBackdrop(K.BOX_BACKDROP)
    box:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    box:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(w, h)
    return box
end

-- a square picture with a colored border (the color says covered / missing)
local function IconButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:SetColorTexture(0.25, 0.25, 0.28, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetAllPoints()
    b.glow:SetColorTexture(1, 0.82, 0, 0.0)
    return b
end

function ns.UI.BuildComposition(page)
    local slots, groupFrames, partyIcons = {}, {}, {}
    local listFrame
    local Refresh

    ---------------------------------------------------------------------------
    -- highlighting who provides an effect
    ---------------------------------------------------------------------------
    local function Highlight(set)
        for i = 1, 40 do
            local s = slots[i]
            if s then s.hl:SetShown(set ~= nil and set[i] == true) end
        end
    end
    local function SetOf(list)
        local set = {}
        for _, i in ipairs(list or {}) do set[i] = true end
        return set
    end

    ---------------------------------------------------------------------------
    -- dragging (left button): from the list, from the specialization icons, or from a slot
    ---------------------------------------------------------------------------
    local drag = {}                          -- { src, icon, text, x0, y0, active }
    local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ghost:SetSize(170, 22)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetBackdrop(K.BOX_BACKDROP)
    ghost:SetBackdropColor(0.1, 0.1, 0.12, 0.95)
    ghost:SetBackdropBorderColor(1, 0.82, 0, 1)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetSize(16, 16)
    ghost.icon:SetPoint("LEFT", ghost, "LEFT", 4, 0)
    ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ghost.text:SetPoint("LEFT", ghost, "LEFT", 24, 0)
    ghost:Hide()
    local driver = CreateFrame("Frame")

    local function Cursor()
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        if not scale or scale == 0 then scale = 1 end
        return x / scale, y / scale
    end
    local function MouseDown()
        local ok, v = pcall(IsMouseButtonDown, "LeftButton")
        return ok and v == true
    end
    local function Over(frame)
        local ok, v = pcall(function() return frame:IsMouseOver() end)
        return ok and v == true
    end
    local function SlotUnderMouse()
        for i = 1, C.Size() do
            if Over(slots[i]) then return i end
        end
        return nil
    end
    local function ShowDropTarget(target)
        for i = 1, 40 do if slots[i] then slots[i].drop:SetShown(target == i) end end
    end

    local function EndDrag()
        ghost:Hide()
        ShowDropTarget(nil)
        drag = {}
        driver:SetScript("OnUpdate", nil)
    end

    -- the button was let go
    local function Release()
        local d = drag
        if d.active then
            local target = SlotUnderMouse()
            if target then
                C.Drop(d.src, target)
            elseif d.src.kind == "slot" and listFrame and Over(listFrame) then
                C.Remove(d.src.index)                -- dropped back on the list
            end
        end
        EndDrag()
        Refresh()
    end

    local function OnDragUpdate()
        if not MouseDown() then Release() return end
        local x, y = Cursor()
        if not drag.active then
            if math.abs(x - drag.x0) + math.abs(y - drag.y0) < 6 then return end
            drag.active = true
            ghost.icon:SetTexture(drag.icon or QUESTION)
            ghost.text:SetText(drag.text or "")
            ghost:Show()
        end
        ghost:ClearAllPoints()
        ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 12, y - 4)
        ShowDropTarget(SlotUnderMouse())
    end

    local function BeginDrag(src, icon, text)
        local x, y = Cursor()
        drag = { src = src, icon = icon, text = text, x0 = x, y0 = y }
        driver:SetScript("OnUpdate", OnDragUpdate)
    end

    ---------------------------------------------------------------------------
    -- top: sizes, roles, reset
    ---------------------------------------------------------------------------
    local sizeButtons = {}
    for n, x in pairs({ [10] = 0, [20] = 38, [40] = 76 }) do
        local b = K.NewButton(page, tostring(n))
        b:SetSize(34, 22)
        b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -66)
        b:SetScript("OnClick", function() C.SetSize(n) Refresh() end)
        sizeButtons[n] = b
    end
    local rolesText = page:Text("GameFontNormal", 128, -70, 560)
    -- how to fill the groups: to the right of the role count (it moves with the length of that text)
    local dragHint = page:Text("GameFontDisableSmall", 128, -72, 300)
    dragHint:SetText("Drag people from group or add generic specs")
    local resetButton = K.NewButton(page, "Reset")
    resetButton:SetSize(64, 22)
    resetButton:SetPoint("TOPLEFT", page, "TOPLEFT", 730, -66)
    resetButton:SetScript("OnClick", function() C.Reset() Refresh() end)

    ---------------------------------------------------------------------------
    -- the specialization icons (drag them into a group: a placeholder character)
    ---------------------------------------------------------------------------
    local px = 0
    local paletteIcons = {}
    for _, class in ipairs(C.CLASS_ORDER) do
        local specs = C.BY_CLASS[class]
        local w = #specs * 24 + (#specs - 1) * 2 + 6
        local cluster = NewBox(page, px, -94, w, 30)
        for k, spec in ipairs(specs) do
            local b = IconButton(cluster, 24)
            b:SetPoint("TOPLEFT", cluster, "TOPLEFT", 3 + (k - 1) * 26, -3)
            b.icon:SetTexture(spec.icon)
            b.spec = spec
            b:SetScript("OnMouseDown", function(_, button)
                if button == "LeftButton" then BeginDrag({ kind = "spec", spec = spec.key }, spec.icon, K.ClassColored(spec.gen, spec.class)) end
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(K.ClassColored(spec.gen, spec.class), 1, 1, 1)
                GameTooltip:AddLine("|c" .. ROLE_COLOR[spec.role] .. ROLE_NAME[spec.role] .. "|r", 1, 1, 1)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            paletteIcons[#paletteIcons + 1] = b
        end
        px = px + w + 3
    end

    ---------------------------------------------------------------------------
    -- the specialization menu of a person (right-click)
    ---------------------------------------------------------------------------
    local function PersonMenu(m, slotIndex)
        local entries = {}
        for _, spec in ipairs(C.BY_CLASS[m.class] or {}) do
            local mark = (m.spec == spec.key) and "  |cff40ff40(now)|r" or ""
            entries[#entries + 1] = {
                text = ("|T%s:14|t %s%s"):format(spec.icon, spec.name, mark),
                action = function() C.SetSpec(m.key, spec.key) Refresh() end,
            }
        end
        if C.Plan().specs[m.key] then
            entries[#entries + 1] = { text = "Use the detected spec", action = function() C.SetSpec(m.key, nil) Refresh() end }
        end
        if slotIndex then
            entries[#entries + 1] = { text = "Take out of the group", action = function() C.Remove(slotIndex) Refresh() end }
        end
        K.OpenMenu(K.ClassColored(m.name, m.class), entries)
    end

    ---------------------------------------------------------------------------
    -- the people of my group (left)
    ---------------------------------------------------------------------------
    listFrame = NewBox(page, 0, GRID_Y, 150, GROUP_H * 2 + GROUP_GAP_Y)
    local listHeader = listFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    listHeader:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 8, -6)

    local function RenderListRow(row, item)
        if not row.pic then
            row.pic = row:CreateTexture(nil, "ARTWORK")
            row.pic:SetSize(16, 16)
            row.pic:SetPoint("LEFT", row, "LEFT", 4, 0)
            row:SetScript("OnMouseDown", function(self, button)
                local m = self.member
                if button == "LeftButton" and m then
                    BeginDrag({ kind = "player", key = m.key }, (C.Spec(m.spec) or {}).icon or QUESTION, K.ClassColored(m.name, m.class))
                end
            end)
        end
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", 26, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        if item.note then
            row.member = nil
            row.pic:Hide()
            row.text:SetText(Gray(item.note))
            row.onClick, row.onRightClick, row.onEnter = nil, nil, nil
            return
        end
        local m = item.member
        row.member = m
        local spec = C.Spec(m.spec)
        row.pic:Show()
        row.pic:SetTexture(spec and spec.icon or QUESTION)
        row.text:SetText(K.ClassColored(m.name, m.class) .. (spec and "" or Gray("  spec?")))
        row.onRightClick = function() PersonMenu(m) end
        row.onEnter = function(r)
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:SetText(K.ClassColored(m.name, m.class), 1, 1, 1)
            GameTooltip:AddLine(spec and spec.name or "Spec not known: right-click to choose one", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end
    local list = K.CreateScrollList(listFrame, 142, GROUP_H * 2 + GROUP_GAP_Y - 28, 22, RenderListRow, { stripes = true, fitTrack = true })
    list.frame:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 4, -24)

    ---------------------------------------------------------------------------
    -- the groups
    ---------------------------------------------------------------------------
    local function SlotTooltip(self)
        local e = C.Entry(self.index)
        if not e then return end
        local spec = C.Spec(e.spec)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(K.ClassColored(e.name, e.class), 1, 1, 1)
        if spec then
            GameTooltip:AddLine(spec.name, 0.8, 0.8, 0.8)
            GameTooltip:AddLine("|c" .. ROLE_COLOR[spec.role] .. ROLE_NAME[spec.role] .. "|r", 1, 1, 1)
        else
            GameTooltip:AddLine("Spec not known: right-click to choose one", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end

    for g = 1, 8 do
        local col, row = (g - 1) % 4, math.floor((g - 1) / 4)
        local gf = NewBox(page, GRID_X + col * (GROUP_W + GROUP_GAP_X), GRID_Y - row * (GROUP_H + GROUP_GAP_Y), GROUP_W, GROUP_H)
        groupFrames[g] = gf
        gf.title = gf:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        gf.title:SetPoint("TOPLEFT", gf, "TOPLEFT", 6, -6)
        gf.title:SetText("Group " .. g)
        gf.more = gf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        gf.more:SetPoint("TOPRIGHT", gf, "TOPRIGHT", -4, -6)
        partyIcons[g] = {}
        for k = 1, 5 do
            local b = IconButton(gf, 18)
            b:SetPoint("TOPRIGHT", gf, "TOPRIGHT", -4 - (5 - k) * 20 - 0, -2)
            b:Hide()
            partyIcons[g][k] = b
            b:SetScript("OnEnter", function(self)
                local buff = self.buff
                if not buff then return end
                local list = C.Analyze().groups[g].party[buff.id]
                Highlight(SetOf(list))
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(buff.name, 1, 1, 1)
                GameTooltip:AddLine(buff.desc, 0.8, 0.8, 0.8, true)
                for _, line in ipairs(buff.extra or {}) do GameTooltip:AddLine(line, 0.6, 0.6, 0.6, true) end
                GameTooltip:AddLine("Group " .. g .. " has it", 0.2, 0.85, 0.3)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() Highlight(nil) GameTooltip:Hide() end)
        end
        for k = 1, 5 do
            local i = (g - 1) * 5 + k
            local s = CreateFrame("Button", nil, gf)
            s:SetSize(GROUP_W - 8, SLOT_H - 1)
            s:SetPoint("TOPLEFT", gf, "TOPLEFT", 4, -(HEAD_H + (k - 1) * SLOT_H))
            s.index = i
            s.bg = s:CreateTexture(nil, "BACKGROUND")
            s.bg:SetAllPoints()
            s.bg:SetColorTexture(0.08, 0.08, 0.09, 1)
            s.icon = s:CreateTexture(nil, "ARTWORK")
            s.icon:SetSize(17, 17)
            s.icon:SetPoint("LEFT", s, "LEFT", 2, 0)
            s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            s.text:SetPoint("LEFT", s, "LEFT", 24, 0)
            s.text:SetPoint("RIGHT", s, "RIGHT", -18, 0)
            s.text:SetJustifyH("LEFT")
            s.text:SetWordWrap(false)
            s.hl = s:CreateTexture(nil, "OVERLAY")
            s.hl:SetAllPoints()
            s.hl:SetColorTexture(1, 0.82, 0, 0.35)
            s.hl:Hide()
            s.drop = s:CreateTexture(nil, "OVERLAY")
            s.drop:SetAllPoints()
            s.drop:SetColorTexture(1, 1, 1, 0.18)
            s.drop:Hide()
            s.x = CreateFrame("Button", nil, s)
            s.x:SetSize(16, SLOT_H - 1)
            s.x:SetPoint("RIGHT", s, "RIGHT", 0, 0)
            s.x.label = s.x:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            s.x.label:SetPoint("CENTER", s.x, "CENTER", 0, 0)
            s.x.label:SetText("|cffff6060x|r")
            s.x:SetScript("OnClick", function() C.Remove(i) GameTooltip:Hide() Refresh() end)
            s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            s:SetScript("OnMouseDown", function(_, button)
                local e = C.Entry(i)
                if button == "LeftButton" and e then
                    BeginDrag({ kind = "slot", index = i }, (C.Spec(e.spec) or {}).icon or QUESTION, K.ClassColored(e.name, e.class))
                end
            end)
            s:SetScript("OnClick", function(_, button)
                if button ~= "RightButton" then return end
                local e = C.Entry(i)
                if not e then return end
                if e.real then PersonMenu(C.byKey[e.key], i) else C.Remove(i) Refresh() end
            end)
            s:SetScript("OnEnter", SlotTooltip)
            s:SetScript("OnLeave", function() GameTooltip:Hide() end)
            slots[i] = s
        end
    end

    ---------------------------------------------------------------------------
    -- the three panels of effects
    ---------------------------------------------------------------------------
    local PANELS = {
        { scope = "raid", title = "Raid buffs", x = 0, w = 260 },
        { scope = "party", title = "Party buffs", x = 266, w = 260 },
        { scope = "debuff", title = "Debuffs and single target", x = 532, w = 268 },
    }
    local buffButtons = {}                 -- [buffId] = button
    local panelFrames = {}
    for _, def in ipairs(PANELS) do
        local box = NewBox(page, def.x, -402, def.w, 214)
        panelFrames[def.scope] = box
        box.title = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
        box.title:SetText(def.title)
        box.total = box:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        box.total:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -8)
        -- the categories in the order they appear in the table
        local cats, order = {}, {}
        for _, b in ipairs(C.BUFFS) do
            if b.scope == def.scope then
                if not cats[b.cat] then cats[b.cat] = {} order[#order + 1] = b.cat end
                table.insert(cats[b.cat], b)
            end
        end
        local y = -26
        local perRow = math.floor((def.w - 16) / 27)
        for _, cat in ipairs(order) do
            local label = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            label:SetPoint("TOPLEFT", box, "TOPLEFT", 8, y)
            label:SetText(cat)
            y = y - 13
            for k, b in ipairs(cats[cat]) do
                local col, rowN = (k - 1) % perRow, math.floor((k - 1) / perRow)
                local btn = IconButton(box, 24)
                btn:SetPoint("TOPLEFT", box, "TOPLEFT", 8 + col * 27, y - rowN * 27)
                btn.icon:SetTexture(b.icon)
                btn.buff = b
                btn:SetScript("OnEnter", function(self)
                    local an = C.Analyze()
                    local st = an[b.scope][b.id]
                    Highlight(SetOf(st and st.slots))
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(b.name, 1, 1, 1)
                    GameTooltip:AddLine(b.desc, 0.8, 0.8, 0.8, true)
                    for _, line in ipairs(b.extra or {}) do GameTooltip:AddLine(line, 0.6, 0.6, 0.6, true) end
                    if b.scope == "party" then GameTooltip:AddLine("Only the group of the one who brings it gets it", 0.6, 0.6, 0.6, true) end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Can be brought by:", 1, 0.82, 0)
                    GameTooltip:AddLine(WhoColored(b), 1, 1, 1, true)
                    GameTooltip:AddLine(" ")
                    if b.scope == "party" then
                        GameTooltip:AddLine(("%d of %d groups have it"):format(st.groups, st.of),
                            unpack(STATUS_COLOR[st.status]))
                    elseif st.status == "ok" then
                        GameTooltip:AddLine(("Covered by %d"):format(#st.slots), unpack(STATUS_COLOR.ok))
                    else
                        GameTooltip:AddLine("Nobody brings this", unpack(STATUS_COLOR.missing))
                    end
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() Highlight(nil) GameTooltip:Hide() end)
                buffButtons[b.id] = btn
            end
            y = y - 27 * math.ceil(#cats[cat] / perRow) - 2
        end
    end

    ---------------------------------------------------------------------------
    -- refresh
    ---------------------------------------------------------------------------
    local function Paint(btn, status, countText)
        local c = STATUS_COLOR[status]
        -- a missing buff: a fainter red border and a more visible picture, so it can still be read
        btn.border:SetColorTexture(c[1], c[2], c[3], status == "missing" and 0.45 or 1)
        btn.icon:SetAlpha(status == "missing" and 0.6 or 1)
        if btn.icon.SetDesaturated then btn.icon:SetDesaturated(status == "missing") end
        btn.count:SetText(countText or "")
    end

    Refresh = function()
        if not page:IsShown() then return end
        C.Refresh()
        local an = C.Analyze()
        local size = C.Size()

        for n, b in pairs(sizeButtons) do
            if n == size then b:LockHighlight() else b:UnlockHighlight() end
        end
        for g = 1, 8 do groupFrames[g]:SetShown(g <= size / 5) end

        -- the groups
        for i = 1, 40 do
            local s = slots[i]
            local e = C.Entry(i)
            if e then
                local spec = C.Spec(e.spec)
                s.icon:SetTexture(spec and spec.icon or QUESTION)
                s.icon:Show()
                s.text:SetText(K.ClassColored(e.name, e.class))
                s.bg:SetColorTexture(0.11, 0.11, 0.13, 1)
                s.x:Show()
            else
                s.icon:Hide()
                s.text:SetText("")
                s.bg:SetColorTexture(0.06, 0.06, 0.07, 1)
                s.x:Hide()
            end
            s.hl:Hide()
            s.drop:Hide()
        end
        for g = 1, size / 5 do
            -- the party buffs this group has, large enough to see; more than fit: the rest as "+n"
            local ids = {}
            for _, b in ipairs(C.BUFFS) do
                if b.scope == "party" and an.groups[g].party[b.id] then ids[#ids + 1] = b end
            end
            local show = #ids > 5 and 4 or #ids
            for k = 1, 5 do
                local btn = partyIcons[g][k]
                if k <= show then
                    -- right aligned: the last shown icon is at the right edge
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPRIGHT", groupFrames[g], "TOPRIGHT", -4 - (show - k) * 20 - (#ids > 5 and 22 or 0), -2)
                    btn.buff = ids[k]
                    btn.icon:SetTexture(ids[k].icon)
                    btn.border:SetColorTexture(0.2, 0.85, 0.3, 1)
                    btn:Show()
                else
                    btn.buff = nil
                    btn:Hide()
                end
            end
            groupFrames[g].more:SetText(#ids > 5 and ("|cff9fe0a8+" .. (#ids - 4) .. "|r") or "")
        end

        -- the people of my group that are not in a group
        local rows = {}
        for _, m in ipairs(C.Unplaced()) do rows[#rows + 1] = { member = m } end
        if #rows == 0 then rows[1] = { note = "Everybody is placed" } end
        list:Render(rows, true)
        listHeader:SetText(("Your group (%d)"):format(#C.members))

        -- the effects
        for _, b in ipairs(C.BUFFS) do
            local btn = buffButtons[b.id]
            if b.scope == "party" then
                local st = an.party[b.id]
                -- the count only where it says something: some of the groups have it ("2/3"); all of them (green) or none (red) need no count
                Paint(btn, st.status, st.status == "partial" and (st.groups .. "/" .. st.of) or "")
            else
                local st = an[b.scope][b.id]
                Paint(btn, st.status, #st.slots > 1 and tostring(#st.slots) or "")
            end
        end
        for scope, box in pairs(panelFrames) do
            local c = an.counts[scope]
            box.total:SetText(("%d / %d"):format(c[1], c[2]))
        end

        -- the roles
        local r = an.roles
        local text = ("|c%sTanks|r |c%s%d|r    |c%sHealers|r |c%s%d|r    |c%sDPS|r |c%s%d|r"):format(
            ROLE_COLOR.TANK, ROLE_COLOR.TANK, r.TANK, ROLE_COLOR.HEALER, ROLE_COLOR.HEALER, r.HEALER, ROLE_COLOR.DPS, ROLE_COLOR.DPS, r.DPS)
        if r.unknown > 0 then text = text .. "    " .. Gray(("no spec %d"):format(r.unknown)) end
        rolesText:SetText(text)
        dragHint:ClearAllPoints()
        dragHint:SetPoint("LEFT", rolesText, "LEFT", (rolesText:GetStringWidth() or 0) + 28, 0)
    end

    page:SetScript("OnShow", function() Refresh() end)
    ns.UI.RefreshComposition = Refresh
    ns.UI.CompUI = {
        slots = slots, groups = groupFrames, palette = paletteIcons, listFrame = listFrame, list = list, buffs = buffButtons,
        size = sizeButtons, reset = resetButton, driver = driver, ghost = ghost, partyIcons = partyIcons, roles = rolesText,
        BeginDrag = BeginDrag, Release = Release, panels = panelFrames, PersonMenu = PersonMenu,
    }
end
