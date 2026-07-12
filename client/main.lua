-- Client: builds the cinematic preview scene, drives the NUI, spawns the
-- preview ped, handles poses / locations, and hands off to the framework spawn
-- once a character is chosen.

local AUTO_OPEN = Config.AutoOpen ~= false

-- Black the screen the moment this resource loads (before the guard thread below
-- has even been scheduled), so a resource/server restart while the player is
-- standing in the world never flashes that world before the selector opens.
if AUTO_OPEN then DoScreenFadeOut(0) end

local isOpen = false
local cam = nil
local previewPed = nil
local anchorZ = nil         -- ground-snapped z for the current location
local locationIndex = 1
local poseIndex = 1
local currentGender = 0
local zoomIndex = 1
local filterName = 'none'
local dofOn = false

local spawnPicking = false  -- true while the spawn-point picker is up (scene stays live)
local pendingSpawn = nil     -- { res = ..., isNew = ... } held between select and spawn pick
local loggedIn = false       -- guards finishLogin so it can only run once
local spawnPreviewActive = false -- true while the camera is showing a spawn point (not the ped)
local spawnPreviewToken = 0      -- debounces rapid spawn-tile selections
local loginLook = nil            -- { done=bool } while the player's look is pre-applied during spawn pick
local poseLoopToken = 0          -- cancels a running spaced-pose loop when the pose changes
local lastPreviewData = nil      -- last character data previewed (to re-render on a setting change)

-- persisted per-player preferences (theme, weather, time, filter, music, volumes)
local PREFS_KEY = 'forger:prefs'
local prefs = {}
local heldWeather = nil     -- re-applied every tick so a server clock/weather sync can't revert it
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

-- decorrelate the random-pose RNG so each session/load varies
CreateThread(function()
    math.randomseed(GetGameTimer())
    for _ = 1, 5 do math.random() end
end)

-- ---------------------------------------------------------------------------
-- loaders
-- ---------------------------------------------------------------------------
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

-- Force the player onto the correct freemode ped for their gender. This is the
-- deterministic base every appearance resource expects; without it a player can
-- stay on whatever ped the game spawned them as (a story ped such as Michael),
-- which is the "I don't spawn as mp_m_freemode" bug. Called before we hand off
-- to illenium so the saved clothing/face has a clean freemode ped to dress.
local function ensureFreemodeModel(gender)
    local model = (gender == 1) and Config.Appearance.fallbackFemale or Config.Appearance.fallbackMale
    local hash = (type(model) == 'string') and joaat(model) or model

    -- Already the right model? Just make sure it's the correct gender freemode
    -- ped and move on (avoids a needless ped rebuild that resets components).
    if GetEntityModel(PlayerPedId()) ~= hash then
        RequestModel(hash)
        local t = GetGameTimer() + 10000
        while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(0) end
        if HasModelLoaded(hash) then
            SetPlayerModel(PlayerId(), hash)
            SetModelAsNoLongerNeeded(hash)
        end
    end

    -- Give the fresh freemode ped default clothing so it never appears as the
    -- naked/underwear default before illenium loads the saved look.
    SetPedDefaultComponentVariation(PlayerPedId())
    SetPedComponentVariation(PlayerPedId(), 4, 0, 0, 0) -- legs
    SetPedComponentVariation(PlayerPedId(), 6, 0, 0, 0) -- shoes
    SetPedComponentVariation(PlayerPedId(), 11, 0, 0, 0) -- torso/jacket
end

-- ---------------------------------------------------------------------------
-- appearance hook
-- ---------------------------------------------------------------------------
-- Give the preview ped a decent default look, then let the configured
-- appearance resource override with the character's saved clothing if it can.
local function applyAppearance(ped, character)
    SetPedDefaultComponentVariation(ped)

    if not character or character.__empty then return end
    if not character.appearance then return end

    -- Dress the preview ped through the clothing bridge (Appearance module),
    -- which handles illenium/fivem-appearance exports, ESX skinchanger maps, etc.
    -- Never let a missing export/resource break the scene.
    Appearance.applyToPed(ped, character.appearance)
