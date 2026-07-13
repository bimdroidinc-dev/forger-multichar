-- Scene Maker (client): an in-game builder (/scene) to pose your character,
-- frame an orbit camera, and set time/weather, then save it as this character's
-- selector backdrop. Self-contained: its own camera + NUI messages so it never
-- collides with the selector's scene code.

if not (Config.SceneMaker and Config.SceneMaker.enabled) then return end

local SM = {
    active = false,
    cam = nil,
    opts = nil,      -- { angle, height, distance, fov, speed }
    cur = nil,       -- eased camera values
    stance = 'stand',
    weather = 'CLEAR',
    hour = 12,
    minute = 0,
    moving = false,
    vehicles = {},   -- placed: { entity, model, plate, coords, heading }
    ghost = nil,     -- vehicle being positioned
    placing = false,
    session = nil,   -- co-op: { role = 'organizer'|'invitee' }
    members = 1,     -- member count (from roster)
}
local COOP = Config.SceneMaker.coop or {}

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local function drawHint(txt)
    SetTextFont(4) SetTextScale(0.45, 0.45) SetTextColour(255, 255, 255, 220)
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(txt)
    EndTextCommandDisplayText(0.5, 0.92)
end

local function stanceById(id)
    for _, s in ipairs(Config.SceneMaker.stances) do
        if s.id == id then return s end
    end
    return nil
end

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function lerp(a, b, t) return a + (b - a) * t end

-- The point the camera orbits: the group centroid while co-op (so the whole
-- scene is framed), otherwise the local ped.
local function camFocus()
    if SM.session and SM.members > 1 then
        local sx, sy, sz, n = 0.0, 0.0, 0.0, 0
        for _, pl in ipairs(GetActivePlayers()) do
            local pp = GetPlayerPed(pl)
            if pp and pp ~= 0 and DoesEntityExist(pp) then
                local c = GetEntityCoords(pp)
                sx, sy, sz, n = sx + c.x, sy + c.y, sz + c.z, n + 1
            end
        end
        if n > 0 then return vector3(sx / n, sy / n, sz / n) end
    end
    return GetEntityCoords(PlayerPedId())
end

-- Frame the orbit camera around the focus point. SM.cur eases toward SM.opts each
-- frame so slider changes glide instead of snapping (no jank).
local function updateCam()
    if not SM.cam or not SM.cur then return end
    local s = camFocus()
    local o, c = SM.opts, SM.cur
    local t = 0.20
    c.angle = c.angle + (((o.angle - c.angle + 540.0) % 360.0) - 180.0) * t
    c.distance = lerp(c.distance, o.distance, t)
    c.height = lerp(c.height, o.height, t)
    c.fov = lerp(c.fov, o.fov, t)
    local a = math.rad(c.angle)
    SetCamCoord(SM.cam, s.x + math.cos(a) * c.distance, s.y + math.sin(a) * c.distance, s.z + c.height)
    PointCamAtCoord(SM.cam, s.x, s.y, s.z + 0.35)
    SetCamFov(SM.cam, c.fov)
end

local function applyStance(id)
    local st = stanceById(id) or stanceById('stand')
    if not st then return end
    SM.stance = st.id
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    if st.scenario then
        TaskStartScenarioInPlace(ped, st.scenario, 0, true)
    elseif st.dict and st.anim then
        RequestAnimDict(st.dict)
        local t = GetGameTimer() + 3000
        while not HasAnimDictLoaded(st.dict) and GetGameTimer() < t do Wait(0) end
        TaskPlayAnim(ped, st.dict, st.anim, 8.0, 8.0, -1, st.flag or 1, 0, false, false, false)
    end
end

-- Are we loaded as a character? The isLoggedIn state bag isn't set on every
-- framework/config, so fall back to the framework's own player data, and if we
-- genuinely can't tell, allow it (the server re-checks before saving).
-- Ground-snap helper: puts a vehicle flat on the surface below so it never
-- floats or sinks. Repeated calls during placement keep it planted.
local function planted(veh)
    if not DoesEntityExist(veh) then return end
    SetVehicleOnGroundProperly(veh)
end

