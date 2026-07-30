local AUTO_OPEN = Config.AutoOpen ~= false

if AUTO_OPEN then DoScreenFadeOut(0) end

local isOpen = false
local cam = nil
local previewPed = nil
local partnerPed = nil
local sceneId = nil
local pairView = false
local anchorZ = nil
local locationIndex = 1
local poseIndex = 1
local currentGender = 0
local zoomIndex = 1
local filterName = 'none'
local dofOn = false
local pairActive = false
local pairArgs = nil
local walkToken = 0

local spawnPicking = false
local pendingSpawn = nil
local loggedIn = false
local spawnPreviewActive = false
local spawnPreviewToken = 0
local loginLook = nil
local poseLoopToken = 0
local sceneStanceToken = 0
local currentScene = nil
local lastPreviewData = nil
local sceneVehicles = {}
local memberPeds = {}
local locationSwitching = false

local function clearSceneVehicles()
    for _, e in ipairs(sceneVehicles) do
        if DoesEntityExist(e) then DeleteEntity(e) end
    end
    sceneVehicles = {}
    for _, e in ipairs(memberPeds) do
        if DoesEntityExist(e) then DeleteEntity(e) end
    end
    memberPeds = {}
end

local function sceneSelfMember(scene, citizenid)
    if not (scene and scene.members) then return nil end
    for _, m in ipairs(scene.members) do
        if m.citizenid == citizenid then return m end
    end
    return scene.members[1]
end

local PREFS_KEY = 'forger:prefs'
local prefs = {}
local heldWeather = nil
local heldHour, heldMinute = nil, nil

local function loadPrefs()
    local raw = GetResourceKvpString(PREFS_KEY)
    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then return decoded end
    end
    return {}
end

local function savePrefs()
    SetResourceKvp(PREFS_KEY, json.encode(prefs))
end

CreateThread(function()
    math.randomseed(GetGameTimer())
    for _ = 1, 5 do math.random() end
end)

local function loadModel(model)
    if type(model) == 'string' then model = joaat(model) end
    RequestModel(model)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
    return model
end

local function loadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
end

-- Force the correct freemode ped by gender BEFORE the appearance resource runs.
-- Without this a player keeps whatever ped the game spawned them as (a story ped
-- such as Michael) whenever the saved skin does not set a model itself.
local function ensureFreemodeModel(gender)
    local model = (gender == 1) and Config.Appearance.fallbackFemale or Config.Appearance.fallbackMale
    local hash = (type(model) == 'string') and joaat(model) or model

    if GetEntityModel(PlayerPedId()) ~= hash then
        RequestModel(hash)
        local t = GetGameTimer() + 10000
        while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(0) end
        if HasModelLoaded(hash) then
            SetPlayerModel(PlayerId(), hash)
            SetModelAsNoLongerNeeded(hash)
        end
    end

    SetPedDefaultComponentVariation(PlayerPedId())
    SetPedComponentVariation(PlayerPedId(), 4, 0, 0, 0)
    SetPedComponentVariation(PlayerPedId(), 6, 0, 0, 0)
    SetPedComponentVariation(PlayerPedId(), 11, 0, 0, 0)
end

-- In Lua an export MUST be called with the colon (exports[res]:fn()). The bracket
-- form drops `ped` into the proxy's hidden self slot, so illenium receives
-- (appearance, nil) and dresses nothing. The export name is dynamic, so we
-- reproduce the colon call by passing the proxy as the self argument.
local function applyPedAppearance(ped, appearance)
    if not ped or not DoesEntityExist(ped) then return false end
    if type(appearance) ~= 'table' or next(appearance) == nil then return false end
    local res = Config.Appearance.resource
    if not res or res == 'none' then return false end
    local fn = Config.Appearance.applyExport or 'setPedAppearance'
    local proxy = exports[res]
    local ok = pcall(function() proxy[fn](proxy, ped, appearance) end)
    return ok
end

local function applyAppearance(ped, character)
    SetPedDefaultComponentVariation(ped)

    if not character or character.__empty then return end

    local res = Config.Appearance.resource
    if res == 'none' then return end

    if character.appearance and (res == 'illenium-appearance' or res == 'fivem-appearance') then
        applyPedAppearance(ped, character.appearance)
    end
end

local camParams = nil
local camStart = 0

local function surfaceZAt(x, y, zGuess)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        x, y, zGuess + 6.0, x, y, zGuess - 12.0, 1 + 16, 0, 7)
    local _, hit, endCoords = GetShapeTestResult(handle)
    if hit and endCoords and endCoords.z and endCoords.z ~= 0.0 then
        return endCoords.z
    end
    local found, gz = GetGroundZFor_3dCoord(x, y, zGuess + 6.0, false)
    if found then return gz end
    return zGuess
end

local function emoteList()
    return (Config.Emotes and Config.Emotes.list) or {}
end

local currentJobName, currentGangName = nil, nil

local function locationMatchesGroup(loc, name)
    if not (loc.group and name) then return false end
    if type(loc.group) == 'table' then
        for _, g in ipairs(loc.group) do
            if g == name then return true end
        end
        return false
    end
    return loc.group == name
end

local locCache = nil
local locCacheKey = nil

