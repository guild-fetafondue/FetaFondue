---@class ns
local ns = select(2, ...)
ns.UI = ns.UI or {}

local function Gold(s) return "|cffffd100" .. tostring(s) .. "|r" end
local function Gray(s) return "|cff999999" .. tostring(s) .. "|r" end
-- a key combination in a tooltip hint (Click, Shift-click, Right-click): stands out from the grey text
local function Key(s) return "|cff66ccff" .. tostring(s) .. "|r" end

local function Commas(n)
    local str = tostring(math.floor(n or 0))
    local out = str:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
local function Plural(n, one, many) return n == 1 and one or many end
-- "just now", "5 minutes ago", "3 hours ago", "2 days ago" for a unix time
local function AgeText(at)
    if not at then return "" end
    local secs = math.max(0, ns.Time() - at)
    if secs < 10 then return "just now" end
    if secs < 90 then return secs .. " seconds ago" end
    if secs < 5400 then return math.floor(secs / 60 + 0.5) .. " minutes ago" end
    if secs < 129600 then return math.floor(secs / 3600 + 0.5) .. " hours ago" end
    return math.floor(secs / 86400 + 0.5) .. " days ago"
end



-- Flat look: plain dark rectangles with a thin 1-pixel border (no stone frames, no classic buttons)
local FLAT = "Interface\\Buttons\\WHITE8X8"
local WINDOW_BACKDROP = {
    bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
local BOX_BACKDROP = WINDOW_BACKDROP

-- Line / Text / Divider helpers, for windows and for panels
local function InstallLayoutHelpers(frame)
    function frame:Line(font, y, width)
        local fs = self:CreateFontString(nil, "ARTWORK", font)
        fs:SetPoint("TOP", self, "TOP", 0, y)
        fs:SetWidth(width or 330)
        return fs
    end

    -- left-aligned text at an exact position (for column layouts)
    function frame:Text(font, x, y, width, justify)
        local fs = self:CreateFontString(nil, "ARTWORK", font)
        fs:SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
        fs:SetWidth(width)
        fs:SetJustifyH(justify or "LEFT")
        return fs
    end

    -- thin gold line; x1/x2 (from the left edge) default to the full width
    function frame:Divider(y, x1, x2)
        local t = self:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(0.55, 0.45, 0.15, 0.55)
        t:SetHeight(1)
        if x1 and x2 then
            t:SetPoint("TOPLEFT", self, "TOPLEFT", x1, y)
            t:SetPoint("TOPRIGHT", self, "TOPLEFT", x2, y)
        else
            t:SetPoint("TOPLEFT", self, "TOPLEFT", 28, y)
            t:SetPoint("TOPRIGHT", self, "TOPRIGHT", -28, y)
        end
    end
end

-- Flat button: dark rectangle, thin border, lighter on hover. text is optional.
local function NewButton(parent, text)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(100, 24)
    b:SetBackdrop(BOX_BACKDROP)
    b:SetBackdropColor(0.15, 0.15, 0.16, 1)
    b:SetBackdropBorderColor(0.3, 0.3, 0.33, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    b:SetFontString(fs)
    b.label = fs
    local function Paint(self, hover)
        if self.locked then
            self:SetBackdropColor(0.3, 0.26, 0.1, 1)
            self:SetBackdropBorderColor(1, 0.82, 0, 1)
        elseif hover then
            self:SetBackdropColor(0.22, 0.22, 0.24, 1)
            self:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
        else
            self:SetBackdropColor(0.15, 0.15, 0.16, 1)
            self:SetBackdropBorderColor(0.3, 0.3, 0.33, 1)
        end
    end
    b:SetScript("OnEnter", function(self) Paint(self, true) end)
    b:SetScript("OnLeave", function(self) Paint(self, false) end)
    b:SetScript("OnDisable", function() fs:SetTextColor(0.5, 0.5, 0.5) end)
    b:SetScript("OnEnable", function() fs:SetTextColor(1, 1, 1) end)
    function b:LockHighlight() self.locked = true Paint(self, false) end
    function b:UnlockHighlight() self.locked = false Paint(self, false) end
    if text then b:SetText(text) end
    return b
end

-- Flat check box with a label; onChange(checked) is called when it is clicked
local function NewCheck(parent, label, onChange)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(280, 20)
    b.box = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.box:SetSize(16, 16)
    b.box:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.box:SetBackdrop(BOX_BACKDROP)
    b.box:SetBackdropColor(0.04, 0.04, 0.045, 1)
    b.box:SetBackdropBorderColor(0.4, 0.4, 0.44, 1)
    b.mark = b.box:CreateTexture(nil, "OVERLAY")
    b.mark:SetPoint("TOPLEFT", b.box, "TOPLEFT", 3, -3)
    b.mark:SetPoint("BOTTOMRIGHT", b.box, "BOTTOMRIGHT", -3, 3)
    b.mark:SetColorTexture(1, 0.82, 0, 1)
    b.mark:Hide()
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    b.label:SetText(label)
    b.checked = false
    function b:SetChecked(v)
        self.checked = v and true or false
        self.mark:SetShown(self.checked)
    end
    function b:GetChecked() return self.checked end
    b:SetScript("OnEnter", function(self) self.box:SetBackdropBorderColor(1, 0.82, 0, 1) end)
    b:SetScript("OnLeave", function(self) self.box:SetBackdropBorderColor(0.4, 0.4, 0.44, 1) end)
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onChange then onChange(self.checked) end
    end)
    return b
end

-- Real tabs for a page (the look of the Management tabs): each tab has its own outline (left, top, right) standing on a thin
-- line; the open tab is lighter and has the gold line below it, on the base line. strip:AddTab(x, label, width) returns the tab
-- (tab:LockHighlight() marks it open, tab:UnlockHighlight() not).
local function NewTabStrip(parent, y)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(800, 28)
    strip:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y or 0)
    local line = strip:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.3, 0.3, 0.33, 1)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)

    function strip:AddTab(x, label, width)
        local b = CreateFrame("Button", nil, self)
        b:SetSize(width or 112, 28)
        b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 0)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        local edges = {}
        local function Edge(p1, p2, w, h)
            local t = b:CreateTexture(nil, "BORDER")
            t:SetPoint(p1, b, p1, 0, 0)
            t:SetPoint(p2, b, p2, 0, 0)
            if w then t:SetWidth(w) end
            if h then t:SetHeight(h) end
            edges[#edges + 1] = t
        end
        Edge("TOPLEFT", "TOPRIGHT", nil, 1)         -- top
        Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)       -- left
        Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)     -- right
        local bar = b:CreateTexture(nil, "OVERLAY")             -- gold line under the open tab, over the base line
        bar:SetHeight(2)
        bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
        bar:SetColorTexture(1, 0.82, 0, 1)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("CENTER", b, "CENTER", 0, 1)
        b:SetFontString(fs)
        b.label = fs
        local function Paint(self2, hover)
            local er, eg, eb = 0.38, 0.38, 0.42
            if self2.locked then
                bg:SetColorTexture(0.12, 0.12, 0.13, 1)
                er, eg, eb = 0.55, 0.55, 0.6
                bar:Show()
                fs:SetTextColor(1, 0.82, 0)
            else
                bg:SetColorTexture(hover and 0.13 or 0.07, hover and 0.13 or 0.07, hover and 0.14 or 0.075, 1)
                bar:Hide()
                fs:SetTextColor(hover and 1 or 0.65, hover and 1 or 0.65, hover and 1 or 0.65)
            end
            for _, t in ipairs(edges) do t:SetColorTexture(er, eg, eb, 1) end
        end
        b:SetScript("OnEnter", function(self2) Paint(self2, true) end)
        b:SetScript("OnLeave", function(self2) Paint(self2, false) end)
        function b:LockHighlight() self.locked = true Paint(self, false) end
        function b:UnlockHighlight() self.locked = false Paint(self, false) end
        b:SetText(label)
        Paint(b, false)
        return b
    end
    return strip