-- Start positioning a garage vehicle. Spawns as a translucent ghost the player
-- nudges with arrows and rotates with Q/E, staying planted every frame, then
-- confirms with Enter (or cancels with Backspace).
local function startPlaceVehicle(model, plate)
    if not SM.active or SM.placing then return end
    for _, v in ipairs(SM.vehicles) do
        if v.plate == plate then notify('That vehicle is already in the scene.') return end
    end

    local hash = joaat(model)
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(0) end
    if not HasModelLoaded(hash) then notify('Could not load that vehicle.') return end

    SM.placing = true
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'scenePanel', show = false })

    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local a0 = math.rad((SM.cur and SM.cur.angle) or 200.0)
    local networked = SM.session ~= nil  -- co-op: other members must see it
    local veh = CreateVehicle(hash, p.x - math.cos(a0) * 5.5, p.y - math.sin(a0) * 5.5, p.z, 0.0, networked, false)
    SetModelAsNoLongerNeeded(hash)
    if networked then
        SetEntityAsMissionEntity(veh, true, true)
        SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), false)
    end
    SetEntityAlpha(veh, 170, false)
    SetVehicleDoorsLocked(veh, 4)
    SetEntityInvincible(veh, true)
    FreezeEntityPosition(veh, true)  -- frozen the WHOLE time so it can't roll/slide

    -- height from the entity origin to the wheels, so we can plant it precisely
    -- with a raycast instead of physics (physics is what made it slide).
    local minD = GetModelDimensions(hash)
    local zoff = -(minD.z or 0.0)
    local function plantAt(x, y, fallbackZ)
        local f, gz = GetGroundZFor_3dCoord(x, y, fallbackZ + 2.0, false)
        return (f and gz or fallbackZ) + zoff
    end

    do
        local c = GetEntityCoords(veh)
        SetEntityCoordsNoOffset(veh, c.x, c.y, plantAt(c.x, c.y, c.z), false, false, false)
    end
    SM.ghost = veh
    local heading = GetEntityHeading(veh)

    CreateThread(function()
        while SM.placing and SM.active and DoesEntityExist(veh) do
            SendNUIMessage({ action = 'sceneInstruct', show = true, mode = 'vehicle' })

            local a = math.rad((SM.cur and SM.cur.angle) or 200.0)
            local fwdX, fwdY = -math.cos(a), -math.sin(a)
            local rgtX, rgtY = -math.sin(a),  math.cos(a)
            local step = IsControlPressed(0, 21) and 0.14 or 0.05  -- hold Shift = faster
            local c = GetEntityCoords(veh)
            local dx, dy = 0.0, 0.0
            if IsControlPressed(0, 172) then dx = dx + fwdX * step; dy = dy + fwdY * step end
            if IsControlPressed(0, 173) then dx = dx - fwdX * step; dy = dy - fwdY * step end
            if IsControlPressed(0, 175) then dx = dx + rgtX * step; dy = dy + rgtY * step end
            if IsControlPressed(0, 174) then dx = dx - rgtX * step; dy = dy - rgtY * step end
            if dx ~= 0.0 or dy ~= 0.0 then
                local nx, ny = c.x + dx, c.y + dy
                SetEntityCoordsNoOffset(veh, nx, ny, plantAt(nx, ny, c.z), false, false, false)
            end
            if IsControlPressed(0, 44) then heading = (heading + 1.4) % 360.0; SetEntityHeading(veh, heading) end
            if IsControlPressed(0, 38) then heading = (heading - 1.4) % 360.0; SetEntityHeading(veh, heading) end

            if IsControlJustPressed(0, 191) or IsControlJustPressed(0, 201) then
                SetEntityAlpha(veh, 255, false)
                SetEntityVelocity(veh, 0.0, 0.0, 0.0)
                FreezeEntityPosition(veh, true)
                local fc = GetEntityCoords(veh)
                SM.vehicles[#SM.vehicles + 1] = {
                    entity = veh, model = model, plate = plate,
                    coords = { x = fc.x, y = fc.y, z = fc.z }, heading = GetEntityHeading(veh),
                }
                SM.ghost = nil
                SM.placing = false
                local plates = {}
                for _, vv in ipairs(SM.vehicles) do plates[#plates + 1] = vv.plate end
                SendNUIMessage({ action = 'sceneVehicles', count = #SM.vehicles, plates = plates })
                SendNUIMessage({ action = 'sceneInstruct', show = false })
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'scenePanel', show = true })
                return
            elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) then
                if DoesEntityExist(veh) then DeleteEntity(veh) end
                SM.ghost = nil
                SM.placing = false
                SendNUIMessage({ action = 'sceneInstruct', show = false })
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'scenePanel', show = true })
                return
            end
            Wait(0)
        end
    end)
