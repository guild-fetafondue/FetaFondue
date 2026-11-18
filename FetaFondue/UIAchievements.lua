---@class ns
local ns = select(2, ...)
local K = ns.K
local Gray, BOX_BACKDROP = K.Gray, K.BOX_BACKDROP
local A = ns.Achievements
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

---------------------------------------------------------------------------
-- Achievements: guild firsts, in the manner of the game's own achievement window: a long list, a framed picture on
-- the left, the name and what it is for, and on the right when it was earned. Nobody has it: greyed out.
-- (No points.) Who was first and when comes from the game's own achievements, shared by everybody's addon.
---------------------------------------------------------------------------
local panel = K.achievementsPanel

local header = panel:Text("GameFontNormalLarge", 0, -4, 300)
header:SetText("Achievements")
local summary = panel:Text("GameFontDisableSmall", 300, -10, 464, "RIGHT")

local ROW_H = 66
local STEP_H = 26                 -- a step (criterion) of an expanded raid achievement
local expanded = {}               -- [achievement key] = true while its steps are shown (or sliding open)
local slide = {}                  -- [achievement key] = how far open the steps are (0 to 1), moving towards the goal
local SLIDE_TIME = 0.2            -- seconds for opening or closing
local function Ease(p) return p * p * (3 - 2 * p) end

