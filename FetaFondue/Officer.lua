---@class ns
local ns = select(2, ...)

-- Officer notes: several notes, shared between the officers and the guild master who use the addon. They travel over the guild's
-- OFFICER addon channel, which only officers receive. A note has a title and a text; the newest save of a note wins.
-- One note, "Important!", is always there: it cannot be renamed or deleted (its text can be changed).

local O = {}
ns.Officer = O

O.DEFAULT_ID = "default"
O.DEFAULT_TITLE = "Important!"
O.MAX_TEXT, O.MAX_TITLE, O.MAX_NOTES = 3000, 40, 40

local DEFAULT = O.DEFAULT_ID

-- gd.notes[id] = { id, title, text, rev (the time of the last save), by, deleted }
local function Store()
    local g = ns.guildName
    if not (ns.DB and g) then return nil end
    local gd = ns.DB.guilds[g]
    if not gd then
        gd = { members = {} }
        ns.DB.guilds[g] = gd
    end
    if not gd.notes then
        gd.notes = {}
        -- the one note of older versions is kept as a note of its own
        local old = gd.officerNote
        if old and (old.text or "") ~= "" then
            gd.notes.legacy = { id = "legacy", title = "Old note", text = old.text, rev = math.max(1, old.rev or 1), by = old.by or "" }
        end
    end
    if not gd.notes[DEFAULT] then
        gd.notes[DEFAULT] = { id = DEFAULT, title = O.DEFAULT_TITLE, text = "", rev = 0, by = "" }
    end
    gd.notes[DEFAULT].title = O.DEFAULT_TITLE          -- (never another name)
    gd.notes[DEFAULT].deleted = nil                    -- (never deleted)
    return gd.notes
end

function O.Notes() return Store() or {} end

function O.GetNote(id)
    local notes = Store()
    return notes and notes[id] or nil
end

local function CleanTitle(title)
    title = tostring(title or ""):gsub("[%c|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    title = title:sub(1, O.MAX_TITLE)
    if title == "" then title = "Untitled" end
    return title
end
O.CleanTitle = CleanTitle

-- the notes that exist, the protected one first, then in the order they were made (the ids start with the time)
function O.List()
    local list = {}
    for id, n in pairs(O.Notes()) do
        if not n.deleted then list[#list + 1] = n end
    end
    -- the shared order (Move): by place; notes without a place follow in the order they were made; the protected one is first
    table.sort(list, function(a, b)
        if a.id == DEFAULT then return b.id ~= DEFAULT end
        if b.id == DEFAULT then return false end
        local pa, pb = a.pos, b.pos
        if pa and pb and pa ~= pb then return pa < pb end
        if pa and not pb then return true end
        if pb and not pa then return false end
        return a.id < b.id
    end)
    return list
end

-- move a note one place up (dir = -1) or down (dir = 1). The order is shared with the other officers (each note carries its
-- place and the time it was set; the newest wins). The protected note stays first and cannot be moved. Returns true when
-- something moved.
function O.Move(id, dir)
    if id == DEFAULT or not (ns.CanModerate() and ns.guildName) then return false end
    local list = O.List()
    local at
    for i, n in ipairs(list) do if n.id == id then at = i end end
    local to = at and at + dir
    if not at or to < 2 or to > #list then return false end    -- (place 1 belongs to the protected note)
    list[at], list[to] = list[to], list[at]
    local stamp = ns.Time()
    for _, n in ipairs(list) do stamp = math.max(stamp, (n.posRev or 0) + 1) end
    local changed = {}
    for i, n in ipairs(list) do
        if n.id ~= DEFAULT and n.pos ~= i then
            n.pos, n.posRev = i, stamp
            changed[#changed + 1] = n.id
        end
    end
    if ns.Sync and ns.Sync.SendOrder then ns.Sync.SendOrder(changed) end
    return true
end

-- a place from another officer: true when it was newer than ours
function O.ReceivePos(id, pos, rev)
    local note = O.GetNote(id)
    if not note or id == DEFAULT or rev <= (note.posRev or 0) then return false end
    note.pos, note.posRev = pos, rev
    if O.OnOrder then O.OnOrder() end
    return true
end

function O.NewID()
    return ("n%x%02x"):format(ns.Time(), ns.Random and ns.Random(0, 255) or math.random(0, 255))
end

local function Bump(note)
    return math.max(ns.Time(), (note.rev or 0) + 1)
end

-- save a note (title and text) and share it with the other officers; returns the note, or nil when it cannot be done
function O.Save(id, title, text)
    if not (ns.CanModerate() and ns.guildName) then return nil end
    local note = O.GetNote(id)
    if not note or note.deleted then return nil end
    if id ~= DEFAULT then note.title = CleanTitle(title) end
    note.text = tostring(text or ""):sub(1, O.MAX_TEXT)
    note.rev, note.by = Bump(note), ns.DisplayName(ns.me)
    if ns.Sync and ns.Sync.SendNote then ns.Sync.SendNote(id) end
    return note
end

-- a new note; returns its id
function O.Create(title)
    if not (ns.CanModerate() and ns.guildName) then return nil end
    local count = 0
    for _ in pairs(O.Notes()) do count = count + 1 end
    if count >= O.MAX_NOTES then return nil, "There are too many notes: delete one first." end
    local id = O.NewID()
    local notes = O.Notes()
    while notes[id] do id = O.NewID() .. "x" end
    notes[id] = { id = id, title = CleanTitle(title or "New note"), text = "", rev = 0, by = "" }
    O.Save(id, title or "New note", "")
    return id
end

-- delete a note (it is kept as a mark for a month so that the others delete it too); the protected one cannot be deleted
function O.Delete(id)
    if id == DEFAULT or not (ns.CanModerate() and ns.guildName) then return false end
    local note = O.GetNote(id)
    if not note or note.deleted then return false end
    note.deleted, note.text = true, ""
    note.rev, note.by = Bump(note), ns.DisplayName(ns.me)
    if ns.Sync and ns.Sync.SendNote then ns.Sync.SendNote(id) end
    if O.OnNote then O.OnNote(note) end
    return true
end

-- a note from another officer (see Sync.lua); true when it was newer than ours
function O.Receive(id, rev, title, text, deleted, by)
    local notes = Store()
    if not notes then return false end
    local note = notes[id]
    if note and rev <= (note.rev or 0) then return false end
    if not note then
        if id == DEFAULT then note = notes[DEFAULT] else
            local count = 0
            for _ in pairs(notes) do count = count + 1 end
            if count >= O.MAX_NOTES then return false end
            note = { id = id }
            notes[id] = note
        end
    end
    note.rev, note.by = rev, by
    note.text = text
    if id == DEFAULT then
        note.title, note.deleted = O.DEFAULT_TITLE, nil         -- (the protected note keeps its name and cannot be deleted)
    else
        note.title, note.deleted = CleanTitle(title), deleted and true or nil
        if note.deleted then note.text = "" end
    end
    if O.OnNote then O.OnNote(note) end
    return true
end

-- "id:rev" of every note including the deleted ones, for the digest the officers repeat now and then
function O.Digest()
    local out = {}
    for id, n in pairs(O.Notes()) do
        if (n.rev or 0) > 0 then out[#out + 1] = ("%s:%d"):format(id, n.rev) end
    end
    table.sort(out)
    return out
end

-- marks of deleted notes older than a month go
function O.Prune()
    local notes = Store()
    if not notes then return end
    for id, n in pairs(notes) do
        if n.deleted and ns.Time() - (n.rev or 0) > 30 * 86400 then notes[id] = nil end
    end
end