end

local function clearVehicles()
    for _, v in ipairs(SM.vehicles) do
        if DoesEntityExist(v.entity) then DeleteEntity(v.entity) end
    end
    SM.vehicles = {}
    if SM.ghost and DoesEntityExist(SM.ghost) then DeleteEntity(SM.ghost) end
    SM.ghost = nil
    SM.placing = false
end

local function loggedIn()
    local st = LocalPlayer and LocalPlayer.state
    if st and st.isLoggedIn ~= nil then
        if st.isLoggedIn == true then return true end
        -- state bag explicitly false: still double-check the framework below
    end
    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    if ok and type(pd) == 'table' and pd.citizenid then return true end
    local ok2, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok2 and core and core.Functions and core.Functions.GetPlayerData then
        local d = core.Functions.GetPlayerData()
        if type(d) == 'table' and d.citizenid then return true end
    end
    -- explicit false from the state bag wins; otherwise allow and let the server decide
    if st and st.isLoggedIn == false then return false end
    return true
end

function SM.open(role)
    if SM.active then return end
    if not loggedIn() then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('Load a character first.')
        EndTextCommandThefeedPostTicker(false, true)
        return
    end
    role = role or 'organizer'
    SM.role = role
    -- A session (with its own private routing bucket) is created even for solo
    -- building, so the player is isolated and doesn't disturb other players' RP.
    -- Inviting simply adds members to the same bucket.
    SM.session = COOP.enabled and { role = role } or nil
    SM.members = 1
    SM.active = true

    local C = Config.SceneMaker.camera
    SM.opts = {
        angle = C.defaults.angle, height = C.defaults.height,
        distance = C.defaults.distance, fov = C.defaults.fov, speed = C.defaults.speed or 0.0,
    }
    SM.cur = { angle = SM.opts.angle, height = SM.opts.height, distance = SM.opts.distance, fov = SM.opts.fov }
    SM.hour, SM.minute = GetClockHours(), GetClockMinutes()
    SM.weather = Config.SceneMaker.weathers[1] or 'CLEAR'

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    -- The player is already standing correctly where they ran /scene, so do NOT
    -- re-snap: SetEntityCoords drops the ped's ROOT to the ground Z, sinking it
    -- to the chest.
    SM.vehicles = {}
    SM.ghost = nil
    SM.placing = false
    applyStance(SM.stance)

    -- organizer (incl. solo): open a session so we get an isolated private bucket.
    -- invitees are already placed in the organizer's bucket server-side.
    if SM.session and role == 'organizer' then
        TriggerServerEvent('forger:server:sceneStart')
    end

    local s = camFocus()
    SM.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', s.x, s.y, s.z + SM.opts.height, 0.0, 0.0, 0.0, SM.opts.fov, false, 0)
    SetCamActive(SM.cam, true)
    RenderScriptCams(true, false, 0, true, true)
    updateCam()

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'sceneOpen', data = {
        stances = Config.SceneMaker.stances,
        weathers = Config.SceneMaker.weathers,
        cam = SM.opts,
        weather = SM.weather,
        hour = SM.hour,
        minute = SM.minute,
        role = role,
        coop = COOP.enabled and true or false,
    } })

    CreateThread(function()
        while SM.active do
            if not SM.moving then
                if SM.opts.speed and SM.opts.speed ~= 0.0 then
                    SM.opts.angle = (SM.opts.angle + SM.opts.speed * GetFrameTime()) % 360.0
                end
                updateCam()
            end
            NetworkOverrideClockTime(SM.hour, SM.minute, 0)
            Wait(0)
        end
    end)
