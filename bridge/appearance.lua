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

local function skinchangerApplyToPed(ped, s)
    if type(s) ~= 'table' then return false end
    local function v(key) return tonumber(s[key]) or 0 end

    pcall(function()
        SetPedHeadBlendData(ped, v('face'), v('face'), 0, v('skin'), v('skin'), 0, 1.0, 1.0, 0.0, false)
    end)

    SetPedComponentVariation(ped, 2, v('hair_1'), v('hair_2'), 0)
    pcall(function() SetPedHairColor(ped, v('hair_color_1'), v('hair_color_2')) end)

    pcall(function()
        SetPedHeadOverlay(ped, 1, v('beard_1'), 1.0)
        SetPedHeadOverlayColor(ped, 1, 1, v('beard_3'), v('beard_3'))
    end)

    SetPedComponentVariation(ped, 1,  v('mask_1'),   v('mask_2'),   0)
    SetPedComponentVariation(ped, 3,  v('arms'),     0,             0)
    SetPedComponentVariation(ped, 4,  v('pants_1'),  v('pants_2'),  0)
    SetPedComponentVariation(ped, 5,  v('bags_1'),   v('bags_2'),   0)
    SetPedComponentVariation(ped, 6,  v('shoes_1'),  v('shoes_2'),  0)
    SetPedComponentVariation(ped, 7,  v('chain_1'),  v('chain_2'),  0)
    SetPedComponentVariation(ped, 8,  v('tshirt_1'), v('tshirt_2'), 0)
    SetPedComponentVariation(ped, 9,  v('bproof_1'), v('bproof_2'), 0)
    SetPedComponentVariation(ped, 10, v('decals_1'), v('decals_2'), 0)
    SetPedComponentVariation(ped, 11, v('torso_1'),  v('torso_2'),  0)

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

local function eventApplyToPlayer()
    if AP.playerEvent then
        pcall(function() TriggerEvent(AP.playerEvent) end)
        return true
    end
    return false
end

function Appearance.applyToPed(ped, data)
    if not ped or not DoesEntityExist(ped) then return false end
    local method = AP.method or 'export'
    if method == 'export' then
        return exportApplyToPed(ped, data)
    elseif method == 'skinchanger' then
        return skinchangerApplyToPed(ped, data)
    end
    return false
end

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

function Appearance.clothingLoadsItself()
    return Config.PostLogin and Config.PostLogin.clothingLoadsItself == true
end
