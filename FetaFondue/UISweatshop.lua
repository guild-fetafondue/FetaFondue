---@class ns
local ns = select(2, ...)
local K = ns.K
local Gold, Gray, Plural, BOX_BACKDROP, CreateScrollList, ColoredRecipeName, RecipeIcon, ItemData, QUESTION, Shifted, LinkRecipe, LinkMaterial, ShowRecipeHover, TotalsHeader, QUALITY_HEX =
    K.Gold, K.Gray, K.Plural, K.BOX_BACKDROP, K.CreateScrollList, K.ColoredRecipeName, K.RecipeIcon, K.ItemData, K.QUESTION, K.Shifted, K.LinkRecipe, K.LinkMaterial, K.ShowRecipeHover, K.TotalsHeader, K.QUALITY_HEX

---------------------------------------------------------------------------
-- Sweatshop, laid out like Profession Master's database view:
--   professions (left)  |  items (middle)  |  details of the selected item with its materials,
--   who can craft it and a Request button, and underneath all the guild's requests (right).
---------------------------------------------------------------------------
-- the page of the first tab ("Requests"): everything below the tab strip (UISweatshopTabs.lua adds the strip and the other tabs)
local root = K.sweatshopPanel
local panel = CreateFrame("Frame", nil, root)
panel:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -34)
panel:SetSize(800, 586)
K.InstallLayoutHelpers(panel)
K.sweatshopRequestsPage = panel

local state = { profession = nil, search = "", online = false, selected = nil, qty = 1, scrollToSelected = false }

local COL_A_W = 176
local COL_B_X, COL_B_W = 188, 282
local COL_C_X, COL_C_W = 482, 318

local function NewBox(x, y, w, h)
    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetBackdrop(BOX_BACKDROP)
    box:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    box:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    box:SetSize(w, h)
    return box
end

local RefreshAll   -- defined below

-- a highlight behind the selected row
local function MarkSelected(row, selected)
    if not row.selTex then
        row.selTex = row:CreateTexture(nil, "BACKGROUND")
        row.selTex:SetAllPoints()
        row.selTex:SetColorTexture(1, 0.82, 0, 0.2)
    end
    row.selTex:SetShown(selected)
end

---------------------------------------------------------------------------
-- left: search, online filter, professions
---------------------------------------------------------------------------
local searchLabel = panel:Text("GameFontNormal", 0, -2, COL_A_W)
searchLabel:SetText("Search")

local search = K.NewEditBox("FetaFondueSearch", panel)
search:SetSize(COL_A_W - 36, 20)
search:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -22)
search:SetAutoFocus(false)
search:SetMaxLetters(40)

local clearButton = CreateFrame("Button", nil, panel)
clearButton:SetSize(18, 18)
clearButton:SetPoint("LEFT", search, "RIGHT", 4, 0)
clearButton.t = clearButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
clearButton.t:SetPoint("CENTER", clearButton, "CENTER", 0, 0)
clearButton.t:SetText("x")
clearButton.t:SetTextColor(1, 0.3, 0.3)
clearButton:SetScript("OnClick", function()
    search:SetText("")
    search:ClearFocus()
end)

local onlineButton = K.NewButton(panel)
onlineButton:SetSize(COL_A_W, 22)
onlineButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -50)
onlineButton:SetText("Online crafters only")
onlineButton:SetScript("OnClick", function()
    state.online = not state.online
    if state.online then onlineButton:LockHighlight() else onlineButton:UnlockHighlight() end
    RefreshAll()
end)

local profLabel = panel:Text("GameFontNormal", 0, -82, COL_A_W)
profLabel:SetText("Profession")
local profBox = NewBox(0, -100, COL_A_W, 486)

-- recipes that at least one online guildie can craft
local function OnlineRecipeSet()
    local set = {}
    local roster = ns.GetRoster()
    for guid, m in pairs(ns.GetMembers() or {}) do
        local entry = ns.FindRosterEntry(roster, guid, m.name)
        if entry and entry.online then
            for _, p in pairs(m.profs) do
                for _, id in ipairs(p.ids) do set[id] = true end
            end
        end
    end
    return set
end