end

function SM.close(silent)
    if not SM.active then return end
    local wasSession = SM.session
    SM.active = false
    SM.moving = false
    SM.session = nil
    SM.members = 1
    clearVehicles()
    RenderScriptCams(false, false, 0, true, true)
    if SM.cam then DestroyCam(SM.cam, false) SM.cam = nil end
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'sceneClose' })
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    -- tell the server we left the session (unless the server is the one ending it)
    if wasSession and not silent then
        TriggerServerEvent('forger:server:sceneLeave')
    end
end

-- ---------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------
local function isOrganizer() return SM.role ~= 'invitee' end
local function isInvitee() return SM.role == 'invitee' end

-- push shared time/weather to the session so invitees see the same lighting
local function syncConfig()
    if SM.session and SM.role == 'organizer' then
        TriggerServerEvent('forger:server:sceneConfig', {
            hour = SM.hour, minute = SM.minute, weather = SM.weather,
        })
    end
end

RegisterNUICallback('sceneStance', function(d, cb)
    if SM.active and d and d.id then applyStance(d.id) end
    cb('ok')
end)

RegisterNUICallback('sceneCam', function(d, cb)
    if SM.active and d then
        local L = Config.SceneMaker.camera.limits
        local o = SM.opts
        if d.angle    ~= nil then o.angle = tonumber(d.angle) % 360.0 end
        if d.height   ~= nil then o.height = clamp(tonumber(d.height), L.height[1], L.height[2]) end
        if d.distance ~= nil then o.distance = clamp(tonumber(d.distance), L.distance[1], L.distance[2]) end
        if d.fov      ~= nil then o.fov = clamp(tonumber(d.fov), L.fov[1], L.fov[2]) end
        if d.speed    ~= nil then o.speed = tonumber(d.speed) end
        updateCam()
    end
    cb('ok')
end)

RegisterNUICallback('sceneWeather', function(d, cb)
    if SM.active and d and d.weather then
        SM.weather = d.weather
        SetOverrideWeather(SM.weather)
        SetWeatherTypeNowPersist(SM.weather)
        SetWeatherTypeNow(SM.weather)
        syncConfig()
    end
    cb('ok')
end)

RegisterNUICallback('sceneTime', function(d, cb)
    if SM.active and d then
        if d.hour ~= nil then SM.hour = math.floor(tonumber(d.hour)) % 24 end
        if d.minute ~= nil then SM.minute = math.floor(tonumber(d.minute)) % 60 end
        NetworkOverrideClockTime(SM.hour, SM.minute, 0)
        syncConfig()
    end
    cb('ok')
end)

-- Reposition: hide the panel, hand the player normal control to walk to a spot,
-- press E to lock it in and return to framing.
RegisterNUICallback('sceneMove', function(_, cb)
    cb('ok')
    if not SM.active or SM.moving then return end
    SM.moving = true
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'scenePanel', show = false })
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    RenderScriptCams(false, false, 0, true, true)

    CreateThread(function()
        SendNUIMessage({ action = 'sceneInstruct', show = true, mode = 'move' })
        while SM.moving and SM.active do
            if IsControlJustPressed(0, 38) or IsControlJustPressed(0, 177) then  -- E or Backspace
                SM.moving = false
                SendNUIMessage({ action = 'sceneInstruct', show = false })
                FreezeEntityPosition(ped, true)
                applyStance(SM.stance)
                local s = GetEntityCoords(ped)
                if not SM.cam then
                    SM.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', s.x, s.y, s.z + SM.opts.height, 0.0, 0.0, 0.0, SM.opts.fov, false, 0)
                    SetCamActive(SM.cam, true)
                end
                RenderScriptCams(true, false, 0, true, true)
                updateCam()
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'scenePanel', show = true })
            end
            Wait(0)
        end
    end)
end)