end

-- Flat text box
local function NewEditBox(name, parent)
    local e = CreateFrame("EditBox", name, parent, "BackdropTemplate")
    e:SetSize(120, 22)
    e:SetBackdrop(BOX_BACKDROP)
    e:SetBackdropColor(0.04, 0.04, 0.045, 1)
    e:SetBackdropBorderColor(0.3, 0.3, 0.33, 1)
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(6, 6, 0, 0)
    e:SetAutoFocus(false)
    return e
end

-- Flat window: dark rectangle, thin border, a slim title bar with the title and an X.
local function NewWindow(name, width, height, noEsc)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetBackdrop(BOX_BACKDROP)
    frame:SetBackdropColor(0.07, 0.07, 0.075, 0.985)
    frame:SetBackdropBorderColor(0.28, 0.28, 0.3, 1)

    -- solid fill (kept as a texture so every window is opaque)
    local solid = frame:CreateTexture(nil, "BACKGROUND")
    solid:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    solid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    solid:SetColorTexture(0.07, 0.07, 0.075, 0.985)
    frame.solid = solid
    frame:Hide()
    if not noEsc then tinsert(UISpecialFrames, name) end -- Esc closes it

    local bar = frame:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    bar:SetHeight(30)
    bar:SetColorTexture(0.1, 0.1, 0.11, 1)
    local barLine = frame:CreateTexture(nil, "ARTWORK")
    barLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -31)
    barLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -31)
    barLine:SetHeight(1)
    barLine:SetColorTexture(0.55, 0.45, 0.15, 0.6)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -9)
    function frame:SetTitle(text) self.title:SetText(text) end

    local close = NewButton(frame, "X")
    close:SetSize(28, 22)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    close:SetBackdropColor(0.1, 0.1, 0.11, 1)
    close:SetBackdropBorderColor(0.1, 0.1, 0.11, 1)
    close:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.15, 0.15, 1) end)
    close:SetScript("OnLeave", function(self) self:SetBackdropColor(0.1, 0.1, 0.11, 1) end)
    close:SetScript("OnClick", function() frame:Hide() end)

    InstallLayoutHelpers(frame)

    return frame