local function filteredLocations(list)
    local key = tostring(currentJobName) .. '|' .. tostring(currentGangName)
    if locCache and locCacheKey == key then return locCache end

    local grouped, public = {}, {}
    for _, loc in ipairs(list) do
        if loc.group then
            if locationMatchesGroup(loc, currentJobName) or locationMatchesGroup(loc, currentGangName) then
                grouped[#grouped + 1] = loc
            end
        else
            public[#public + 1] = loc
        end
    end

    local out = list
    if #grouped > 0 then out = grouped
    elseif #public > 0 then out = public end

    locCache, locCacheKey = out, key
    return out
end

local function invalidateLocationCache()
    locCache, locCacheKey = nil, nil
end

local function activeLocations()
    if pairActive and Config.CoupleLocations and #Config.CoupleLocations > 0 then
        return Config.CoupleLocations
    end
    return filteredLocations(Config.Locations)
end

local function activeLoc()
    local locs = activeLocations()
    local idx = locationIndex
    if idx < 1 or idx > #locs then idx = 1 end
    return locs[idx], idx
end

local function locPed(loc)
    if loc.ped then return loc.ped end
    if loc.from then return loc.from end
    return vec4(0.0, 0.0, 70.0, 0.0)
end

-- Request collision FIRST and wait for the world, then place and hold the
-- position. Placing before the area has streamed leaves the ped floating or
-- buried to the chest.
local function placePed(ped, x, y, z, heading, waitForCollision)
    local S = Config.Scene or {}
    if not (ped and DoesEntityExist(ped)) then return z end

    RequestCollisionAtCoord(x, y, z)

    if waitForCollision then
        local deadline = GetGameTimer() + (S.collisionTimeoutMs or 5000)
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
            RequestCollisionAtCoord(x, y, z)
            Wait(0)
        end
    end

    local finalZ = z
    if S.groundSnap ~= false then
        finalZ = surfaceZAt(x, y, z)
        SetEntityCoords(ped, x, y, finalZ, false, false, false, false)
    else
        SetEntityCoordsNoOffset(ped, x, y, finalZ, false, false, false)
    end
    SetEntityHeading(ped, heading or 0.0)

    local tol = S.placeTolerance or 1.0
    local deadline = GetGameTimer() + (S.placeTimeoutMs or 3000)
    local target = vector3(x, y, finalZ)
    while DoesEntityExist(ped) and GetGameTimer() < deadline do
        if #(GetEntityCoords(ped) - target) <= tol then break end
        if S.groundSnap ~= false then
            SetEntityCoords(ped, x, y, finalZ, false, false, false, false)
        else
            SetEntityCoordsNoOffset(ped, x, y, finalZ, false, false, false)
        end
        SetEntityHeading(ped, heading or 0.0)
        Wait(0)
    end

    return finalZ
end

local function playStance(ped, stanceId)
    if not (Config.SceneMaker and Config.SceneMaker.stances) then return false end
    local st
    for _, s in ipairs(Config.SceneMaker.stances) do
        if s.id == stanceId then st = s break end
    end
    if not st then return false end
    if not DoesEntityExist(ped) then return false end

    local myToken = sceneStanceToken
    local function valid() return myToken == sceneStanceToken and DoesEntityExist(ped) end

    local function isPosed()
        if not DoesEntityExist(ped) then return false end
        if st.scenario then return IsPedUsingScenario(ped, st.scenario) end
        if st.dict and st.anim then return IsEntityPlayingAnim(ped, st.dict, st.anim, 3) end
        return false
    end

    local function apply()
        if not DoesEntityExist(ped) then return end
        SetPedCanRagdoll(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, true)
        ClearPedTasksImmediately(ped)
        if st.dict and st.anim then
            if HasAnimDictLoaded(st.dict) then
                TaskPlayAnim(ped, st.dict, st.anim, 8.0, -8.0, -1, st.flag or 1, 0.0, false, false, false)
                SetPedKeepTask(ped, true)
            end
        elseif st.scenario then
            local c = GetEntityCoords(ped)
            local hd = GetEntityHeading(ped)
            FreezeEntityPosition(ped, false)
            SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
            SetEntityHeading(ped, hd)
            TaskStartScenarioInPlace(ped, st.scenario, 0, true)
            SetPedKeepTask(ped, true)
        end
    end

    CreateThread(function()
        local c0 = GetEntityCoords(ped)
        local dl = GetGameTimer() + 8000
        while valid() and not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < dl do
            RequestCollisionAtCoord(c0.x, c0.y, c0.z)
            Wait(0)
        end
        if not valid() then return end

        if st.dict and st.anim then
            RequestAnimDict(st.dict)
            local adl = GetGameTimer() + 3000
            while not HasAnimDictLoaded(st.dict) and GetGameTimer() < adl do Wait(0) end
            if not valid() then return end
        end

        apply()
        local stableSince = nil
        local settleDl = GetGameTimer() + 1500
        while valid() and GetGameTimer() < settleDl do
            if isPosed() then
                stableSince = stableSince or GetGameTimer()
                if GetGameTimer() - stableSince >= 300 then break end
            else
                stableSince = nil
                apply()
            end
            Wait(50)
        end

        if st.dict and st.anim then RemoveAnimDict(st.dict) end
        if valid() then SetEntityAlpha(ped, 255, false) end

        if st.scenario then
            local anchor = GetEntityCoords(ped)
            local ah = GetEntityHeading(ped)
            while valid() do
                Wait(1500)
                if not valid() then return end
                if #(GetEntityCoords(ped) - anchor) > 0.12 then
                    SetEntityCoordsNoOffset(ped, anchor.x, anchor.y, anchor.z, false, false, false)
                    SetEntityHeading(ped, ah)
                end
            end
        end
    end)
    return true
end

-- Watchdog around ForgerPlayEmote. A scenario is a continuous hold, so it is only
-- re-applied if cleared (the appearance apply does this); a dict+anim cycles.
-- Scenario peds must stay UNFROZEN to animate, so the position is pinned instead.
local function loopEmote(ped, emote)
    if not emote then return end
    poseLoopToken = poseLoopToken + 1
    local myToken = poseLoopToken
    local L = Config.EmoteLoop or {}

    CreateThread(function()
        local applied = ForgerPlayEmote(ped, emote)
        if not applied then return end

        if applied.scenario or applied.animName then
            local anchor = GetEntityCoords(ped)
            local heading = GetEntityHeading(ped)

            local settleDl = GetGameTimer() + 1500
            while myToken == poseLoopToken and ped == previewPed and DoesEntityExist(ped)
                  and GetGameTimer() < settleDl do
                if not ForgerIsPlayingEmote(ped, applied) then
                    ForgerPlayEmote(ped, applied)
                end
                Wait(50)
            end
            if myToken ~= poseLoopToken then return end

            while myToken == poseLoopToken and ped == previewPed and DoesEntityExist(ped) do
                if not ForgerIsPlayingEmote(ped, applied) then
                    ForgerPlayEmote(ped, applied)
                end
                if #(GetEntityCoords(ped) - anchor) > 0.12 then
                    SetEntityCoordsNoOffset(ped, anchor.x, anchor.y, anchor.z, false, false, false)
                    SetEntityHeading(ped, heading)
                end
                Wait(500)
            end
            return
        end

        local spaced = L.spaced
        local durMs = math.max((GetAnimDuration(applied.dict, applied.anim) or 0) * 1000.0, L.minCycleMs or 2200)
        local gapMs = (L.gapSeconds or 1.4) * 1000.0
        while myToken == poseLoopToken and ped == previewPed and DoesEntityExist(ped) do
            local endAt = GetGameTimer() + durMs
            while myToken == poseLoopToken and GetGameTimer() < endAt do
                if ped == previewPed and DoesEntityExist(ped)
                   and not IsEntityPlayingAnim(ped, applied.dict, applied.anim, 3) then
                    ForgerPlayEmote(ped, applied)
                end
                Wait(120)
            end
            if myToken ~= poseLoopToken then return end
            if spaced then
                if DoesEntityExist(ped) then StopAnimTask(ped, applied.dict, applied.anim, 4.0) end
                Wait(gapMs)
            end
            if myToken ~= poseLoopToken then return end
            ForgerPlayEmote(ped, applied)
        end
    end)
end

local scenarioSceneId = nil

local function clearPropScenario()
    if scenarioSceneId then
        pcall(function() DisposeSynchronizedScene(scenarioSceneId) end)
        scenarioSceneId = nil
    end
end

local function setupPropScenario(ped, def, x, y, z, heading)
    if not (def and def.dict and def.anim) then return false end
    if not (ped and DoesEntityExist(ped)) then return false end

    clearPropScenario()
    loadAnimDict(def.dict)
    if not HasAnimDictLoaded(def.dict) then return false end

    local originZ = z + (def.zOffset or 0.0)
    local rotZ = def.rotZ or heading or 0.0

    scenarioSceneId = CreateSynchronizedScene(x, y, originZ, 0.0, 0.0, rotZ, 2)
    SetSynchronizedSceneLooped(scenarioSceneId, true)

    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    TaskSynchronizedScene(ped, scenarioSceneId, def.dict, def.anim, 1.5, -4.0, 0, 0, 1148846080, 0)

    for _, prop in ipairs(def.props or {}) do
        local hash = (type(prop.model) == 'string') and joaat(prop.model) or prop.model
        RequestModel(hash)
        local dl = GetGameTimer() + 4000
        while not HasModelLoaded(hash) and GetGameTimer() < dl do Wait(0) end
        if HasModelLoaded(hash) then
            local obj = CreateObject(hash, x, y, originZ, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            PlaySynchronizedEntityAnim(obj, scenarioSceneId, prop.anim, def.dict, 1.0, -4.0, 1, 1000.0)
            sceneVehicles[#sceneVehicles + 1] = obj
        end
    end

    return true
end

local function spawnPreviewPed(character, keepPose)
    if previewPed and DoesEntityExist(previewPed) then
        DeleteEntity(previewPed)
        previewPed = nil
    end
    clearPropScenario()
    clearSceneVehicles()
    NewLoadSceneStop()
    sceneStanceToken = sceneStanceToken + 1

    currentScene = nil
    local selfMember = nil
    if not pairActive and prefs.customScene and character and type(character.scene) == 'table' then
        local sc = character.scene
        if sc.coords or sc.members then
            currentScene = sc
            if sc.members then selfMember = sceneSelfMember(sc, character.citizenid) end
        end
    end

    local loc = activeLoc()
    local lp = locPed(loc)
    if currentScene then
        if selfMember and selfMember.coords then
            lp = { x = selfMember.coords.x, y = selfMember.coords.y, z = selfMember.coords.z, w = selfMember.heading or 0.0 }
        elseif currentScene.coords then
            lp = { x = currentScene.coords.x, y = currentScene.coords.y, z = currentScene.coords.z, w = currentScene.coords.w or 0.0 }
        end
    end
    local gender = character and character.gender or currentGender
    currentGender = gender

    local model
    if character and type(character.appearance) == 'table' and character.appearance.model then
        model = character.appearance.model
    else
        model = gender == 1 and Config.Appearance.fallbackFemale or Config.Appearance.fallbackMale
    end
    model = loadModel(model)

    local isScene = currentScene ~= nil
    previewPed = CreatePed(2, model, lp.x, lp.y, lp.z + (isScene and 0.0 or 3.0), lp.w, false, true)
    SetEntityInvincible(previewPed, true)
    SetBlockingOfNonTemporaryEvents(previewPed, true)
    SetEntityAlpha(previewPed, 255, false)

    if isScene then
        SetEntityAlpha(previewPed, 0, false)
        SetEntityCoordsNoOffset(previewPed, lp.x, lp.y, lp.z, false, false, false)
        SetEntityHeading(previewPed, lp.w or 0.0)
        anchorZ = lp.z
        SetFocusPosAndVel(lp.x, lp.y, lp.z, 0.0, 0.0, 0.0)
        RequestCollisionAtCoord(lp.x, lp.y, lp.z)
        NewLoadSceneStartSphere(lp.x, lp.y, lp.z, 80.0, 0)
        CreateThread(function()
            local dl = GetGameTimer() + 6000
            while not IsNewLoadSceneLoaded() and GetGameTimer() < dl do
                RequestCollisionAtCoord(lp.x, lp.y, lp.z)
                Wait(0)
            end
            NewLoadSceneStop()
        end)
    else
        SetFocusPosAndVel(lp.x, lp.y, lp.z, 0.0, 0.0, 0.0)
        anchorZ = placePed(previewPed, lp.x, lp.y, lp.z, lp.w, false)
        if not HasCollisionLoadedAroundEntity(previewPed) then
            SetEntityAlpha(previewPed, 0, false)
            local pedRef = previewPed
            CreateThread(function()
                local z = placePed(pedRef, lp.x, lp.y, lp.z, lp.w, true)
                if pedRef == previewPed and DoesEntityExist(pedRef) then
                    anchorZ = z
                    SetEntityAlpha(pedRef, 255, false)
                end
            end)
        end
    end
    FreezeEntityPosition(previewPed, true)

    applyAppearance(previewPed, character)
    SetModelAsNoLongerNeeded(model)

    if character and type(character.appearance) == 'table' then
        local pedRef = previewPed
        local look = character.appearance
        CreateThread(function()
            Wait(0)
            Wait(0)
            if pedRef == previewPed and DoesEntityExist(pedRef) then
                applyPedAppearance(pedRef, look)
            end
        end)
    end

    if currentScene then
        poseLoopToken = poseLoopToken + 1
        if not playStance(previewPed, (selfMember and selfMember.stance) or currentScene.stance) then
            SetEntityAlpha(previewPed, 255, false)
        end

        if currentScene.members then
            for _, m in ipairs(currentScene.members) do
                if m.coords and m.citizenid ~= character.citizenid then
                    local mm = (type(m.appearance) == 'table' and m.appearance.model) or joaat('mp_m_freemode_01')
                    RequestModel(mm)
                    local dl = GetGameTimer() + 3000
                    while not HasModelLoaded(mm) and GetGameTimer() < dl do Wait(0) end
                    if HasModelLoaded(mm) then
                        local mp = CreatePed(2, mm, m.coords.x, m.coords.y, m.coords.z, m.heading or 0.0, false, true)
                        SetModelAsNoLongerNeeded(mm)
                        SetEntityInvincible(mp, true)
                        SetBlockingOfNonTemporaryEvents(mp, true)
                        SetEntityAlpha(mp, 0, false)
                        local mf, mgz = GetGroundZFor_3dCoord(m.coords.x, m.coords.y, m.coords.z + 1.0, false)
                        if mf then SetEntityCoordsNoOffset(mp, m.coords.x, m.coords.y, mgz, false, false, false) end
                        FreezeEntityPosition(mp, true)
                        if type(m.appearance) == 'table' then
                            applyPedAppearance(mp, m.appearance)
                        end
                        if not playStance(mp, m.stance) then
                            SetEntityAlpha(mp, 255, false)
                        end
                        memberPeds[#memberPeds + 1] = mp
                    end
                end
            end
        end

        if currentScene.weather then
            SetWeatherTypeNowPersist(currentScene.weather)
            SetWeatherTypeNow(currentScene.weather)
        end
        if currentScene.hour then
            NetworkOverrideClockTime(currentScene.hour, currentScene.minute or 0, 0)
        end
        if type(currentScene.vehicles) == 'table' then
            for _, v in ipairs(currentScene.vehicles) do
                if v.model and v.coords then
                    local h = joaat(v.model)
                    RequestModel(h)
                    local dl = GetGameTimer() + 4000
                    while not HasModelLoaded(h) and GetGameTimer() < dl do Wait(0) end
                    if HasModelLoaded(h) then
                        local veh = CreateVehicle(h, v.coords.x + 0.0, v.coords.y + 0.0, v.coords.z + 0.0, v.heading or 0.0, false, false)
                        SetModelAsNoLongerNeeded(h)
                        SetEntityInvincible(veh, true)
                        SetVehicleDoorsLocked(veh, 4)
                        SetEntityCoordsNoOffset(veh, v.coords.x + 0.0, v.coords.y + 0.0, v.coords.z + 0.0, false, false, false)
                        SetEntityHeading(veh, v.heading or 0.0)
                        SetVehicleOnGroundProperly(veh)
                        FreezeEntityPosition(veh, true)
                        sceneVehicles[#sceneVehicles + 1] = veh
                    end
                end
            end
        end
        return
    end

    if previewPed and DoesEntityExist(previewPed) then
        ClearPedTasksImmediately(previewPed)
    end

    if (loc.mode == 2) and loc.scenario then
        local def = (Config.PropScenarios or {})[loc.scenario]
        poseLoopToken = poseLoopToken + 1
        if setupPropScenario(previewPed, def, lp.x, lp.y, (anchorZ or lp.z), lp.w) then
            return
        end
        print(('^3[forger-multicharacter] prop scenario "%s" could not be built; using an emote instead.^0')
            :format(tostring(loc.scenario)))
    end

    local emotes = emoteList()
    local emote
    if keepPose and poseIndex and emotes[poseIndex] then
        emote = emotes[poseIndex]
    elseif loc.emote then
        emote = loc.emote
        poseIndex = 1
    elseif #emotes > 0 then
        if Config.Emotes and Config.Emotes.randomOnLoad ~= false then
            poseIndex = math.random(#emotes)
        else
            poseIndex = 1
        end
        emote = emotes[poseIndex]
    end

    loopEmote(previewPed, emote)
end

local function buildCamParams()
    local C = Config.Camera
    local zoom = (C.zoom and C.zoom[zoomIndex]) or {}
    local locData = activeLoc()

    local p = {
        mode = (locData and tonumber(locData.mode)) or 1,
        motion = C.motion,
        distance = zoom.distance or C.distance or 3.1,
        height = zoom.height or C.height or 0.62,
        pointAt = zoom.pointAt or C.pointAt or 0.62,
        fov = zoom.fov or C.fov or 44.0,
        offset = zoom.offset or vec3(-1.5, 1.5, 0.6),
        focus = zoom.focus or vec3(0.3, 0.0, 0.6),
        soloFov = zoom.soloFov or 16.0,
        swayArc = C.swayArc,
        swaySpeed = C.swaySpeed, orbitSpeed = C.orbitSpeed,
        pushAmount = C.pushAmount, pushSpeed = C.pushSpeed,
    }

    if locData then
        if locData.camCoords then p.camCoords = locData.camCoords end
        if locData.focusOffset then p.focusOffset = locData.focusOffset end
        if locData.blurOptions then p.blurOptions = locData.blurOptions end
        if locData.fov then p.soloFov = locData.fov + 0.0 p.fov = locData.fov + 0.0 end
    end

    if p.mode == 2 then
        local add = C.scenarioOffsetAdd or vec3(-0.3, 0.6, 0.15)
        p.offset = vec3(p.offset.x + add.x, p.offset.y + add.y, p.offset.z + add.z)
        p.soloFov = p.soloFov + (C.scenarioFovAdd or 6.0)
    end

    local locCam = locData and locData.cam
    if type(locCam) == 'table' then
        for k, v in pairs(locCam) do p[k] = v end
    end

    if pairView then
        p.mode = 1
        p.motion = C.pairMotion or p.motion
        p.distance = p.distance + (C.pairDistanceAdd or 1.3)
        p.height = p.height + (C.pairHeightAdd or 0.2)
        p.pointAt = p.pointAt + (C.pairPointAtAdd or 0.18)
        p.fov = p.fov + (C.pairFovAdd or 5.0)
        p.swayArc = C.pairSwayArc or p.swayArc
    end
    return p
end

local posturePed = nil
local function applyPosture(p)
    if (Config.Camera.posture or 'side') ~= 'front' then return end
    if not (previewPed and DoesEntityExist(previewPed)) then return end
    if posturePed == previewPed then return end
    if pairView or currentScene then return end
    posturePed = previewPed
    local rot = math.deg(math.atan(-p.offset.x, p.offset.y))
    SetEntityHeading(previewPed, GetEntityHeading(previewPed) + rot)
end

local function computeCamPose(t)
    local p = camParams
    local loc = activeLoc()
    local lp = locPed(loc)

    if currentScene then
        local sc = currentScene.cam or {}
        local fx, fy, fz
        if currentScene.members then
            local sx, sy, sz, n = 0.0, 0.0, 0.0, 0
            for _, m in ipairs(currentScene.members) do
                if m.coords then sx, sy, sz, n = sx + m.coords.x, sy + m.coords.y, sz + m.coords.z, n + 1 end
            end
            if n > 0 then fx, fy, fz = sx / n, sy / n, sz / n end
        end
        if not fx and previewPed and DoesEntityExist(previewPed) then
            local c = GetEntityCoords(previewPed)
            fx, fy, fz = c.x, c.y, c.z
        end
        if fx then
            local dist = p.distance
            local height = p.height
            local pointAt = p.pointAt or 0.62
            local fov = p.fov
            local a = math.rad((tonumber(sc.angle) or 200.0) + (tonumber(sc.speed) or 0.0) * t)
            return fx + math.cos(a) * dist, fy + math.sin(a) * dist, fz + height,
                   fx, fy, fz + pointAt, fov
        end
    end

    if p.mode == 3 and p.camCoords and not pairView then
        local fo = p.focusOffset or vec3(0.0, 0.0, 0.5)
        local pc = (previewPed and DoesEntityExist(previewPed)) and GetEntityCoords(previewPed)
                   or vector3(lp.x, lp.y, (anchorZ or lp.z))
        return p.camCoords.x, p.camCoords.y, p.camCoords.z,
               pc.x + fo.x, pc.y + fo.y, pc.z + fo.z, p.soloFov
    end

    if (p.mode == 1 or p.mode == 2) and not pairView and not (loc.type == 'walk')
       and previewPed and DoesEntityExist(previewPed) then
        local ox, oy, oz = p.offset.x, p.offset.y, p.offset.z
        local fx, fy, fz = p.focus.x, p.focus.y, p.focus.z

        if p.motion == 'sway' then
            ox = ox + (p.swayArc or 14.0) * 0.02 * math.sin(t * (p.swaySpeed or 0.05) * 2.0 * math.pi)
        elseif p.motion == 'pan' then
            ox = ox + (p.panArc or 16.0) * 0.02 * math.sin(t * (p.panSpeed or 0.02) * 2.0 * math.pi)
        elseif p.motion == 'push' then
            local push = (p.pushAmount or 0.5) * math.sin(t * (p.pushSpeed or 0.06) * 2.0 * math.pi)
            oy = oy + push
        end

        local camPos = GetOffsetFromEntityInWorldCoords(previewPed, ox, oy, oz)
        local aim = GetOffsetFromEntityInWorldCoords(previewPed, fx, fy, fz)
        return camPos.x, camPos.y, camPos.z, aim.x, aim.y, aim.z, p.soloFov
    end

    local cx, cy, cz, baseAngle
    if loc.type == 'walk' and previewPed and DoesEntityExist(previewPed) then
        local c = GetEntityCoords(previewPed)
        cx, cy, cz = c.x, c.y, c.z
        local fwd = GetEntityForwardVector(previewPed)
        baseAngle = math.atan(fwd.y, fwd.x)
        if p.view == 'back' then baseAngle = baseAngle + math.pi end
    elseif pairView then
        cx, cy, cz = lp.x, lp.y, (anchorZ or lp.z)
        local w = math.rad(lp.w)
        local fx, fy = -math.sin(w), math.cos(w)
        baseAngle = math.atan(fy, fx)
        if p.view == 'back' then
            baseAngle = baseAngle + math.pi
        else
            baseAngle = baseAngle + math.rad(34.0)
        end
    else
        local c = GetEntityCoords(previewPed)
        cx, cy, cz = c.x, c.y, c.z
        local fwd = GetEntityForwardVector(previewPed)
        baseAngle = math.atan(fwd.y, fwd.x)
        if p.view == 'back' then baseAngle = baseAngle + math.pi end
    end

    local angle, distance = baseAngle, p.distance
    if p.motion == 'sway' then
        angle = baseAngle + math.rad(p.swayArc or 14.0) * math.sin(t * (p.swaySpeed or 0.05) * 2.0 * math.pi)
    elseif p.motion == 'orbit' then
        angle = baseAngle + math.rad((p.orbitSpeed or 3.0) * t)
    elseif p.motion == 'pan' then
        angle = baseAngle + math.rad(p.panArc or 16.0) * math.sin(t * (p.panSpeed or 0.02) * 2.0 * math.pi)
    elseif p.motion == 'push' then
        distance = p.distance + (p.pushAmount or 0.5) * math.sin(t * (p.pushSpeed or 0.06) * 2.0 * math.pi)
    end

    local camX = cx + math.cos(angle) * distance
    local camY = cy + math.sin(angle) * distance
    local camZ = cz + p.height
    return camX, camY, camZ, cx, cy, cz + p.pointAt, p.fov
end

local introFrom = nil
local introStart = 0
local introDur = 0

local function beginIntro(cx, cy, cz, fov)
    local I = Config.Camera.intro or {}
    if I.enabled == false then introFrom = nil return end
    local j = I.jitter or 0.3
    introFrom = { x = cx + j * 0.5, y = cy - j, z = cz + j * 0.2, fov = fov - (I.fovOffset or 3.0) }
    introStart = GetGameTimer()
    introDur = I.duration or 5000
end

local function lerp(a, b, k) return a + (b - a) * k end

local function applyIntro(cx, cy, cz, fov)
    if not introFrom then return cx, cy, cz, fov end
    local k = (GetGameTimer() - introStart) / introDur
    if k >= 1.0 then introFrom = nil return cx, cy, cz, fov end
    if k < 0.0 then k = 0.0 end
    local e = 1.0 - (1.0 - k) * (1.0 - k)
    return lerp(introFrom.x, cx, e), lerp(introFrom.y, cy, e), lerp(introFrom.z, cz, e),
           lerp(introFrom.fov, fov, e)
end

local function applySceneDof()
    local D = Config.Camera.dof or {}
    if D.enabled == false or not cam then return end
    local blur = camParams and camParams.blurOptions
    SetCamUseShallowDofMode(cam, true)
    SetCamNearDof(cam, (blur and blur.near) or D.near or 0.5)
    local far = (blur and blur.far)
    if not far then far = pairView and (D.pairFar or 3.0) or (D.far or 2.0) end
    SetCamFarDof(cam, far)
    SetCamDofStrength(cam, D.strength or 1.0)
    pcall(function() SetCamDofMaxNearInFocusDistanceBlendLevel(cam, 0.5) end)
    pcall(function() SetCamDofMaxNearInFocusDistance(cam, D.maxNearInFocus or 1.5) end)
    pcall(function() SetCamDofFocusDistanceBias(cam, D.focusBias or 2.0) end)
    SetUseHiDof()
end

local function updateCameraFrame()
    if not cam or not camParams or not previewPed or not DoesEntityExist(previewPed) then return end
    local t = (GetGameTimer() - camStart) / 1000.0
    local cx, cy, cz, ax, ay, az, fov = computeCamPose(t)
    cx, cy, cz, fov = applyIntro(cx, cy, cz, fov)
    SetCamCoord(cam, cx, cy, cz)
    PointCamAtCoord(cam, ax, ay, az)
    SetCamFov(cam, fov)
end

local function setupCamera(withIntro)
    camParams = buildCamParams()
    camStart = GetGameTimer()
    if not previewPed or not DoesEntityExist(previewPed) then return end

    applyPosture(camParams)

    local cx, cy, cz, ax, ay, az, fov = computeCamPose(0)
    if withIntro then
        beginIntro(cx, cy, cz, fov)
        cx, cy, cz, fov = applyIntro(cx, cy, cz, fov)
    else
        introFrom = nil
    end

    if cam then DestroyCam(cam, false) cam = nil end
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', cx, cy, cz, 0.0, 0.0, 0.0, fov, false, 0)
    PointCamAtCoord(cam, ax, ay, az)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
    applySceneDof()
end

local function applyGameFilter(name)
    filterName = name or 'none'
    ClearTimecycleModifier()
    dofOn = false
    if filterName == 'none' then return end
    local f = Config.Filters and Config.Filters[filterName]
    if not f then return end
    if f.timecycle then
        SetTimecycleModifier(f.timecycle)
        SetTimecycleModifierStrength(f.strength or 1.0)
    end
    if f.dof then dofOn = true end
end

-- A plain SetNuiFocus(true, true) does NOT rebuild a cursor that was dropped
-- while focus stayed ON. Toggling off then on in the SAME frame rebuilds it;
-- with no Wait between the calls the off state never renders, so there is no blink.
local function forceCursor()
    SetNuiFocus(false, false)
    SetNuiFocus(true, true)
end

CreateThread(function()
    while true do
        if isOpen or spawnPicking then
            SetEntityLocallyInvisible(PlayerPedId())
            if cam and not spawnPreviewActive then updateCameraFrame() end
            if heldHour then NetworkOverrideClockTime(heldHour, heldMinute or 0, 0) end
            if not spawnPreviewActive and cam and previewPed and DoesEntityExist(previewPed) then
                if dofOn then
                    local camC = GetCamCoord(cam)
                    local pedC = GetEntityCoords(previewPed)
                    local dist = #(camC - pedC)
                    SetUseHiDof()
                    SetCamUseShallowDofMode(cam, true)
                    SetCamNearDof(cam, math.max(0.1, dist - 0.9))
                    SetCamFarDof(cam, dist + 0.5)
                    SetCamDofStrength(cam, 1.0)
                elseif (Config.Camera.dof or {}).enabled ~= false then
                    SetUseHiDof()
                end
            end
            Wait(0)
        else
            Wait(200)
        end
    end
end)

CreateThread(function()
    local lastAssert = 0
    while true do
        if isOpen or spawnPicking then
            local now = GetGameTimer()
            if not IsNuiFocused() then
                forceCursor()
                lastAssert = now
            elseif now - lastAssert >= 250 then
                forceCursor()
                lastAssert = now
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        if isOpen or spawnPicking then
            if currentScene and currentScene.weather then
                SetWeatherTypeNowPersist(currentScene.weather)
                SetWeatherTypeNow(currentScene.weather)
                if currentScene.hour then NetworkOverrideClockTime(currentScene.hour, currentScene.minute or 0, 0) end
                Wait(1000)
            elseif heldWeather then
                SetWeatherTypeNowPersist(heldWeather)
                SetWeatherTypeNow(heldWeather)
                if heldHour then NetworkOverrideClockTime(heldHour, heldMinute or 0, 0) end
                Wait(2000)
            else
                Wait(1000)
            end
        else
            Wait(1000)
        end
    end
end)

local function teardownScene()
    RenderScriptCams(false, false, 0, true, false)
    if cam then DestroyCam(cam, false) cam = nil end
    camParams = nil
    ClearTimecycleModifier()
    dofOn = false
    ClearFocus()
    if previewPed and DoesEntityExist(previewPed) then DeleteEntity(previewPed) previewPed = nil end
    if partnerPed and DoesEntityExist(partnerPed) then DeleteEntity(partnerPed) partnerPed = nil end
    clearPropScenario()
    clearSceneVehicles()
    sceneId = nil
    pairView = false
    anchorZ = nil
    spawnPreviewActive = false

    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetPlayerControl(PlayerId(), true, 0)
end

local function prepareLocalPlayer()
    local loc = activeLoc()
    local lp = locPed(loc)
    local ped = PlayerPedId()
    local S = Config.Scene or {}

    RequestCollisionAtCoord(lp.x, lp.y, lp.z)
    SetEntityVisible(ped, false, false)
    SetEntityCoordsNoOffset(ped, lp.x, lp.y, lp.z + 1.0, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityHeading(ped, lp.w or 0.0)
    SetEntityCollision(ped, false, false)

    SetFocusPosAndVel(lp.x, lp.y, lp.z, 0.0, 0.0, 0.0)

    local deadline = GetGameTimer() + (S.collisionTimeoutMs or 5000)
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(lp.x, lp.y, lp.z)
        Wait(0)
    end

    anchorZ = nil
end

local function startCoupleWalk(loc)
    walkToken = walkToken + 1
    local myToken = walkToken
    local from, to = loc.from, loc.to
    if not from or not to then return end
    local speed = loc.walkSpeed or 1.0

    local h = math.rad(from.w)
    local rx, ry = math.cos(h), math.sin(h)
    local off = 0.65

    loadAnimDict('move_m@casual@a')
    CreateThread(function()
        while myToken == walkToken and pairActive do
            if not (previewPed and DoesEntityExist(previewPed) and partnerPed and DoesEntityExist(partnerPed)) then return end
            FreezeEntityPosition(previewPed, false)
            FreezeEntityPosition(partnerPed, false)
            SetEntityCoordsNoOffset(previewPed, from.x, from.y, from.z, false, false, false)
            SetEntityCoordsNoOffset(partnerPed, from.x + rx * off, from.y + ry * off, from.z, false, false, false)
            SetEntityHeading(previewPed, from.w)
            SetEntityHeading(partnerPed, from.w)
            SetPedDesiredMoveBlendRatio(previewPed, 1.0)
            SetPedDesiredMoveBlendRatio(partnerPed, 1.0)

            TaskGoStraightToCoord(previewPed, to.x, to.y, to.z, speed, 20000, to.w, 0.5)
            TaskGoStraightToCoord(partnerPed, to.x + rx * off, to.y + ry * off, to.z, speed, 20000, to.w, 0.5)

            local deadline = GetGameTimer() + 30000
            while myToken == walkToken and pairActive and GetGameTimer() < deadline do
                local c = GetEntityCoords(previewPed)
                if #(c - vector3(to.x, to.y, to.z)) < 1.6 then break end
                Wait(150)
            end
            if myToken ~= walkToken then return end
            Wait(500)
        end
    end)
end

-- Gender-paired clips are always complementary: the viewed ped takes its own
-- gender's clip and the partner takes the other. Both peds are LOCAL to each
-- client, so each client only has to be self-consistent.
local function resolvePairClips(emote, selfRole, partnerRole, selfGender)
    if emote.dict and emote.m and emote.f then
        local isFemale = (selfGender == 1)
        return { dict = emote.dict, clip = isFemale and emote.f or emote.m },
               { dict = emote.dict, clip = isFemale and emote.m or emote.f }
    end
    if emote.dict and emote.left and emote.right then
        return { dict = emote.dict, clip = emote.left },
               { dict = emote.dict, clip = emote.right }
    end
    return emote[selfRole], emote[partnerRole]
end

function ForgerStartPairScene(emote, selfRole, partnerRole, partnerGender, appearance)
    if not previewPed or not DoesEntityExist(previewPed) then return end
    local selfAnim, partnerAnim = resolvePairClips(emote, selfRole, partnerRole, currentGender)
    if not selfAnim or not partnerAnim then return end

    pairArgs = { emote = emote, selfRole = selfRole, partnerRole = partnerRole, partnerGender = partnerGender, appearance = appearance }
    pairActive = true
    currentScene = nil
    poseLoopToken = poseLoopToken + 1

    loadAnimDict(selfAnim.dict)
    loadAnimDict(partnerAnim.dict)

    if not partnerPed or not DoesEntityExist(partnerPed) then
        local model = (partnerGender == 1) and Config.Appearance.fallbackFemale or Config.Appearance.fallbackMale
        model = loadModel(model)
        partnerPed = CreatePed(2, model, 0.0, 0.0, 0.0, 0.0, false, true)
        SetEntityInvincible(partnerPed, true)
        SetBlockingOfNonTemporaryEvents(partnerPed, true)
        SetPedDefaultComponentVariation(partnerPed)
        SetModelAsNoLongerNeeded(model)
    end

    if appearance then
        applyPedAppearance(partnerPed, appearance)
    end

    local loc = activeLoc()

    if loc.type == 'walk' then
        startCoupleWalk(loc)
        pairView = true
        setupCamera()
        return
    end

    walkToken = walkToken + 1
    local lp = locPed(loc)

    if emote.upperBody then
        local z = anchorZ or lp.z
        local h = math.rad(lp.w)
        local rx, ry = math.cos(h), math.sin(h)
        local off = emote.sideOffset or 0.55
        SetEntityCoords(previewPed, lp.x, lp.y, z, false, false, false, false)
        SetEntityHeading(previewPed, lp.w)
        SetEntityCoords(partnerPed, lp.x + rx * off, lp.y + ry * off, z, false, false, false, false)
        SetEntityHeading(partnerPed, lp.w)

        if emote.walk then
            FreezeEntityPosition(previewPed, false)
            FreezeEntityPosition(partnerPed, false)
            loadAnimDict('move_m@casual@a')
            TaskPlayAnim(previewPed, 'move_m@casual@a', 'walk', 4.0, 4.0, -1, 1, 0, false, false, false)
            TaskPlayAnim(partnerPed, 'move_m@casual@a', 'walk', 4.0, 4.0, -1, 1, 0, false, false, false)
        else
            FreezeEntityPosition(previewPed, true)
            FreezeEntityPosition(partnerPed, true)
        end

        loadAnimDict(selfAnim.dict)
        loadAnimDict(partnerAnim.dict)
        local upBlend = (Config.Partner and Config.Partner.emoteBlendIn) or 1.5
        TaskPlayAnim(previewPed, selfAnim.dict, selfAnim.clip, upBlend, 4.0, -1, 49, 0, false, false, false)
        TaskPlayAnim(partnerPed, partnerAnim.dict, partnerAnim.clip, upBlend, 4.0, -1, 49, 0, false, false, false)

        pairView = true
        setupCamera()
        return
    end

    local z = (anchorZ or lp.z) + (Config.Partner.sceneZOffset or 0.98) + (emote.zOffset or 0.0)
    local heading = (lp.w or 0.0) + (emote.headingOffset or 0.0)

    ClearPedTasksImmediately(previewPed)
    ClearPedTasksImmediately(partnerPed)

    -- A synchronised scene drives each ped's transform, so a FROZEN ped will not move
    -- into place - it just plays the animation where it was pinned.
    FreezeEntityPosition(previewPed, false)
    FreezeEntityPosition(partnerPed, false)

    local coupleBlend = (Config.Partner and Config.Partner.emoteBlendIn) or 1.5
    sceneId = CreateSynchronizedScene(lp.x, lp.y, z, 0.0, 0.0, heading, 2)
    SetSynchronizedSceneLooped(sceneId, true)
    TaskSynchronizedScene(previewPed, sceneId, selfAnim.dict, selfAnim.clip, coupleBlend, -4.0, 0, 0, 1148846080, 0)
    TaskSynchronizedScene(partnerPed, sceneId, partnerAnim.dict, partnerAnim.clip, coupleBlend, -4.0, 0, 0, 1148846080, 0)

    pairView = true
    setupCamera()
end

function ForgerReapplyPairScene()
    if pairActive and pairArgs then
        ForgerStartPairScene(pairArgs.emote, pairArgs.selfRole, pairArgs.partnerRole, pairArgs.partnerGender, pairArgs.appearance)
    end
end

function ForgerStopPairScene()
    -- partnerHide fires for ANY viewed character with no partner, which is most of
    -- them on every browse. Without this guard it cleared the freshly applied emote.
    if not pairActive and not (partnerPed and DoesEntityExist(partnerPed)) then return end

    pairActive = false
    pairArgs = nil
    walkToken = walkToken + 1
    if partnerPed and DoesEntityExist(partnerPed) then DeleteEntity(partnerPed) partnerPed = nil end
    sceneId = nil
    pairView = false
    if isOpen and lastPreviewData then
        spawnPreviewPed(lastPreviewData)
    elseif previewPed and DoesEntityExist(previewPed) then
        ForgerCancelEmote(previewPed)
        poseIndex = 1
        local loc = activeLoc()
        loopEmote(previewPed, ForgerEmoteForLocation(loc))
    end
    setupCamera()
end

function ForgerIsOpen() return isOpen end

local function openSelector()
    if isOpen then return end
    isOpen = true

    -- Until the loading screen NUI is shut down its frame sits on top of the NUI stack
    -- and the mouse cursor will not render, however often SetNuiFocus is called.
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    currentJobName, currentGangName = nil, nil
    invalidateLocationCache()
    posturePed = nil

    do
        local locs = activeLocations()
        if Config.RandomLocationOnLoad and #locs > 1 then
            locationIndex = math.random(#locs)
        else
            locationIndex = 1
        end
    end
    loggedIn = false
    spawnPicking = false
    pendingSpawn = nil
    spawnPreviewActive = false
    loginLook = nil

    local ped = PlayerPedId()
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetPlayerControl(PlayerId(), false, 0)

    DoScreenFadeOut(0)
    SendNUIMessage({ action = 'blackoutOn' })
    Wait(50)

    prefs = loadPrefs()
    zoomIndex = tonumber(prefs.zoom) or Config.Camera.defaultZoom or 1
    do
        local count = (Config.Camera.zoom and #Config.Camera.zoom) or 1
        if zoomIndex < 1 then zoomIndex = 1 elseif zoomIndex > count then zoomIndex = count end
    end
    applyGameFilter(prefs.filter or 'none')

    prepareLocalPlayer()
    spawnPreviewPed(nil)
    setupCamera(true)
    for _ = 1, 3 do updateCameraFrame() Wait(0) end

    SetNuiFocus(false, false)
    Wait(0)
    SetNuiFocus(true, true)
    SetCursorLocation(0.5, 0.5)
    SendNUIMessage({ action = 'open' })
    CreateThread(function()
        while isOpen do
            if not IsNuiFocused() then forceCursor() end
            Wait(400)
        end
    end)

    heldWeather = prefs.weather or Config.DefaultSettings.weather
    heldHour = tonumber(prefs.hour) or Config.DefaultSettings.hour
    heldMinute = tonumber(prefs.minute) or Config.DefaultSettings.minute
    SetWeatherTypeNowPersist(heldWeather)
    SetWeatherTypeNow(heldWeather)
    NetworkOverrideClockTime(heldHour, heldMinute, 0)

    TriggerServerEvent('forger:server:requestCharacters')
    if Config.Partner.enabled then TriggerServerEvent('forger:server:partnerPresence', true) end

    SendNUIMessage({ action = 'prefs', data = prefs })

    Wait(150)
    SendNUIMessage({ action = 'blackoutOff' })
    Wait(30)
    DoScreenFadeIn(400)
end

local function closeSelector(fade)
    if not isOpen then return end
    isOpen = false
    if Config.Partner.enabled then TriggerServerEvent('forger:server:partnerPresence', false) end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if fade then
        DoScreenFadeOut(300)
        Wait(350)
    end
    teardownScene()
    if fade then DoScreenFadeIn(400) end
end

RegisterNetEvent('forger:client:setCharacters', function(payload)
    SendNUIMessage({ action = 'setData', data = payload })
end)

local function applySavedAppearance(appearance)
    local A = Config.Appearance or {}
    if A.resource == 'none' or not A.resource then return false end
    if type(appearance) ~= 'table' or next(appearance) == nil then return false end

    local model = appearance.model
    if type(model) == 'string' then model = joaat(model) end
    if not model or model == 0 then return false end
    if GetEntityModel(PlayerPedId()) ~= model then
        RequestModel(model)
        local t = GetGameTimer() + 10000
        while not HasModelLoaded(model) and GetGameTimer() < t do Wait(0) end
        if not HasModelLoaded(model) then return false end
        SetPlayerModel(PlayerId(), model)
        SetModelAsNoLongerNeeded(model)
        Wait(50)
    end

    local exp = A.applyExport
    pcall(function()
        if exp == 'setPlayerAppearance' then
            exports[A.resource]:setPlayerAppearance(appearance)
        else
            exports[A.resource]:setPedAppearance(PlayerPedId(), appearance)
        end
    end)
    return true
end

local function applyPlayerLook(res, gender)
    local P = Config.PostLogin or {}
    local hasAppearance = res.appearance ~= nil
        and type(res.appearance) == 'table' and next(res.appearance) ~= nil
    if P.applyAppearance then
        local applied = hasAppearance and applySavedAppearance(res.appearance)
        if not applied and P.forceFreemodeModel ~= false then
            ensureFreemodeModel(gender)
        end
    elseif P.forceFreemodeModel ~= false then
        ensureFreemodeModel(gender)
    end
end

local function finishLogin(res, isNew)
    if loggedIn then return end
    loggedIn = true
    isOpen = false
    spawnPicking = false
    spawnPreviewToken = spawnPreviewToken + 1
    if Config.Partner.enabled then TriggerServerEvent('forger:server:partnerPresence', false) end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    SendNUIMessage({ action = 'spawnClose' })

    local P = Config.PostLogin or {}
    local gender = res.gender or 0
    local target = (P.teleportToLast and res.coords and res.coords.x) and res.coords or P.defaultSpawn

    DoScreenFadeOut(200)
    Wait(220)
    teardownScene()
    FreezeEntityPosition(PlayerPedId(), true)

    local ldl = GetGameTimer() + 5000
    while GetGameTimer() < ldl do
        local st = LocalPlayer and LocalPlayer.state
        if st and st.isLoggedIn then break end
        Wait(50)
    end

    if isNew then
        if P.forceFreemodeModel ~= false then ensureFreemodeModel(gender) end
        if P.newCharacterEvent then pcall(function() TriggerEvent(P.newCharacterEvent) end) end
    elseif loginLook then
        local dl = GetGameTimer() + 5000
        while not loginLook.done and GetGameTimer() < dl do Wait(20) end
    else
        applyPlayerLook(res, gender)
    end

    local ped = PlayerPedId()
    if target and target.x then
        SetEntityCoordsNoOffset(ped, target.x + 0.0, target.y + 0.0, target.z + 0.0, false, false, false)
        SetEntityHeading(ped, target.w or 0.0)
        if not HasCollisionLoadedAroundEntity(ped) then
            RequestCollisionAtCoord(target.x, target.y, target.z)
            NewLoadSceneStartSphere(target.x, target.y, target.z, 40.0, 0)
            local deadline = GetGameTimer() + 4000
            while not IsNewLoadSceneLoaded() and not HasCollisionLoadedAroundEntity(ped)
                  and GetGameTimer() < deadline do
                RequestCollisionAtCoord(target.x, target.y, target.z)
                Wait(0)
            end
            NewLoadSceneStop()
        end
    end
    ClearFocus()

    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), true, 0)

    -- Login only tells the CORE it has a character. Everything else - HUD, phone,
    -- garages, jobs, dispatch, inventory - waits for these spawn-confirmation events,
    -- so without them the rest of the server behaves as if nobody joined.
    if P.notifyLoaded ~= false then
        if P.serverLoadedEvent then
            TriggerServerEvent(P.serverLoadedEvent)
        end
        if P.clientLoadedEvent then
            TriggerEvent(P.clientLoadedEvent)
        end
        for _, ev in ipairs(P.extraLoadedEvents or {}) do
            if ev.name then
                local args = ev.args or {}
                if ev.server then
                    TriggerServerEvent(ev.name, table.unpack(args))
                else
                    TriggerEvent(ev.name, table.unpack(args))
                end
            end
        end
        TriggerServerEvent('forger:server:playerSpawned')
    end

    heldWeather, heldHour, heldMinute = nil, nil, nil
    -- Release the selector's weather/clock hold, or the override survives into the world.
    if P.restoreWeatherSync ~= false then
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        NetworkClearClockTimeOverride()
        if P.weatherSyncEvent then
            pcall(function() TriggerEvent(P.weatherSyncEvent) end)
        end
    end

    do
        local fc = GetEntityCoords(ped)
        TriggerServerEvent('forger:server:spawnPlaced', {
            x = fc.x, y = fc.y, z = fc.z, w = GetEntityHeading(ped),
        })
    end

    DoScreenFadeIn(300)
end

local function buildSpawnTiles(res)
    local S = Config.Spawn or {}
    local tiles = {}
    if S.allowLastLocation ~= false and res and res.coords and res.coords.x then
        tiles[#tiles + 1] = {
            id = '__last',
            label = S.lastLocationLabel or 'Last Location',
            desc = S.lastLocationDesc or 'Return to where you logged off',
            icon = 'history',
            last = true,
        }
    end
    for _, sp in ipairs(S.locations or {}) do
        tiles[#tiles + 1] = {
            id = sp.id,
            label = sp.label or sp.id,
            desc = sp.desc or '',
            icon = sp.icon or 'map-pin',
        }
    end
    return tiles
end

local function resolveSpawnCoords(id)
    local S = Config.Spawn or {}
    if id == '__last' then
        local res = pendingSpawn and pendingSpawn.res
        if res and res.coords and res.coords.x then return res.coords end
        return S.default
    end
    for _, sp in ipairs(S.locations or {}) do
        if sp.id == id then return sp.coords end
    end
    return S.default
end

local function previewSpawnBackdrop(coords)
    if not coords or not coords.x then return end
    spawnPreviewToken = spawnPreviewToken + 1
    local token = spawnPreviewToken
    spawnPreviewActive = true

    DoScreenFadeOut(160)
    Wait(180)
    if token ~= spawnPreviewToken then return end

    sceneStanceToken = sceneStanceToken + 1
    if previewPed and DoesEntityExist(previewPed) then SetEntityVisible(previewPed, false, false) end
    if partnerPed and DoesEntityExist(partnerPed) then SetEntityVisible(partnerPed, false, false) end
    for _, e in ipairs(sceneVehicles) do if DoesEntityExist(e) then SetEntityVisible(e, false, false) end end
    for _, e in ipairs(memberPeds) do if DoesEntityExist(e) then SetEntityVisible(e, false, false) end end

    SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    NewLoadSceneStartSphere(coords.x, coords.y, coords.z, 80.0, 0)
    local dl = GetGameTimer() + 800
    while not IsNewLoadSceneLoaded() and GetGameTimer() < dl do Wait(0) end
    NewLoadSceneStop()
    if token ~= spawnPreviewToken then return end

    local h = math.rad(coords.w or 0.0)
    local fx, fy = -math.sin(h), math.cos(h)
    local rx, ry = math.cos(h), math.sin(h)
    local dist, side, height = 7.5, 2.5, 2.6
    local camX = coords.x - fx * dist + rx * side
    local camY = coords.y - fy * dist + ry * side
    local camZ = coords.z + height

    if not cam then
        cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camX, camY, camZ, 0.0, 0.0, 0.0, 48.0, false, 0)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, false)
    else
        SetCamCoord(cam, camX, camY, camZ)
        SetCamFov(cam, 48.0)
    end
    PointCamAtCoord(cam, coords.x, coords.y, coords.z + 0.4)

    local pp = PlayerPedId()
    SetEntityCoordsNoOffset(pp, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(pp, coords.w or 0.0)
    FreezeEntityPosition(pp, true)
    SetEntityVisible(pp, false, false)
    SetEntityLocallyInvisible(pp)

    Wait(30)
    if token ~= spawnPreviewToken then return end
    DoScreenFadeIn(200)
end

local function beginSpawnSelection(res, isNew)
    local S = Config.Spawn or {}
    local usePicker = S.enabled ~= false
    if isNew and S.showForNewCharacters == false then usePicker = false end

    local tiles = usePicker and buildSpawnTiles(res) or {}
    if #tiles == 0 then usePicker = false end

    loginLook = nil

    if not usePicker then
        finishLogin(res, isNew)
        return
    end

    pendingSpawn = { res = res, isNew = isNew }
    isOpen = false
    spawnPicking = true

    if not isNew then
        loginLook = { done = false }
        local lookRes = res
        CreateThread(function()
            applyPlayerLook(lookRes, lookRes.gender or 0)
            local p = PlayerPedId()
            SetEntityVisible(p, false, false)
            SetEntityLocallyInvisible(p)
            FreezeEntityPosition(p, true)
            if loginLook then loginLook.done = true end
        end)
    end

    SendNUIMessage({ action = 'spawnHide' })
    SetNuiFocus(false, false)
    Wait(0)
    SetNuiFocus(true, true)
    SetCursorLocation(0.5, 0.5)
    SendNUIMessage({ action = 'spawnOpen', data = {
        spawns = tiles,
        brand = Config.Brand,
        title = S.title or 'CHOOSE SPAWN',
        subtitle = S.subtitle or 'Where do you want to start?',
    } })

    CreateThread(function()
        for _ = 1, 6 do
            if not spawnPicking then return end
            if not IsNuiFocused() then forceCursor() end
            Wait(180)
        end
    end)
end

RegisterNetEvent('forger:client:actionResult', function(res)
    if res.action == 'select' and res.ok then
        beginSpawnSelection(res, false)
        return
    end
    if res.action == 'create' and res.ok then
        beginSpawnSelection(res, true)
        return
    end
    SendNUIMessage({ action = 'actionResult', data = res })
end)

RegisterNUICallback('spawnSelect', function(data, cb)
    cb('ok')
    if not spawnPicking or not pendingSpawn then return end

    local res, isNew = pendingSpawn.res, pendingSpawn.isNew
    pendingSpawn = nil
    spawnPicking = false
    spawnPreviewToken = spawnPreviewToken + 1

    local id = data and data.id
    if id and id ~= '__last' then
        local chosen = resolveSpawnCoords(id)
        if chosen and chosen.x then
            res.coords = { x = chosen.x, y = chosen.y, z = chosen.z, w = chosen.w or 0.0 }
        end
    end

    finishLogin(res, isNew)
end)

RegisterNUICallback('spawnPreview', function(data, cb)
    cb('ok')
    if not spawnPicking then return end
    previewSpawnBackdrop(resolveSpawnCoords(data and data.id))
end)

RegisterNUICallback('spawnBack', function(_, cb)
    cb('ok')
    if not spawnPicking then return end
    spawnPicking = false
    spawnPreviewActive = false
    spawnPreviewToken = spawnPreviewToken + 1
    pendingSpawn = nil
    isOpen = true

    DoScreenFadeOut(240)
    Wait(260)
    prepareLocalPlayer()
    spawnPreviewPed(lastPreviewData or { gender = currentGender }, true)
    setupCamera()
    SendNUIMessage({ action = 'spawnClose' })
    SendNUIMessage({ action = 'spawnShow' })
    Wait(80)
    DoScreenFadeIn(300)
end)

RegisterNetEvent('forger:client:open', function()
    openSelector()
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    openSelector()
end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    openSelector()
end)

RegisterNetEvent('forger:client:actionResult', function(res)
    if res and res.action == 'logout' and res.ok == false and res.reason == 'no_permission' then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName("You don't have permission to log out.")
        EndTextCommandThefeedPostTicker(false, true)
    end
end)

RegisterNUICallback('play', function(data, cb)
    TriggerServerEvent('forger:server:selectCharacter', data.citizenid)
    cb('ok')
end)

RegisterNUICallback('create', function(data, cb)
    TriggerServerEvent('forger:server:createCharacter', data)
    cb('ok')
end)

RegisterNUICallback('delete', function(data, cb)
    TriggerServerEvent('forger:server:deleteCharacter', data.citizenid)
    cb('ok')
end)

RegisterNUICallback('preview', function(data, cb)
    if isOpen then
        lastPreviewData = data
        local newJob = data and data.jobName or nil
        local newGang = data and data.gangName or nil
        if newJob ~= currentJobName or newGang ~= currentGangName then
            currentJobName, currentGangName = newJob, newGang
            invalidateLocationCache()
            local locs = activeLocations()
            if locationIndex > #locs then locationIndex = 1 end
        end
        spawnPreviewPed(data)
        setupCamera()
    end
    cb('ok')
end)

RegisterNUICallback('setFilter', function(data, cb)
    applyGameFilter(data and data.name)
    prefs.filter = filterName
    savePrefs()
    cb('ok')
end)

RegisterNUICallback('setZoom', function(data, cb)
    if isOpen then
        local n = tonumber(data and data.index) or 1
        local count = (Config.Camera.zoom and #Config.Camera.zoom) or 1
        if n < 1 then n = 1 elseif n > count then n = count end
        zoomIndex = n
        prefs.zoom = n
        savePrefs()
        setupCamera()
    end
    cb('ok')
end)

RegisterNUICallback('changePose', function(_, cb)
    if currentScene then cb('scene') return end
    local loc = activeLoc()
    if loc and loc.mode == 2 then cb('scenario') return end

    if isOpen and previewPed and DoesEntityExist(previewPed) then
        local emotes = emoteList()
        if #emotes > 0 then
            poseIndex = (poseIndex or 1) + 1
            if poseIndex > #emotes then poseIndex = 1 end
            ForgerCancelEmote(previewPed)
            loopEmote(previewPed, emotes[poseIndex])
        end
    end
    cb('ok')
end)

RegisterNUICallback('changeLocation', function(_, cb)
    cb('ok')
    if currentScene then return end
    if not isOpen then return end
    if locationSwitching then return end
    locationSwitching = true

    CreateThread(function()
        local locs = activeLocations()
        locationIndex = locationIndex + 1
        if locationIndex > #locs then locationIndex = 1 end

        DoScreenFadeOut(180)
        Wait(200)

        prepareLocalPlayer()
        spawnPreviewPed(lastPreviewData or { gender = currentGender }, true)
        if pairActive then
            ForgerReapplyPairScene()
        else
            setupCamera()
        end
        for _ = 1, 2 do updateCameraFrame() Wait(0) end

        SendNUIMessage({ action = 'locationChanged', label = (locs[locationIndex] and locs[locationIndex].label) or '' })
        forceCursor()
        DoScreenFadeIn(220)
        locationSwitching = false
    end)
end)

RegisterNUICallback('applySetting', function(data, cb)
    if data.key == 'weather' and data.value then
        heldWeather = data.value
        SetWeatherTypeNowPersist(data.value)
        SetWeatherTypeNow(data.value)
        prefs.weather = data.value
        savePrefs()
    elseif data.key == 'time' then
        heldHour = tonumber(data.hour) or 12
        heldMinute = tonumber(data.minute) or 0
        NetworkOverrideClockTime(heldHour, heldMinute, 0)
        prefs.hour, prefs.minute = heldHour, heldMinute
        savePrefs()
    elseif data.key == 'customScene' then
        prefs.customScene = data.value and true or false
        savePrefs()
        if not prefs.customScene then
            if heldWeather then SetWeatherTypeNowPersist(heldWeather) SetWeatherTypeNow(heldWeather) end
            if heldHour then NetworkOverrideClockTime(heldHour, heldMinute or 0, 0) end
        end
        if isOpen and lastPreviewData then
            spawnPreviewPed(lastPreviewData)
            setupCamera()
        end
    end
    cb('ok')
end)

RegisterNUICallback('savePrefs', function(data, cb)
    if type(data) == 'table' then
        for k, v in pairs(data) do prefs[k] = v end
        savePrefs()
    end
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    cb('ok')
end)

CreateThread(function()
    if GetResourceState('spawnmanager') == 'started' then
        pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
    end
end)

if AUTO_OPEN then
    CreateThread(function()
        DoScreenFadeOut(0)
        local guard = true
        CreateThread(function()
            while guard do
                local ped = PlayerPedId()
                if ped and ped ~= 0 then
                    SetEntityLocallyInvisible(ped)
                    FreezeEntityPosition(ped, true)
                    SetEntityCollision(ped, false, false)
                    SetPlayerControl(PlayerId(), false, 0)
                end
                DoScreenFadeOut(0)
                Wait(0)
            end
        end)

        while not NetworkIsSessionStarted() do Wait(200) end
        Wait(300)
        guard = false
        openSelector()
    end)
end

RegisterCommand('multichar', function()
    openSelector()
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and (isOpen or spawnPicking) then
        teardownScene()
        SetNuiFocus(false, false)
    end
end)
