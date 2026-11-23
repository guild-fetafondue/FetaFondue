---@class ns
local ns = select(2, ...)

-- Your own requests: what you would like a guildie to craft for you.
-- For now they are only kept on your side; sharing them with crafters comes later.

local MAX_QTY = 999

-- every change to my list gets a new revision and is shared with the guild
local function Touch()
    if not (ns.DB and ns.myGUID) then return end
    ns.DB.requestRev[ns.myGUID] = ns.Time()
    if ns.Sync then ns.Sync.OnRequestsChanged() end
    if ns.RefreshUI then ns.RefreshUI() end
end

function ns.GetRequests()
    if not (ns.DB and ns.myGUID) then return {} end
    local list = ns.DB.requests[ns.myGUID]
    if not list then
        list = {}
        ns.DB.requests[ns.myGUID] = list
    end
    return list
end

-- Asking again for the same recipe adds to the existing request.
function ns.AddRequest(recipeID, name, qty)
    qty = math.max(1, math.min(MAX_QTY, math.floor(tonumber(qty) or 1)))
    local list = ns.GetRequests()
    for _, r in ipairs(list) do
        if r.id == recipeID then
            r.qty = math.min(MAX_QTY, r.qty + qty)
            Touch()
            return r
        end
    end
    local r = { id = recipeID, name = name, qty = qty, t = ns.Time() }
    list[#list + 1] = r
    Touch()
    return r
end

-- Favourite items of the Sweatshop (mine only: saved on this installation, never sent to the guild).
function ns.IsFavourite(id)
    return ns.DB ~= nil and ns.DB.favourites ~= nil and ns.DB.favourites[id] == true
end
function ns.SetFavourite(id, on)
    if not ns.DB then return end
    ns.DB.favourites = ns.DB.favourites or {}
    ns.DB.favourites[id] = on and true or nil
end
function ns.FavouriteCount()
    local n = 0
    for _ in pairs((ns.DB and ns.DB.favourites) or {}) do n = n + 1 end
    return n
end

-- Total materials for a quantity: reagents per craft times the number of crafts needed.
-- Returns list of { id, count }, crafts, amount made per craft.
function ns.TotalMaterials(info, qty)
    local made = math.max(1, info.made or 1)
    local crafts = math.ceil(qty / made)
    local list = {}
    for _, r in ipairs(info.reagents or {}) do
        list[#list + 1] = { id = r.id, count = r.count * crafts }
    end
    return list, crafts, made
end

-- Everybody's open requests in the guild (mine included), for the dashboard.
function ns.GetGuildRequests()
    local out = {}
    if not (ns.DB and ns.guildName) then return out end
    local members = ns.GetMembers() or {}
    local roster = ns.GetRoster()

    local function Add(guid, m, list)
        local entry = ns.FindRosterEntry(roster, guid, m.name)
        if roster.total > 0 and not entry then return end   -- left the guild
        local who = ns.DisplayName(entry and entry.name or m.name)
        local online = entry and entry.online or false
        for _, r in ipairs(list) do
            out[#out + 1] = {
                guid = guid, who = who, online = online, mine = ns.IsMine(guid),
                id = r.id, qty = r.qty, name = r.name or ns.RecipeName(r.id),
            }
        end
    end

    for guid, ch in pairs(ns.DB.mine) do
        if ch.guild == ns.guildName then Add(guid, ch, ns.DB.requests[guid] or {}) end
    end
    for guid, m in pairs(members) do
        if not ns.IsMine(guid) and m.reqs then Add(guid, m, m.reqs.list) end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.who < b.who
    end)
    return out
end

-- Remove a request from the dashboard list (right-click). Mine: remove it from my list. Somebody else's:
-- only the guild master and officers may, and everybody drops it.
function ns.DeleteGuildRequest(r)
    if r.mine then
        local list = ns.DB.requests[r.guid] or {}
        for i = #list, 1, -1 do
            if list[i].id == r.id then table.remove(list, i) end
        end
        ns.DB.requestRev[r.guid] = ns.Time()
        if r.guid == ns.myGUID and ns.Sync then ns.Sync.OnRequestsChanged() end
        if ns.RefreshUI then ns.RefreshUI() end
        return true
    end
    if ns.CanModerate() and ns.Sync then
        ns.Sync.DeleteRequest(r.guid, r.id)
        return true
    end
    return false
end
