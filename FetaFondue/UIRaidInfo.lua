---@class ns
local ns = select(2, ...)
local K = ns.K
local NewWindow, Gray, ClassColored = K.NewWindow, K.Gray, K.ClassColored
local R = ns.Raids

---------------------------------------------------------------------------
-- The raid window: everything about one raid, laid out like the message that Raid-Helper makes in Discord (the guild
-- is used to it): the title, the description, who organizes it and when, the roles, the sign-ups by class (and the
-- Tank slot), and at the bottom bench, late, tentative and absence. Characters are shown, not Discord names.
-- Opened from the dashboard, from the Events tab and from the 15 minute reminder.
--
-- And the reminder window: 15 minutes before a raid that I (or an alt) signed up for, when the game is calm.
---------------------------------------------------------------------------
local win = NewWindow("FetaFondueRaidInfo", 700, 660)
win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
win:SetMovable(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:SetTitle("Raid")

-- "Invite all" (officers and the guild master): invites everybody who signed up and is online (Invite.lua)
local currentRec = nil
local titleFS                 -- (the title of the raid, made below: the button takes room from it)
-- on the row of the title, at the right, and easy to see (the gold highlight of a pressed button)
local inviteButton = K.NewButton(win, "Invite all")
inviteButton:SetSize(170, 30)
inviteButton:SetPoint("TOPRIGHT", win, "TOPRIGHT", -24, -46)
inviteButton:LockHighlight()
local inviteStatus = win:Text("GameFontDisableSmall", 256, -80, 420, "RIGHT")

-- The game does not let an addon write in the guild chat (it blocks the call), so the line is put in the chat box, ready: one Enter sends it.
local function PrepareGuildLine(text)
    if K.OpenChatWith then
        K.OpenChatWith("/g " .. text)
        return true
    end
    return false
end

local chatNote = nil           -- what the player has to do about the guild chat line
local function RefreshInvite()
    local rec = currentRec
    local I = ns.Invite
    local show = rec ~= nil and ns.CanModerate() and rec.start + 3 * 3600 >= ns.Time()
    inviteButton:SetShown(show)
    inviteStatus:SetShown(show)
    if titleFS then titleFS:SetWidth(show and 460 or 650) end        -- (a long title does not run under the button)
    if not show then return end
    local st = I.State()
    if st.running and st.raidId ~= rec.id then
        inviteButton:SetEnabled(false)
        inviteButton:SetText("Invite all")
        inviteStatus:SetText(Gray("Inviting for another raid"))
    elseif st.running then
        inviteButton:SetEnabled(true)
        inviteButton:SetText(st.mode == "manual" and ("Invite next (%d left)"):format(st.left) or ("Stop (%d left)"):format(st.left))
        local text = st.mode == "manual" and "One invite for each click" or ("Invited %d of %d"):format(st.invited, st.total)
        inviteStatus:SetText(Gray(text) .. (I.note and ("  |cffff9a3c" .. I.note .. "|r") or "") .. (chatNote and ("  |cffffd100" .. chatNote .. "|r") or ""))
    else
        inviteButton:SetEnabled(true)            -- (always: with nobody online the click says so)
        inviteButton:SetText("Invite all")
        -- only what happened last is shown (nothing is written in the chat); how many are invited is in the question that comes first
        local parts = {}
        if I.message then parts[#parts + 1] = "|cffffd100" .. I.message .. "|r" end
        if I.note then parts[#parts + 1] = "|cffff9a3c" .. I.note .. "|r" end
        if chatNote then parts[#parts + 1] = "|cffffd100" .. chatNote .. "|r" end
        inviteStatus:SetText(table.concat(parts, "  "))
    end
end

-- hovering the button shows who is invited and who is not, and why
inviteButton:SetScript("OnEnter", function(self)
    if not currentRec then return end
    local I = ns.Invite
    local plan = I.State().running and I.State().plan or I.Plan(currentRec)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Invite everybody who signed up and is online", 1, 0.82, 0)
    for _, line in ipairs(I.Details(plan)) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
end)
inviteButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- the first click asks, in a window of our own; Yes starts the invites at once (the first one goes out with that click) and
-- writes one line in the guild chat
inviteButton:SetScript("OnClick", function()
    local I = ns.Invite
    local rec = currentRec
    if I.State().running then
        I.Click()
        RefreshInvite()
        return
    end
    local plan = I.Plan(rec)
    if #plan.list == 0 then
        I.message = "Nobody to invite. (Nobody who signed up is online and free to invite.)"
        RefreshInvite()
        return
    end
    local n = #plan.list
    K.Confirm("Invite all", ("You are about to invite %d %s. Are you sure?"):format(n, n == 1 and "person" or "people"), function()
        chatNote = nil
        local ok, why = I.Start(rec)
        if not ok then
            I.message = why
        else
            local title = tostring(rec.title or ""):sub(1, 60)
            if PrepareGuildLine(("Invites starting for %s. If you've signed up and not on your main character, whisper me for an invite after relogging."):format(title)) then
                chatNote = "Press Enter to post the line in the guild chat."
            end
        end
        RefreshInvite()
    end)
end)
ns.Invite.OnChanged = RefreshInvite

-- a thin stripe in the colour of the event on the left (like the stripe of the message in Discord); the background is the addon's own
local stripe = win:CreateTexture(nil, "OVERLAY")
stripe:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -38)
stripe:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 12)
stripe:SetWidth(4)
stripe:SetColorTexture(0.9, 0.2, 0.2, 1)

local scroll = CreateFrame("ScrollFrame", "FetaFondueRaidInfoScroll", win)
scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 28, -48)
scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -20, 20)
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(self, delta)
    local cur, max = tonumber(self:GetVerticalScroll()) or 0, tonumber(self:GetVerticalScrollRange()) or 0
    self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 40)))