local function BuildProfessionItems()
    local rec = ns.Professions.GuildRecipes()
    local onlineSet = state.online and OnlineRecipeSet() or nil
    local all, seen = 0, {}
    local list = {}
    for _, id in ipairs(ns.PROFESSION_ORDER) do
        local key = tostring(id)
        local e = rec[key]
        local count = 0
        if e then
            for _, rid in ipairs(e.ids) do
                if not onlineSet or onlineSet[rid] then
                    count = count + 1
                    if not seen[rid] then seen[rid] = true all = all + 1 end
                end
            end
        end
        -- "Online crafters only": a profession nobody online can craft is not listed
        if not (onlineSet and count == 0) then
            list[#list + 1] = { kind = "prof", key = key, name = ns.PROFESSIONS[id] or key, count = count, icon = ns.PROFESSION_ICONS[id] }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    table.insert(list, 1, { kind = "prof", key = nil, name = "All professions", count = all, icon = "Interface\\Icons\\INV_Misc_Book_09" })
    -- the chosen profession disappeared from the list: back to all of them
    if state.profession then
        local still = false
        for _, item in ipairs(list) do if item.key == state.profession then still = true end end
        if not still then state.profession = nil end
    end
    return list
end

-- A long profession name is shortened with "..." so that the count after it always stays visible.
local measure = profBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
measure:SetAlpha(0)
local PROF_TEXT_W = COL_A_W - 12 - 12            -- the width of a row (the stripes run to the end of the box) minus its padding

local function ProfessionText(item)
    local count = item.count > 0 and (" " .. Gray("(" .. item.count .. ")")) or ""
    local function Build(name) return ("|T%s:22|t  %s%s"):format(item.icon or QUESTION, name, count) end
    measure:SetText(Build(item.name))
    if (measure:GetStringWidth() or 0) <= PROF_TEXT_W then return Build(item.name) end
    local chars = {}
    for ch in item.name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    for n = #chars - 1, 1, -1 do
        local short = table.concat(chars, "", 1, n) .. "..."
        measure:SetText(Build(short))
        if (measure:GetStringWidth() or 0) <= PROF_TEXT_W then return Build(short) end
    end
    return Build((chars[1] or "") .. "...")
end

local function RenderProfessionRow(row, item)
    row:EnableMouse(true)
    MarkSelected(row, state.profession == item.key)
    row.text:SetFontObject("GameFontNormal")
    row.text:SetText(ProfessionText(item))
    row.onClick = function()
        state.profession = item.key
        RefreshAll()
    end
end
local profList = CreateScrollList(profBox, COL_A_W - 12, 486 - 16, 28, RenderProfessionRow, { stripes = true, insideTrack = true })
profList.frame:SetPoint("TOPLEFT", profBox, "TOPLEFT", 6, -8)

---------------------------------------------------------------------------
-- middle: the items
---------------------------------------------------------------------------
local itemLabel = panel:Text("GameFontNormal", COL_B_X, -2, COL_B_W)
itemLabel:SetText("Item")
local itemBox = NewBox(COL_B_X, -22, COL_B_W, 564)

local function BuildRecipeItems()
    local rec = ns.Professions.GuildRecipes()
    local words = {}
    for w in state.search:lower():gmatch("%S+") do words[#words + 1] = w end
    local onlineSet = state.online and OnlineRecipeSet() or nil
    local items, seen = {}, {}
    local function Consider(key, id)
        if seen[id] then return end
        if onlineSet and not onlineSet[id] then return end
        local name = ns.RecipeName(id)
        local lname = name:lower()
        for _, w in ipairs(words) do
            if not lname:find(w, 1, true) then return end
        end
        seen[id] = true
        items[#items + 1] = { kind = "recipe", id = id, name = name, lname = lname, key = key }
    end
    if state.profession then
        local e = rec[state.profession]
        if e then for _, id in ipairs(e.ids) do Consider(state.profession, id) end end
    else
        for key, e in pairs(rec) do
            for _, id in ipairs(e.ids) do Consider(key, id) end
        end
    end
    table.sort(items, function(a, b)
        if a.lname ~= b.lname then return a.lname < b.lname end
        return a.id < b.id
    end)
    return items
end

local function Select(id, qty)
    state.selected = id
    state.qty = qty or 1
    RefreshAll(true)
end

local function RenderRecipeRow(row, item)
    if item.kind == "note" then
        row:EnableMouse(false)
        MarkSelected(row, false)
        row.text:SetFontObject("GameFontDisable")
        row.text:SetText(item.text)
        return
    end
    row:EnableMouse(true)
    MarkSelected(row, state.selected == item.id)
    row.text:SetFontObject("GameFontHighlight")
    local info = ns.RecipeInfo(item.id)
    local fallback = item.key and ns.PROFESSION_ICONS[tonumber(item.key)] or nil
    row.text:SetText(("|T%s:22|t  %s"):format(tostring(RecipeIcon(item.id, info, fallback)), ColoredRecipeName(item.id, item.name)))
    row.onClick = function()
        if Shifted() then LinkRecipe(item.id, item.name) else Select(item.id) end
    end
    row.onEnter = function(r)
        ShowRecipeHover(r, item.id, item.name, { K.Key("Click") .. ": show the details", K.Key("Shift-click") .. ": link in chat" })
    end
end
local itemList = CreateScrollList(itemBox, COL_B_W - 8 - 28, 564 - 16, 28, RenderRecipeRow, { stripes = true })
itemList.frame:SetPoint("TOPLEFT", itemBox, "TOPLEFT", 6, -8)

---------------------------------------------------------------------------
-- right, top: details of the selected item
---------------------------------------------------------------------------
local detailBox = NewBox(COL_C_X, -2, COL_C_W, 376)

local detailIcon = detailBox:CreateTexture(nil, "ARTWORK")
detailIcon:SetSize(40, 40)
detailIcon:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 10, -10)
-- Shift-click on the picture links the item in the chat (a recipe link for a craft that makes no item)
local detailHit = CreateFrame("Button", nil, detailBox)
detailHit:SetSize(40, 40)
detailHit:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 10, -10)
detailHit:SetScript("OnClick", function()
    local id = state.selected
    if not id or not Shifted() then return end
    local info = ns.RecipeInfo(id)
    local name = ns.RecipeName(id)
    if info and info.item then
        local itemName = ItemData(info.item)
        local link = K.ItemLinkFor(info.item, itemName or name)
        K.SendToChat(link, link)
    else
        K.SendToChat(K.RecipeLinkFor(id, name))
    end
end)
detailHit:SetScript("OnEnter", function(self)
    if not state.selected then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Shift-click: link it in the chat", 1, 1, 1)
    GameTooltip:Show()
end)
detailHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
local detailName = detailBox:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
detailName:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 58, -12)
detailName:SetWidth(250)
detailName:SetJustifyH("LEFT")
detailName:SetWordWrap(false)
local detailProf = detailBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
detailProf:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 58, -34)
detailProf:SetWidth(250)
detailProf:SetJustifyH("LEFT")
local tipText = detailBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
tipText:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 10, -62)
tipText:SetWidth(298)
tipText:SetJustifyH("LEFT")
tipText:SetJustifyV("TOP")
tipText:SetWordWrap(true)
local TIP_HEIGHT = 96