end

-- ---------------------------------------------------------------------------
-- scene
-- ---------------------------------------------------------------------------
local camParams = nil       -- active camera params for the render loop
local camStart = 0          -- time the current shot began (for motion)

-- Make sure the world (collision) around a point is streamed in.
local function ensureCollision(x, y, z)
    RequestCollisionAtCoord(x, y, z)
    local ped = PlayerPedId()
    local deadline = GetGameTimer() + 4000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        Wait(0)
    end
end

-- Find the topmost solid surface z at (x,y) via a downward ray. This hits pier
-- decks / roads / terrain correctly (unlike the ground native, which returns the
-- terrain under a deck).
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

-- Stand a ped on the surface. Uses SetEntityCoords (the *offset* variant), which
-- places the feet at z. SetEntityCoordsNoOffset would put the ped's centre at z
-- and sink it to the waist - that was the earlier bug.
local function snapPedToGround(ped, x, y, zGuess, heading)
    local z = surfaceZAt(x, y, zGuess)
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    SetEntityHeading(ped, heading)
    return z  -- surface z (feet level)
end

local function poseList(gender)
    return Config.Poses[(gender == 1) and 'female' or 'male'] or Config.Poses.male or {}
end

-- The active location table + a safe index (clamped to the set's length).
local function activeLoc()
    local locs = Config.Locations
    local idx = locationIndex
    if idx < 1 or idx > #locs then idx = 1 end
    return locs[idx], idx
end

-- Anchor coords for a location.
local function locPed(loc)
    if loc.ped then return loc.ped end
    return vec4(0.0, 0.0, 70.0, 0.0)
end

local function playPose(ped, pose)
    if not pose then return end
    loadAnimDict(pose.dict)
    -- flag 49 = looping upper-body/secondary: the emote drives only the upper
    -- body so the legs stay in their own (idle/walk) motion. flag 1 = full body.
    local flag = pose.upperBody and 49 or 1
    local blendIn = Config.PoseBlendIn or 8.0  -- high = instant snap into the pose
    TaskPlayAnim(ped, pose.dict, pose.anim, blendIn, blendIn, -1, flag, 0, false, false, false)
end

-- Loop a pose. With Config.EmoteLoop.spaced the emote plays a cycle, pauses, then
-- replays (a spaced loop) instead of running continuously. The thread also
-- re-asserts the anim if something (e.g. the appearance apply) clears it, so the
-- ped never ends up standing still. Cancelled by bumping poseLoopToken.
local function loopPose(ped, pose)
    if not pose then return end
    poseLoopToken = poseLoopToken + 1
    local myToken = poseLoopToken
    local L = Config.EmoteLoop or {}
    local spaced = L.spaced
    loadAnimDict(pose.dict)
    local flag = pose.upperBody and 49 or 1
    local blendIn = Config.PoseBlendIn or 8.0

    CreateThread(function()
        local durMs = math.max((GetAnimDuration(pose.dict, pose.anim) or 0) * 1000.0, L.minCycleMs or 2200)
        local gapMs = (L.gapSeconds or 1.4) * 1000.0
        while myToken == poseLoopToken and ped == previewPed and DoesEntityExist(ped) do
            TaskPlayAnim(ped, pose.dict, pose.anim, blendIn, 4.0, -1, flag, 0, false, false, false)
            -- hold for one cycle, re-asserting if the anim gets cleared
            local endAt = GetGameTimer() + durMs
            while myToken == poseLoopToken and GetGameTimer() < endAt do
                if ped == previewPed and DoesEntityExist(ped)
                   and not IsEntityPlayingAnim(ped, pose.dict, pose.anim, 3) then
                    TaskPlayAnim(ped, pose.dict, pose.anim, blendIn, 4.0, -1, flag, 0, false, false, false)
                end
                Wait(120)
            end
            if myToken ~= poseLoopToken then return end
            if spaced then
                if DoesEntityExist(ped) then StopAnimTask(ped, pose.dict, pose.anim, 4.0) end
                Wait(gapMs)   -- spaced pause before the next cycle
            end
        end
    end)
end

local function spawnPreviewPed(character, keepPose)
    if previewPed and DoesEntityExist(previewPed) then
        DeleteEntity(previewPed)
        previewPed = nil
    end

    local loc = activeLoc()
    local lp = locPed(loc)
    local gender = character and character.gender or currentGender
    currentGender = gender

    -- Prefer the model the appearance was saved on (authoritative), else the
    -- gender freemode model. This makes the preview match the real character.
    local model
    if character and type(character.appearance) == 'table' and character.appearance.model then
        model = character.appearance.model
    else
        model = gender == 1 and Config.Appearance.fallbackFemale or Config.Appearance.fallbackMale
    end
    model = loadModel(model)

    previewPed = CreatePed(2, model, lp.x, lp.y, lp.z + 3.0, lp.w, false, true)
    SetEntityInvincible(previewPed, true)
    SetBlockingOfNonTemporaryEvents(previewPed, true)
    SetEntityAlpha(previewPed, 255, false)

    -- stand it on the ground, then lock it there
    anchorZ = snapPedToGround(previewPed, lp.x, lp.y, lp.z, lp.w)
    FreezeEntityPosition(previewPed, true)

    applyAppearance(previewPed, character)
    SetModelAsNoLongerNeeded(model)

    -- pick the pose: keep the current one on location change / back, otherwise a
    -- random pose (or index 1 if randomization is disabled)
    local poses = poseList(gender)
    if keepPose and poseIndex and poses[poseIndex] then
        -- keep current poseIndex
    elseif Config.RandomPoseOnLoad and #poses > 0 then
        poseIndex = math.random(#poses)
    else
        poseIndex = 1
    end

    -- Loop the pose (spaced if configured). loopPose runs a self-healing thread
    -- that re-asserts the anim if the appearance apply clears it, so the ped
    -- always ends up performing the emote.
    loopPose(previewPed, poses[poseIndex])
end

-- Build the active camera parameter set (defaults <- per-location <- pair).
local function buildCamParams()
    local C = Config.Camera
    local zoom = (C.zoom and C.zoom[zoomIndex]) or {}
    local p = {
        motion = C.motion,
        distance = zoom.distance or C.distance or 3.1,
        height = zoom.height or C.height or 0.62,
        pointAt = zoom.pointAt or C.pointAt or 0.62,
        fov = zoom.fov or C.fov or 44.0,
        swayArc = C.swayArc,
        swaySpeed = C.swaySpeed, orbitSpeed = C.orbitSpeed,
        pushAmount = C.pushAmount, pushSpeed = C.pushSpeed,
    }
    local locData = activeLoc()
    local locCam = locData and locData.cam
    if type(locCam) == 'table' then
        for k, v in pairs(locCam) do p[k] = v end
    end
    return p
end

-- Compute where the camera should be at time t (seconds since the shot began).
local function computeCamPose(t)
    local p = camParams

    local cx, cy, cz, baseAngle
    local c = GetEntityCoords(previewPed)
    cx, cy, cz = c.x, c.y, c.z
    local fwd = GetEntityForwardVector(previewPed)
    baseAngle = math.atan(fwd.y, fwd.x)
    if p.view == 'back' then baseAngle = baseAngle + math.pi end

    local angle, distance = baseAngle, p.distance
    if p.motion == 'sway' then
        angle = baseAngle + math.rad(p.swayArc or 14.0) * math.sin(t * (p.swaySpeed or 0.05) * 2.0 * math.pi)
    elseif p.motion == 'orbit' then
        angle = baseAngle + math.rad((p.orbitSpeed or 3.0) * t)
    elseif p.motion == 'pan' then
        -- slow cinematic side-to-side pan
        angle = baseAngle + math.rad(p.panArc or 16.0) * math.sin(t * (p.panSpeed or 0.02) * 2.0 * math.pi)
    elseif p.motion == 'push' then
        distance = p.distance + (p.pushAmount or 0.5) * math.sin(t * (p.pushSpeed or 0.06) * 2.0 * math.pi)
    end

    local camX = cx + math.cos(angle) * distance
    local camY = cy + math.sin(angle) * distance
    local camZ = cz + p.height
    return camX, camY, camZ, cx, cy, cz + p.pointAt, p.fov
end

-- Per-frame camera update (moves the existing cam).
local function updateCameraFrame()
    if not cam or not camParams or not previewPed or not DoesEntityExist(previewPed) then return end
    local t = (GetGameTimer() - camStart) / 1000.0
    local cx, cy, cz, ax, ay, az, fov = computeCamPose(t)
    SetCamCoord(cam, cx, cy, cz)
    PointCamAtCoord(cam, ax, ay, az)
    SetCamFov(cam, fov)
end

-- Create the cam already at its final position so it never eases/falls into place.
local function setupCamera()
    camParams = buildCamParams()
    camStart = GetGameTimer()
    if not previewPed or not DoesEntityExist(previewPed) then return end

    local cx, cy, cz, ax, ay, az, fov = computeCamPose(0)
    if cam then DestroyCam(cam, false) cam = nil end
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', cx, cy, cz, 0.0, 0.0, 0.0, fov, false, 0)
    PointCamAtCoord(cam, ax, ay, az)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
end

-- Apply a filter game-side: timecycle colour grade and/or DOF background blur.
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

-- master scene loop: hides the real player, drives the camera, holds the time,
-- and applies depth-of-field when the Portrait filter is active.
CreateThread(function()
    while true do
        if isOpen or spawnPicking then
            SetEntityLocallyInvisible(PlayerPedId())
            if cam and not spawnPreviewActive then updateCameraFrame() end
            -- hold the chosen time every frame so a server clock sync can't win
            if heldHour then NetworkOverrideClockTime(heldHour, heldMinute or 0, 0) end
            -- depth-of-field background blur (Portrait filter) - only while the
            -- camera is framing the preview ped, not a spawn-point backdrop
            if dofOn and not spawnPreviewActive and cam and previewPed and DoesEntityExist(previewPed) then
                local camC = GetCamCoord(cam)
                local pedC = GetEntityCoords(previewPed)
                local dist = #(camC - pedC)
                SetUseHiDof()
                SetCamUseShallowDofMode(cam, true)
                SetCamNearDof(cam, math.max(0.1, dist - 0.9))
                SetCamFarDof(cam, dist + 0.5)
                SetCamDofStrength(cam, 1.0)
            end
            Wait(0)
        else
            Wait(200)
        end
    end
end)

-- keep NUI focus + cursor active while the selector is open. Only re-grab when
-- focus is actually lost - re-asserting every tick makes the cursor blink out on
-- click. The delayed re-asserts in openSelector cover slow-loading NUI.
CreateThread(function()
    while true do
        if isOpen or spawnPicking then
            if not IsNuiFocused() then SetNuiFocus(true, true) end
            Wait(400)
        else
            Wait(500)
        end
    end
end)

-- re-apply the chosen weather periodically so a server weather sync can't revert
-- the held weather/time the player set in the selector.
CreateThread(function()
    while true do
        if isOpen or spawnPicking then
            if heldWeather then
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
    SetEntityCoordsNoOffset(ped, lp.x, lp.y, lp.z + 1.0, false, false, false)
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    -- force the streamer to load full detail at the scene (no black load-scene)
    SetFocusPosAndVel(lp.x, lp.y, lp.z, 0.0, 0.0, 0.0)
    ensureCollision(lp.x, lp.y, lp.z)
    anchorZ = nil
end

function ForgerIsOpen() return isOpen end

-- ---------------------------------------------------------------------------
-- open / close
-- ---------------------------------------------------------------------------
local function openSelector()
    if isOpen then return end
    isOpen = true
    locationIndex = 1
    -- fresh session: allow finishLogin to run and clear any stale spawn state
    loggedIn = false
    spawnPicking = false
    pendingSpawn = nil
    spawnPreviewActive = false
    loginLook = nil

    -- hide the player immediately so it's never seen spawning/falling
    local ped = PlayerPedId()
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetPlayerControl(PlayerId(), false, 0)

    DoScreenFadeOut(0)  -- instant black: never show the world while we build the scene
    SendNUIMessage({ action = 'blackoutOn' })  -- NUI cover in case the game fade lags
    Wait(50)

    -- load saved prefs first so the initial camera/weather/time reflect them
    prefs = loadPrefs()
    zoomIndex = tonumber(prefs.zoom) or Config.Camera.defaultZoom or 1
    do
        local count = (Config.Camera.zoom and #Config.Camera.zoom) or 1
        if zoomIndex < 1 then zoomIndex = 1 elseif zoomIndex > count then zoomIndex = count end
    end
    applyGameFilter(prefs.filter or 'none')

    prepareLocalPlayer()
    spawnPreviewPed(nil)
    setupCamera()
    -- let the cam settle on the ped for a couple of frames before revealing
    for _ = 1, 3 do updateCameraFrame() Wait(0) end

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open' })
    -- some clients ignore the first focus call if the NUI page isn't ready yet;
    -- re-assert a few times over the first second so everyone gets the cursor.
    CreateThread(function()
        for _ = 1, 6 do
            if not isOpen then return end
            if not IsNuiFocused() then SetNuiFocus(true, true) end
            Wait(180)
        end
    end)

    -- weather + time: use saved prefs when present, else config defaults. These
    -- are "held" (re-applied every tick) so a server sync can't revert them.
    heldWeather = prefs.weather or Config.DefaultSettings.weather
    heldHour = tonumber(prefs.hour) or Config.DefaultSettings.hour
    heldMinute = tonumber(prefs.minute) or Config.DefaultSettings.minute
    SetWeatherTypeNowPersist(heldWeather)
    SetWeatherTypeNow(heldWeather)
    NetworkOverrideClockTime(heldHour, heldMinute, 0)

    TriggerServerEvent('forger:server:requestCharacters')

    -- push saved prefs so the UI restores theme / filter / music / volumes / etc.
    SendNUIMessage({ action = 'prefs', data = prefs })

    Wait(150)
    -- reveal: drop the NUI cover (game is still faded black), then fade the game in
    SendNUIMessage({ action = 'blackoutOff' })
    Wait(30)
    DoScreenFadeIn(400)
end

local function closeSelector(fade)
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if fade then
        DoScreenFadeOut(300)
        Wait(350)
    end
    teardownScene()
    if fade then DoScreenFadeIn(400) end
end

-- ---------------------------------------------------------------------------
-- server -> client
-- ---------------------------------------------------------------------------
RegisterNetEvent('forger:client:setCharacters', function(payload)
    SendNUIMessage({ action = 'setData', data = payload })
end)

-- Set the REAL player ped's model + clothing for an existing character. Runs
-- while the ped is hidden (during the spawn picker or the login fade), so the
-- final spawn doesn't have to do a slow model-swap inside the black screen.
-- All clothing-resource specifics live in client/appearance.lua (Appearance.*).
local function applyPlayerLook(res, gender)
    local P = Config.PostLogin or {}

    -- If the clothing resource dresses the player itself on the framework's
    -- player-loaded event, we must not fight it - just ensure a clean base ped.
    if Appearance.clothingLoadsItself() then
        if P.forceFreemodeModel ~= false then ensureFreemodeModel(gender) end
        return
    end

    local hasAppearance = res.appearance ~= nil
        and type(res.appearance) == 'table' and next(res.appearance) ~= nil

    if P.applyAppearance then
        -- Give the clothing bridge a clean freemode base first (so export-based
        -- resources that only set components have the right ped), then apply.
        if P.forceFreemodeModel ~= false then ensureFreemodeModel(gender) end
        local applied = hasAppearance and Appearance.applyToPlayer(res.appearance, gender)
        if not applied and P.forceFreemodeModel ~= false then
            ensureFreemodeModel(gender)  -- no saved look / apply failed: freemode base
        end
    elseif P.forceFreemodeModel ~= false then
        ensureFreemodeModel(gender)
    end
end

-- Hand off to the world after a character is chosen: close the selector, set the
-- correct model + appearance, and move the player to their last saved position.
-- This is a minimal self-contained spawn so you don't spawn as the wrong ped.
local function finishLogin(res, isNew)
    if loggedIn then return end
    loggedIn = true
    isOpen = false
    spawnPicking = false
    spawnPreviewToken = spawnPreviewToken + 1  -- cancel any in-flight backdrop preview
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    SendNUIMessage({ action = 'spawnClose' })

    local P = Config.PostLogin or {}
    local gender = res.gender or 0
    local target = (P.teleportToLast and res.coords and res.coords.x) and res.coords or P.defaultSpawn

    DoScreenFadeOut(200)
    Wait(220)
    teardownScene()
    FreezeEntityPosition(PlayerPedId(), true)  -- teardown unfroze it; hold until placed

    -- Make sure the framework has the player loaded (money/job/inventory). This is
    -- normally already true since login happened when Play was pressed.
    local ldl = GetGameTimer() + 5000
    while GetGameTimer() < ldl do
        local st = LocalPlayer and LocalPlayer.state
        if st and st.isLoggedIn then break end
        Wait(50)
    end

    -- Appearance. For an EXISTING character the look was already applied to the
    -- (hidden) player ped while the spawn picker was open, so here we just wait for
    -- that to finish (usually instant) - no slow model-swap inside the black screen.
    -- If it was never started (picker disabled), apply it now. New characters open
    -- the creator here.
    if isNew then
        if P.forceFreemodeModel ~= false then ensureFreemodeModel(gender) end
        -- Open the clothing resource's creator so the new character gets a saved
        -- look (illenium etc.). Some frameworks (ESX) open it themselves, so this
        -- is optional - see Config.Appearance.apply.newCharacterEvent.
        local newEvt = ((Config.Appearance or {}).apply or {}).newCharacterEvent
        if newEvt then pcall(function() TriggerEvent(newEvt) end) end
    elseif loginLook then
        local dl = GetGameTimer() + 5000
        while not loginLook.done and GetGameTimer() < dl do Wait(20) end
    else
        applyPlayerLook(res, gender)   -- picker was disabled: apply now
    end

    -- The spawn preview already teleported the player here and streamed the area,
    -- so collision is usually ALREADY loaded and we can reveal immediately. Only
    -- run a (short) load scene as a fallback if it isn't.
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

    DoScreenFadeIn(300)
end

-- Build the list of spawn tiles for the picker. Includes "Last Location" only
-- when the character actually has a saved position to return to.
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

-- Resolve a spawn tile id to world coords. '__last' returns the character's
-- saved position (held in pendingSpawn); a fixed id returns its config coords.
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

-- Move the live backdrop camera to a spawn point so the player previews where
-- they will appear. Streams the destination behind a short fade so there is no
-- pop-in, and debounces rapid tile switches with a token.
local function previewSpawnBackdrop(coords)
    if not coords or not coords.x then return end
    spawnPreviewToken = spawnPreviewToken + 1
    local token = spawnPreviewToken
    spawnPreviewActive = true

    DoScreenFadeOut(160)
    Wait(180)
    if token ~= spawnPreviewToken then return end  -- superseded by a newer pick

    -- stream the destination area in
    SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    NewLoadSceneStartSphere(coords.x, coords.y, coords.z, 80.0, 0)
    local dl = GetGameTimer() + 800
    while not IsNewLoadSceneLoaded() and GetGameTimer() < dl do Wait(0) end
    NewLoadSceneStop()
    if token ~= spawnPreviewToken then return end

    -- elevated 3/4 establishing shot facing the spawn spot
    local h = math.rad(coords.w or 0.0)
    local fx, fy = -math.sin(h), math.cos(h)   -- forward vector
    local rx, ry = math.cos(h), math.sin(h)    -- right vector
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

    -- Move the (hidden) REAL player ped to this spawn NOW, so the world streams
    -- AROUND the player while they're still in the picker. Then finishLogin finds
    -- the area already loaded and reveals almost instantly instead of blacking out.
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

-- Called after a character is chosen. If the spawn picker is enabled it swaps the
-- character UI for the spawn UI (keeping the cinematic scene live behind it), then
-- waits for a choice. Otherwise it hands straight off to finishLogin.
local function beginSpawnSelection(res, isNew)
    local S = Config.Spawn or {}
    local usePicker = S.enabled ~= false
    if isNew and S.showForNewCharacters == false then usePicker = false end

    local tiles = usePicker and buildSpawnTiles(res) or {}
    if #tiles == 0 then usePicker = false end

    loginLook = nil  -- reset any stale pre-apply state

    if not usePicker then
        finishLogin(res, isNew)
        return
    end

    pendingSpawn = { res = res, isNew = isNew }
    isOpen = false          -- character screen is logically done
    spawnPicking = true     -- but keep the scene + camera + focus alive

    -- Pre-apply the character's model + clothing to the (hidden) REAL player ped
    -- NOW, while the picker is open, so finishLogin only has to teleport. This is
    -- what removes the model-swap from inside the black spawn screen.
    if not isNew then
        loginLook = { done = false }
        local lookRes = res
        CreateThread(function()
            applyPlayerLook(lookRes, lookRes.gender or 0)
            -- the model swap can create a fresh ped; keep it hidden + pinned so it
            -- doesn't flicker into view or fall while the picker is still up
            local p = PlayerPedId()
            SetEntityVisible(p, false, false)
            SetEntityLocallyInvisible(p)
            FreezeEntityPosition(p, true)
            if loginLook then loginLook.done = true end
        end)
    end

    -- hide the character UI (music keeps playing), reveal the spawn UI over the
    -- same live backdrop
    SendNUIMessage({ action = 'spawnHide' })
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'spawnOpen', data = {
        spawns = tiles,
        brand = Config.Brand,
        title = S.title or 'CHOOSE SPAWN',
        subtitle = S.subtitle or 'Where do you want to start?',
    } })

    -- re-assert focus a few times in case the NUI page is slow to accept it
    CreateThread(function()
        for _ = 1, 6 do
            if not spawnPicking then return end
            if not IsNuiFocused() then SetNuiFocus(true, true) end
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
    -- forward failures / delete outcomes to the UI
    SendNUIMessage({ action = 'actionResult', data = res })
end)

-- NUI -> client: the player picked a spawn tile.
RegisterNUICallback('spawnSelect', function(data, cb)
    cb('ok')
    if not spawnPicking or not pendingSpawn then return end

    local res, isNew = pendingSpawn.res, pendingSpawn.isNew
    pendingSpawn = nil
    spawnPicking = false
    spawnPreviewToken = spawnPreviewToken + 1  -- cancel any in-flight backdrop preview

    local id = data and data.id
    if id and id ~= '__last' then
        local chosen = resolveSpawnCoords(id)
        if chosen and chosen.x then
            res.coords = { x = chosen.x, y = chosen.y, z = chosen.z, w = chosen.w or 0.0 }
        end
    end
    -- id == '__last' keeps res.coords (the saved position) untouched

    finishLogin(res, isNew)
end)

-- NUI -> client: the player highlighted a spawn tile; show that location.
RegisterNUICallback('spawnPreview', function(data, cb)
    cb('ok')
    if not spawnPicking then return end
    previewSpawnBackdrop(resolveSpawnCoords(data and data.id))
end)

-- NUI -> client: the player pressed Back; restore the character selector.
RegisterNUICallback('spawnBack', function(_, cb)
    cb('ok')
    if not spawnPicking then return end
    spawnPicking = false
    spawnPreviewActive = false
    spawnPreviewToken = spawnPreviewToken + 1  -- cancel any in-flight preview
    pendingSpawn = nil
    isOpen = true

    DoScreenFadeOut(240)
    Wait(260)
    -- restore streaming focus + the preview ped/camera at the showcase location
    prepareLocalPlayer()
    spawnPreviewPed({ gender = currentGender }, true)  -- keep the current pose
    setupCamera()
    -- hide the spawn UI and bring the character UI back (music never stopped)
    SendNUIMessage({ action = 'spawnClose' })
    SendNUIMessage({ action = 'spawnShow' })
    Wait(80)
    DoScreenFadeIn(300)
end)

RegisterNetEvent('forger:client:open', function()
    openSelector()
end)

-- Re-open the selector whenever the framework logs the player out of their
-- character (via /logout, an admin action, or any other resource). This mirrors
-- how mil-multichar hooks qbx_core's logout. openSelector() guards against
-- double-opening, so it's safe if forger:client:open also fires.
RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    openSelector()
end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    openSelector()
end)

-- Feedback when /logout is denied by the ace permission (screen is on the world,
-- not the NUI, so use a game notification).
RegisterNetEvent('forger:client:actionResult', function(res)
    if res and res.action == 'logout' and res.ok == false and res.reason == 'no_permission' then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName("You don't have permission to log out.")
        EndTextCommandThefeedPostTicker(false, true)
    end
end)

-- ---------------------------------------------------------------------------
-- NUI -> client
-- ---------------------------------------------------------------------------
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

-- Rebuild the preview ped when the user browses to a different character/slot.
RegisterNUICallback('preview', function(data, cb)
    if isOpen then
        lastPreviewData = data
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
    if isOpen and previewPed and DoesEntityExist(previewPed) then
        local poses = poseList(currentGender)
        poseIndex = poseIndex + 1
        if poseIndex > #poses then poseIndex = 1 end
        ClearPedTasksImmediately(previewPed)
        loopPose(previewPed, poses[poseIndex])
    end
    cb('ok')
end)

RegisterNUICallback('changeLocation', function(_, cb)
    if isOpen then
        local locs = Config.Locations
        locationIndex = locationIndex + 1
        if locationIndex > #locs then locationIndex = 1 end
        prepareLocalPlayer()
        spawnPreviewPed({ gender = currentGender }, true)  -- keep the current pose
        setupCamera()
        SendNUIMessage({ action = 'locationChanged', label = (locs[locationIndex] and locs[locationIndex].label) or '' })
    end
    cb('ok')
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
    end
    cb('ok')
end)

-- Persist the full settings blob (theme, filter, music url, volumes, menu style,
-- toggles, etc.) so the player's setup is restored next time they load in.
RegisterNUICallback('savePrefs', function(data, cb)
    if type(data) == 'table' then
        for k, v in pairs(data) do prefs[k] = v end
        savePrefs()
    end
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    -- "Exit" leaves the player at the selector; most servers map this to a
    -- disconnect. Kept as a no-op close so it never boots people accidentally.
    cb('ok')
end)

-- ---------------------------------------------------------------------------
-- auto open on first join
-- ---------------------------------------------------------------------------
-- Stop the default spawn manager from respawning the player. Without this the
-- game keeps respawning (each respawn does a top-down establishing pan + fade)
-- while the player sits on the character screen with no character loaded.
CreateThread(function()
    if GetResourceState('spawnmanager') == 'started' then
        pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
    end
end)

if AUTO_OPEN then
    CreateThread(function()
        DoScreenFadeOut(0)  -- ensure black before we even schedule the inner guard
        -- Keep the freshly-spawned player hidden/pinned AND the screen black so
        -- the game's spawn establishing pan is never visible before we take over.
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

-- Manual entry point for testing or custom connect flows.
RegisterCommand('multichar', function()
    openSelector()
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and (isOpen or spawnPicking) then
        teardownScene()
        SetNuiFocus(false, false)
    end
end)