end

-- A plain panel (no border): the pages inside the main window
local function NewPanel(name, parent, width, height)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetSize(width, height)
    InstallLayoutHelpers(frame)
    frame:Hide()
    return frame
end

local function GuildTitle()
    return ns.guildName or ns.GuildName() or ns.GUILD_FALLBACK
end

---------------------------------------------------------------------------
-- Item and recipe details (used by the hover tooltip and the request popup)
---------------------------------------------------------------------------
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- name, icon, quality of an item; asks the game to load it if it is not cached yet
-- Item name, icon and quality. The game loads item data from the server one item at a time, which is why
-- icons used to pop in slowly. So: (1) what the game already knows is used at once, the icon even before the
-- rest (GetItemInfoInstant needs no server), (2) everything the game told us is kept in the saved data and
-- used the next time before the game answers, (3) each missing item is asked for once, not on every redraw,
-- and (4) K.PreloadItems asks for all the items of known recipes in the background.
local memo = {}          -- this session: [itemID] = { name, icon, quality }
local requested = {}     -- [itemID] = when it was last asked for
local ITEM_CACHE_MAX = 4000

local function ItemData(itemID)
    if not itemID then return nil end
    local m = memo[itemID]
    if m then return m.name, m.icon, m.quality end
    local name, quality, icon
    pcall(function()
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local n, _, q, _, _, _, _, _, _, tex = getInfo(itemID)
        name, quality, icon = n, q, tex
        if not icon then
            if C_Item and C_Item.GetItemInfoInstant then icon = select(5, C_Item.GetItemInfoInstant(itemID)) end
            if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(itemID)
            elseif not icon and GetItemIcon then icon = GetItemIcon(itemID) end
        end
    end)
    local cache = ns.DB and ns.DB.itemCache
    local saved = cache and cache[itemID]
    if name and icon and quality then
        memo[itemID] = { name = name, icon = icon, quality = quality }
        if cache and (not saved or saved.n ~= name or saved.i ~= icon or saved.q ~= quality) then
            if saved or (ns.DB.itemCacheCount or 0) < ITEM_CACHE_MAX then
                if not saved then ns.DB.itemCacheCount = (ns.DB.itemCacheCount or 0) + 1 end
                cache[itemID] = { n = name, i = icon, q = quality }
            end
        end
        return name, icon, quality
    end
    -- not complete yet: fill the gaps from the saved copy, and ask the game once
    if saved then
        name, icon, quality = name or saved.n, icon or saved.i, quality or saved.q
    end
    local now = ns.Now and ns.Now() or 0
    if not (requested[itemID] and now - requested[itemID] < 60) then
        requested[itemID] = now
        pcall(function()
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        end)
    end
    return name, icon, quality
end

