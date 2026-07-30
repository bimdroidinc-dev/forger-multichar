local presence = {}
local incoming = {}
local sent = {}
local emoteIdx = {}

CreateThread(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS forger_partners (
        citizenid VARCHAR(64) NOT NULL PRIMARY KEY,
        partner VARCHAR(64) NOT NULL,
        mode VARCHAR(16) NOT NULL DEFAULT 'couple',
        role VARCHAR(2) NOT NULL DEFAULT 'a'
    )]])
end)

local function dbGetPartner(cid)
    if not cid then return nil end
    return MySQL.single.await('SELECT partner, mode, role FROM forger_partners WHERE citizenid = ?', { cid })
end

local function dbSetPartner(a, b, mode)
    MySQL.query.await('REPLACE INTO forger_partners (citizenid, partner, mode, role) VALUES (?, ?, ?, ?)', { a, b, mode, 'a' })
    MySQL.query.await('REPLACE INTO forger_partners (citizenid, partner, mode, role) VALUES (?, ?, ?, ?)', { b, a, mode, 'b' })
end

local function dbClearPartner(cid)
    if not cid then return nil end
    local row = dbGetPartner(cid)
    if row then MySQL.query.await('DELETE FROM forger_partners WHERE citizenid = ?', { row.partner }) end
    MySQL.query.await('DELETE FROM forger_partners WHERE citizenid = ?', { cid })
    return row and row.partner or nil
end

