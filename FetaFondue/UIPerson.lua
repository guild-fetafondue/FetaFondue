---@class ns
local ns = select(2, ...)
local K = ns.K
local NewWindow, Gold, Gray, BOX_BACKDROP, ColoredRecipeName, CreateScrollList, ItemData, LinkMaterial, LinkRecipe, QUESTION, RecipeIcon, Shifted, ShowRecipeHover, TotalsHeader =
    K.NewWindow, K.Gold, K.Gray, K.BOX_BACKDROP, K.ColoredRecipeName, K.CreateScrollList, K.ItemData, K.LinkMaterial, K.LinkRecipe, K.QUESTION, K.RecipeIcon, K.Shifted, K.ShowRecipeHover, K.TotalsHeader

do
-- Browse one guildie's profession, laid out like the classic profession window: a skill bar, the list of
-- recipes, the selected recipe with its reagents, and a quantity box with a Request button (where the
-- classic window has "Create").
local PV_W, PV_H = 430, 612
local pv = NewWindow("FetaFondueProfession", PV_W, PV_H)
pv:SetPoint("CENTER", UIParent, "CENTER", 240, 0)
pv:SetMovable(true)
pv:RegisterForDrag("LeftButton")
pv:SetScript("OnDragStart", pv.StartMoving)
pv:SetScript("OnDragStop", pv.StopMovingOrSizing)

-- solid background (the dialog art alone is see-through in places)
local pvBackground = pv:CreateTexture(nil, "BACKGROUND")
pvBackground:SetPoint("TOPLEFT", pv, "TOPLEFT", 9, -9)
pvBackground:SetPoint("BOTTOMRIGHT", pv, "BOTTOMRIGHT", -9, 9)
pvBackground:SetColorTexture(0.07, 0.07, 0.075, 1)

-- skill bar
local BAR_W = 236
local pvBar = CreateFrame("Frame", nil, pv)
pvBar:SetSize(BAR_W, 18)
pvBar:SetPoint("TOPLEFT", pv, "TOPLEFT", 28, -46)
local pvBarBG = pvBar:CreateTexture(nil, "BACKGROUND")
pvBarBG:SetAllPoints()
pvBarBG:SetColorTexture(0.04, 0.04, 0.1, 0.9)
local pvBarFill = pvBar:CreateTexture(nil, "ARTWORK")
pvBarFill:SetPoint("TOPLEFT", pvBar, "TOPLEFT", 1, -1)
pvBarFill:SetPoint("BOTTOMLEFT", pvBar, "BOTTOMLEFT", 1, 1)
pvBarFill:SetColorTexture(0.15, 0.4, 0.85, 1)
local pvBarText = pvBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pvBarText:SetPoint("CENTER", pvBar, "CENTER", 0, 0)

-- filter box
local pvSearch = K.NewEditBox("FetaFonduePVSearch", pv)
pvSearch:SetSize(118, 22)
pvSearch:SetPoint("TOPLEFT", pv, "TOPLEFT", 282, -44)
pvSearch:SetAutoFocus(false)
pvSearch:SetMaxLetters(30)
local pvPlaceholder = pvSearch:CreateFontString(nil, "ARTWORK", "GameFontDisable")
pvPlaceholder:SetPoint("LEFT", pvSearch, "LEFT", 2, 0)
pvPlaceholder:SetText("Filter")

local pvStatus = pv:Text("GameFontDisableSmall", 28, -66, 372)

-- recipe list
local PV_LIST_H = 200
local pvBox = CreateFrame("Frame", nil, pv, "BackdropTemplate")
pvBox:SetBackdrop(BOX_BACKDROP)
pvBox:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
pvBox:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
pvBox:SetPoint("TOPLEFT", pv, "TOPLEFT", 24, -84)
pvBox:SetSize(382, PV_LIST_H)