-- The first one to claim it, and that is all: one name, one moment. A raid is the guild's: the moment of its first clear.
local function Tip(owner, item)
    local def = item.def
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(A.Label(def.key), 1, 0.82, 0)
    GameTooltip:AddLine(def.desc, 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    local first = item.first
    if def.kind == "raid" then
        if first then
            GameTooltip:AddLine(("First guild clear: %s"):format(date(first.time and "%Y-%m-%d %H:%M" or "%Y-%m-%d", first.ts)), 1, 0.82, 0)
        else
            GameTooltip:AddLine("The guild has not cleared it yet.", 0.6, 0.6, 0.6, true)
        end
        -- the steps (bosses) as the game lists them, each done when it died with enough guildies in the group
        if item.total and item.total > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(("Steps: %d of %d (a boss counts when it dies with %d or more guildies in the group)"):format(item.done, item.total, A.RAID_MIN), 0.8, 0.8, 0.8, true)
            for _, step in ipairs(item.steps) do
                local icon = step.done and "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14|t " or "|TInterface\\RAIDFRAME\\ReadyCheck-Waiting:14|t "
                local when = step.done and ("  " .. date(step.time and "%Y-%m-%d %H:%M" or "%Y-%m-%d", step.ts)) or ""
                GameTooltip:AddLine(icon .. step.name .. when, step.done and 1 or 0.6, step.done and 1 or 0.6, step.done and 1 or 0.6)
            end
        end
    elseif first then
        GameTooltip:AddLine(("First: %s   %s"):format(first.name or "?", date(first.time and "%Y-%m-%d %H:%M" or "%Y-%m-%d", first.ts)), 1, 0.82, 0)
    else
        GameTooltip:AddLine("Nobody in the guild yet.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function RenderRow(row, item)
    if not row.title then
        row.back = row:CreateTexture(nil, "BACKGROUND")
        row.back:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        row.back:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
        row.accent = row:CreateTexture(nil, "BORDER")
        row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
        row.accent:SetWidth(3)
        row.frame = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.frame:SetSize(52, 52)
        row.frame:SetPoint("LEFT", row, "LEFT", 12, 0)
        row.frame:SetBackdrop(BOX_BACKDROP)
        row.frame:SetBackdropColor(0.02, 0.02, 0.025, 1)
        row.icon = row.frame:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 3, -3)
        row.icon:SetPoint("BOTTOMRIGHT", row.frame, "BOTTOMRIGHT", -3, 3)
        row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        row.title:SetPoint("TOPLEFT", row.frame, "TOPRIGHT", 14, -4)
        row.title:SetWidth(420)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.desc = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.desc:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -6)
        row.desc:SetWidth(420)
        row.desc:SetJustifyH("LEFT")
        row.desc:SetWordWrap(false)
        row.when = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.when:SetPoint("RIGHT", row, "RIGHT", -16, 8)
        row.when:SetWidth(210)
        row.when:SetJustifyH("RIGHT")
        row.who = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.who:SetPoint("RIGHT", row, "RIGHT", -16, -10)
        row.who:SetWidth(210)
        row.who:SetJustifyH("RIGHT")
        row.groupName = row:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        row.groupName:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 6)
        row.groupName:SetJustifyH("LEFT")
        row.rule = row:CreateTexture(nil, "ARTWORK")
        row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.rule:SetHeight(1)
        row.rule:SetColorTexture(1, 0.82, 0, 0.35)
    end
    if not row.stepName then
        row.stepIcon = row:CreateTexture(nil, "ARTWORK")
        row.stepIcon:SetSize(14, 14)
        row.stepIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 96, -6)
        row.stepName = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.stepName:SetPoint("TOPLEFT", row, "TOPLEFT", 118, -5)
        row.stepName:SetWidth(420)
        row.stepName:SetJustifyH("LEFT")
        row.stepName:SetWordWrap(false)
        row.stepWhen = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.stepWhen:SetPoint("TOPRIGHT", row, "TOPRIGHT", -16, -6)
        row.stepWhen:SetWidth(210)
        row.stepWhen:SetJustifyH("RIGHT")
        row.expand = row:CreateTexture(nil, "OVERLAY")
        row.expand:SetSize(14, 14)
        row.expand:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 8)
    end
    row.text:SetText("")
    row:EnableMouse(item.def ~= nil)
    -- the steps of an opening or closing achievement are cut off at the bottom, so that they slide out from under it
    row:SetClipsChildren(item.step ~= nil)
    row:SetAlpha(item.alpha or 1)
    -- a step of an expanded raid achievement: a small line under it with a tick or a waiting mark
    if item.step then
        local s = item.step
        row.back:Show()
        row.back:SetColorTexture(0.03, 0.03, 0.036, 1)
        row.accent:SetColorTexture(1, 0.82, 0, s.done and 0.5 or 0)
        row.accent:SetShown(s.done)
        row.frame:Hide() row.rule:Hide() row.expand:Hide()
        row.title:SetText("") row.desc:SetText("") row.when:SetText("") row.who:SetText("") row.groupName:SetText("")
        row.stepIcon:SetTexture(s.done and "Interface\\RAIDFRAME\\ReadyCheck-Ready" or "Interface\\RAIDFRAME\\ReadyCheck-Waiting")
        row.stepIcon:Show()
        row.stepName:SetText(s.name)
        row.stepName:SetTextColor(s.done and 1 or 0.55, s.done and 1 or 0.55, s.done and 1 or 0.57)
        row.stepWhen:SetText(s.done and date(s.time and "%Y-%m-%d  %H:%M" or "%Y-%m-%d", s.ts) or Gray("Not yet"))
        row.stepWhen:SetTextColor(s.done and 1 or 0.5, s.done and 1 or 0.5, s.done and 1 or 0.5)
        row.stepName:Show() row.stepWhen:Show()
        return
    end
    row.stepIcon:Hide() row.stepName:Hide() row.stepWhen:Hide()
    row.expand:Hide()
    if item.header then
        row.back:Hide() row.accent:Hide() row.frame:Hide() row.title:SetText("") row.desc:SetText("") row.when:SetText("") row.who:SetText("")
        row.groupName:SetText(item.header)
        row.groupName:SetTextColor(1, 0.82, 0)
        row.rule:Show()
        return
    end
    row.groupName:SetText("")
    row.rule:Hide()
    row.back:Show()
    row.frame:Show()
    local def, first = item.def, item.first
    row.icon:SetTexture(A.Icon(def.key) or QUESTION)
    row.title:SetText(A.Label(def.key))
    row.desc:SetText(def.desc)
    if first then
        -- earned: full colour
        row.back:SetColorTexture(0.1, 0.09, 0.055, 1)
        row.accent:SetColorTexture(1, 0.82, 0, 1)
        row.accent:Show()
        row.frame:SetBackdropBorderColor(1, 0.82, 0, 1)
        row.icon:SetDesaturated(false)
        row.title:SetTextColor(1, 0.82, 0)
        row.desc:SetTextColor(0.92, 0.92, 0.92)
        row.when:SetText(date(first.time and "%Y-%m-%d  %H:%M" or "%Y-%m-%d", first.ts))
        row.when:SetTextColor(1, 1, 1)
        if def.kind == "person" then
            local entry = ns.FindRosterEntry(ns.GetRoster(), first.guid, first.name)
            row.who:SetText(K.ClassColored(ns.DisplayName(first.name or "?"), entry and entry.class))
        else
            row.who:SetText("")
        end
    else
        -- not earned by anybody: grey
        row.back:SetColorTexture(0.045, 0.045, 0.05, 1)
        row.accent:Hide()
        row.frame:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
        row.icon:SetDesaturated(true)
        row.title:SetTextColor(0.5, 0.5, 0.52)
        row.desc:SetTextColor(0.38, 0.38, 0.4)
        row.when:SetText(Gray((def.kind == "raid" and (item.done or 0) > 0 and (item.total or 0) > 0) and ("%d of %d bosses"):format(item.done, item.total) or "Not yet"))
        row.who:SetText("")
    end
    row.onEnter = function(self) Tip(self, item) end
    -- a raid with steps opens and closes with a click, like the game's own achievements: the steps show under it
    if item.steps and #item.steps > 0 then
        row.expand:SetTexture(expanded[def.key] and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        row.expand:Show()
        row.onClick = function()
            expanded[def.key] = not expanded[def.key] or nil
            slide[def.key] = slide[def.key] or 0          -- (the animation below does the rest, a frame at a time)
            ns.UI.RefreshAchievements()                   -- (the plus turns into a minus at once)
        end
    end
end

local list = K.CreateScrollList(panel, 764, 568, ROW_H, RenderRow)
list.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -34)

