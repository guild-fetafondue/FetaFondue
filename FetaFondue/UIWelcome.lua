---@class ns
local ns = select(2, ...)
local K = ns.K
local NewWindow, Gold, Gray, BOX_BACKDROP = K.NewWindow, K.Gold, K.Gray, K.BOX_BACKDROP

---------------------------------------------------------------------------
-- Welcome: shown once on the first run. Explains which of your own windows to open so the addon can
-- read your professions, gear and talents, and shows live what has been picked up so far.
---------------------------------------------------------------------------
-- not closed by Esc or by opening other panels (talents, character...): you are supposed to open those
local win = NewWindow("FetaFondueWelcome", 700, 740, true)
win:SetFrameStrata("FULLSCREEN_DIALOG")
win:SetPoint("CENTER", 0, 0)
win:SetMovable(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:SetTitle("Welcome to FetaFondue")

local intro = win:Text("GameFontHighlight", 30, -50, 640)
intro:SetText("FetaFondue shows what your guild can craft, who is online, how the guild is doing and what your guildmates wear. "
    .. "It learns about you from your own game windows, so please open them once on every character you play. After that it "
    .. "keeps everything up to date and shares it with your guildmates by itself.")

local MEDIA = "Interface\\AddOns\\FetaFondue\\Media\\"
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local OPEN = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t"
local NONE = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"

local function NewCard(y, height)
    local box = CreateFrame("Frame", nil, win, "BackdropTemplate")
    box:SetBackdrop(BOX_BACKDROP)
    box:SetBackdropColor(0.045, 0.045, 0.05, 0.95)
    box:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
    box:SetPoint("TOPLEFT", win, "TOPLEFT", 28, y)
    box:SetSize(644, height)
    return box
end

local function CardImage(card, file)
    local img = card:CreateTexture(nil, "ARTWORK")
    img:SetSize(240, 120)
    img:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -14)
    img:SetTexture(MEDIA .. file)
    return img
end

-- 1. professions ------------------------------------------------------------------
local card1 = NewCard(-118, 292)
CardImage(card1, "welcome_professions.tga")
local title1 = card1:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title1:SetPoint("TOPLEFT", card1, "TOPLEFT", 270, -14)
title1:SetText("1. Open each of your professions")
local body1 = card1:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
body1:SetPoint("TOPLEFT", card1, "TOPLEFT", 270, -42)
body1:SetWidth(360)
body1:SetJustifyH("LEFT")
body1:SetJustifyV("TOP")
body1:SetText("Open your professions window (from your spellbook, or the profession buttons) and click each of your professions, "
    .. "one by one. The game only hands an addon your recipes while that profession's window is open, so every profession "
    .. "has to be opened once. Gathering professions without recipes (Herbalism, Skinning, Fishing) need nothing.")
local status1 = card1:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
status1:SetPoint("TOPLEFT", card1, "TOPLEFT", 16, -146)
status1:SetWidth(610)
status1:SetJustifyH("LEFT")
status1:SetJustifyV("TOP")
status1:SetSpacing(3)

-- Profession Master (optional helper): is it there?
local pmStatus = win:Text("GameFontHighlight", 30, -616, 640)

-- 2. character and talents -----------------------------------------------------------
local card2 = NewCard(-418, 92)
local title2 = card2:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title2:SetPoint("TOPLEFT", card2, "TOPLEFT", 16, -12)
title2:SetText("2. Open your character panel and your talents")
local body2 = card2:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
body2:SetPoint("TOPLEFT", card2, "TOPLEFT", 16, -36)
body2:SetWidth(612)
body2:SetJustifyH("LEFT")
body2:SetText("Press C and open your talents (N) once, and again after you change your talents or switch specialization. "
    .. "Your gear and talents are then shown to guildmates who click on you.")
local status2 = card2:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
status2:SetPoint("TOPLEFT", card2, "TOPLEFT", 16, -68)
status2:SetWidth(612)
status2:SetJustifyH("LEFT")

-- 3. around ----------------------------------------------------------------------------
local card3 = NewCard(-518, 90)
local title3 = card3:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title3:SetPoint("TOPLEFT", card3, "TOPLEFT", 16, -12)
title3:SetText("3. Find your way around")
local body3 = card3:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
body3:SetPoint("TOPLEFT", card3, "TOPLEFT", 16, -36)
body3:SetWidth(612)
body3:SetJustifyH("LEFT")
body3:SetJustifyV("TOP")
body3:SetSpacing(2)
body3:SetText("|cffffd100Dashboard|r  guild numbers, requests, who is online. Click a name to see their gear and talents.\n"
    .. "|cffffd100Sweatshop|r  who can craft what, and ask for items.   |cffffd100Analytics|r  levels, professions, races, roles.\n"
    .. "|cffffd100Events|r  the game calendar.   Type |cff66ccff/ff|r any time to open or close the window.")

