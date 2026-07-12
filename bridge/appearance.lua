-- ---------------------------------------------------------------------------
-- Client appearance bridge  (clothing-resource agnostic)
-- ---------------------------------------------------------------------------
-- Puts a saved look onto:
--   * the PREVIEW ped   -> Appearance.applyToPed(ped, data)
--   * the real PLAYER   -> Appearance.applyToPlayer(data, gender)
--
-- The method is chosen by Config.Appearance.apply.method:
--   'export'      - illenium-appearance / fivem-appearance style exports that
--                   take a ped. Exact preview + player.
--   'skinchanger' - ESX classic (esx_skin/skinchanger). Component-map data is
--                   applied to the preview ped natively (best effort) and to the
--                   player via skinchanger events.
--   'event'       - fire a player-only outfit event (qb-clothing). No ped preview.
--   'none'        - never apply; default peds are used.
-- ---------------------------------------------------------------------------

Appearance = {}

local A = Config.Appearance or {}
local AP = A.apply or {}

local function loadModelHash(model)
    if type(model) == 'string' then model = joaat(model) end
    if not model or model == 0 then return nil end
    RequestModel(model)
    local t = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(0) end
    return HasModelLoaded(model) and model or nil
end

local function loadDict(dict)
    RequestAnimDict(dict)
end

-- ---------------------------------------------------------------------------
-- export method (illenium-appearance / fivem-appearance / qbx_clothing)
-- ---------------------------------------------------------------------------
local function exportApplyToPed(ped, data)
    if not data or A.resource == 'none' or not A.resource then return false end
    local fn = AP.pedExport or 'setPedAppearance'
    local ok = pcall(function()
        exports[A.resource][fn](ped, data)
    end)
    return ok
end

local function exportApplyToPlayer(data)
    if not data or A.resource == 'none' or not A.resource then return false end
    -- Set the model the look was saved on first (so the correct ped is dressed).
    if type(data) == 'table' and data.model then
        local m = loadModelHash(data.model)
        if m then
            SetPlayerModel(PlayerId(), m)
            SetModelAsNoLongerNeeded(m)
            Wait(50)
        end
    end
    local ok = pcall(function()
        if AP.playerExport then
            exports[A.resource][AP.playerExport](data)
        else
            exports[A.resource][AP.pedExport or 'setPedAppearance'](PlayerPedId(), data)
        end
    end)
    return ok
end

-- ---------------------------------------------------------------------------
-- skinchanger method (ESX classic component map)
-- ---------------------------------------------------------------------------
-- A skinchanger "skin" is a flat map of component/prop indices. skinchanger's
-- own loadSkin only targets the player ped, so for the PREVIEW ped we apply the
-- map with natives. This is a faithful subset (clothing, props, hair, basic
-- head blend); the real player gets the exact skinchanger apply on spawn.
local function skinchangerApplyToPed(ped, s)
    if type(s) ~= 'table' then return false end
    local function v(key) return tonumber(s[key]) or 0 end

    -- Head blend (face shape / skin tone) - approximate.
    pcall(function()
        SetPedHeadBlendData(ped, v('face'), v('face'), 0, v('skin'), v('skin'), 0, 1.0, 1.0, 0.0, false)
    end)

    -- Hair (component 2) + hair colour overlay.
    SetPedComponentVariation(ped, 2, v('hair_1'), v('hair_2'), 0)
    pcall(function() SetPedHairColor(ped, v('hair_color_1'), v('hair_color_2')) end)

    -- Facial overlays (beard / eyebrows) - best effort.
    pcall(function()
        SetPedHeadOverlay(ped, 1, v('beard_1'), 1.0)   -- beard
        SetPedHeadOverlayColor(ped, 1, 1, v('beard_3'), v('beard_3'))
    end)

    -- Clothing components: SetPedComponentVariation(ped, id, drawable, texture, palette)
    SetPedComponentVariation(ped, 1,  v('mask_1'),   v('mask_2'),   0)  -- mask
    SetPedComponentVariation(ped, 3,  v('arms'),     0,             0)  -- arms/torso
    SetPedComponentVariation(ped, 4,  v('pants_1'),  v('pants_2'),  0)  -- legs
    SetPedComponentVariation(ped, 5,  v('bags_1'),   v('bags_2'),   0)  -- bag
    SetPedComponentVariation(ped, 6,  v('shoes_1'),  v('shoes_2'),  0)  -- shoes
    SetPedComponentVariation(ped, 7,  v('chain_1'),  v('chain_2'),  0)  -- accessory
    SetPedComponentVariation(ped, 8,  v('tshirt_1'), v('tshirt_2'), 0)  -- undershirt
    SetPedComponentVariation(ped, 9,  v('bproof_1'), v('bproof_2'), 0)  -- body armour
    SetPedComponentVariation(ped, 10, v('decals_1'), v('decals_2'), 0)  -- decals
    SetPedComponentVariation(ped, 11, v('torso_1'),  v('torso_2'),  0)  -- top

    -- Props: SetPedPropIndex(ped, propId, drawable, texture, attach)
    if v('helmet_1') < 0 then ClearPedProp(ped, 0) else SetPedPropIndex(ped, 0, v('helmet_1'), v('helmet_2'), true) end
    if v('glasses_1') < 0 then ClearPedProp(ped, 1) else SetPedPropIndex(ped, 1, v('glasses_1'), v('glasses_2'), true) end
    if v('ears_1') < 0 then ClearPedProp(ped, 2) else SetPedPropIndex(ped, 2, v('ears_1'), v('ears_2'), true) end
    return true
end

local function skinchangerApplyToPlayer(s, gender)
    local isMale = (tonumber(gender) ~= 1)
    pcall(function() TriggerEvent('skinchanger:loadDefaultModel', isMale) end)
    Wait(150)
    if type(s) == 'table' then
        pcall(function() TriggerEvent('skinchanger:loadSkin', s) end)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- event method (qb-clothing outfit loader; player only)
-- ---------------------------------------------------------------------------
local function eventApplyToPlayer()
    if AP.playerEvent then
        pcall(function() TriggerEvent(AP.playerEvent) end)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- public API
-- ---------------------------------------------------------------------------
-- Dress a preview ped. Returns true if it applied something.
function Appearance.applyToPed(ped, data)
    if not ped or not DoesEntityExist(ped) then return false end
    local method = AP.method or 'export'
    if method == 'export' then
        return exportApplyToPed(ped, data)
    elseif method == 'skinchanger' then
        return skinchangerApplyToPed(ped, data)
    end
    -- 'event' and 'none' can't target an arbitrary ped: preview stays default.
    return false
end

-- Dress the real player on spawn. Returns true if it applied a model/look.
function Appearance.applyToPlayer(data, gender)
    local method = AP.method or 'export'
    if method == 'export' then
        if type(data) ~= 'table' or next(data) == nil then return false end
        return exportApplyToPlayer(data)
    elseif method == 'skinchanger' then
        return skinchangerApplyToPlayer(data, gender)
    elseif method == 'event' then
        return eventApplyToPlayer()
    end
    return false
end

-- Does the configured clothing resource dress the player itself on load? If so,
-- the spawn flow can skip applying (see Config.PostLogin.clothingLoadsItself).
function Appearance.clothingLoadsItself()
    return Config.PostLogin and Config.PostLogin.clothingLoadsItself == true
end