local function RenderProfessionRow(row, item)
    if not row.sel then
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.28)
    end
    if item.kind == "note" then
        row.sel:Hide()
        row:EnableMouse(false)
        row.text:SetFontObject("GameFontDisable")
        row.text:SetText(item.text)
        return
    end
    row.sel:SetShown(item.id == pv.selected)
    row:EnableMouse(true)
    row.text:SetFontObject("GameFontHighlight")
    row.text:SetText(item.text)
    row.onClick = function()
        if Shifted() then
            LinkRecipe(item.id, item.name)
        else
            pv.selected = item.id
            ns.UI.RefreshProfessionView(true)
        end
    end
    row.onEnter = function(r)
        ShowRecipeHover(r, item.id, item.name, "Click to select. Shift-click: link in chat")
    end
end
local pvList = CreateScrollList(pvBox, 382 - 8 - 28, PV_LIST_H - 16, 20, RenderProfessionRow)
pvList.frame:SetPoint("TOPLEFT", pvBox, "TOPLEFT", 6, -8)

-- selected recipe: icon, name, requirement, reagents
local PV_DETAIL_TOP, PV_DETAIL_H = -292, 246
local pvDetail = CreateFrame("Frame", nil, pv, "BackdropTemplate")
pvDetail:SetBackdrop(BOX_BACKDROP)
pvDetail:SetBackdropColor(0.06, 0.06, 0.065, 1)
pvDetail:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
pvDetail:SetPoint("TOPLEFT", pv, "TOPLEFT", 24, PV_DETAIL_TOP)
pvDetail:SetSize(382, PV_DETAIL_H)

local pvIconFrame = pvDetail:CreateTexture(nil, "BACKGROUND")
pvIconFrame:SetSize(48, 48)
pvIconFrame:SetPoint("TOPLEFT", pvDetail, "TOPLEFT", 12, -12)
pvIconFrame:SetColorTexture(0.7, 0.55, 0.15, 1)
local pvIconBtn = CreateFrame("Button", nil, pvDetail)
pvIconBtn:SetSize(44, 44)
pvIconBtn:SetPoint("TOPLEFT", pvDetail, "TOPLEFT", 14, -14)
local pvIcon = pvIconBtn:CreateTexture(nil, "ARTWORK")
pvIcon:SetAllPoints()
local pvName = pvDetail:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
pvName:SetPoint("TOPLEFT", pvDetail, "TOPLEFT", 68, -16)
pvName:SetWidth(300)
pvName:SetJustifyH("LEFT")
local pvRequires = pvDetail:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
pvRequires:SetPoint("TOPLEFT", pvDetail, "TOPLEFT", 68, -40)
pvRequires:SetWidth(300)
pvRequires:SetJustifyH("LEFT")
local pvReagentsHeader = pvDetail:CreateFontString(nil, "ARTWORK", "GameFontNormal")
pvReagentsHeader:SetPoint("TOPLEFT", pvDetail, "TOPLEFT", 14, -74)
pvReagentsHeader:SetWidth(354)
pvReagentsHeader:SetJustifyH("LEFT")

pvIconBtn:SetScript("OnEnter", function(self)
    if pv.selected then
        ShowRecipeHover(self, pv.selected, ns.RecipeName(pv.selected), "Shift-click: link in chat")
    end
end)
pvIconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
pvIconBtn:SetScript("OnClick", function()
    if Shifted() and pv.selected then
        LinkRecipe(pv.selected, ns.RecipeName(pv.selected), tonumber(pv.qty and pv.qty:GetText()))
    end
end)

