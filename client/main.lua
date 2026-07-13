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
local partnerPed = nil      -- second ped shown when paired
local sceneId = nil         -- synchronized scene handle
local pairView = false      -- widen the shot while paired
local anchorZ = nil         -- ground-snapped z for the current location
local locationIndex = 1
local poseIndex = 1
local currentGender = 0
local zoomIndex = 1
local filterName = 'none'
local dofOn = false
local pairActive = false
local pairArgs = nil    -- { emote, selfRole, partnerRole, partnerGender } for re-applying
local walkToken = 0     -- cancels the couple-walk loop when the scene changes/stops

local spawnPicking = false  -- true while the spawn-point picker is up (scene stays live)
local pendingSpawn = nil     -- { res = ..., isNew = ... } held between select and spawn pick
local loggedIn = false       -- guards finishLogin so it can only run once
local spawnPreviewActive = false -- true while the camera is showing a spawn point (not the ped)
local spawnPreviewToken = 0      -- debounces rapid spawn-tile selections
local loginLook = nil            -- { done=bool } while the player's look is pre-applied during spawn pick
local poseLoopToken = 0          -- cancels a running spaced-pose loop when the pose changes
local sceneStanceToken = 0       -- cancels running scene-stance loops when the preview changes
local currentScene = nil         -- saved custom scene (backdrop) for the character being viewed
local lastPreviewData = nil      -- last character data previewed (to re-render on a setting change)
local sceneVehicles = {}         -- local vehicles spawned for a custom-scene backdrop
local memberPeds = {}            -- extra peds for the other members of a co-op scene
local locationSwitching = false  -- true while a location change is fading/rebuilding

-- Remove any vehicles + member peds spawned for a custom scene backdrop.
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

-- Find the member entry for the character being viewed (co-op scenes).
local function sceneSelfMember(scene, citizenid)
    if not (scene and scene.members) then return nil end
    for _, m in ipairs(scene.members) do
        if m.citizenid == citizenid then return m end
    end
    return scene.members[1]
end

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
-- Push a saved appearance table onto ANY ped through the configured clothing
-- resource. In Lua an export MUST be called with the colon (exports[res]:fn());
-- the bracket form exports[res][fn](ped, data) drops `ped` into the proxy's
-- hidden self slot, so illenium receives (appearance, nil) and dresses nothing -
-- the "clothing did not update" bug. The export name is dynamic (Config), so we
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

    -- Optional: if the server sent saved appearance and you run illenium /
    -- fivem-appearance, apply it. Never let a missing export break the scene.
    if character.appearance and (res == 'illenium-appearance' or res == 'fivem-appearance') then
        applyPedAppearance(ped, character.appearance)
    end
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
    return z  -- surface z (feet level), used as the paired-scene origin
end

local function poseList(gender)
    return Config.Poses[(gender == 1) and 'female' or 'male'] or Config.Poses.male or {}
end

-- Which scene set is active: the couple set when the viewed character has a
-- partner, otherwise the normal set.
local function activeLocations()
    if pairActive and Config.CoupleLocations and #Config.CoupleLocations > 0 then
        return Config.CoupleLocations
    end
    return Config.Locations
end