function ns.UI.RefreshAchievements()
    if not panel:IsShown() then return end
    local items = A.Rows()
    local total, done = 0, 0
    for _, item in ipairs(items) do
        if item.def then
            total = total + 1
            if item.first then done = done + 1 end
        end
    end
    -- the steps of the opened achievements go right under them
    local shown = {}
    for _, item in ipairs(items) do
        shown[#shown + 1] = item
        local open = item.def and slide[item.def.key]
        if open and open > 0 and item.steps then
            for _, step in ipairs(item.steps) do shown[#shown + 1] = { step = step, height = STEP_H * Ease(open), alpha = open } end
        end
    end
    list:Render(shown, true)
    local text = ("%d of %d achieved by the guild"):format(done, total)
    if A.available == false then text = text .. "   " .. "This game client does not list achievements: only what guildmates share is shown." end
    summary:SetText(Gray(text))
end

A.OnChanged = function() ns.UI.RefreshAchievements() end

-- the slide: every frame the steps move a bit towards open or closed
local animator = CreateFrame("Frame", "FetaFondueAchievementsAnimator", panel)
animator:SetScript("OnUpdate", function(self, elapsed)
    local moved = false
    for key, p in pairs(slide) do
        local goal = expanded[key] and 1 or 0
        if p ~= goal then
            moved = true
            if goal == 1 then p = math.min(1, p + elapsed / SLIDE_TIME) else p = math.max(0, p - elapsed / SLIDE_TIME) end
            if p == 0 and not expanded[key] then slide[key] = nil else slide[key] = p end
        end
    end
    if moved then ns.UI.RefreshAchievements() end
end)