local REAGENT_ROWS, REAGENT_ROW_H = 8, 20
local pvReagentRows = {}
local function GetReagentRow(i)
    local row = pvReagentRows[i]
    if not row then
        row = CreateFrame("Button", nil, pvDetail)
        row:SetHeight(REAGENT_ROW_H)
        row:SetPoint("TOPLEFT", pvDetail, "TOPLEFT", 14, -(94 + (i - 1) * REAGENT_ROW_H))
        row:SetPoint("TOPRIGHT", pvDetail, "TOPRIGHT", -14, -(94 + (i - 1) * REAGENT_ROW_H))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetJustifyH("LEFT")
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 0.82, 0, 0.15)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
            if (GameTooltip:NumLines() or 0) == 0 then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.itemID) end
            if (GameTooltip:NumLines() or 0) == 0 then GameTooltip:SetText(self.itemName or "", 1, 1, 1) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Shift-click: link it in chat, or search it in the auction house", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self) LinkMaterial(self.itemID, self.itemName, self.itemCount) end)
        pvReagentRows[i] = row
    end
    return row
end

local function ItemCountOf(itemID)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return nil end
    local ok, n = pcall(fn, itemID, true)
    return ok and n or nil
end

-- bottom: quantity and Request (like Create All / quantity / Create)
local pvNote = pv:Text("GameFontNormal", 28, -(PV_H - 62), 374, "CENTER")

local pvClose = K.NewButton(pv)
pvClose:SetSize(80, 26)
pvClose:SetPoint("BOTTOMLEFT", pv, "BOTTOMLEFT", 24, 22)
pvClose:SetText("Close")
pvClose:SetScript("OnClick", function() pv:Hide() end)

local pvRequest = K.NewButton(pv)
pvRequest:SetSize(110, 26)
pvRequest:SetPoint("BOTTOMRIGHT", pv, "BOTTOMRIGHT", -24, 22)
pvRequest:SetText("Request")

local pvPlus = K.NewButton(pv)
pvPlus:SetSize(24, 24)
pvPlus:SetPoint("BOTTOMRIGHT", pv, "BOTTOMRIGHT", -142, 23)
pvPlus:SetText("+")
local pvQty = K.NewEditBox("FetaFonduePVQuantity", pv)
pvQty:SetSize(40, 22)
pvQty:SetPoint("BOTTOMRIGHT", pv, "BOTTOMRIGHT", -176, 24)
pvQty:SetAutoFocus(false)
pvQty:SetNumeric(true)
pvQty:SetMaxLetters(3)
pvQty:SetJustifyH("CENTER")
pv.qty = pvQty
local pvMinus = K.NewButton(pv)
pvMinus:SetSize(24, 24)
pvMinus:SetPoint("BOTTOMRIGHT", pv, "BOTTOMRIGHT", -222, 23)
pvMinus:SetText("-")

local function PVQuantity()
    return math.max(1, math.min(999, tonumber(pvQty:GetText()) or 1))
end

local function RenderProfessionDetail()
    local id = pv.selected
    for _, row in ipairs(pvReagentRows) do row:Hide() end
    if not id then
        pvIcon:SetTexture(QUESTION)
        pvName:SetText("")
        pvRequires:SetText("")
        pvReagentsHeader:SetText("")
        return
    end
    local name = ns.RecipeName(id)
    local info = ns.RecipeInfo(id)
    pvIcon:SetTexture(RecipeIcon(id, info, pv.fallbackIcon))
    pvName:SetText(ColoredRecipeName(id, name))

    local prof = ns.Professions.RecipeRequirements({ id })[id]
    if prof and prof.name then
        pvRequires:SetText("Profession: " .. prof.name)
    else
        pvRequires:SetText("")
    end

    local n = PVQuantity()
    if info and #info.reagents > 0 then
        local list, crafts, made = ns.TotalMaterials(info, n)
        pvReagentsHeader:SetText((TotalsHeader(n, crafts, made):gsub("^Materials", "Reagents")))
        for i, r in ipairs(list) do
            if i > REAGENT_ROWS then break end
            local row = GetReagentRow(i)
            local iname, icon = ItemData(r.id)
            row.itemID, row.itemName, row.itemCount = r.id, iname or ("item " .. r.id), r.count
            row.icon:SetTexture(icon or QUESTION)
            local have = ItemCountOf(r.id)
            local haveText = ""
            if have then
                haveText = (have >= r.count) and Gray("  (you have " .. have .. ")") or ("  |cffff6060(you have " .. have .. ")|r")
            end
            row.text:SetText(("%s × %s%s"):format(Gold(r.count), row.itemName, haveText))
            row:Show()
        end
    elseif info then
        pvReagentsHeader:SetText("No reagents needed")
    else
        pvReagentsHeader:SetText("Asking guildmates for the reagents")
        if ns.Sync then ns.Sync.RequestRecipeInfo(id) end
    end
