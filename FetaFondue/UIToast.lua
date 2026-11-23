---@class ns
local ns = select(2, ...)
local K = ns.K
local Gray, ClassColored = K.Gray, K.ClassColored

---------------------------------------------------------------------------
-- Toasts: small messages that appear at the top of the screen, stay a few seconds and close by themselves (they are our
-- own frames; nothing of Blizzard's alert system is touched). Up to three are shown at once, the rest wait in a queue.
-- Hovering a toast keeps it open; a click closes it. The achievement toast is one use of it.
---------------------------------------------------------------------------
local MAX_SHOWN, WIDTH, HEIGHT, GAP = 3, 340, 86, 8
local FADE_IN, FADE_OUT, HOLD = 0.25, 1, 4
local active, queue, pool = {}, {}, {}

local manager = CreateFrame("Frame", "FetaFondueToastManager")

local function Layout()
    for i, t in ipairs(active) do
        t:ClearAllPoints()
        t:SetPoint("TOP", UIParent, "TOP", 0, -150 - (i - 1) * (HEIGHT + GAP))
    end
end

local Pump
local function Close(t)
    t:Hide()
    for i, other in ipairs(active) do if other == t then table.remove(active, i) break end end
    pool[#pool + 1] = t
    Layout()
    Pump()
end

local function NewToast()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata(K.STRATA_ALERT)
    f:SetBackdrop(K.BOX_BACKDROP)
    f:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
    f:SetBackdropBorderColor(1, 0.82, 0, 1)
    f:EnableMouse(true)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(52, 52)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -16)
    f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 78, -10)
    f.title:SetWidth(WIDTH - 92)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.line1 = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.line1:SetPoint("TOPLEFT", f, "TOPLEFT", 78, -32)
    f.line1:SetWidth(WIDTH - 92)
    f.line1:SetJustifyH("LEFT")
    f.line1:SetJustifyV("TOP")
    f.line1:SetHeight(28)
    f.line2 = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    f.line2:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 78, 8)
    f.line2:SetWidth(WIDTH - 92)
    f.line2:SetJustifyH("LEFT")
    f:SetScript("OnEnter", function(self) self.hover = true end)
    f:SetScript("OnLeave", function(self) self.hover = false end)
    f:SetScript("OnMouseUp", function(self) Close(self) end)
    return f
end

Pump = function()
    while #queue > 0 and #active < MAX_SHOWN do
        local opts = table.remove(queue, 1)
        local t = table.remove(pool) or NewToast()
        t.age, t.hover, t.duration = 0, false, opts.duration or HOLD
        t.icon:SetTexture(opts.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        t.title:SetText(opts.title or "")
        t.line1:SetText(opts.line1 or "")
        t.line2:SetText(opts.line2 or "")
        t:SetAlpha(0)
        t:Show()
        active[#active + 1] = t
        Layout()
    end
end

-- the clock of the toasts: fade in, stay (not while the mouse is over), fade out, close
manager:SetScript("OnUpdate", function(self, elapsed)
    for i = #active, 1, -1 do
        local t = active[i]
        if t then
            if t.hover then
                t.age = math.min(t.age, t.duration)       -- (hovering keeps it open)
            else
                t.age = t.age + elapsed
            end
            if t.age < FADE_IN then
                t:SetAlpha(t.age / FADE_IN)
            elseif t.age <= t.duration then
                t:SetAlpha(1)
            elseif t.age < t.duration + FADE_OUT then
                t:SetAlpha(1 - (t.age - t.duration) / FADE_OUT)
            else
                Close(t)
            end
        end
    end
end)

-- opts: icon, title, line1, line2, duration
function ns.UI.Toast(opts)
    if ns.DB and ns.DB.toasts == false then return false end
    queue[#queue + 1] = opts
    Pump()
    return true
end

function ns.UI.ToastState() return #active, #queue end

---------------------------------------------------------------------------
-- the achievement toast: the achievement, who claimed it first (not for a raid: that is the whole guild's) and when
---------------------------------------------------------------------------
function ns.UI.AchievementToast(key, name, guid, ts)
    if not ns.ToastAllowed(ts) then return end
    local A = ns.Achievements
    local def = A and A.byKey[key]
    if not def then return false end
    local label = A.Label(key)
    local when = date("%Y-%m-%d  %H:%M", ts)
    local line1
    if def.kind == "raid" then
        line1 = ("The guild cleared %s for the first time!"):format(def.place or label)
    else
        local entry = ns.FindRosterEntry(ns.GetRoster(), guid, name)
        line1 = ("%s is the first in the guild!"):format(ClassColored(ns.DisplayName(name or "?"), entry and entry.class))
    end
    return ns.UI.Toast({ icon = A.Icon(key), title = label, line1 = line1, line2 = Gray(when) })
end

-- somebody joined the guild
function ns.UI.JoinToast(guid, ts)
    if not ns.ToastAllowed(ts) then return end
    local entry = ns.FindRosterEntry(ns.GetRoster(), guid, nil)
    if not entry then return false end
    local line1 = ("%s has joined the guild. Welcome!"):format(ClassColored(ns.DisplayName(entry.name), entry.class))
    local lvl = tonumber(entry.level)
    return ns.UI.Toast({
        icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01", title = "New guildmate", line1 = line1,
        line2 = (lvl and (Gray("Level " .. lvl .. " ") ) or "") .. ClassColored((entry.classDisplay and entry.classDisplay ~= "" and entry.classDisplay) or K.ClassName(entry.class), entry.class),
    })
end

-- /ff toast: a test
function ns.UI.TestToast()
    return ns.UI.Toast({
        icon = "Interface\\Icons\\Achievement_Level_60", title = "Test toast", line1 = "This is how an achievement toast looks.",
        line2 = Gray(date("%Y-%m-%d  %H:%M", ns.Time())),
    })
end