-- ask the game for the items of every recipe we know (results, materials), a few at a time
local preloading = false
local function PreloadItems()
    if preloading or not ns.DB then return end
    local ids, seen = {}, {}
    local function Add(id)
        if id and not seen[id] and not memo[id] then seen[id] = true ids[#ids + 1] = id end
    end
    for _, info in pairs(ns.DB.recipeInfo or {}) do
        Add(info.item)
        for _, r in ipairs(info.reagents or {}) do Add(r.id) end
    end
    if #ids == 0 then return end
    preloading = true
    local i = 1
    local function Step()
        for _ = 1, 12 do
            if i > #ids then preloading = false return end
            ItemData(ids[i])
            i = i + 1
        end
        ns.After(0.3, Step)
    end
    Step()
end

local function RecipeIcon(recipeID, info, fallback)
    if info and info.icon then return info.icon end
    if info and info.item then
        local _, icon = ItemData(info.item)
        if icon then return icon end
    end
    local icon
    pcall(function()
        if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(recipeID)
        elseif GetSpellTexture then icon = GetSpellTexture(recipeID) end
        if not icon and C_Spell and C_Spell.GetSpellInfo then
            local si = C_Spell.GetSpellInfo(recipeID)
            icon = si and (si.iconID or si.originalIconID)
        end
        if not icon and C_Spell and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(recipeID) end
    end)
    local cache = ns.DB and ns.DB.iconCache
    if icon then
        if cache and cache[recipeID] ~= icon then cache[recipeID] = icon end
        return icon
    end
    return (cache and cache[recipeID]) or fallback or QUESTION
end

local function MaterialLines(info)
    local out = {}
    for _, r in ipairs(info.reagents or {}) do
        local name, icon = ItemData(r.id)
        out[#out + 1] = ("|T%s:14|t %s × %s"):format(icon or QUESTION, Gold(r.count), name or ("item " .. r.id))
    end
    return out
end

-- Recipe names in the color of the item they make (gray, white, green, blue, purple, orange...).
local QUALITY_HEX = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
    [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff",
}
local function ColoredRecipeName(recipeID, name)
    local info = ns.RecipeInfo(recipeID)
    if info and info.item then
        local _, _, quality = ItemData(info.item)
        if quality == nil and C_Item and C_Item.GetItemQualityByID then
            pcall(function() quality = C_Item.GetItemQualityByID(info.item) end)
        end
        local hex = quality and QUALITY_HEX[quality]
        if hex then return "|cff" .. hex .. name .. "|r" end
    end
    return name
end

local function TotalsHeader(qty, crafts, made)
    if made > 1 then
        return ("Materials for %d (%d %s, %d per craft):"):format(qty, crafts, crafts == 1 and "craft" or "crafts", made)
    end
    return ("Materials for %d:"):format(qty)
end

-- A real item link for a material, so it can go into chat or the auction house search.
local function ItemLinkFor(itemID, name)
    local link
    pcall(function()
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local _, l = getInfo(itemID)
        link = l
    end)
    return link or ("|cffffffff|Hitem:%d|h[%s]|h|r"):format(itemID, name or ("item " .. itemID))
end

local function Shifted()
    return (IsModifiedClick and IsModifiedClick("CHATLINK")) or IsShiftKeyDown()
end

-- A recipe link: others can hover it to see what it makes and needs.
local function RecipeLinkFor(recipeID, name)
    local link
    pcall(function()
        if C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink then link = C_TradeSkillUI.GetRecipeLink(recipeID) end
    end)
    return link or ("|cffffd000|Henchant:%d|h[%s]|h|r"):format(recipeID, name or ("recipe " .. recipeID))
end

local function OpenChatWith(text)
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(text)
    elseif ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(text)
    end
end

-- text goes into the chat box if one is open; otherwise a plain item link may go into the auction
-- house search; otherwise the chat box is opened with the text in it.
local function SendToChat(text, plainItemLink)
    local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if box then
        ChatEdit_InsertLink(text)
        return
    end
    if plainItemLink and HandleModifiedItemClick and HandleModifiedItemClick(plainItemLink) then return end
    OpenChatWith(text)
end

local function WithAmount(count, link)
    if count and count > 0 then return ("%dx %s"):format(count, link) end
    return link
end

-- Shift-click on a material: the item link into chat, or the item into the auction house search.
local function LinkMaterial(itemID, name, count)
    if not Shifted() then return end
    local link = ItemLinkFor(itemID, name)
    SendToChat(link, link)      -- just the item: an amount in front would break a search in the auction house
end

-- Shift-click on a recipe: the recipe link; Ctrl+Shift: the item it makes.
local function LinkRecipe(recipeID, name, qty)
    local info = ns.RecipeInfo(recipeID)
    if IsControlKeyDown and IsControlKeyDown() and info and info.item then
        local itemName = ItemData(info.item)
        local link = ItemLinkFor(info.item, itemName or name)
        SendToChat(link, link)
    else
        SendToChat(RecipeLinkFor(recipeID, name))
    end
end

-- Header and lines for "materials needed for N items" (reagents per craft x crafts needed).
local function TotalsText(info, qty)
    local list, crafts, made = ns.TotalMaterials(info, qty)
    local header = TotalsHeader(qty, crafts, made)
    local lines = {}
    for _, r in ipairs(list) do
        local name, icon = ItemData(r.id)
        lines[#lines + 1] = ("|T%s:14|t %s × %s"):format(icon or QUESTION, Gold(r.count), name or ("item " .. r.id))
    end
    return header, lines
end

-- Fills a tooltip: the crafted item's own tooltip (stats) and the materials needed.
-- Details come from our saved data (read from profession windows, shared in the guild). If we do not
-- have them yet, the game's own recipe tooltip is tried and the guild is asked.
local function FillRecipeTooltip(tip, recipeID, name)
    local info = ns.RecipeInfo(recipeID)
    tip:ClearLines()

    if info and info.item then
        pcall(tip.SetItemByID, tip, info.item)
        if (tip:NumLines() or 0) == 0 then pcall(tip.SetHyperlink, tip, "item:" .. info.item) end
    end
    if (tip:NumLines() or 0) == 0 then
        if info then
            pcall(tip.SetSpellByID, tip, recipeID)                      -- enchants and other recipes without an item
        else
            pcall(tip.SetHyperlink, tip, "enchant:" .. recipeID)        -- the game's own recipe tooltip
            if (tip:NumLines() or 0) == 0 then pcall(tip.SetSpellByID, tip, recipeID) end
        end
    end
    if (tip:NumLines() or 0) == 0 then tip:SetText(name or ns.RecipeName(recipeID), 1, 0.82, 0) end

    if info and #info.reagents > 0 then
        tip:AddLine(" ")
        tip:AddLine("Materials:", 1, 0.82, 0)
        for _, line in ipairs(MaterialLines(info)) do tip:AddLine(line, 1, 1, 1) end
    elseif not info then
        tip:AddLine(" ")
        tip:AddLine("Asking guildmates for the item details", 0.6, 0.6, 0.6)
        if ns.Sync then ns.Sync.RequestRecipeInfo(recipeID) end
    end
    tip:Show()
    return true
end

-- Hovering a recipe row: the tooltip stays in sync if details arrive while it is open.
local hover
local function ShowRecipeHover(row, recipeID, name, hint, qty)
    hover = { row = row, id = recipeID, name = name, hint = hint, qty = qty }
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    FillRecipeTooltip(GameTooltip, recipeID, name)
    local info = ns.RecipeInfo(recipeID)
    if qty and info and #info.reagents > 0 then
        local header, lines = TotalsText(info, qty)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(header, 1, 0.82, 0)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 1, 1, 1) end
    end
    if hint then
        GameTooltip:AddLine(" ")
        -- one short line per hint (a table of lines), long text wraps; never one very wide line
        for _, line in ipairs(type(hint) == "table" and hint or { hint }) do
            GameTooltip:AddLine(line, 0.6, 0.6, 0.6, true)
        end
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Scrolling list (rows are reused, so long lists stay cheap)
---------------------------------------------------------------------------
local scrollCount = 0
-- opts.stripes: every second row has a slightly lighter background (easier to follow a line across)
local function CreateScrollList(parent, width, height, rowHeight, renderRow, opts)
    opts = opts or {}
    scrollCount = scrollCount + 1
    local sf = CreateFrame("ScrollFrame", "FetaFondueScroll" .. scrollCount, parent)
    sf.stripes = opts.stripes == true
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur, max = tonumber(self:GetVerticalScroll()) or 0, tonumber(self:GetVerticalScrollRange()) or 0
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * rowHeight * 3)))
    end)

    -- slim scroll bar to the right of the list
    local track = CreateFrame("Frame", nil, parent)
    track:SetSize(6, height)
    if opts.insideTrack then
        track:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -1, 0)        -- (on top of the end of the rows: they reach the end of the box)
        track:SetFrameLevel(sf:GetFrameLevel() + 5)
    else
        track:SetPoint("TOPLEFT", sf, "TOPRIGHT", 8, 0)
    end
    local trackBG = track:CreateTexture(nil, "BACKGROUND")
    trackBG:SetAllPoints()
    trackBG:SetColorTexture(0.1, 0.1, 0.11, 1)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetSize(6, 30)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(0.4, 0.4, 0.43, 1)
    track:Hide()

    local function UpdateThumb()
        local range = tonumber(sf:GetVerticalScrollRange()) or 0
        if range <= 0 then track:Hide() return end
        track:Show()
        local thumbH = math.max(24, height * height / (height + range))
        thumb:SetHeight(thumbH)
        local pos = (tonumber(sf:GetVerticalScroll()) or 0) / range
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -pos * (height - thumbH))
    end
    sf:SetScript("OnVerticalScroll", UpdateThumb)
    sf:SetScript("OnScrollRangeChanged", UpdateThumb)
    -- drag the thumb
    thumb:SetScript("OnMouseDown", function(self)
        local _, y = GetCursorPosition()
        self.dragY, self.dragScroll = y / UIParent:GetEffectiveScale(), tonumber(sf:GetVerticalScroll()) or 0
        self:SetScript("OnUpdate", function(btn)
            local _, cy = GetCursorPosition()
            cy = cy / UIParent:GetEffectiveScale()
            local range = tonumber(sf:GetVerticalScrollRange()) or 0
            local travel = math.max(1, height - btn:GetHeight())
            sf:SetVerticalScroll(math.max(0, math.min(range, btn.dragScroll + (btn.dragY - cy) / travel * range)))
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

    sf:SetSize(width, height)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width, 1)
    sf:SetScrollChild(content)

    local list = { frame = sf, rows = {} }

    local function GetRow(i)
        local row = list.rows[i]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * rowHeight)
            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints()
            row.stripe:SetColorTexture(1, 1, 1, 0.045)
            row.stripe:Hide()
            row.sel = row:CreateTexture(nil, "BACKGROUND")      -- (the row of the open item: item.selected)
            row.sel:SetAllPoints()
            row.sel:SetColorTexture(1, 0.82, 0, 0.16)
            row.sel:Hide()
            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.hl = row:CreateTexture(nil, "HIGHLIGHT")
            row.hl:SetAllPoints()
            row.hl:SetColorTexture(1, 0.82, 0, 0.15)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if self.onRightClick then self.onRightClick(self) end
                    return
                end
                if self.onClick then self.onClick(self) end
            end)
            row:SetScript("OnEnter", function(self)
                if self.onEnter then self.onEnter(self) end
            end)
            row:SetScript("OnLeave", function()
                hover = nil
                GameTooltip:Hide()
            end)
            list.rows[i] = row
        end
        return row
    end

    function list:ScrollToIndex(i)
        local target = math.max(0, (i - 2) * rowHeight)
        local maxScroll = sf:GetVerticalScrollRange() or 0
        sf:SetVerticalScroll(math.min(target, maxScroll))
    end

    -- an item may have a height of its own (item.height); all others use the row height of the list
    function list:Render(items, keepScroll)
        local y = 0
        for i, item in ipairs(items) do
            local row = GetRow(i)
            local h = item.height or rowHeight
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            row:SetHeight(h)
            y = y + h
            row:Show()
            row.onClick, row.onEnter, row.onRightClick = nil, nil, nil
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            if row.remove then row.remove:Hide() end
            row.stripe:SetShown(opts.stripes == true and i % 2 == 0)
            row.sel:SetShown(item.selected == true)
            renderRow(row, item)
        end
        for i = #items + 1, #self.rows do self.rows[i]:Hide() end
        content:SetHeight(math.max(1, y))
        if not keepScroll then sf:SetVerticalScroll(0) end
        UpdateThumb()
    end

    return list