end

-- A profession with no recipes (Herbalism, Skinning, Fishing, or nothing shared yet) gets a small
-- "Nothing to craft" screen instead of the regular profession window.
local pvEmptyIcon = pv:CreateTexture(nil, "ARTWORK")
pvEmptyIcon:SetSize(64, 64)
pvEmptyIcon:SetPoint("TOP", pv, "TOP", 0, -64)
local pvEmptyTitle = pv:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
pvEmptyTitle:SetPoint("TOP", pv, "TOP", 0, -144)
pvEmptyTitle:SetText("Nothing to craft")
local pvEmptySub = pv:Text("GameFontHighlight", 28, -176, 374, "CENTER")
pvEmptyIcon:Hide()
pvEmptyTitle:Hide()
pvEmptySub:Hide()

local pvRegular = { pvBar, pvSearch, pvStatus, pvBox, pvDetail, pvNote, pvPlus, pvQty, pvMinus, pvRequest }
local function SetPVEmpty(isEmpty, subText)
    for _, f in ipairs(pvRegular) do f:SetShown(not isEmpty) end
    pvEmptyIcon:SetShown(isEmpty)
    pvEmptyTitle:SetShown(isEmpty)
    pvEmptySub:SetShown(isEmpty)
    if isEmpty then
        pvEmptyIcon:SetTexture(pv.fallbackIcon or QUESTION)
        pvEmptySub:SetText(subText or "")
    end
    pv:SetSize(PV_W, isEmpty and 290 or PV_H)
    pvClose:ClearAllPoints()
    if isEmpty then
        pvClose:SetPoint("BOTTOM", pv, "BOTTOM", 0, 24)
    else
        pvClose:SetPoint("BOTTOMLEFT", pv, "BOTTOMLEFT", 24, 22)
    end
end