local function fetchCharacterLook(cid)
    if not cid then return nil end
    local look = { gender = 0, appearance = nil }

    local prow = MySQL.single.await(
        ('SELECT %s FROM %s WHERE %s = ?'):format(Config.DB.columnCharInfo, Config.DB.table, Config.DB.columnCitizenId),
        { cid })
    if prow and prow[Config.DB.columnCharInfo] then
        local ok, ci = pcall(json.decode, prow[Config.DB.columnCharInfo])
        if ok and type(ci) == 'table' then
            look.name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', '')
            if ci.gender == 1 or ci.gender == '1' then look.gender = 1 end
        end
    end

    local A = Config.Appearance
    if A.skinTable then
        local q = ('SELECT %s FROM %s WHERE %s = ?'):format(A.skinColumn, A.skinTable, A.skinIdColumn)
        local args = { cid }
        if A.skinActiveColumn then
            q = q .. (' AND %s = ?'):format(A.skinActiveColumn)
            args[#args + 1] = 1
        end
        local ok, srow = pcall(function() return MySQL.single.await(q, args) end)
        if ok and srow and srow[A.skinColumn] then
            local ok2, dec = pcall(json.decode, srow[A.skinColumn])
            look.appearance = ok2 and dec or srow[A.skinColumn]
        end
    end
    return look
end

local function onlineByCitizen(cid)
    if not cid then return nil end
    for src, p in pairs(presence) do
        if p.citizenid == cid then return src end
    end
    return nil
end

local function pushLists(src)
    local inc, snt = {}, {}
    for fromId, r in pairs(incoming[src] or {}) do inc[#inc + 1] = { id = fromId, name = r.name, mode = r.mode } end
    for toId, r in pairs(sent[src] or {}) do snt[#snt + 1] = { id = toId, name = r.name, mode = r.mode } end
    TriggerClientEvent('forger:client:partnerLists', src, { incoming = inc, sent = snt })
end

local function clearRequest(fromId, toId)
    if sent[fromId] then sent[fromId][toId] = nil end
    if incoming[toId] then incoming[toId][fromId] = nil end
end

local function evaluateShow(src)
    local p = presence[src]
    if not p or not p.citizenid then
        return TriggerClientEvent('forger:client:partnerHide', src)
    end
    local rel = dbGetPartner(p.citizenid)
    if not rel then
        return TriggerClientEvent('forger:client:partnerHide', src)
    end

    local look = fetchCharacterLook(rel.partner) or { gender = 0 }
    local partnerSrc = onlineByCitizen(rel.partner)
    if partnerSrc and presence[partnerSrc] and presence[partnerSrc].citizenid == rel.partner then
        look.name = presence[partnerSrc].name or look.name
        look.gender = presence[partnerSrc].gender or look.gender
    end

    TriggerClientEvent('forger:client:partnerShow', src, {
        mode = rel.mode,
        selfRole = rel.role,
        gender = look.gender or 0,
        name = look.name,
        appearance = look.appearance,
        emoteIndex = emoteIdx[p.citizenid] or 1,
    })
end

RegisterNetEvent('forger:server:partnerPresence', function(open)
    local src = source
    if open then
        presence[src] = presence[src] or {}
        TriggerClientEvent('forger:client:partnerYourId', src, { id = src })
        pushLists(src)
    else
        local cid = presence[src] and presence[src].citizenid
        presence[src] = nil
        for fromId in pairs(incoming[src] or {}) do clearRequest(fromId, src); pushLists(fromId) end
        for toId in pairs(sent[src] or {}) do clearRequest(src, toId); pushLists(toId) end
        incoming[src] = nil
        sent[src] = nil
        if cid then
            local rel = dbGetPartner(cid)
            if rel then local psrc = onlineByCitizen(rel.partner); if psrc then evaluateShow(psrc) end end
        end
    end
end)

RegisterNetEvent('forger:server:partnerSetChar', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    presence[src] = presence[src] or {}
    presence[src].citizenid = data.citizenid
    presence[src].name = tostring(data.name or GetPlayerName(src)):sub(1, 40)
    presence[src].gender = tonumber(data.gender) == 1 and 1 or 0
    evaluateShow(src)
    if data.citizenid then
        local rel = dbGetPartner(data.citizenid)
        if rel then local psrc = onlineByCitizen(rel.partner); if psrc then evaluateShow(psrc) end end
    end
end)

RegisterNetEvent('forger:server:partnerSearch', function(query)
    local src = source
    query = tostring(query or ''):lower()
    if #query < (Config.Partner.searchMinChars or 1) then
        return TriggerClientEvent('forger:client:partnerSearchResults', src, { results = {} })
    end
    local results = {}
    for otherSrc, p in pairs(presence) do
        if otherSrc ~= src and p.citizenid then
            local name = (p.name or ''):lower()
            if tostring(otherSrc) == query or name:find(query, 1, true) then
                results[#results + 1] = { id = otherSrc, name = p.name }
                if #results >= 15 then break end
            end
        end
    end
    TriggerClientEvent('forger:client:partnerSearchResults', src, { results = results })
end)

RegisterNetEvent('forger:server:partnerInvite', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local toId = tonumber(payload.targetId)
    local mode = (payload.mode == 'friend') and 'friend' or 'couple'
    if not toId or toId == src then return end
    if not presence[src] or not presence[toId] then return end
    if not presence[src].citizenid or not presence[toId].citizenid then return end

    sent[src] = sent[src] or {}
    incoming[toId] = incoming[toId] or {}
    local expires = os.time() + (Config.Partner.requestTimeout or 60)
    sent[src][toId] = { mode = mode, name = presence[toId].name, expires = expires }
    incoming[toId][src] = { mode = mode, name = presence[src].name, expires = expires }

    pushLists(src)
    pushLists(toId)
    TriggerClientEvent('forger:client:partnerPrompt', toId, { fromId = src, name = presence[src].name, mode = mode })
end)

RegisterNetEvent('forger:server:partnerRespond', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local fromId = tonumber(payload.fromId)
    local accept = payload.accept == true
    if not fromId then return end

    local req = incoming[src] and incoming[src][fromId]
    if not req then return end
    clearRequest(fromId, src)

    if not accept then
        pushLists(src); pushLists(fromId)
        TriggerClientEvent('forger:client:partnerDeclined', fromId, { name = presence[src] and presence[src].name })
        return
    end

    if not presence[src] or not presence[fromId] then pushLists(src); pushLists(fromId); return end
    local aCid = presence[fromId].citizenid
    local bCid = presence[src].citizenid
    if not aCid or not bCid then pushLists(src); pushLists(fromId); return end

    dbSetPartner(aCid, bCid, req.mode)
    emoteIdx[aCid] = 1
    emoteIdx[bCid] = 1

    for f in pairs(incoming[fromId] or {}) do clearRequest(f, fromId); pushLists(f) end
    for t in pairs(sent[fromId] or {}) do clearRequest(fromId, t); pushLists(t) end
    for f in pairs(incoming[src] or {}) do clearRequest(f, src); pushLists(f) end
    for t in pairs(sent[src] or {}) do clearRequest(src, t); pushLists(t) end

    TriggerClientEvent('forger:client:partnerMatched', fromId, { mode = req.mode })
    TriggerClientEvent('forger:client:partnerMatched', src, { mode = req.mode })
    evaluateShow(fromId)
    evaluateShow(src)
    pushLists(src)
    pushLists(fromId)
end)

RegisterNetEvent('forger:server:partnerCancel', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local toId = tonumber(payload.targetId)
    if not toId then return end
    clearRequest(src, toId)
    pushLists(src)
    pushLists(toId)
end)

RegisterNetEvent('forger:server:partnerEmote', function(payload)
    local src = source
    local p = presence[src]
    if not p or not p.citizenid then return end
    local rel = dbGetPartner(p.citizenid)
    if not rel then return end
    local list = Config.Partner.emotes[rel.mode]
    local count = list and #list or 0
    if count == 0 then return end

    local idx = emoteIdx[p.citizenid] or 1
    if type(payload) == 'table' and payload.index then idx = tonumber(payload.index)
    elseif type(payload) == 'table' and payload.delta then idx = idx + tonumber(payload.delta) end
    idx = ((idx - 1) % count) + 1

    emoteIdx[p.citizenid] = idx
    emoteIdx[rel.partner] = idx

    TriggerClientEvent('forger:client:partnerEmote', src, { mode = rel.mode, emoteIndex = idx })
    local psrc = onlineByCitizen(rel.partner)
    if psrc then TriggerClientEvent('forger:client:partnerEmote', psrc, { mode = rel.mode, emoteIndex = idx }) end
end)

RegisterNetEvent('forger:server:partnerUnpair', function()
    local src = source
    local cid = presence[src] and presence[src].citizenid
    if not cid then return end
    local partnerCid = dbClearPartner(cid)
    evaluateShow(src)
    if partnerCid then
        local psrc = onlineByCitizen(partnerCid)
        if psrc then
            TriggerClientEvent('forger:client:partnerEnded', psrc, { reason = 'ended' })
            evaluateShow(psrc)
        end
    end
    TriggerClientEvent('forger:client:partnerEnded', src, { reason = 'ended' })
end)

AddEventHandler('forger:server:characterSelected', function(src)
    presence[src] = nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    local cid = presence[src] and presence[src].citizenid
    presence[src] = nil
    for fromId in pairs(incoming[src] or {}) do clearRequest(fromId, src); pushLists(fromId) end
    for toId in pairs(sent[src] or {}) do clearRequest(src, toId); pushLists(toId) end
    incoming[src] = nil
    sent[src] = nil
    if cid then
        local rel = dbGetPartner(cid)
        if rel then local psrc = onlineByCitizen(rel.partner); if psrc then evaluateShow(psrc) end end
    end
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for target, reqs in pairs(incoming) do
            for fromId, r in pairs(reqs) do
                if r.expires and r.expires < now then
                    clearRequest(fromId, target)
                    pushLists(target); pushLists(fromId)
                end
            end
        end
    end
end)