RegisterNUICallback('sceneSave', function(_, cb)
    cb('ok')
    if not SM.active then return end
    -- invitees can't save; only the organizer finishes the scene
    if isInvitee() then
        notify('Only the scene organizer can save the scene.')
        return
    end
    -- co-op with other members: sync the final camera + time/weather, then record
    -- (the server snapshots everyone and saves the scene to all their characters)
    if SM.session and SM.members > 1 then
        TriggerServerEvent('forger:server:sceneConfig', {
            hour = SM.hour, minute = SM.minute, weather = SM.weather,
        })
        TriggerServerEvent('forger:server:sceneRecord', SM.opts)  -- pass the framing directly
        return
    end
    -- solo save
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local vehs = {}
    for _, v in ipairs(SM.vehicles) do
        vehs[#vehs + 1] = { model = v.model, plate = v.plate, coords = v.coords, heading = v.heading }
    end
    TriggerServerEvent('forger:server:saveScene', {
        coords = { x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) },
        stance = SM.stance,
        cam = SM.opts,
        vehicles = vehs,
        weather = SM.weather,
        hour = SM.hour, minute = SM.minute,
    })
end)

-- garage / vehicle placement
RegisterNUICallback('sceneGarage', function(_, cb)
    TriggerServerEvent('forger:server:getGarage')
    cb('ok')
end)

RegisterNUICallback('scenePlaceVehicle', function(d, cb)
    cb('ok')
    if SM.active and d and d.model then startPlaceVehicle(d.model, d.plate or '') end
end)

RegisterNUICallback('sceneRemoveVehicles', function(_, cb)
    clearVehicles()
    SendNUIMessage({ action = 'sceneVehicles', count = 0 })
    cb('ok')
end)

RegisterNetEvent('forger:client:garageList', function(list)
    SendNUIMessage({ action = 'sceneGarage', list = list or {} })
end)

RegisterNUICallback('sceneClear', function(_, cb)
    TriggerServerEvent('forger:server:clearScene')
    cb('ok')
end)

RegisterNUICallback('sceneClose', function(_, cb)
    SM.close()
    cb('ok')
end)

RegisterNetEvent('forger:client:sceneSaved', function(res)
    local msg = 'Scene saved as this character\'s backdrop.'
    if res and res.cleared then msg = 'Scene cleared.'
    elseif not (res and res.ok) then
        msg = (res and res.reason == 'no_character') and 'Load a character first.' or 'Could not save the scene.'
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
    if res and res.ok and not res.cleared then SM.close() end
end)

-- ---------------------------------------------------------------------------
-- co-op
-- ---------------------------------------------------------------------------
local APPEARANCE_RESOURCE = (Config.Appearance and Config.Appearance.resource) or 'illenium-appearance'

local function applyConfigSync(cfg)
    if type(cfg) ~= 'table' then return end
    if cfg.hour ~= nil then SM.hour = math.floor(cfg.hour) % 24 end
    if cfg.minute ~= nil then SM.minute = math.floor(cfg.minute) % 60 end
    if cfg.weather then
        SM.weather = cfg.weather
        SetOverrideWeather(SM.weather); SetWeatherTypeNowPersist(SM.weather); SetWeatherTypeNow(SM.weather)
    end
    NetworkOverrideClockTime(SM.hour, SM.minute, 0)
    SendNUIMessage({ action = 'sceneConfigSync', hour = SM.hour, minute = SM.minute, weather = SM.weather })
end