end)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(650, 10)
scroll:SetScrollChild(content)

-- the title has a font of its own
titleFS = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
titleFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
titleFS:SetWidth(650)
titleFS:SetJustifyH("LEFT")
titleFS:SetWordWrap(false)
pcall(titleFS.SetFont, titleFS, "Fonts\\MORPHEUS.TTF", 28, "")
titleFS:SetTextColor(1, 1, 1)
titleFS.isTitle = true

-- text cells and pictures are reused: everything sits on a grid (columns at fixed x, rows at fixed steps)
local pool, used = {}, 0
local function Cell(template, x, y, width, justify, wrap)
    used = used + 1
    local fs = pool[used]
    if not fs then
        fs = content:CreateFontString(nil, "ARTWORK", template)
        pool[used] = fs
    end
    fs:SetFontObject(template)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(wrap == true)
    fs:SetSpacing(2)
    fs:Show()
    return fs
end

local texPool, texUsed = {}, 0
local function Tex(x, y, w, h)
    texUsed = texUsed + 1
    local t = texPool[texUsed]
    if not t then
        t = content:CreateTexture(nil, "ARTWORK")
        texPool[texUsed] = t
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    t:SetSize(w, h)
    t:SetTexCoord(0, 1, 0, 1)
    t:SetVertexColor(1, 1, 1, 1)
    t:Show()
    return t
end

-- a picture from a path or a file id; a path the game does not know shows nothing (no green square)
local function Icon(path, x, y, size)
    local t = Tex(x, y, size, size)
    if type(path) == "string" and C_Texture and C_Texture.GetFileIDFromPath then
        local ok, id = pcall(C_Texture.GetFileIDFromPath, path)
        if ok and not id then t:Hide() return t end
    end
    t:SetTexture(path)
    return t
end

