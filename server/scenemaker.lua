SceneMaker = SceneMaker or {}

if not (Config.SceneMaker and Config.SceneMaker.enabled) then return end

CreateThread(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS forger_scenes (
        citizenid VARCHAR(64) NOT NULL,
        data LONGTEXT NOT NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (citizenid)
    )]])
end)

function SceneMaker.getForCitizen(cid)
    if not cid then return nil end
    local ok, row = pcall(function()
        return MySQL.single.await('SELECT data FROM forger_scenes WHERE citizenid = ?', { cid })
    end)
    if ok and row and row.data then
        local okd, dec = pcall(json.decode, row.data)
        if okd and type(dec) == 'table' then return dec end
    end
    return nil
end

local function citizenidOf(src)
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if ok and p and p.PlayerData and p.PlayerData.citizenid then return p.PlayerData.citizenid end
    local ok2, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok2 and core and core.Functions and core.Functions.GetPlayer then
        local qp = core.Functions.GetPlayer(src)
        if qp and qp.PlayerData and qp.PlayerData.citizenid then return qp.PlayerData.citizenid end
    end
    if FW.core and FW.core.Functions and FW.core.Functions.GetPlayer then
        local qp = FW.core.Functions.GetPlayer(src)
        if qp and qp.PlayerData and qp.PlayerData.citizenid then return qp.PlayerData.citizenid end
    end
    return nil
end

local function sanitize(data)
    if type(data) ~= 'table' then return nil end
    local function num(v, d) v = tonumber(v); return v ~= nil and v or d end
    local c = type(data.coords) == 'table' and data.coords or {}
    local cam = type(data.cam) == 'table' and data.cam or {}

    local vehicles = {}
    if type(data.vehicles) == 'table' then
        for _, v in ipairs(data.vehicles) do
            if type(v) == 'table' and type(v.model) == 'string' and type(v.coords) == 'table' then
                vehicles[#vehicles + 1] = {
                    model = v.model:sub(1, 32),
                    plate = type(v.plate) == 'string' and v.plate:sub(1, 12) or nil,
                    coords = { x = num(v.coords.x, 0.0), y = num(v.coords.y, 0.0), z = num(v.coords.z, 70.0) },
                    heading = num(v.heading, 0.0),
                }
                if #vehicles >= 8 then break end
            end
        end
    end

    local out = {
        coords = { x = num(c.x, 0.0), y = num(c.y, 0.0), z = num(c.z, 70.0), w = num(c.w, 0.0) },
        stance = type(data.stance) == 'string' and data.stance:sub(1, 48) or nil,
        cam = {
            angle    = num(cam.angle, 200.0),
            height   = num(cam.height, 0.55),
            distance = num(cam.distance, 3.4),
            fov      = num(cam.fov, 45.0),
            speed    = num(cam.speed, 0.0),
        },
        vehicles = vehicles,
        weather = type(data.weather) == 'string' and data.weather:sub(1, 24) or 'CLEAR',
        hour = math.max(0, math.min(23, math.floor(num(data.hour, 12)))),
        minute = math.max(0, math.min(59, math.floor(num(data.minute, 0)))),
    }
    return out
end