-- Organizer clicks Invite: gather nearby players and show a picker in the UI.
RegisterNUICallback('sceneInvite', function(_, cb)
    cb('ok')
    if not (SM.active and isOrganizer()) then return end
    local myPos = GetEntityCoords(PlayerPedId())
    local radius = COOP.inviteRadius or 14.0
    local players = {}
    for _, pl in ipairs(GetActivePlayers()) do
        if pl ~= PlayerId() then
            local pp = GetPlayerPed(pl)
            if pp and pp ~= 0 and DoesEntityExist(pp) and #(GetEntityCoords(pp) - myPos) <= radius then
                local sid = GetPlayerServerId(pl)
                players[#players + 1] = { id = sid, name = GetPlayerName(pl) or ('Player ' .. sid) }
            end
        end
    end
    SendNUIMessage({ action = 'sceneInvitePicker', players = players })
end)

-- Organizer picked who to invite: start the co-op session (if not already) and
-- send the invites to exactly those players.
RegisterNUICallback('sceneInviteSend', function(d, cb)
    cb('ok')
    if not (SM.active and isOrganizer() and d and type(d.ids) == 'table' and #d.ids > 0) then return end
    if not SM.session then
        SM.session = { role = 'organizer' }
        TriggerServerEvent('forger:server:sceneStart')
        Wait(90)  -- let the session register server-side
    end
    TriggerServerEvent('forger:server:sceneInvite', d.ids)
    notify('Invite sent to ' .. #d.ids .. ' player(s).')
end)

-- Received an invite: show a NUI prompt, accept/decline with keys.
RegisterNetEvent('forger:client:sceneInvited', function(data)
    if SM.active then return end
    local org = (data and data.orgName) or 'A player'
    SendNUIMessage({ action = 'sceneInvitePrompt', show = true, name = org })
    CreateThread(function()
        local deadline = GetGameTimer() + ((COOP.inviteTimeout or 30) * 1000)
        while GetGameTimer() < deadline do
            if IsControlJustPressed(0, 191) or IsControlJustPressed(0, 201) then
                SendNUIMessage({ action = 'sceneInvitePrompt', show = false })
                TriggerServerEvent('forger:server:sceneInviteRespond', true)
                return
            elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) then
                SendNUIMessage({ action = 'sceneInvitePrompt', show = false })
                TriggerServerEvent('forger:server:sceneInviteRespond', false)
                return
            end
            Wait(0)
        end
        SendNUIMessage({ action = 'sceneInvitePrompt', show = false })
        TriggerServerEvent('forger:server:sceneInviteRespond', false)
    end)
end)

RegisterNetEvent('forger:client:sceneJoined', function(data)
    if SM.active then SM.close(true) end
    SM.open('invitee')
    if data and data.config then applyConfigSync(data.config) end
end)

RegisterNetEvent('forger:client:sceneConfigSync', function(cfg)
    if SM.active then applyConfigSync(cfg) end
end)

RegisterNetEvent('forger:client:sceneRoster', function(roster)
    SM.members = (type(roster) == 'table') and #roster or 1
    SendNUIMessage({ action = 'sceneRoster', roster = roster or {} })
end)

-- Snapshot request (on record): send our appearance + stance + transform + cars.
RegisterNetEvent('forger:client:sceneSnapshot', function()
    if not SM.active then
        TriggerServerEvent('forger:server:sceneSnapshotReply', {})
        return
    end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local appearance
    pcall(function()
        if GetResourceState(APPEARANCE_RESOURCE):find('start') then
            appearance = exports[APPEARANCE_RESOURCE]:getPedAppearance(ped)
        end
    end)
    local vehs = {}
    for _, v in ipairs(SM.vehicles) do
        vehs[#vehs + 1] = { model = v.model, coords = v.coords, heading = v.heading }
    end
    TriggerServerEvent('forger:server:sceneSnapshotReply', {
        coords = { x = c.x, y = c.y, z = c.z },
        heading = GetEntityHeading(ped),
        stance = SM.stance,
        appearance = appearance,
        vehicles = vehs,
    })
end)

RegisterNetEvent('forger:client:sceneRecorded', function(res)
    notify('Scene saved to ' .. ((res and res.saved) or 0) .. ' character(s).')
    SM.close(true)  -- session already ended server-side
end)

RegisterNetEvent('forger:client:sceneEnded', function(data)
    if data and data.reason == 'organizer_left' then notify('The scene organizer left.')
    elseif data and data.reason == 'recorded' then  -- handled by sceneRecorded
    end
    SM.close(true)
end)

RegisterNetEvent('forger:client:sceneNotify', function(msg)
    notify(msg or '')
end)

-- ---------------------------------------------------------------------------
-- entry points
-- ---------------------------------------------------------------------------
RegisterCommand(Config.SceneMaker.command or 'scene', function()
    SM.open()
end, false)

RegisterNetEvent('forger:client:openScene', function()
    SM.open()
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and SM.active then SM.close() end
end)