-- a plain coloured rectangle (a number's box, an underline)
local function Box(x, y, w, h, r, g, b, a)
    local t = Tex(x, y, w, h)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- the width of a text (measured when the game can)
local measure = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
measure:SetAlpha(0)
local function TextWidth(text)
    measure:SetText(text)
    local w = measure.GetStringWidth and measure:GetStringWidth() or 0
    if type(w) ~= "number" or w <= 0 then w = #text * 6.5 end
    return w
end

-- how tall a wrapped text is (measured when the game can, else guessed from the number of characters per line)
local function TextHeight(fs, plain, charsPerLine, lineHeight)
    local h = fs.GetStringHeight and fs:GetStringHeight() or 0
    if type(h) ~= "number" or h <= 0 then
        h = math.max(1, math.ceil(#plain / charsPerLine)) * lineHeight
    end
    return h
end

---------------------------------------------------------------------------
-- the pictures (the game's own icons; the spec icons are the classic talent trees)
---------------------------------------------------------------------------
local ICON = "Interface\\Icons\\"
local INFO_ICON = {
    leader = "Interface\\GroupFrame\\UI-Group-LeaderIcon", raid = ICON .. "INV_Misc_GroupNeedMore", date = ICON .. "INV_Misc_Note_06",
    clock = ICON .. "INV_Misc_PocketWatch_01", ago = ICON .. "Spell_Nature_TimeStop",
}
local ROLE_ICON = {
    T = ICON .. "Ability_Defend", M = ICON .. "Ability_MeleeDamage", R = ICON .. "Ability_Marksmanship", H = ICON .. "Spell_Holy_FlashHeal",
    D = ICON .. "Ability_MeleeDamage",
}
local STATE_ICON = {
    bench = ICON .. "Spell_Nature_Sleep", late = ICON .. "INV_Misc_PocketWatch_01",
    tentative = "Interface\\RAIDFRAME\\ReadyCheck-Waiting", absent = "Interface\\RAIDFRAME\\ReadyCheck-NotReady",
}
local CLASS_ICON = {
    WARRIOR = 626008, PALADIN = 626003, HUNTER = 626000, ROGUE = 626005, PRIEST = 626004, SHAMAN = 626006, MAGE = 626001,
    WARLOCK = 626007, DRUID = 625999, TANK = ICON .. "Ability_Defend",
}
local SPEC_ICON = {
    WARRIOR = { arms = "Ability_Rogue_Eviscerate", fury = "Ability_Warrior_InnerRage", protection = "INV_Shield_06" },
    PALADIN = { holy = "Spell_Holy_HolyBolt", protection = "Spell_Holy_DevotionAura", retribution = "Spell_Holy_AuraOfLight" },
    HUNTER = { beastmastery = "Ability_Hunter_BeastTaming", marksmanship = "Ability_Marksmanship", survival = "Ability_Hunter_SwiftStrike" },
    ROGUE = { assassination = "Ability_Rogue_Eviscerate", combat = "Ability_BackStab", subtlety = "Ability_Stealth" },
    PRIEST = { discipline = "Spell_Holy_WordFortitude", holy = "Spell_Holy_HolyBolt", shadow = "Spell_Shadow_ShadowWordPain", smite = "Spell_Holy_HolySmite" },
    SHAMAN = { elemental = "Spell_Nature_Lightning", enhancement = "Spell_Nature_LightningShield", restoration = "Spell_Nature_MagicImmunity" },
    MAGE = { arcane = "Spell_Holy_MagicalSentry", fire = "Spell_Fire_FireBolt02", frost = "Spell_Frost_FrostBolt02" },
    WARLOCK = { affliction = "Spell_Shadow_DeathCoil", demonology = "Spell_Shadow_Metamorphosis", destruction = "Spell_Shadow_RainOfFire" },
    DRUID = { balance = "Spell_Nature_StarFall", feral = "Ability_Racial_BearForm", guardian = "Ability_Racial_BearForm", restoration = "Spell_Nature_HealingTouch", dreamstate = "Spell_Nature_HealingTouch" },
}
-- the icon of a sign-up's specialization; the class icon when the spec is not known
local function SpecIcon(class, spec)
    local list = SPEC_ICON[class or ""]
    local name = list and list[(spec or ""):lower():gsub("%d+$", "")]
    if name then return ICON .. name end
    return CLASS_ICON[class or ""]
end
ns.UI.RaidSpecIcon = SpecIcon

local COLS = { 0, 220, 440 }           -- the three columns of the window
local ROW = 20                         -- one row of names
local GROUP_ORDER = { "TANK", "WARRIOR", "DRUID", "PALADIN", "ROGUE", "HUNTER", "PRIEST", "MAGE", "WARLOCK", "SHAMAN" }
local ROLE_NAMES = { T = "Tanks", M = "Melee", R = "Ranged", H = "Healers" }
local STATE_LINES = { { "bench", "Bench" }, { "late", "Late" }, { "tentative", "Tentative" }, { "absent", "Absence" } }

local function GroupLabel(key)
    if key == "TANK" then return "Tank" end
    if key == "" then return "Signed up" end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[key]) or (key:sub(1, 1) .. key:sub(2):lower())
end

-- the number of a sign-up in its little dark box; returns the width of the box
local function NumberBox(x, y, p, minWidth)
    local text = p and p > 0 and tostring(p) or ""
    local w = math.max(minWidth or 22, TextWidth(text) + 10)
    Box(x, y, w, 16, 0.17, 0.18, 0.21)
    local n = Cell("GameFontHighlightSmall", x, y + 1, w, "CENTER")
    n:SetText(text)
    return w
end

-- a line of text with a thin line under it (Discord underlines its headers and links)
local function Underlined(template, x, y, width, text)
    local fs = Cell(template, x, y, width)
    fs:SetText(text)
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    Box(x, y + 15, math.min(width, TextWidth(plain)), 1, 0.8, 0.8, 0.82)
    return fs
end

---------------------------------------------------------------------------
-- Who is online, and the right-click menu to invite somebody
---------------------------------------------------------------------------
-- a small green light next to a sign-up whose person is online (the character that signed up or another one of theirs)
local function OnlineDot(x, y)
    local path = "Interface\\COMMON\\Indicator-Green"
    local known = true
    if C_Texture and C_Texture.GetFileIDFromPath then
        local ok, id = pcall(C_Texture.GetFileIDFromPath, path)
        known = not (ok and not id)
    end
    if known then Icon(path, x, y, 10) else Box(x, y + 1, 8, 8, 0.25, 0.9, 0.35) end
end

-- right-click on a name: invite one of the guild characters of that person (officers and the guild master)
local function OpenSignupMenu(s)
    if not ns.CanModerate() then return end
    local roster = ns.GetRoster()
    local entries = {}
    for _, e in ipairs(R.CandidateChars(s.n, roster)) do
        local name = ns.DisplayName(e.name)
        local label = ClassColored(name, e.class)
        if e.online then
            entries[#entries + 1] = { text = "Invite " .. label .. " |cff40ff40online|r", action = function() K.InviteToGroup(e.name) end }
        else
            entries[#entries + 1] = { text = "Invite " .. label .. Gray(" offline") }
        end
    end
    if #entries == 0 then entries[1] = { text = Gray("No guild character matched") } end
    K.OpenMenu(R.CharName(s.n, roster), entries)
end

local function SignupTip(owner, s)
    local roster = ns.GetRoster()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(R.CharName(s.n, roster), 1, 1, 1)
    if R.CharName(s.n, roster) ~= s.n then GameTooltip:AddLine("Discord: " .. s.n, 0.6, 0.6, 0.6) end
    local who = R.SignupOnline(s, roster)
    if s.st == "absent" then
        GameTooltip:AddLine("Absent", 0.8, 0.5, 0.5)
    elseif who then
        GameTooltip:AddLine("Online as " .. ClassColored(ns.DisplayName(who.name), who.class), 0.25, 1, 0.35)
    else
        GameTooltip:AddLine("Offline", 0.6, 0.6, 0.6)
    end
    if ns.CanModerate() then GameTooltip:AddLine("Right-click: invite", 0.8, 0.8, 0.8) end
    GameTooltip:Show()
end

-- an area over a name that can be right-clicked and hovered
local hitPool, hitUsed = {}, 0
local function Hit(x, y, w, h, s)
    hitUsed = hitUsed + 1
    local b = hitPool[hitUsed]
    if not b then
        b = CreateFrame("Button", nil, content)
        b:RegisterForClicks("RightButtonUp")
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.07)
        b:SetScript("OnClick", function(self, button) if button == "RightButton" and self.signup then OpenSignupMenu(self.signup) end end)
        b:SetScript("OnEnter", function(self) if self.signup then SignupTip(self, self.signup) end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        hitPool[hitUsed] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    b:SetSize(w, h)
    b.signup = s
    b:Show()
    return b
end

-- the green check after a name: this person is in my group
local CHECK_MARK = " |TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local CHECK_W = 18

-- the date, the time and "in 2 days" follow the game's clock choice (local or server time) and keep up with the time passing
local timeCells = {}
local function UpdateTimes()
    local rec = currentRec
    if not rec then return end
    local texts = { date = R.DateText(rec.start), clock = R.TimeText(rec.start), ago = R.RelativeLong(rec.start) }
    for key, cell in pairs(timeCells) do
        local text = texts[key]
        if text and cell.shown ~= text then
            cell.shown = text
            cell.fs:SetText(text)
            if cell.line then cell.line:SetWidth(math.min(190, TextWidth(text))) end
        end
    end
end

local function ShowRaid(rec, keepScroll)
    local scrollWas = keepScroll and (tonumber(scroll:GetVerticalScroll()) or 0) or 0
    timeCells = {}
    local _, progress = ns.Invite.ShowProgress(rec)       -- (officers and the guild master: after Invite all for this raid, or in its group)
    for i = 1, used do pool[i]:Hide() end
    for i = 1, texUsed do texPool[i]:Hide() end
    for i = 1, hitUsed do hitPool[i]:Hide() end
    used, texUsed, hitUsed = 0, 0, 0
    local roster = ns.GetRoster()
    local counts = R.Counts(rec)
    titleFS:SetText(rec.title)
    -- the stripe is in the colour of the event
    local cr, cg, cb = 0.9, 0.2, 0.2
    if rec.color and rec.color:match("^%x%x%x%x%x%x$") then
        cr, cg, cb = tonumber(rec.color:sub(1, 2), 16) / 255, tonumber(rec.color:sub(3, 4), 16) / 255, tonumber(rec.color:sub(5, 6), 16) / 255
    end
    stripe:SetColorTexture(cr, cg, cb, 1)
    local y = 46

    -- the description under the title
    if rec.desc and rec.desc ~= "" then
        local d = Cell("GameFontHighlight", 0, y, 650, "LEFT", true)
        d:SetText(rec.desc)
        y = y + TextHeight(d, rec.desc, 88, 16) + 14
    else
        y = y + 4
    end

    -- the info grid, like in Discord: the leader and how many signed up; the date, the time and how long
    local info = {
        { 1, 1, "leader", rec.leader ~= "" and rec.leader or nil, false },
        { 2, 1, "raid", tostring(counts.signed), false },
        { 1, 2, "date", R.DateText(rec.start), true },
        { 2, 2, "clock", R.TimeText(rec.start), true },
        { 3, 2, "ago", R.RelativeLong(rec.start), true },
    }
    for _, c in ipairs(info) do
        local col, row, icon, value, underline = c[1], c[2], c[3], c[4], c[5]
        if value then
            local cy = y + (row - 1) * 24
            Icon(INFO_ICON[icon], COLS[col], cy, 16)
            local v = Cell("GameFontHighlight", COLS[col] + 22, cy, 190)
            v:SetText(value)
            local line
            if underline then line = Box(COLS[col] + 22, cy + 15, math.min(190, TextWidth(value)), 1, 0.8, 0.8, 0.82) end
            if icon == "date" or icon == "clock" or icon == "ago" then timeCells[icon] = { fs = v, line = line, shown = value } end
        end
    end
    y = y + 2 * 24 + 14

    -- the roles, three to a row, in the order of the template: [shield] Tanks 3/3   Ranged 5   Melee 2   Healers 3/6
    local order = (rec.roleOrder and rec.roleOrder ~= "") and rec.roleOrder or "TMRH"
    local cellsDone = 0
    local function RoleCell(code, label, n, limit)
        local col = cellsDone % 3
        local ry = y + math.floor(cellsDone / 3) * 24
        Icon(ROLE_ICON[code], COLS[col + 1], ry, 16)
        local cell = Cell("GameFontNormal", COLS[col + 1] + 22, ry, 190)
        cell:SetText(limit and ("|cffcccccc%s|r |cffffffff%d/%d|r"):format(label, n, limit) or ("|cffcccccc%s|r |cffffffff%d|r"):format(label, n))
        cellsDone = cellsDone + 1
    end
    local roleCount = { T = counts.tanks, M = counts.melee, R = counts.ranged, H = counts.healers }
    for i = 1, #order do
        local code = order:sub(i, i)
        local n, limit = roleCount[code] or 0, rec.limits and rec.limits[code]
        if ROLE_NAMES[code] and (n > 0 or limit) then RoleCell(code, ROLE_NAMES[code], n, limit) end
    end
    if counts.other > 0 then RoleCell("D", "Other", counts.other, nil) end
    if cellsDone > 0 then y = y + math.ceil(cellsDone / 3) * 24 + 12 end

    -- the signed up by slot (Tank, then the classes in the order of the template): three columns; each has a header with
    -- the class picture, and a row per sign-up: the spec picture, the number in its box, the character
    local groups = {}
    for _, s in ipairs(rec.signups or {}) do
        if s.st == "signed" then
            local key = (s.g and s.g ~= "") and s.g or (s.c or "")
            groups[key] = groups[key] or {}
            table.insert(groups[key], s)
        end
    end
    local sequence, seen = {}, {}
    for _, key in ipairs((rec.classOrder and #rec.classOrder > 0) and rec.classOrder or GROUP_ORDER) do
        if groups[key] and not seen[key] then sequence[#sequence + 1] = key seen[key] = true end
    end
    local extra = {}
    for key in pairs(groups) do if not seen[key] then extra[#extra + 1] = key end end
    table.sort(extra)
    for _, key in ipairs(extra) do sequence[#sequence + 1] = key end
    for rowStart = 1, #sequence, 3 do
        local tallest = 0
        for col = 0, 2 do
            local key = sequence[rowStart + col]
            if key then
                local x = COLS[col + 1]
                local list = groups[key]
                table.sort(list, function(a, b)
                    if (a.p or 0) ~= (b.p or 0) then return (a.p or 0) < (b.p or 0) end
                    return a.n < b.n
                end)
                Icon(CLASS_ICON[key], x, y, 16)
                Underlined("GameFontHighlight", x + 22, y, 188, ("%s |cffcccccc(%d)|r"):format(GroupLabel(key), #list))
                for i, s in ipairs(list) do
                    local ry = y + 24 + (i - 1) * ROW
                    Icon(SpecIcon(s.c ~= "" and s.c or key, s.s), x, ry, 16)
                    NumberBox(x + 22, ry, s.p, 22)
                    if R.SignupOnline(s, roster) then OnlineDot(x + 49, ry + 3) end
                    local name = Cell("GameFontHighlight", x + 63, ry + 2, 147)
                    name:SetText(R.CharName(s.n, roster) .. ((progress and progress.inGroup[s]) and CHECK_MARK or ""))
                    Hit(x + 22, ry - 1, 188, ROW - 2, s)
                end
                tallest = math.max(tallest, 24 + #list * ROW)
            end
        end
        y = y + tallest + 14
    end

    -- bench, late, tentative and absence at the bottom: "Absence (5) :" and then number boxes and names that wrap
    for _, st in ipairs(STATE_LINES) do
        local members = {}
        for _, s in ipairs(rec.signups or {}) do
            if s.st == st[1] then members[#members + 1] = s end
        end
        if #members > 0 then
            table.sort(members, function(a, b)
                if (a.p or 0) ~= (b.p or 0) then return (a.p or 0) < (b.p or 0) end
                return a.n < b.n
            end)
            Icon(STATE_ICON[st[1]], 0, y, 16)
            local label = Cell("GameFontHighlight", 22, y, 112)
            label:SetText(("%s |cffcccccc(%d) :|r"):format(st[2], #members))
            local fx, fy = 138, y
            for _, s in ipairs(members) do
                local name = R.CharName(s.n, roster)
                local here = progress and progress.inGroup[s]
                local nameW = TextWidth(name) + 2 + (here and CHECK_W or 0)
                local boxW = (s.p and s.p > 0) and math.max(22, TextWidth(tostring(s.p)) + 10) or 0
                local online = st[1] ~= "absent" and R.SignupOnline(s, roster) ~= nil       -- (not for the absent)
                local lead = (boxW > 0 and boxW + 4 or 0) + (online and 14 or 0)
                if fx + lead + nameW > 650 and fx > 138 then fx, fy = 138, fy + ROW end
                if boxW > 0 then NumberBox(fx, fy, s.p, 22) end
                if online then OnlineDot(fx + (boxW > 0 and boxW + 4 or 0), fy + 3) end
                local n = Cell("GameFontHighlight", fx + lead, fy + 2, nameW + 8)
                n:SetText(name .. (here and CHECK_MARK or ""))
                Hit(fx, fy - 1, lead + nameW + 4, ROW - 2, s)
                fx = fx + lead + nameW + 12
            end
            y = fy + ROW + 8
        end
    end

    -- after "Invite all": who signed up and is not in the group yet (character names; the Discord name when nobody is known)
    if progress then
        y = y + 4
        Box(0, y, 650, 1, 0.25, 0.25, 0.28)
        y = y + 10
        local head = Cell("GameFontNormal", 0, y, 650)
        if #progress.missing == 0 then
            head:SetText("|cff40ff40Everybody who signed up is in the group.|r")
            y = y + 22
        else
            head:SetText(("Not in the group yet |cffcccccc(%d)|r"):format(#progress.missing))
            y = y + 22
            -- one name after the other, wrapping; a name of a recognised guild character can be right-clicked to invite it
            local fx, fy = 0, y
            for i, s in ipairs(progress.missing) do
                local name = R.CharName(s.n, roster)
                local shown = name .. (i < #progress.missing and "," or "")
                local w = TextWidth(shown) + 2
                if fx + w > 650 and fx > 0 then fx, fy = 0, fy + ROW end
                local n = Cell("GameFontHighlight", fx, fy + 2, w + 8)
                n:SetText(shown)
                if #R.CandidateChars(s.n, roster) > 0 then Hit(fx, fy - 1, TextWidth(name) + 4, ROW - 2, s) end
                fx = fx + w + 6
            end
            y = fy + ROW + 6
        end
    end

    UpdateTimes()
    content:SetHeight(y + 12)
    scroll:SetVerticalScroll(scrollWas)
end

-- the time keeps up (and follows the game's clock option); who has come is looked at again when the group changes, and every
-- few seconds (the group may change without a sign the addon sees, and a character may log in)
local tick, progressTick = 0, 0
win:SetScript("OnUpdate", function(self, elapsed)
    tick, progressTick = tick + elapsed, progressTick + elapsed
    if tick >= 5 then
        tick = 0
        UpdateTimes()
    end
    if progressTick >= 15 then
        progressTick = 0
        if currentRec and (ns.Invite.ShowProgress(currentRec)) then ShowRaid(currentRec, true) end
    end
end)
ns.HookEvent("GROUP_ROSTER_UPDATE", function()
    if win:IsShown() and currentRec and (ns.Invite.ShowProgress(currentRec)) then ShowRaid(currentRec, true) end
end)

function ns.UI.OpenRaidInfo(rec)
    if not rec then return end
    currentRec = rec
    inviteConfirmUntil = 0
    if not ns.Invite.State().running then ns.Invite.message = nil ns.Invite.note = nil chatNote = nil end
    ShowRaid(rec)
    RefreshInvite()
    win:Show()
end

K.RegisterCloser(function() win:Hide() end)

---------------------------------------------------------------------------
-- the reminder: 15 minutes before a raid I am signed up for
---------------------------------------------------------------------------
local rem = NewWindow("FetaFondueRaidReminder", 400, 260)
rem:SetFrameStrata(K.STRATA_ALERT)
rem:SetPoint("TOP", UIParent, "TOP", 0, -160)
rem:SetMovable(true)
rem:RegisterForDrag("LeftButton")
rem:SetScript("OnDragStart", rem.StartMoving)
rem:SetScript("OnDragStop", rem.StopMovingOrSizing)
rem:SetTitle("Raid starting soon")

local remTitle = rem:Text("GameFontNormalLarge", 20, -42, 360)
remTitle:SetTextColor(1, 0.6, 0.24)
remTitle:SetWordWrap(false)
local remBody = rem:Text("GameFontHighlight", 20, -70, 360)
remBody:SetWordWrap(true)
remBody:SetSpacing(3)
remBody:SetJustifyV("TOP")
local remDetails = K.NewButton(rem, "Details")
remDetails:SetSize(110, 26)
remDetails:SetPoint("BOTTOMLEFT", rem, "BOTTOMLEFT", 20, 16)
local remClose = K.NewButton(rem, "Close")
remClose:SetSize(110, 26)
remClose:SetPoint("BOTTOMRIGHT", rem, "BOTTOMRIGHT", -20, 16)
remClose:SetScript("OnClick", function() rem:Hide() end)

local remRec = nil
remDetails:SetScript("OnClick", function()
    if remRec then ns.UI.OpenRaidInfo(remRec) end
    rem:Hide()
end)

-- the same lines as on the dashboard
function ns.UI.RaidCompactText(rec, maxChars)
    local s = R.Summary(rec)
    local lines = {}
    if s.desc then lines[#lines + 1] = s.desc:sub(1, 120) end
    lines[#lines + 1] = ("%s   %s"):format(s.when, Gray(s.left))
    if s.organizer then lines[#lines + 1] = Gray("organized by " .. s.organizer) end
    if s.signed > 0 then lines[#lines + 1] = ("|cffffd100Signed up (%d):|r %s"):format(s.signed, s.roles) end
    if s.others ~= "" then lines[#lines + 1] = Gray(s.others) end
    if s.mine then lines[#lines + 1] = "|cff66ff66You: " .. R.StateText(s.mine) .. "|r" end
    return lines
end

function ns.UI.ShowRaidReminder(rec)
    remRec = rec
    remTitle:SetText(rec.title)
    local lines = ns.UI.RaidCompactText(rec)
    remBody:SetText(table.concat(lines, "\n"))
    local total = 0
    for _, l in ipairs(lines) do total = total + math.max(1, math.ceil(#(l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) / 52)) end
    rem:SetHeight(math.max(190, math.min(420, 120 + total * 16 + 40)))
    rem:Show()
end

K.RegisterCloser(function() rem:Hide() end)