-- rebuild the list (and the detail). keepScroll: stay where the list is scrolled to.
function ns.UI.RefreshProfessionView(keepScroll)
    if not pv:IsShown() then return end
    local members = ns.GetMembers() or {}
    local m = (ns.DB.mine[pv.guid]) or members[pv.guid]
    local p = m and m.profs[pv.key]
    if not p then
        SetPVEmpty(false)
        pvStatus:SetText("")
        pvBarText:SetText("")
        pvBarFill:SetWidth(1)
        pvList:Render({ { kind = "note", text = "No data for this profession." } })
        pv.selected = nil
        RenderProfessionDetail()
        return
    end

    local roster = ns.GetRoster()
    local entry = ns.FindRosterEntry(roster, pv.guid, m.name)
    local name = ns.DisplayName(entry and entry.name or m.name)
    local profName = ns.Professions.ProfessionName(pv.key, p.name)
    pv:SetTitle(name .. " - " .. profName)

    pv.fallbackIcon = ns.PROFESSION_ICONS[tonumber(pv.key)]
    if #p.ids == 0 then
        local skillLine = (p.rank and p.rank > 0) and (p.max and p.max > 0 and ("Skill %d / %d"):format(p.rank, p.max) or ("Skill %d"):format(p.rank)) or ""
        SetPVEmpty(true, ("%s has no %s recipes to craft.\n%s"):format(name, profName, Gray(skillLine)))
        pv.selected = nil
        return
    end
    SetPVEmpty(false)

    -- skill bar
    local rank, max = p.rank or 0, p.max or 0
    pvBarText:SetText(max > 0 and ("Skill %d / %d"):format(rank, max) or ("Skill %d"):format(rank))
    pvBarFill:SetWidth(math.max(1, (BAR_W - 2) * ((max > 0) and math.min(1, rank / max) or 0)))
    local state = (entry and entry.online) and "|cff40ff40online|r" or "|cffb0b0b0offline|r"
    pvStatus:SetText(("%d %s · %s"):format(#p.ids, #p.ids == 1 and "recipe" or "recipes", state))

    local words = {}
    for word in ((pvSearch:GetText() or ""):lower()):gmatch("%S+") do words[#words + 1] = word end
    local items, selectedStillThere = {}, false
    for _, id in ipairs(p.ids) do
        local lower = ns.RecipeLower(id)
        local all = true
        for _, word in ipairs(words) do
            if not lower:find(word, 1, true) then all = false break end
        end
        if all then
            local rname = ns.RecipeName(id)
            if id == pv.selected then selectedStillThere = true end
            items[#items + 1] = {
                kind = "recipe", id = id, name = rname,
                text = ("|T%s:16|t %s"):format(tostring(RecipeIcon(id, ns.RecipeInfo(id), pv.fallbackIcon)), ColoredRecipeName(id, rname)),
            }
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    if #items == 0 then
        pv.selected = nil
        items[1] = { kind = "note", text = #p.ids == 0 and "No recipes shared yet." or "No recipes match." }
    elseif not selectedStillThere then
        pv.selected = items[1].id
    end
    pvList:Render(items, keepScroll)
    if pv.scrollToSelected and pv.selected then
        pv.scrollToSelected = false
        for i, it in ipairs(items) do
            if it.id == pv.selected then
                ns.After(0.05, function() pvList:ScrollToIndex(i) end)
                break
            end
        end
    end
    RenderProfessionDetail()
end

function ns.UI.RefreshProfessionDetail()
    if pv:IsShown() then RenderProfessionDetail() end
end

local function DoRequest()
    local id = pv.selected
    if not id then return end
    local n = PVQuantity()
    local name = ns.RecipeName(id)
    ns.AddRequest(id, name, n)
    ns.UI.RefreshRequests()
    pv.noteToken = (pv.noteToken or 0) + 1
    local token = pv.noteToken
    pvNote:SetText(("|cff40ff40Requested %d × %s|r"):format(n, name))
    ns.After(4, function()
        if pv.noteToken == token then pvNote:SetText("") end
    end)
end
pvRequest:SetScript("OnClick", DoRequest)
pvQty:SetScript("OnEnterPressed", DoRequest)
pvQty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
pvQty:SetScript("OnTextChanged", function() if pv:IsShown() then RenderProfessionDetail() end end)
pvPlus:SetScript("OnClick", function() pvQty:SetText(tostring(math.min(999, PVQuantity() + 1))) end)
pvMinus:SetScript("OnClick", function() pvQty:SetText(tostring(math.max(1, PVQuantity() - 1))) end)

pvSearch:SetScript("OnTextChanged", function(self)
    pvPlaceholder:SetShown((self:GetText() or "") == "")
    ns.UI.RefreshProfessionView()
end)
pvSearch:SetScript("OnEscapePressed", function(self)
    if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
end)

-- recipeID / qty (optional): open on that recipe with that quantity filled in
function ns.UI.OpenProfessionView(guid, key, recipeID, qty)
    pv.guid, pv.key, pv.selected = guid, key, recipeID
    pv.scrollToSelected = recipeID ~= nil
    pvSearch:SetText("")
    pvQty:SetText(tostring(math.max(1, math.min(999, tonumber(qty) or 1))))
    pvNote:SetText("")
    pv:Show()
    ns.UI.RefreshProfessionView()
end

-- lets the dashboard / toggle close this window without knowing its locals
function ns.UI.CloseProfessionView() pv:Hide() end
end

K.RegisterCloser(function() ns.UI.CloseProfessionView() end)