-- the item's tooltip text (Binds when equipped, stats, use...), read through a hidden tooltip
local scanTip
pcall(function()
    scanTip = CreateFrame("GameTooltip", "FetaFondueScanTip", UIParent, "GameTooltipTemplate")
end)

-- what the item is and does: its tooltip lines (Binds when equipped, stats, Use: ...), shown whole
-- the "Reagents: A (2), B" line of the game's own spell tooltip, as a list of texts (names only)
local function ReagentsFromLines(lines)
    local label = (type(_G.SPELL_REAGENTS) == "string" and _G.SPELL_REAGENTS ~= "") and _G.SPELL_REAGENTS or "Reagents: "
    label = label:gsub("%s+$", "")
    for _, line in ipairs(lines) do
        local plain = tostring(line):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if plain:sub(1, #label) == label then
            local rest = plain:sub(#label + 1):gsub("^[%s:]+", "")
            local out = {}
            for piece in rest:gmatch("[^,]+") do
                local t = piece:gsub("^%s+", ""):gsub("%s+$", "")
                if t ~= "" then out[#out + 1] = t end
            end
            if #out > 0 then return out end
        end
    end
    return nil
end

local function TooltipLines(id, info)
    local lines = {}
    if not scanTip then return lines end
    pcall(function()
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:ClearLines()
        if info and info.item then scanTip:SetHyperlink("item:" .. info.item) else scanTip:SetSpellByID(id) end
        local n = tonumber(scanTip:NumLines()) or 0
        for i = 2, math.min(n, 16) do
            local fs = _G["FetaFondueScanTipTextLeft" .. i]
            local text = fs and fs:GetText()
            local lower = type(text) == "string" and text:lower() or ""
            local isIDLine = lower:find("item%s*id") or lower:find("icon%s*id") or lower:find("spell%s*id")
                or lower:find("file%s*id") or lower:find("itemid") or lower:find("iconid") or lower:find("spellid")
            if type(text) == "string" and text ~= "" and not isIDLine then
                local r, g, b = fs:GetTextColor()
                if type(r) == "number" then
                    text = ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
                end
                lines[#lines + 1] = text
            end
        end
    end)
    return lines
end

-- show as many whole lines as fit into the box (never cut a line in the middle)
local function ShowDescription(lines)
    local n = #lines
    tipText:SetText(table.concat(lines, "\n", 1, n))
    while n > 1 and (tonumber(tipText:GetStringHeight()) or 0) > TIP_HEIGHT do
        n = n - 1
        tipText:SetText(table.concat(lines, "\n", 1, n))
    end
    if n == 0 then tipText:SetText("") end
end

-- materials
local reagentHeader = detailBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
reagentHeader:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 10, -164)
reagentHeader:SetWidth(298)
reagentHeader:SetJustifyH("LEFT")

local function RenderReagentRow(row, item)
    if item.kind == "note" then
        row:EnableMouse(false)
        row.text:SetFontObject("GameFontDisable")
        row.text:SetText(item.text)
        return
    end
    row:EnableMouse(true)
    row.text:SetFontObject("GameFontHighlight")
    local name, icon, quality = ItemData(item.id)
    local hex = quality and QUALITY_HEX[quality]
    local shown = name or ("item " .. item.id)
    local colored = hex and ("|cff" .. hex .. shown .. "|r") or shown
    local have = 0
    pcall(function() have = GetItemCount(item.id, true) or 0 end)
    local short = have < item.count and ("  |cffff4040(you have " .. have .. ")|r") or ""
    row.text:SetText(("|T%s:16|t %s × %s%s"):format(tostring(icon or QUESTION), Gold(item.count), colored, short))
    row.onClick = function() LinkMaterial(item.id, shown, item.count) end
    row.onEnter = function(r)
        GameTooltip:SetOwner(r, "ANCHOR_LEFT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. item.id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(K.Key("Shift-click") .. ": link it in chat,", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("or search it in the auction house", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end
end
local reagentList = CreateScrollList(detailBox, 270, 90, 18, RenderReagentRow, { stripes = true })
reagentList.frame:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 10, -182)

-- who can craft it
local playersHeader = detailBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
playersHeader:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 10, -278)
playersHeader:SetWidth(298)
playersHeader:SetJustifyH("LEFT")

local function RenderPlayerRow(row, item)
    if item.kind == "note" then
        row:EnableMouse(false)
        row.text:SetFontObject("GameFontDisable")
        row.text:SetText(item.text)
        return
    end
    row:EnableMouse(true)
    row.text:SetFontObject("GameFontHighlight")
    local c = item.crafter
    local color = c.online and "|cff40ff40" or "|cff999999"
    local skill = c.rank and c.rank > 0 and Gray("  skill " .. c.rank) or ""
    row.text:SetText(("%s%s|r%s%s"):format(color, c.name, skill, c.online and "" or Gray("  offline")))
    row.onClick = function() ns.UI.OpenProfessionView(c.guid, c.key, item.recipe, state.qty) end
    row.onEnter = function(r)
        GameTooltip:SetOwner(r, "ANCHOR_LEFT")
        GameTooltip:SetText(c.name, 1, 1, 1)
        GameTooltip:AddLine(K.Key("Click") .. ": browse their whole profession", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end
end
local playersList = CreateScrollList(detailBox, 270, 36, 18, RenderPlayerRow, { stripes = true })
playersList.frame:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 10, -294)

-- quantity and Request
local minusButton = K.NewButton(detailBox)
minusButton:SetSize(24, 24)
minusButton:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 10, -342)
minusButton:SetText("-")
local qtyBox = K.NewEditBox("FetaFondueQuantity", detailBox)
qtyBox:SetSize(44, 20)
qtyBox:SetPoint("LEFT", minusButton, "RIGHT", 8, 0)
qtyBox:SetAutoFocus(false)
qtyBox:SetNumeric(true)
qtyBox:SetMaxLetters(3)
qtyBox:SetJustifyH("CENTER")
local plusButton = K.NewButton(detailBox)
plusButton:SetSize(24, 24)
plusButton:SetPoint("LEFT", qtyBox, "RIGHT", 8, 0)
plusButton:SetText("+")
local requestButton = K.NewButton(detailBox)
requestButton:SetSize(96, 24)
requestButton:SetPoint("LEFT", plusButton, "RIGHT", 12, 0)
requestButton:SetText("Request")
local confirmText = detailBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
confirmText:SetPoint("LEFT", requestButton, "RIGHT", 8, 0)
confirmText:SetWidth(70)
confirmText:SetJustifyH("LEFT")

local function SetQty(n)
    state.qty = math.max(1, math.min(999, math.floor(tonumber(n) or 1)))
    qtyBox:SetText(tostring(state.qty))
    RefreshAll(true)
end
minusButton:SetScript("OnClick", function() SetQty(state.qty - 1) end)
plusButton:SetScript("OnClick", function() SetQty(state.qty + 1) end)
qtyBox:SetScript("OnEnterPressed", function(self)
    SetQty(self:GetText())
    self:ClearFocus()
end)
qtyBox:SetScript("OnEditFocusLost", function(self)
    local n = tonumber(self:GetText())
    if n and n ~= state.qty then SetQty(n) end
end)

requestButton:SetScript("OnClick", function()
    local id = state.selected
    if not id then return end
    local n = tonumber(qtyBox:GetText()) or state.qty
    state.qty = math.max(1, math.min(999, math.floor(n)))
    ns.AddRequest(id, ns.RecipeName(id), state.qty)
    confirmText:SetText("|cff40ff40Requested|r")
end)

local function RefreshDetails()
    local id = state.selected
    confirmText:SetText("")
    qtyBox:SetText(tostring(state.qty))
    if not id then
        detailIcon:SetTexture(QUESTION)
        detailName:SetText(Gray("Pick an item"))
        detailProf:SetText("")
        tipText:SetText("")
        reagentHeader:SetText("")
        reagentList:Render({ { kind = "note", text = "Select an item on the left." } })
        playersHeader:SetText("")
        playersList:Render({ { kind = "note", text = "" } })
        requestButton:Disable()
        return
    end
    requestButton:Enable()

    local name = ns.RecipeName(id)
    local info = ns.RecipeInfo(id)
    -- freshly synced recipe: nobody has sent its details yet. The game can often tell by itself; otherwise ask the guild
    if not info then info = ns.Professions.LearnInfoFromGame(id) end
    if not info and ns.Sync then ns.Sync.RequestRecipeInfo(id) end

    detailIcon:SetTexture(RecipeIcon(id, info, QUESTION))
    detailName:SetText(ColoredRecipeName(id, name))

    local req = ns.Professions.RecipeRequirements({ id })[id]
    if req and req.name then
        local icon = req.key and ns.PROFESSION_ICONS[tonumber(req.key)]
        detailProf:SetText(("%s|cff8fc7ff%s%s|r"):format(icon and ("|T" .. icon .. ":14|t ") or "", req.name, req.skill and (" " .. req.skill) or ""))
    else
        detailProf:SetText("")
    end

    local tipLines = TooltipLines(id, info)
    ShowDescription(tipLines)

    -- materials for the quantity
    if info and #info.reagents > 0 then
        local list, crafts, made = ns.TotalMaterials(info, state.qty)
        reagentHeader:SetText(TotalsHeader(state.qty, crafts, made))
        reagentList:Render(list, true)
    else
        -- no saved details: the game's own tooltip may still name the reagents (names only, no amounts per quantity)
        local named = (not info) and ReagentsFromLines(tipLines) or nil
        if named then
            reagentHeader:SetText("Materials (from the game's tooltip)")
            local rows = {}
            for _, t in ipairs(named) do rows[#rows + 1] = { kind = "note", text = t } end
            reagentList:Render(rows)
        else
            reagentHeader:SetText("Materials")
            reagentList:Render({ { kind = "note", text = info and "No materials needed." or "Materials not known yet (asking guildmates)" } })
        end
    end

    -- who can craft it
    local crafters = ns.Professions.FindCrafters(id)
    if state.online then
        local only = {}
        for _, c in ipairs(crafters) do if c.online then only[#only + 1] = c end end
        crafters = only
    end
    playersHeader:SetText(("Crafters (%d)"):format(#crafters))
    local rows = {}
    for _, c in ipairs(crafters) do rows[#rows + 1] = { kind = "player", crafter = c, recipe = id } end
    if #rows == 0 then rows[1] = { kind = "note", text = "Nobody known can craft this." } end
    playersList:Render(rows)
end

---------------------------------------------------------------------------
-- right, bottom: all requests
---------------------------------------------------------------------------
local requestsHeader = panel:Text("GameFontNormal", COL_C_X, -384, COL_C_W - 110)
local requestBox = NewBox(COL_C_X, -402, COL_C_W, 184)

local requestList = CreateScrollList(requestBox, COL_C_W - 8 - 28, 184 - 16, 22,
    K.RequestRowRenderer({ withDelete = true, onOpen = function(r) ns.UI.OpenSweatshopRecipe(r.id, r.qty) end }), { stripes = true })
requestList.frame:SetPoint("TOPLEFT", requestBox, "TOPLEFT", 6, -8)

-- (officers and the guild master) all requests of the guild, not only mine and the ones I can fulfil; same switch as on the dashboard
local allRequestsCheck = K.NewCheck(panel, "All requests", function(checked)
    ns.DB.showAllRequests = checked
    if ns.UI.RefreshHome then ns.UI.RefreshHome() end
    ns.UI.RefreshRequests()
end)
allRequestsCheck:SetWidth(104)
allRequestsCheck:SetPoint("RIGHT", requestBox, "TOPRIGHT", 0, 11)

local function RefreshRequests()
    local allItems = K.GatherRequests()
    local canAll = ns.CanModerate()
    local showAll = ns.DB.showAllRequests == true and canAll
    local items, can = {}, 0
    for _, item in ipairs(allItems) do
        if item.canFulfill then can = can + 1 end
        if showAll or (item.req and item.req.mine) or item.canFulfill or item.altCanFulfill then items[#items + 1] = item end
    end
    allRequestsCheck:SetShown(canAll)
    allRequestsCheck:SetChecked(ns.DB.showAllRequests == true)
    requestsHeader:SetText(("Requests (%d)%s"):format(#items, can > 0 and ("  |cff40ff40" .. can .. " you can craft|r") or ""))
    if #items == 0 then
        items = { { kind = "note", text = showAll and "Nobody has requested anything yet." or "No requests by you, and none that you can fulfill." } }
    end
    requestList:Render(items, true)
end
ns.UI.RefreshRequests = RefreshRequests

---------------------------------------------------------------------------
-- putting it together
---------------------------------------------------------------------------
RefreshAll = function(keepScroll)
    profList:Render(BuildProfessionItems(), true)
    local items = BuildRecipeItems()
    if #items == 0 then
        items = { { kind = "note", text = "Nothing matches." } }
    end
    itemList:Render(items, keepScroll)
    if state.scrollToSelected and state.selected then
        for i, item in ipairs(items) do
            if item.id == state.selected then itemList:ScrollToIndex(i) break end
        end
        state.scrollToSelected = false
    end
    RefreshDetails()
    RefreshRequests()
end

-- keepScroll: do not make the lists jump when data arrives
function ns.UI.RefreshSweatshop(keepScroll)
    if not root:IsShown() then return end
    if panel:IsShown() then RefreshAll(keepScroll) end
    if ns.UI.RefreshSweatshopTabs then ns.UI.RefreshSweatshopTabs() end
end

-- Open an item (for example from a request): its profession, the item selected and the quantity filled in
function ns.UI.OpenSweatshopRecipe(id, qty)
    local req = ns.Professions.RecipeRequirements({ id })[id]
    state.profession = req and req.key or nil
    state.search = ""
    search:SetText("")
    state.selected = id
    state.qty = math.max(1, math.floor(tonumber(qty) or 1))
    state.scrollToSelected = true
    if ns.UI.SweatshopSelectTab then ns.UI.SweatshopSelectTab("requests") end
    ns.ShowWorkshop()
    RefreshAll()
end

search:SetScript("OnTextChanged", function(self)
    state.search = self:GetText() or ""
    if root:IsShown() and panel:IsShown() then RefreshAll() end
end)
search:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

root:SetScript("OnShow", function()
    ns.RequestRoster()
    ns.UI.RefreshSweatshop()
end)
