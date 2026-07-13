-- Server side framework bridge.
-- Only the login / create handoff is framework specific. Reading and deleting
-- rows is done with plain oxmysql in server/main.lua so it works everywhere.

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
    -- give cores a moment to start
    Wait(500)
    detect()
end)

-- Build a charinfo table both cores understand.
local function buildCharInfo(data)
    return {
        firstname = data.firstname,
        lastname = data.lastname,
        birthdate = data.birthdate,
        gender = data.gender,            -- 0 male, 1 female
        nationality = data.nationality,
        backstory = data.backstory,      -- custom, safe to store
        phone = nil,                     -- let framework generate
        account = nil,
    }
end

-- Which citizenid (if any) this player is currently loaded as. nil while they
-- are still on the character screen (not logged into any character yet).
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

-- True if the player is already logged in as exactly this character.
function FW.IsLoggedInAs(src, citizenid)
    return currentCitizenId(src) == citizenid
end

-- Log the player out of their current character (used before switching).
function FW.Logout(src)
    if FW.name == 'qbx' then
        pcall(function() exports.qbx_core:Logout(src) end)
    elseif FW.name == 'qb' and FW.core then
        pcall(function() FW.core.Player.Logout(src) end)
    end
end

-- Load an EXISTING character and hand off to the framework spawn flow.
---@return boolean ok, string? err
function FW.Login(src, citizenid)
    -- IDEMPOTENT: if this player is already loaded as this exact character, do
    -- nothing. Re-running the core's Login on an already-loaded player is what
    -- some cores / anti-cheats flag as an exploit. This happens when the player
    -- opens the spawn selector, presses Back, then presses Play again.
    if FW.IsLoggedInAs(src, citizenid) then
        return true, nil
    end
    -- Switching from a DIFFERENT already-loaded character: log the old one out
    -- first so the core does a clean load rather than a double login.
    if currentCitizenId(src) then
        FW.Logout(src)
        Wait(200)
    end

    if FW.name == 'qbx' then
        -- IMPORTANT: log in through the qb-core BRIDGE (core.Player.Login), not
        -- exports.qbx_core:Login. The bridge fires 'QBCore:Client:OnPlayerLoaded',
        -- which is the event illenium-appearance (QB path) listens for to auto-load
        -- the saved skin. qbx_core:Login does not, so the appearance never loads.
        -- Requires the qbx bridge: setr qbx:enablebridge true
        local ok, success = pcall(function()
            local core = exports['qb-core']:GetCoreObject()
            return core.Player.Login(src, citizenid) and true or false
        end)
        if ok then return success == true, nil end
        -- bridge unavailable: fall back to native qbx login
        local ok2, reason = exports.qbx_core:Login(src, citizenid)
        return ok2 == true, reason
    elseif FW.name == 'qb' then
        if not FW.core then return false, 'core missing' end
        local ok = FW.core.Player.Login(src, citizenid)
        return ok == true, nil
    end
    return false, 'no framework'
end

-- Create a NEW character then log into it.
---@return boolean ok, string? err
function FW.CreateAndLogin(src, data, cid)
    local charinfo = buildCharInfo(data)

    if FW.name == 'qbx' then
        local newData = {
            charinfo = charinfo,
            money = { cash = Config.Creation.startingMoney.cash, bank = Config.Creation.startingMoney.bank },
        }
        local ok, reason = exports.qbx_core:Login(src, nil, newData)
        return ok == true, reason

    elseif FW.name == 'qb' then
        if not FW.core then return false, 'core missing' end
        -- qb-core creates on Login when passed a newData table and citizenid=false.
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
