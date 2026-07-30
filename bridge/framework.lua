FW = { name = 'unknown', core = nil }

local function detect()
    local forced = Config.Framework
    local hasQbx = GetResourceState('qbx_core') == 'started'
    local hasQb = GetResourceState('qb-core') == 'started'

    if forced == 'qbx' or (forced == 'auto' and hasQbx) then
        FW.name = 'qbx'
    elseif forced == 'qb' or (forced == 'auto' and hasQb) then
        FW.name = 'qb'
        FW.core = exports['qb-core']:GetCoreObject()
    else
        FW.name = 'unknown'
        print('^1[forger-multicharacter] No supported framework detected (qbx_core / qb-core). Login handoff will fail.^0')
    end
    print(('^2[forger-multicharacter]^0 framework resolved to: %s'):format(FW.name))
end

CreateThread(function()
    Wait(500)
    detect()
end)

local function buildCharInfo(data)
    return {
        firstname = data.firstname,
        lastname = data.lastname,
        birthdate = data.birthdate,
        gender = data.gender,
        nationality = data.nationality,
        backstory = data.backstory,
        phone = nil,
        account = nil,
    }
end

local function currentCitizenId(src)
    if FW.name == 'qbx' then
        local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        if ok and p and p.PlayerData then return p.PlayerData.citizenid end
    elseif FW.name == 'qb' then
        if not FW.core then return nil end
        local p = FW.core.Functions.GetPlayer(src)
        if p and p.PlayerData then return p.PlayerData.citizenid end
    end
    return nil
end

function FW.IsLoggedInAs(src, citizenid)
    return currentCitizenId(src) == citizenid
end

-- qb-core registers commands per-character; without this the player has none until
-- they reconnect. qbx does it itself.
function FW.RefreshCommands(src)
    if FW.name == 'qb' and FW.core then
        pcall(function() FW.core.Commands.Refresh(src) end)
    end
end

function FW.GetPlayer(src)
    if FW.name == 'qbx' then
        local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        if ok then return p end
    elseif FW.name == 'qb' and FW.core then
        return FW.core.Functions.GetPlayer(src)
    end
    return nil
end

local loadedState = {}

local function markLoaded(src)
    src = tonumber(src)
    if src then loadedState[src] = true end
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    markLoaded(src)
end)
AddEventHandler('qbx_core:server:playerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    markLoaded(src)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) loadedState[tonumber(src) or 0] = nil end)
AddEventHandler('qbx_core:server:playerLoggedOut', function(src) loadedState[tonumber(src) or 0] = nil end)
AddEventHandler('playerDropped', function() loadedState[source] = nil end)

function FW.ClearLoaded(src)
    loadedState[tonumber(src) or 0] = nil
end

-- FW.Login returning true only means the call was accepted; the core still has
-- async work to do (money, job, metadata, inventory). Replying to the client
-- before its PlayerLoaded event fires is what left the server thinking the player
-- had never loaded in.
function FW.WaitForLoaded(src, timeoutMs)
    if loadedState[src] then return true end
    local deadline = GetGameTimer() + (tonumber(timeoutMs) or 10000)
    while GetGameTimer() < deadline do
        if loadedState[src] then return true end
        local p = FW.GetPlayer(src)
        if p and p.PlayerData and p.PlayerData.citizenid then
            markLoaded(src)
            return true
        end
        Wait(50)
    end
    return false
end

function FW.Logout(src)
    if FW.name == 'qbx' then
        pcall(function() exports.qbx_core:Logout(src) end)
    elseif FW.name == 'qb' and FW.core then
        pcall(function() FW.core.Player.Logout(src) end)
    end
end

function FW.Login(src, citizenid)
    -- IDEMPOTENT: re-running the core's Login on an already-loaded player is what some
    -- cores and anti-cheats flag as an exploit. Happens when a player opens the spawn
    -- selector, presses Back, then presses Play again.
    if FW.IsLoggedInAs(src, citizenid) then
        return true, nil
    end
    if currentCitizenId(src) then
        FW.Logout(src)
        Wait(200)
    end
    FW.ClearLoaded(src)

    if FW.name == 'qbx' then
        -- Log in through the qb-core BRIDGE, not exports.qbx_core:Login. The bridge fires
        -- QBCore:Client:OnPlayerLoaded, which is what illenium-appearance listens for to
        -- auto-load the saved skin. Requires: setr qbx:enablebridge true
        local ok, success = pcall(function()
            local core = exports['qb-core']:GetCoreObject()
            return core.Player.Login(src, citizenid) and true or false
        end)
        if ok then return success == true, nil end
        local ok2, reason = exports.qbx_core:Login(src, citizenid)
        return ok2 == true, reason
    elseif FW.name == 'qb' then
        if not FW.core then return false, 'core missing' end
        local ok = FW.core.Player.Login(src, citizenid)
        return ok == true, nil
    end
    return false, 'no framework'
end

function FW.CreateAndLogin(src, data, cid)
    local charinfo = buildCharInfo(data)
    FW.ClearLoaded(src)

    if FW.name == 'qbx' then
        local newData = {
            charinfo = charinfo,
            money = { cash = Config.Creation.startingMoney.cash, bank = Config.Creation.startingMoney.bank },
        }
        local ok, reason = exports.qbx_core:Login(src, nil, newData)
        return ok == true, reason

    elseif FW.name == 'qb' then
        if not FW.core then return false, 'core missing' end
        local newData = {
            cid = cid,
            charinfo = charinfo,
            money = {
                cash = Config.Creation.startingMoney.cash,
                bank = Config.Creation.startingMoney.bank,
                crypto = 0,
            },
        }
        local ok = FW.core.Player.Login(src, false, newData)
        return ok == true, nil
    end

    return false, 'no framework'
end