-- The active scene table + a safe index (clamped to the active set's length).
local function activeLoc()
    local locs = activeLocations()
    local idx = locationIndex
    if idx < 1 or idx > #locs then idx = 1 end
    return locs[idx], idx
end

-- Anchor coords for a scene. Walk scenes anchor at their `from` point; a walk
-- scene stores its coords in .from/.to instead of .ped.
local function locPed(loc)
    if loc.ped then return loc.ped end
    if loc.from then return loc.from end
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

-- Play a saved-scene stance (from Config.SceneMaker.stances) on a ped. Used ONLY
-- for a custom scene backdrop (never for the default single / couple scene, which
-- use playPose + poseLoop), so this logic can't collide with those emotes.
--
-- Two things had to be true for this to work reliably:
--   1. TIMING: the ped is created at the saved scene coords, which may not be
--      streamed yet. A scenario issued before the world has collision around the
--      ped just leaves it idle, so we wait for collision first.
--   2. SURVIVING A CLOBBER: right after we pose, something in the pipeline (the
--      appearance apply settling, a re-seat, a rapid rebuild) can clear the task
--      an instant later - which looked like "it tried then stopped". So we watch
--      the pose during a short settle window and RE-APPLY if it gets cleared.
-- Both happen while the ped is HIDDEN (the caller spawns it at alpha 0); we only
-- reveal it once the pose has actually held for a moment. Result: it appears
-- already in the stance, never idle, and never visibly restarts.
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

    -- true when the ped is actually holding this stance right now
    local function isPosed()
        if not DoesEntityExist(ped) then return false end
        if st.scenario then return IsPedUsingScenario(ped, st.scenario) end
        if st.dict and st.anim then return IsEntityPlayingAnim(ped, st.dict, st.anim, 3) end
        return false
    end

    -- apply the pose once (assumes collision is present so it will take).
    -- SCENARIOS: proven in testing to only animate on an UNFROZEN ped here, so we
    -- unfreeze and hold position by pinning coords instead (visually identical).
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
        -- 1) wait for collision around the ped so the pose can take
        local c0 = GetEntityCoords(ped)
        local dl = GetGameTimer() + 8000
        while valid() and not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < dl do
            RequestCollisionAtCoord(c0.x, c0.y, c0.z)
            Wait(0)
        end
        if not valid() then return end

        -- preload the anim dict (scenarios need nothing)
        if st.dict and st.anim then
            RequestAnimDict(st.dict)
            local adl = GetGameTimer() + 3000
            while not HasAnimDictLoaded(st.dict) and GetGameTimer() < adl do Wait(0) end
            if not valid() then return end
        end

        -- 2) apply, then hold it through the settle window: if anything clears the
        -- pose, re-apply (invisibly - the ped is still hidden). Reveal only once the
        -- pose has held continuously for a short spell (or we run out of window).
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
        -- posed and holding: reveal (it was spawned hidden to hide the idle frame)
        if valid() then SetEntityAlpha(ped, 255, false) end

        -- Scenario peds stay UNFROZEN so the scenario keeps animating; keep them
        -- planted with a light position-only corrector (never touches the task,
        -- so the stance never restarts).
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
            -- hold for one cycle, re-asserting if the anim gets cleared. When it is
            -- NOT playing we clear tasks first: if some other task is blocking the
            -- emote (which is what made poses "try and stop"), a plain TaskPlayAnim
            -- keeps losing to it - clearing first frees the ped to take the pose.
            local endAt = GetGameTimer() + durMs
            while myToken == poseLoopToken and GetGameTimer() < endAt do
                if ped == previewPed and DoesEntityExist(ped)
                   and not IsEntityPlayingAnim(ped, pose.dict, pose.anim, 3) then
                    ClearPedTasksImmediately(ped)
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
    clearSceneVehicles()  -- drop any vehicles from the previously viewed scene
    NewLoadSceneStop()    -- cancel any load scene a previous custom scene started
    sceneStanceToken = sceneStanceToken + 1  -- stop stance loops from the previous preview

    -- Custom scene backdrop. Only used when the player opted in via the settings
    -- toggle (prefs.customScene) AND this character actually has a saved scene.
    -- A partner ALWAYS wins: while paired we ignore the custom scene entirely so
    -- the couple scene shows instead. Default (toggle off) = normal single scene.
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

    -- Prefer the model the appearance was saved on (authoritative), else the
    -- gender freemode model. This makes the preview match the real character.
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
        -- Spawn hidden: the ped streams in over a few frames and the scenario only
        -- takes once the world is present around it. playStance reveals it the
        -- instant it is posed, so the idle/streaming frames are never seen.
        SetEntityAlpha(previewPed, 0, false)
        -- the saved coords are where the player actually stood, so trust that Z
        -- (a fresh ground-snap fails while the far area is still streaming and would
        -- leave the ped floating or sunk). Stream the area around it.
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
        -- Normal location: we may be returning from a custom scene that moved the
        -- streaming focus far away. Re-focus here; if the ground isn't loaded yet,
        -- hide the ped and snap it properly once it streams in (snapping into an
        -- unstreamed area buries the ped to the chest).
        SetFocusPosAndVel(lp.x, lp.y, lp.z, 0.0, 0.0, 0.0)
        RequestCollisionAtCoord(lp.x, lp.y, lp.z)
        anchorZ = snapPedToGround(previewPed, lp.x, lp.y, lp.z, lp.w)
        if not HasCollisionLoadedAroundEntity(previewPed) then
            SetEntityAlpha(previewPed, 0, false)
            local pedRef = previewPed
            CreateThread(function()
                local dl = GetGameTimer() + 6000
                while not HasCollisionLoadedAroundEntity(pedRef) and GetGameTimer() < dl do
                    RequestCollisionAtCoord(lp.x, lp.y, lp.z)
                    Wait(0)
                end
                if pedRef == previewPed and DoesEntityExist(pedRef) then
                    anchorZ = snapPedToGround(pedRef, lp.x, lp.y, lp.z, lp.w)
                    FreezeEntityPosition(pedRef, true)
                    SetEntityAlpha(pedRef, 255, false)
                end
            end)
        end
    end
    FreezeEntityPosition(previewPed, true)

    applyAppearance(previewPed, character)
    SetModelAsNoLongerNeeded(model)

    -- Re-assert the look a couple of frames later. Some appearance natives (head
    -- blend / components) silently no-op on the same frame a ped is created, which
    -- shows up as the clothing not updating when you browse characters. Guard on
    -- ped identity so a fast character switch never dresses the wrong ped.
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

    -- Custom scene: hold the saved stance + apply its time/weather, and stop here.
    if currentScene then
        poseLoopToken = poseLoopToken + 1  -- no pose loop; the stance is a hold
        if not playStance(previewPed, (selfMember and selfMember.stance) or currentScene.stance) then
            -- no valid stance to pose: reveal the ped anyway so it is never invisible
            SetEntityAlpha(previewPed, 255, false)
        end

        -- Co-op: spawn the OTHER members with their saved appearance + stance.
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
                        SetEntityAlpha(mp, 0, false)  -- hidden until playStance poses + reveals it
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

        -- apply the scene's own weather/time immediately (the weather tick loop
        -- keeps it locked while this scene is shown, without touching the player's
        -- own held weather/time, which resume when they browse away).
        if currentScene.weather then
            SetWeatherTypeNowPersist(currentScene.weather)
            SetWeatherTypeNow(currentScene.weather)
        end
        if currentScene.hour then
            NetworkOverrideClockTime(currentScene.hour, currentScene.minute or 0, 0)
        end
        -- Spawn the saved vehicles at their EXACT saved transform. The transform
        -- was captured after the game planted the car on the ground, so re-using
        -- it places the car flush - no floating and no sinking. Frozen so they
        -- can't roll or settle.
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
                        SetVehicleOnGroundProperly(veh)  -- refine once, then pin
                        FreezeEntityPosition(veh, true)
                        sceneVehicles[#sceneVehicles + 1] = veh
                    end
                end
            end
        end
        return
    end

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

    -- Loop the pose (spaced if configured). Clear the default AI task CreatePed
    -- leaves on the ped first - otherwise it can silently block the emote (the same
    -- reason the stance "did nothing"). loopPose then self-heals if the appearance
    -- apply clears the anim, so the ped always ends up performing the emote.
    if previewPed and DoesEntityExist(previewPed) then
        ClearPedTasksImmediately(previewPed)
    end
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
    if pairView then
        p.motion = C.pairMotion or p.motion
        -- keep the selected zoom preset, just widen it so both characters fit
        p.distance = p.distance + (C.pairDistanceAdd or 1.3)
        p.height = p.height + (C.pairHeightAdd or 0.2)
        p.pointAt = p.pointAt + (C.pairPointAtAdd or 0.18)
        p.fov = p.fov + (C.pairFovAdd or 5.0)
        p.swayArc = C.pairSwayArc or p.swayArc
    end
    return p
end

-- Compute where the camera should be at time t (seconds since the shot began).
local function computeCamPose(t)
    local p = camParams
    local loc = activeLoc()
    local lp = locPed(loc)

    -- Custom saved scene: orbit at the scene's saved ANGLE (the framing direction
    -- the player chose) but use the SELECTOR'S zoom (Close/Medium/Far) for the
    -- distance/height/fov - the same zoom the normal character scenes use. This
    -- keeps the Z-key zoom working and stops the saved distance from fighting it.
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

    local cx, cy, cz, baseAngle
    if loc.type == 'walk' and previewPed and DoesEntityExist(previewPed) then
        -- Follow the walking couple: focus on the lead ped, camera ahead of them
        -- (front view) so they read as strolling toward the shot.
        local c = GetEntityCoords(previewPed)
        cx, cy, cz = c.x, c.y, c.z
        local fwd = GetEntityForwardVector(previewPed)
        baseAngle = math.atan(fwd.y, fwd.x)
        if p.view == 'back' then baseAngle = baseAngle + math.pi end
    elseif pairView then
        -- Frame the shared couple scene at the location anchor.
        cx, cy, cz = lp.x, lp.y, (anchorZ or lp.z)
        local w = math.rad(lp.w)
        local fx, fy = -math.sin(w), math.cos(w)          -- scene forward
        baseAngle = math.atan(fy, fx)
        if p.view == 'back' then
            baseAngle = baseAngle + math.pi               -- camera behind the couple
        else
            baseAngle = baseAngle + math.rad(34.0)        -- 3/4 front so both faces show
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
        -- slow cinematic side-to-side pan (used by the couple Overlook scene)
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

