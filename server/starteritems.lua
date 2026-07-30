StarterItems = {}

local INVENTORY_NONE = 0
local INVENTORY_OX = 1
local INVENTORY_QB = 2

local inventory = INVENTORY_NONE

CreateThread(function()
    Wait(500)
    if GetResourceState('ox_inventory') == 'started' then
        inventory = INVENTORY_OX
    elseif GetResourceState('qb-inventory') == 'started' then
        inventory = INVENTORY_QB
    end
end)

local function addItem(src, item, amount, metadata, slot)
    amount = tonumber(amount) or 1
    if amount < 1 then return false end

    if inventory == INVENTORY_OX then
        local ok = pcall(function()
            exports.ox_inventory:AddItem(src, item, amount, metadata, slot)
        end)
        if ok then return true end
    end

    if inventory == INVENTORY_QB then
        local ok = pcall(function()
            exports['qb-inventory']:AddItem(src, item, amount, slot, metadata, 'forger-multicharacter')
        end)
        if ok then return true end
    end

    -- fall back to the core's own inventory
    local player = FW.GetPlayer(src)
    if player and player.Functions and player.Functions.AddItem then
        local ok = pcall(function()
            player.Functions.AddItem(item, amount, slot, metadata)
        end)
        if ok then return true end
    end

    return false
end

-- Build the licence metadata ourselves when no ID card resource is installed, so
-- the item is not handed out blank.
local function licenceMetadata(src, item)
    local player = FW.GetPlayer(src)
    local ci = player and player.PlayerData and player.PlayerData.charinfo
    if not ci then return {} end

    if item == 'id_card' then
        return {
            citizenid = player.PlayerData.citizenid,
            firstname = ci.firstname,
            lastname = ci.lastname,
            birthdate = ci.birthdate,
            gender = ci.gender,
            nationality = ci.nationality,
        }
    end

    return {
        firstname = ci.firstname,
        lastname = ci.lastname,
        birthdate = ci.birthdate,
        type = 'Class C Driver License',
    }
end

local ID_RESOURCES = {
    { name = 'um-idcard',  export = 'CreateMetaLicense' },
    { name = 'bl_idcard',  export = 'createLicense' },
    { name = 'qbx_idcard', export = 'CreateMetaLicense' },
}

local function giveIdCard(src, item)
    for _, r in ipairs(ID_RESOURCES) do
        if GetResourceState(r.name) == 'started' then
            local ok = pcall(function()
                local proxy = exports[r.name]
                proxy[r.export](proxy, src, item)
            end)
            if ok then return true end
        end
    end
    return addItem(src, item, 1, licenceMetadata(src, item))
end

---Give the configured starter items to a brand new character.
---@param src number
function StarterItems.give(src)
    local C = Config.StarterItems
    if not (C and C.enabled) then return end

    local given, failed = 0, {}
    for _, entry in ipairs(C.items or {}) do
        if entry.item then
            local ok
            if entry.item == 'id_card' or entry.item == 'driver_license' then
                if C.giveIdCards == false then
                    ok = true
                else
                    ok = giveIdCard(src, entry.item)
                end
            else
                ok = addItem(src, entry.item, entry.amount or 1, entry.metadata, entry.slot)
            end
            if ok then
                given = given + 1
            else
                failed[#failed + 1] = entry.item
            end
        end
    end

    if #failed > 0 then
        print(('^3[forger-multicharacter] could not give starter items to %s: %s. Check the item names exist in your items list.^0')
            :format(GetPlayerName(src) or ('src ' .. src), table.concat(failed, ', ')))
    end

    TriggerEvent('forger:server:starterItemsGiven', src, given)
end