RegisterNetEvent('forger:server:getGarage', function()
    local src = source
    local cid = citizenidOf(src)
    if not cid then
        TriggerClientEvent('forger:client:garageList', src, {})
        return
    end
    local ok, rows = pcall(function()
        return MySQL.query.await('SELECT vehicle, plate FROM player_vehicles WHERE citizenid = ?', { cid })
    end)
    local out = {}
    if ok and rows then
        for _, r in ipairs(rows) do
            if r.vehicle then
                out[#out + 1] = { model = r.vehicle, plate = (r.plate or ''):gsub('%s+$', '') }
            end
        end
    end
    TriggerClientEvent('forger:client:garageList', src, out)
end)

function SceneMaker.saveSceneFor(cid, scene)
    if not cid or type(scene) ~= 'table' then return false end
    local copy = {}
    for k, v in pairs(scene) do copy[k] = v end
    copy.owner = cid
    local ok, encoded = pcall(json.encode, copy)
    if not ok or type(encoded) ~= 'string' then return false end
    MySQL.query('REPLACE INTO forger_scenes (citizenid, data) VALUES (?, ?)', { cid, encoded })
    return true
end

RegisterNetEvent('forger:server:saveScene', function(data)
    local src = source
    if Config.SceneMaker.restricted and not IsPlayerAceAllowed(src, Config.SceneMaker.ace or 'forger.scene') then
        return
    end
    local cid = citizenidOf(src)
    if not cid then
        TriggerClientEvent('forger:client:sceneSaved', src, { ok = false, reason = 'no_character' })
        return
    end
    local scene = sanitize(data)
    if not scene then
        TriggerClientEvent('forger:client:sceneSaved', src, { ok = false, reason = 'bad_data' })
        return
    end
    scene.owner = cid
    local encoded = json.encode(scene)
    MySQL.query('REPLACE INTO forger_scenes (citizenid, data) VALUES (?, ?)', { cid, encoded })
    TriggerClientEvent('forger:client:sceneSaved', src, { ok = true })
end)

RegisterNetEvent('forger:server:clearScene', function()
    local src = source
    local cid = citizenidOf(src)
    if not cid then return end
    MySQL.query('DELETE FROM forger_scenes WHERE citizenid = ?', { cid })
    TriggerClientEvent('forger:client:sceneSaved', src, { ok = true, cleared = true })
end)

local COOP = Config.SceneMaker.coop or {}

if COOP.enabled then
    local sessions  = {}
    local memberOf  = {}
    local invites   = {}
    local nextBucket = COOP.bucketBase or 720000

    local function nameOf(src) return GetPlayerName(src) or ('Player ' .. src) end

    local function pedCoords(src)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then return GetEntityCoords(ped) end
        return nil
    end

    local function pushRoster(session)
        if not session then return end
        local roster = {}
        for _, m in ipairs(session.order) do
            if session.members[m] then
                roster[#roster + 1] = { name = nameOf(m), organizer = (m == session.org) }
            end
        end
        for m in pairs(session.members) do
            TriggerClientEvent('forger:client:sceneRoster', m, roster)
        end
    end

    local function removeMember(src, silent)
        local org = memberOf[src]
        if not org then return end
        local session = sessions[org]
        memberOf[src] = nil
        SetPlayerRoutingBucket(src, 0)
        if session then
            session.members[src] = nil
            for i = #session.order, 1, -1 do
                if session.order[i] == src then table.remove(session.order, i) end
            end
        end
        if not silent then
            TriggerClientEvent('forger:client:sceneEnded', src, { left = true })
        end
        return session
    end

    local function endSession(org, reason)
        local session = sessions[org]
        if not session then return end
        for m in pairs(session.members) do
            memberOf[m] = nil
            SetPlayerRoutingBucket(m, 0)
            TriggerClientEvent('forger:client:sceneEnded', m, { reason = reason })
        end
        sessions[org] = nil
    end

    local function leaveAny(src)
        invites[src] = nil
        local org = memberOf[src]
        if not org then return end
        if org == src then
            endSession(src, 'organizer_left')
        else
            local session = removeMember(src)
            if session then pushRoster(session) end
        end
    end
    SceneMaker.leaveCoop = leaveAny

    RegisterNetEvent('forger:server:sceneStart', function()
        local src = source
        leaveAny(src)
        local bucket = nextBucket
        nextBucket = nextBucket + 1
        if nextBucket > (COOP.bucketBase or 720000) + 500 then nextBucket = COOP.bucketBase or 720000 end
        sessions[src] = {
            org = src, members = { [src] = true }, order = { src },
            bucket = bucket, config = { hour = 12, minute = 0, weather = 'CLEAR', cam = nil },
        }
        memberOf[src] = src
        SetPlayerRoutingBucket(src, bucket)
        pushRoster(sessions[src])
    end)

    RegisterNetEvent('forger:server:sceneInvite', function(targets)
        local src = source
        local session = sessions[src]
        if not session or session.org ~= src then return end
        if type(targets) ~= 'table' then return end
        local myPos = pedCoords(src)
        if not myPos then return end
        local radius = COOP.inviteRadius or 14.0
        local slots = (COOP.maxInvitees or 4) + 1
        local invited = 0
        for _, tid in ipairs(targets) do
            tid = tonumber(tid)
            if tid and tid ~= src and not memberOf[tid] and not invites[tid] then
                if #session.order + invited >= slots then break end
                local tp = pedCoords(tid)
                if tp and #(myPos - tp) <= radius then
                    invites[tid] = { org = src, expires = os.time() + (COOP.inviteTimeout or 30) }
                    invited = invited + 1
                    TriggerClientEvent('forger:client:sceneInvited', tid, { org = src, orgName = nameOf(src) })
                end
            end
        end
        if invited == 0 then
            TriggerClientEvent('forger:client:sceneNotify', src, 'No nearby players to invite.')
        end
    end)

    RegisterNetEvent('forger:server:sceneInviteRespond', function(accept)
        local src = source
        local inv = invites[src]
        invites[src] = nil
        if not inv then return end
        local session = sessions[inv.org]
        if not session then
            TriggerClientEvent('forger:client:sceneNotify', src, 'That scene is no longer available.')
            return
        end
        if not accept then return end
        if #session.order >= (COOP.maxInvitees or 4) + 1 then
            TriggerClientEvent('forger:client:sceneNotify', src, 'That scene is full.')
            return
        end
        leaveAny(src)
        session.members[src] = true
        session.order[#session.order + 1] = src
        memberOf[src] = inv.org
        SetPlayerRoutingBucket(src, session.bucket)
        TriggerClientEvent('forger:client:sceneJoined', src, { role = 'invitee', config = session.config })
        pushRoster(session)
    end)

    RegisterNetEvent('forger:server:sceneConfig', function(cfg)
        local src = source
        local session = sessions[src]
        if not session or session.org ~= src or type(cfg) ~= 'table' then return end
        local c = session.config
        if cfg.hour ~= nil then c.hour = math.floor(tonumber(cfg.hour) or 12) % 24 end
        if cfg.minute ~= nil then c.minute = math.floor(tonumber(cfg.minute) or 0) % 60 end
        if cfg.weather ~= nil and type(cfg.weather) == 'string' then c.weather = cfg.weather:sub(1, 24) end
        if type(cfg.cam) == 'table' then c.cam = cfg.cam end
        for m in pairs(session.members) do
            if m ~= src then TriggerClientEvent('forger:client:sceneConfigSync', m, session.config) end
        end
    end)

    RegisterNetEvent('forger:server:sceneLeave', function()
        leaveAny(source)
    end)

    RegisterNetEvent('forger:server:sceneRecord', function(cam)
        local src = source
        local session = sessions[src]
        if not session or session.org ~= src then return end
        if session.rec then return end
        if type(cam) == 'table' then session.config.cam = cam end

        session.rec = { snaps = {}, need = 0, done = 0 }
        for m in pairs(session.members) do session.rec.need = session.rec.need + 1 end

        for m in pairs(session.members) do
            TriggerClientEvent('forger:client:sceneSnapshot', m)
        end

        CreateThread(function()
            local deadline = GetGameTimer() + 2500
            while session.rec and session.rec.done < session.rec.need and GetGameTimer() < deadline do
                Wait(50)
            end
            if not sessions[src] or not session.rec then return end

            local members, vehicles = {}, {}
            for m, snap in pairs(session.rec.snaps) do
                local cid = citizenidOf(m)
                if cid and type(snap) == 'table' and type(snap.coords) == 'table' then
                    members[#members + 1] = {
                        citizenid = cid,
                        appearance = snap.appearance,
                        stance = type(snap.stance) == 'string' and snap.stance:sub(1, 48) or 'stand',
                        coords = { x = tonumber(snap.coords.x) or 0.0, y = tonumber(snap.coords.y) or 0.0, z = tonumber(snap.coords.z) or 70.0 },
                        heading = tonumber(snap.heading) or 0.0,
                    }
                    if type(snap.vehicles) == 'table' then
                        for _, v in ipairs(snap.vehicles) do
                            if type(v) == 'table' and type(v.model) == 'string' and type(v.coords) == 'table' and #vehicles < 12 then
                                vehicles[#vehicles + 1] = {
                                    model = v.model:sub(1, 32),
                                    coords = { x = tonumber(v.coords.x) or 0.0, y = tonumber(v.coords.y) or 0.0, z = tonumber(v.coords.z) or 70.0 },
                                    heading = tonumber(v.heading) or 0.0,
                                }
                            end
                        end
                    end
                end
            end

            local base = {
                coop = true,
                members = members,
                vehicles = vehicles,
                cam = session.config.cam,
                weather = session.config.weather,
                hour = session.config.hour,
                minute = session.config.minute,
                recordedAt = os.time(),
            }

            local saved = 0
            for _, mem in ipairs(members) do
                if SceneMaker.saveSceneFor(mem.citizenid, base) then saved = saved + 1 end
            end

            for m in pairs(session.members) do
                TriggerClientEvent('forger:client:sceneRecorded', m, { members = #members, saved = saved })
            end
            session.rec = nil
            endSession(src, 'recorded')
        end)
    end)

    RegisterNetEvent('forger:server:sceneSnapshotReply', function(snap)
        local src = source
        local org = memberOf[src]
        local session = org and sessions[org]
        if not session or not session.rec then return end
        if session.rec.snaps[src] == nil then
            session.rec.snaps[src] = snap or {}
            session.rec.done = session.rec.done + 1
        end
    end)

    CreateThread(function()
        while true do
            local now = os.time()
            for inv, data in pairs(invites) do
                if data.expires <= now then invites[inv] = nil end
            end
            Wait(2000)
        end
    end)

    AddEventHandler('playerDropped', function()
        leaveAny(source)
    end)

    AddEventHandler('onResourceStop', function(res)
        if res ~= GetCurrentResourceName() then return end
        for org in pairs(sessions) do endSession(org, 'resource_stop') end
    end)
end