-- Force the NUI mouse cursor to (re)appear. A plain SetNuiFocus(true, true) does
-- NOT rebuild a cursor that was dropped while focus stayed ON (for example when
-- another resource calls SetNuiFocus(true, false), or after a teleport/stream).
-- Toggling focus off then on in the SAME frame rebuilds the cursor; because there
-- is no Wait between the two calls the "off" state never renders, so there is no
-- visible blink. This is what keeps the cursor always visible on the selector.
local function forceCursor()
    SetNuiFocus(false, false)
    SetNuiFocus(true, true)
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

-- keep the mouse cursor active for the WHOLE time the character-select or
-- spawn-select screen is up. Two layers:
--   1. per-frame recovery when focus is fully lost (IsNuiFocused false), so any
--      transient grab is fixed within one frame;
--   2. a low-frequency unconditional re-assert (every 250ms). IsNuiFocused can't
--      see the case where focus is technically on but the CURSOR flag was dropped
--      (e.g. another resource called SetNuiFocus(true, false)); the periodic
--      re-assert restores the cursor in that case too, and at 250ms it is far too
--      infrequent to cause any visible blink.
CreateThread(function()
    local lastAssert = 0
    while true do
        if isOpen or spawnPicking then
            local now = GetGameTimer()
            if not IsNuiFocused() then
                forceCursor()
                lastAssert = now
            elseif now - lastAssert >= 250 then
                -- focus is on but the cursor may have been dropped; a same-frame
                -- toggle rebuilds it (a plain true->true re-assert would not).
                forceCursor()
                lastAssert = now
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- re-apply the chosen weather periodically so a server weather sync can't revert
-- it. While a custom scene is on screen, its weather/time win (without disturbing
-- the player's own held weather/time, which resume as soon as the scene is gone).
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
    SetEntityCoordsNoOffset(ped, lp.x, lp.y, lp.z + 1.0, false, false, false)
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    -- force the streamer to load full detail at the scene (no black load-scene)
    SetFocusPosAndVel(lp.x, lp.y, lp.z, 0.0, 0.0, 0.0)
    ensureCollision(lp.x, lp.y, lp.z)
    anchorZ = nil
end

-- ---------------------------------------------------------------------------
-- couple / friend paired scene (driven by client/partner.lua)
-- ---------------------------------------------------------------------------
-- selfRole / partnerRole are 'a' or 'b'; emote is a Config.Partner.emotes entry.
-- appearance (optional) clones the partner's real character look.
-- Walk the couple from loc.from to loc.to, then loop back to the start. Runs in
-- its own thread; walkToken cancels it when the scene changes or the pair stops.
local function startCoupleWalk(loc)
    walkToken = walkToken + 1
    local myToken = walkToken
    local from, to = loc.from, loc.to
    if not from or not to then return end
    local speed = loc.walkSpeed or 1.0

    local h = math.rad(from.w)
    local rx, ry = math.cos(h), math.sin(h)    -- right vector (side-by-side offset)
    local off = 0.65

    loadAnimDict('move_m@casual@a')
    CreateThread(function()
        while myToken == walkToken and pairActive do
            if not (previewPed and DoesEntityExist(previewPed) and partnerPed and DoesEntityExist(partnerPed)) then return end
            -- place both at the start, side by side, facing the walk direction
            FreezeEntityPosition(previewPed, false)
            FreezeEntityPosition(partnerPed, false)
            SetEntityCoordsNoOffset(previewPed, from.x, from.y, from.z, false, false, false)
            SetEntityCoordsNoOffset(partnerPed, from.x + rx * off, from.y + ry * off, from.z, false, false, false)
            SetEntityHeading(previewPed, from.w)
            SetEntityHeading(partnerPed, from.w)
            SetPedDesiredMoveBlendRatio(previewPed, 1.0)
            SetPedDesiredMoveBlendRatio(partnerPed, 1.0)

            -- stroll to the end point (straight line; the path is open)
            TaskGoStraightToCoord(previewPed, to.x, to.y, to.z, speed, 20000, to.w, 0.5)
            TaskGoStraightToCoord(partnerPed, to.x + rx * off, to.y + ry * off, to.z, speed, 20000, to.w, 0.5)

            -- wait until the lead ped reaches the end (or a safety timeout)
            local deadline = GetGameTimer() + 30000
            while myToken == walkToken and pairActive and GetGameTimer() < deadline do
                local c = GetEntityCoords(previewPed)
                if #(c - vector3(to.x, to.y, to.z)) < 1.6 then break end
                Wait(150)
            end
            if myToken ~= walkToken then return end
            Wait(500)  -- brief pause at the end before looping back to the start
        end
    end)
end

function ForgerStartPairScene(emote, selfRole, partnerRole, partnerGender, appearance)
    if not previewPed or not DoesEntityExist(previewPed) then return end
    local selfAnim, partnerAnim = emote[selfRole], emote[partnerRole]
    if not selfAnim or not partnerAnim then return end

    pairArgs = { emote = emote, selfRole = selfRole, partnerRole = partnerRole, partnerGender = partnerGender, appearance = appearance }
    pairActive = true
    currentScene = nil                 -- a partner ALWAYS overrides the custom scene
    poseLoopToken = poseLoopToken + 1  -- stop the single-ped pose loop; the couple scene drives the ped now

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

    -- clone the partner's saved appearance if we have it and an appearance
    -- resource is configured; otherwise the default-gender ped is used.
    if appearance then
        applyPedAppearance(partnerPed, appearance)
    end

    local loc = activeLoc()

    -- WALK scene: the couple strolls from `from` to `to` and loops. No static
    -- emote here - the walk IS the scene.
    if loc.type == 'walk' then
        startCoupleWalk(loc)
        pairView = true
        setupCamera()
        return
    end

    walkToken = walkToken + 1  -- cancel any walk loop from a previous scene
    local lp = locPed(loc)

    -- Upper-body path: the two peds stand side by side and the emote plays on the
    -- UPPER body only, leaving the legs free.
    if emote.upperBody then
        local z = anchorZ or lp.z
        local h = math.rad(lp.w)
        local rx, ry = math.cos(h), math.sin(h)          -- right vector
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

    -- These emote-pack clips are authored with the origin at the ped's root, so
    -- the synchronized-scene origin must be raised off the ground or the peds
    -- sink to the waist. Offset is tunable in Config.Partner.sceneZOffset.
    local z = (anchorZ or lp.z) + (Config.Partner.sceneZOffset or 0.98)

    ClearPedTasksImmediately(previewPed)
    ClearPedTasksImmediately(partnerPed)

    -- Both peds share one scene origin; the authored a/b offset aligns them.
    local coupleBlend = (Config.Partner and Config.Partner.emoteBlendIn) or 1.5
    sceneId = CreateSynchronizedScene(lp.x, lp.y, z, 0.0, 0.0, lp.w, 2)
    SetSynchronizedSceneLooped(sceneId, true)
    TaskSynchronizedScene(previewPed, sceneId, selfAnim.dict, selfAnim.clip, coupleBlend, -4.0, 0, 0, 1148846080, 0)
    TaskSynchronizedScene(partnerPed, sceneId, partnerAnim.dict, partnerAnim.clip, coupleBlend, -4.0, 0, 0, 1148846080, 0)

    pairView = true
    setupCamera()
end

-- Re-run the current paired scene at the current location (used when the player
-- changes location while paired, so the partner comes along).
function ForgerReapplyPairScene()
    if pairActive and pairArgs then
        ForgerStartPairScene(pairArgs.emote, pairArgs.selfRole, pairArgs.partnerRole, pairArgs.partnerGender, pairArgs.appearance)
    end
end

function ForgerStopPairScene()
    -- CRITICAL GUARD: the server sends partnerHide for ANY viewed character that
    -- simply has no partner - which is most characters, on every browse. Without
    -- this guard that message cleared the freshly applied stance/pose an instant
    -- after every spawn ("it tries to apply and stops immediately"). Only do the
    -- teardown when a pair scene is actually active.
    if not pairActive and not (partnerPed and DoesEntityExist(partnerPed)) then return end

    pairActive = false
    pairArgs = nil
    walkToken = walkToken + 1  -- stop any couple-walk loop
    if partnerPed and DoesEntityExist(partnerPed) then DeleteEntity(partnerPed) partnerPed = nil end
    sceneId = nil
    pairView = false
    -- Rebuild from the last previewed character so the CORRECT presentation comes
    -- back: a custom scene routes to the stance path, a normal character to the
    -- default pose path. (The old code always forced the default pose loop, which
    -- also stomped custom scenes.)
    if isOpen and lastPreviewData then
        spawnPreviewPed(lastPreviewData)
    elseif previewPed and DoesEntityExist(previewPed) then
        ClearPedTasksImmediately(previewPed)
        poseIndex = 1
        loopPose(previewPed, poseList(currentGender)[poseIndex])
    end
    setupCamera()
end

function ForgerIsOpen() return isOpen end

-- ---------------------------------------------------------------------------
-- open / close
-- ---------------------------------------------------------------------------
local function openSelector()
    if isOpen then return end
    isOpen = true

    -- CRITICAL for the cursor: until the loading screen NUI is shut down, its
    -- frame sits on top of the NUI stack and the mouse cursor will NOT render,
    -- no matter how often SetNuiFocus(true, true) is called underneath it. This
    -- resource never called it, which is why the cursor never showed. Both calls
    -- are safe no-ops when the loading screen is already gone (e.g. /logout).
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

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

    -- HARD focus toggle: if focus got wedged while the loading NUI was up, a
    -- plain re-assert (true -> true) never re-creates the cursor. Off for one
    -- frame, then on, rebuilds it cleanly. The screen is still faded black here,
    -- so the toggle is invisible.
    SetNuiFocus(false, false)
    Wait(0)
    SetNuiFocus(true, true)
    SetCursorLocation(0.5, 0.5)  -- put the cursor mid-screen so it is instantly visible
    SendNUIMessage({ action = 'open' })
    -- Keep the cursor focused for the WHOLE time the selector is open (not just the
    -- first second). A slow scene load or a game grab can drop the cursor; this
    -- re-asserts it so it never goes missing.
    CreateThread(function()
        while isOpen do
            if not IsNuiFocused() then forceCursor() end
            Wait(400)
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
    if Config.Partner.enabled then TriggerServerEvent('forger:server:partnerPresence', true) end

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

-- ---------------------------------------------------------------------------
-- server -> client
-- ---------------------------------------------------------------------------
RegisterNetEvent('forger:client:setCharacters', function(payload)
    SendNUIMessage({ action = 'setData', data = payload })
end)

-- Apply a saved appearance straight to the local player through the appearance
-- resource. Mirrors how mil-multichar does it: set the ped MODEL from the saved
-- data first, then apply the clothing/face on top. Using the model + setPedAppearance
-- (rather than trusting a single export to do both) guarantees the correct ped
-- even if the appearance JSON is slightly off. Returns true if it applied a model.
local function applySavedAppearance(appearance)
    local A = Config.Appearance or {}
    if A.resource == 'none' or not A.resource then return false end
    -- must be a decoded table (not a raw string / empty)
    if type(appearance) ~= 'table' or next(appearance) == nil then return false end

    -- 1) set the model the look was saved on (fall back to gender freemode)
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

    -- 2) apply the clothing/face/props/hair/tattoos on top of that model
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

-- Set the REAL player ped's model + clothing for an existing character. Runs
-- while the ped is hidden (during the spawn picker or the login fade), so the
-- final spawn doesn't have to do a slow model-swap inside the black screen.
local function applyPlayerLook(res, gender)
    local P = Config.PostLogin or {}
    local hasAppearance = res.appearance ~= nil
        and type(res.appearance) == 'table' and next(res.appearance) ~= nil
    if P.applyAppearance then
        local applied = hasAppearance and applySavedAppearance(res.appearance)
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
        if P.newCharacterEvent then pcall(function() TriggerEvent(P.newCharacterEvent) end) end
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

    -- Tell the server where the player ACTUALLY ended up so it writes this as the
    -- character's last position - healing any parked showcase/picker coords a
    -- framework save may have stored while we were on the selection screens.
    do
        local fc = GetEntityCoords(ped)
        TriggerServerEvent('forger:server:spawnPlaced', {
            x = fc.x, y = fc.y, z = fc.z, w = GetEntityHeading(ped),
        })
    end

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

    -- Hide the character-scene entities so the spawn-location preview shows ONLY
    -- the location. A custom scene (its ped, stance, and vehicles) sits at the
    -- character's coords, which can be the exact "last location" spawn spot.
    sceneStanceToken = sceneStanceToken + 1
    if previewPed and DoesEntityExist(previewPed) then SetEntityVisible(previewPed, false, false) end
    if partnerPed and DoesEntityExist(partnerPed) then SetEntityVisible(partnerPed, false, false) end
    for _, e in ipairs(sceneVehicles) do if DoesEntityExist(e) then SetEntityVisible(e, false, false) end end
    for _, e in ipairs(memberPeds) do if DoesEntityExist(e) then SetEntityVisible(e, false, false) end end

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
    SetNuiFocus(false, false)
    Wait(0)
    SetNuiFocus(true, true)
    SetCursorLocation(0.5, 0.5)  -- cursor instantly visible on the spawn screen
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
    -- restore streaming focus + the preview ped/camera at the showcase location.
    -- Use the full last-previewed character so appearance AND a custom scene come
    -- back exactly as they were (a bare gender stub lost both).
    prepareLocalPlayer()
    spawnPreviewPed(lastPreviewData or { gender = currentGender }, true)  -- keep the current pose
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
    -- A custom scene holds its saved STANCE; poses are a default-scene feature.
    -- Never let the pose cycle touch a scene ped (it would clear the stance).
    if currentScene then cb('scene') return end
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
    cb('ok')  -- answer the UI immediately; the transition runs on its own thread
    -- A custom scene IS its own location (the saved coords). Location cycling is a
    -- default-scene feature; running it on a scene would tear the scene down.
    if currentScene then return end
    if not isOpen then return end
    if locationSwitching then return end  -- ignore rapid re-entry while mid-transition
    locationSwitching = true

    CreateThread(function()
        local locs = activeLocations()
        locationIndex = locationIndex + 1
        if locationIndex > #locs then locationIndex = 1 end

        -- Fade to black around the rebuild. Without it the change is a hard cut:
        -- the old ped is deleted, the new area streams in, and the new ped snaps to
        -- the floor all on screen - which is the "changing location looks broken"
        -- bug. The fade hides the teardown + stream + ground-snap entirely.
        DoScreenFadeOut(180)
        Wait(200)

        prepareLocalPlayer()
        -- Rebuild with the FULL last-previewed character (not a bare gender stub)
        -- so the appearance survives the location change.
        spawnPreviewPed(lastPreviewData or { gender = currentGender }, true)  -- keep the current pose
        if pairActive then
            ForgerReapplyPairScene()   -- bring the partner to the new location
        else
            setupCamera()
        end
        -- settle the camera on the new ped before we fade back in
        for _ = 1, 2 do updateCameraFrame() Wait(0) end

        SendNUIMessage({ action = 'locationChanged', label = (locs[locationIndex] and locs[locationIndex].label) or '' })
        forceCursor()  -- the teleport/stream can drop the cursor; rebuild it
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
        -- re-render the character currently on screen so the choice applies now.
        -- If we're turning the custom scene OFF, also restore the normal time/
        -- weather the player had set in the selector.
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