end


-- the tooltip of the recipe row under the mouse updates when details arrive
local function RefreshHover(id)
    if hover and hover.row:IsShown() and (id == nil or hover.id == id) then
        ShowRecipeHover(hover.row, hover.id, hover.name, hover.hint, hover.qty)
    end
end

-- windows that must close together with the main window
local closers = {}
local function RegisterCloser(fn) closers[#closers + 1] = fn end

-- "Label: Anna, Bob, Cleo  +4" cut so that it fits a line: the names are added while there is room (measured with a
-- hidden text of the same font), the rest is counted
local function FitList(measure, prefix, names, maxWidth)
    for i = 1, #names do
        measure:SetText(prefix .. table.concat(names, ", ", 1, i) .. (i < #names and ("  +" .. (#names - i)) or ""))
        if (measure:GetStringWidth() or 0) > maxWidth then
            if i == 1 then return prefix .. names[1] end
            return prefix .. table.concat(names, ", ", 1, i - 1) .. "|cff999999  +" .. (#names - i + 1) .. "|r"
        end
    end
    return prefix .. table.concat(names, ", ")
end
local function CloseAll() for _, fn in ipairs(closers) do fn() end end

-- A slim scroll bar (a track and a thumb you can drag) for a scroll frame; it only shows when there is something to scroll.
-- The track is put at (x, y) from the top right corner of "parent".
local function AttachScrollbar(sf, parent, height, x, y)
    local track = CreateFrame("Frame", nil, parent)
    track:SetSize(6, height)
    track:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, y)
    local trackBG = track:CreateTexture(nil, "BACKGROUND")
    trackBG:SetAllPoints()
    trackBG:SetColorTexture(0.1, 0.1, 0.11, 1)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetSize(6, 30)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(0.4, 0.4, 0.43, 1)
    track:Hide()
    local function Update()
        local range = tonumber(sf:GetVerticalScrollRange()) or 0
        if range <= 0 then track:Hide() return end
        track:Show()
        local view = tonumber(sf:GetHeight()) or height
        local thumbH = math.max(24, height * view / (view + range))
        thumb:SetHeight(thumbH)
        local pos = (tonumber(sf:GetVerticalScroll()) or 0) / range
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -pos * (height - thumbH))
    end
    sf:SetScript("OnVerticalScroll", Update)
    sf:SetScript("OnScrollRangeChanged", Update)
    thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        self.dragY, self.dragScroll = cy / UIParent:GetEffectiveScale(), tonumber(sf:GetVerticalScroll()) or 0
        self:SetScript("OnUpdate", function(btn)
            local _, cy2 = GetCursorPosition()
            cy2 = cy2 / UIParent:GetEffectiveScale()
            local range = tonumber(sf:GetVerticalScrollRange()) or 0
            local travel = math.max(1, height - btn:GetHeight())
            sf:SetVerticalScroll(math.max(0, math.min(range, btn.dragScroll + (btn.dragY - cy2) / travel * range)))
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    return Update, track
end

-- A visible cursor for an edit box: the game's own one is hard to see on our dark boxes. While the box has the focus its frame
-- turns gold and a thin gold cursor blinks where the typing goes (the box tells where with OnCursorChanged). frame: what gets the
-- gold border (the box itself when nothing else is given). The box's own scripts are not replaced (HookScript), and the blinking is
-- done by a frame of its own, so nothing of this touches how the box handles the mouse and the keys.
local function AttachCaret(edit, frame)
    frame = frame or edit
    local caret = edit:CreateTexture(nil, "OVERLAY")
    caret:SetColorTexture(1, 0.82, 0, 1)
    caret:SetSize(2, 14)
    caret:Hide()
    edit.caret = caret
    local blinker = CreateFrame("Frame")
    local focused, blink = false, 0
    local normal = { 0.22, 0.22, 0.25, 1 }
    local function Hook(name, fn)
        if edit.HookScript then
            edit:HookScript(name, fn)
        else
            local old = edit.GetScript and edit:GetScript(name)
            edit:SetScript(name, function(...) if old then old(...) end fn(...) end)
        end
    end
    Hook("OnCursorChanged", function(self, x, y, w, h)
        caret:ClearAllPoints()
        caret:SetPoint("TOPLEFT", edit, "TOPLEFT", tonumber(x) or 0, tonumber(y) or 0)
        caret:SetSize(2, tonumber(h) or 14)
        blink = 0
        if focused then caret:Show() end
    end)
    Hook("OnEditFocusGained", function()
        focused, blink = true, 0
        caret:Show()
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(1, 0.82, 0, 1) end
        blinker:SetScript("OnUpdate", function(self, elapsed)
            blink = blink + (elapsed or 0)
            if blink >= 1 then blink = 0 end
            caret:SetShown(blink < 0.6)
        end)
    end)
    Hook("OnEditFocusLost", function()
        focused = false
        caret:Hide()
        blinker:SetScript("OnUpdate", nil)
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(normal[1], normal[2], normal[3], normal[4]) end
    end)
    edit.blinker = blinker
end

-- A question with Yes and No in a window of our own (nothing of the game's popups): Confirm(title, text, onYes, yesText, noText).
-- onYes runs inside the click on Yes, so it still counts as the player's own action.
local confirmWin, confirmText, confirmYes, confirmNo, confirmAction
local function Confirm(title, text, onYes, yesText, noText)
    if not confirmWin then
        confirmWin = NewWindow("FetaFondueConfirm", 420, 150)
        -- above every other window (a window that opens it, like the raid window, is in the fullscreen layer: its content would
        -- otherwise draw over this window's background)
        confirmWin:SetFrameStrata("TOOLTIP")
        confirmWin:SetFrameLevel(100)
        confirmWin:SetPoint("CENTER", UIParent, "CENTER", 0, 90)
        confirmText = confirmWin:Text("GameFontHighlight", 24, -52, 372, "CENTER")
        confirmText:SetWordWrap(true)
        confirmYes = NewButton(confirmWin, "Yes")
        confirmYes:SetSize(120, 28)
        confirmYes:SetPoint("BOTTOMRIGHT", confirmWin, "BOTTOM", -8, 18)
        confirmNo = NewButton(confirmWin, "No")
        confirmNo:SetSize(120, 28)
        confirmNo:SetPoint("BOTTOMLEFT", confirmWin, "BOTTOM", 8, 18)
        confirmYes:SetScript("OnClick", function()
            local action = confirmAction
            confirmAction = nil
            confirmWin:Hide()
            if action then action() end
        end)
        confirmNo:SetScript("OnClick", function()
            confirmAction = nil
            confirmWin:Hide()
        end)
        confirmWin:SetScript("OnHide", function() confirmAction = nil end)
    end
    confirmWin:SetTitle(title or "")
    confirmText:SetText(text or "")
    confirmYes:SetText(yesText or "Yes")
    confirmNo:SetText(noText or "No")
    confirmAction = onYes
    confirmWin:Show()
end

ns.K = {
    Confirm = Confirm,
    AttachScrollbar = AttachScrollbar,
    AttachCaret = AttachCaret,
    Gold = Gold,
    Gray = Gray,
    Commas = Commas,
    Plural = Plural,
    AgeText = AgeText,
    InstallLayoutHelpers = InstallLayoutHelpers,
    NewWindow = NewWindow,
    NewPanel = NewPanel,
    Key = Key,
    GuildTitle = GuildTitle,
    ItemData = ItemData,
    RecipeIcon = RecipeIcon,
    MaterialLines = MaterialLines,
    ColoredRecipeName = ColoredRecipeName,
    TotalsHeader = TotalsHeader,
    ItemLinkFor = ItemLinkFor,
    Shifted = Shifted,
    RecipeLinkFor = RecipeLinkFor,
    OpenChatWith = OpenChatWith,
    SendToChat = SendToChat,
    WithAmount = WithAmount,
    LinkMaterial = LinkMaterial,
    LinkRecipe = LinkRecipe,
    TotalsText = TotalsText,
    FillRecipeTooltip = FillRecipeTooltip,
    ShowRecipeHover = ShowRecipeHover,
    CreateScrollList = CreateScrollList,
    WINDOW_BACKDROP = WINDOW_BACKDROP,
    BOX_BACKDROP = BOX_BACKDROP,
    QUESTION = QUESTION,
    QUALITY_HEX = QUALITY_HEX,
    RefreshHover = RefreshHover,
    RegisterCloser = RegisterCloser,
    FitList = FitList,
    CloseAll = CloseAll,
    NewButton = NewButton,
    NewCheck = NewCheck,
    NewTabStrip = NewTabStrip,
    PreloadItems = PreloadItems,
    NewEditBox = NewEditBox,
}