-- footer ------------------------------------------------------------------------------------
local go = K.NewButton(win)
go:SetSize(250, 28)
go:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -28, 44)
go:SetText("Got it - open FetaFondue")
local loginCheck = K.NewCheck(win, "Open the window when I log in", function(checked) ns.DB.openOnLogin = checked end)
loginCheck:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 30, 48)
local again = win:Text("GameFontDisableSmall", 28, -712, 644, "CENTER")
again:SetText("You can bring this screen back any time with /ff welcome. What is shared: see the README.")

-- live status -----------------------------------------------------------------------------------
local GATHERING = { [182] = true, [393] = true, [356] = true }   -- Herbalism, Skinning, Fishing: no recipes

local function ProfessionLines()
    local own = ns.GetOwn()
    local list = {}
    if own then
        for key, p in pairs(own.profs) do
            list[#list + 1] = { key = key, name = ns.Professions.ProfessionName(key, p.name), p = p }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    if #list == 0 then
        return Gray("No professions found yet. They show up here as soon as the game has told the addon which ones you have.")
    end
    local lines = {}
    for _, e in ipairs(list) do
        local id = tonumber(e.key)
        local icon = id and ns.PROFESSION_ICONS[id]
        local iconText = icon and ("|T" .. icon .. ":16|t ") or ""
        local state
        if id and GATHERING[id] then
            state = NONE .. " " .. Gray("no recipes to read")
        elseif #e.p.ids > 0 then
            state = CHECK .. " |cff40ff40" .. #e.p.ids .. " recipes read and shared|r"
        else
            state = OPEN .. " |cffffd100open this profession's window|r"
        end
        lines[#lines + 1] = ("%s%s   %s"):format(iconText, e.name, state)
    end
    return table.concat(lines, "\n")
end

local function PMLine()
    if ns.Professions.PMApi() then
        return CHECK .. " |cff40ff40Profession Master found: skill requirements and your known recipes are read from it|r"
    end
    return NONE .. " " .. Gray("Profession Master not found (optional): install it to see the skill every recipe needs")
end

-- gear and talents of this character, as far as the game has told the addon
local function CharacterLine()
    local ok, brief = pcall(ns.Inspect.SelfBrief)
    if not ok or not brief or not brief.ready then return NONE .. " " .. Gray("reading your gear and talents in a moment...") end
    local gear = (brief.items > 0 and CHECK or OPEN) .. (" Gear: %d of 19 slots read"):format(brief.items)
    local talents
    if not brief.talents then
        talents = OPEN .. " |cffffd100open your talents (N)|r"
    else
        talents = CHECK .. " Talents read" .. (brief.tree and (": " .. brief.tree .. (" (%d points)"):format(brief.points)) or "")
    end
    return gear .. "      " .. talents
end

local function Render()
    status1:SetText(ProfessionLines())
    pmStatus:SetText(PMLine())
    status2:SetText(CharacterLine())
    loginCheck:SetChecked(ns.DB.openOnLogin == true)
end

function ns.UI.RefreshWelcome()
    if win:IsShown() then Render() end
end

function ns.UI.ShowWelcome()
    win:Show()
    Render()
end

local function Finish()
    ns.DB.welcomeSeen = true
    win:Hide()
end

go:SetScript("OnClick", function()
    Finish()
    ns.ShowDashboard()       -- the first time, the dashboard opens whatever the login box says
end)
win:SetScript("OnHide", function() ns.DB.welcomeSeen = true end)
win:SetScript("OnShow", Render)

-- what happens when the game starts: the welcome screen once, afterwards the Home page (if enabled)
function ns.UI.ShowOnLogin()
    if not ns.DB.welcomeSeen then
        ns.UI.ShowWelcome()
    elseif ns.DB.openOnLogin then
        ns.ShowDashboard()
    end
end

---------------------------------------------------------------------------
-- A newer version of the addon exists (a guildmate's addon said so): one window, once for each login
---------------------------------------------------------------------------
local upd = NewWindow("FetaFondueUpdate", 440, 230)
upd:SetFrameStrata("FULLSCREEN_DIALOG")
upd:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
upd:SetMovable(true)
upd:RegisterForDrag("LeftButton")
upd:SetScript("OnDragStart", upd.StartMoving)
upd:SetScript("OnDragStop", upd.StopMovingOrSizing)
upd:SetTitle("Update available")
local updHead = upd:Text("GameFontNormalLarge", 24, -46, 392)
updHead:SetTextColor(1, 0.82, 0)
local updBody = upd:Text("GameFontHighlight", 24, -78, 392)
updBody:SetWordWrap(true)
updBody:SetJustifyV("TOP")
updBody:SetSpacing(3)
local updOk = K.NewButton(upd, "Got it")
updOk:SetSize(120, 28)
updOk:SetPoint("BOTTOM", upd, "BOTTOM", 0, 18)
updOk:SetScript("OnClick", function() upd:Hide() end)

function ns.UI.ShowUpdate(newer)
    updHead:SetText("A newer version is out")
    updBody:SetText(("There is a newer version (%s) of FetaFondue compared to yours (%s).\n\n"
        .. "Please go to the fetafondue-addon channel in Discord and download the newest version."):format(tostring(newer), ns.Version()))
    upd:Show()
end
