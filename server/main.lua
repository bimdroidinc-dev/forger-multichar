-- ---------------------------------------------------------------------------
-- Server core: lists, creates, deletes and selects characters.
-- ---------------------------------------------------------------------------
-- Framework-agnostic: all reads/writes/logins go through the FW.* API in
-- bridge/framework.lua, which handles the QBCore / Qbox / ESX differences. Every
-- destructive / selecting action verifies the character belongs to the
-- requesting player before doing anything.

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function nameAllowed(name)
    if type(name) ~= 'string' then return false end
    local len = #name
    if len < Config.Creation.minNameLength or len > Config.Creation.maxNameLength then
        return false
    end
    local pattern = Config.Creation.allowNumbersInName and "^[%w%s'%-]+$" or "^[%a%s'%-]+$"
    return name:match(pattern) ~= nil
end

-- Shape a normalized character (from FW.FetchCharacters) into the payload the
-- NUI expects.
local function toClient(c)
    return {
        citizenid = c.id,
        firstname = c.firstname or 'Unknown',
        lastname = c.lastname or '',
        gender = c.gender or 0,
        nationality = c.nationality or 'Unknown',
        birthdate = c.birthdate or '',
        backstory = c.backstory or '',
        job = { label = c.jobLabel or 'Unemployed', grade = c.jobGrade or '' },
        cash = c.cash or 0,
        bank = c.bank or 0,
        playtime = c.playtime or '0m',
        appearance = c.appearance,
    }
end

-- Slot ceiling the framework itself enforces (ESX), clamped over Config.Slots.
local function clampToFrameworkCeiling(maxSlots)
    local ceiling = FW.FrameworkSlotCeiling()
    if ceiling and maxSlots > ceiling then return ceiling end
    return maxSlots
end

-- Send the character list + slot allowance + UI config to a player.
local function sendCharacterList(src, extra)
    local raw = FW.FetchCharacters(src)
    local characters = {}
    for _, c in ipairs(raw) do characters[#characters + 1] = toClient(c) end

    if #characters == 0 then
        print(('^3[forger-multicharacter] 0 characters for %s. If this player has characters, check your framework/DB config.^0')
            :format(GetPlayerName(src) or ('src ' .. src)))
    end

    Slots.resolve(src, function(maxSlots)
        maxSlots = clampToFrameworkCeiling(maxSlots)
        local payload = {
            characters = characters,
            maxSlots = maxSlots,
            used = #characters,
            settings = Config.DefaultSettings,
            brand = Config.Brand,
            weatherOptions = Config.WeatherOptions,
            nationalities = Config.Creation.nationalities,
            locations = (function()
                local l = {}
                for _, loc in ipairs(Config.Locations) do l[#l + 1] = loc.label end
                return l
            end)(),
        }
        TriggerClientEvent('forger:client:setCharacters', src, payload)
        if extra then extra() end
    end)
end

-- Count a player's characters (for slot enforcement on create).
local function characterCount(src)
    return #FW.FetchCharacters(src)
end

-- ---------------------------------------------------------------------------
-- net: request character list + slot allowance
-- ---------------------------------------------------------------------------
RegisterNetEvent('forger:server:requestCharacters', function()
    sendCharacterList(source)
end)

-- ---------------------------------------------------------------------------
-- net: select (play) an existing character
-- ---------------------------------------------------------------------------
RegisterNetEvent('forger:server:selectCharacter', function(citizenid)
    local src = source

    if not FW.OwnsCharacter(src, citizenid) then
        return TriggerClientEvent('forger:client:actionResult', src, {
            action = 'select', ok = false, err = Locales['en']['err_not_your_char'],
        })
    end

    local ok, err = FW.Login(src, citizenid)
    if ok then
        TriggerEvent('forger:server:characterSelected', src)
        local data = FW.GetSpawnData(src, citizenid)
        return TriggerClientEvent('forger:client:actionResult', src, {
            action = 'select', ok = true,
            coords = data.coords, gender = data.gender or 0, appearance = data.appearance,
        })
    end
    TriggerClientEvent('forger:client:actionResult', src, {
        action = 'select', ok = false, err = err or Locales['en']['err_generic'],
    })
end)

-- ---------------------------------------------------------------------------
-- net: create a new character
-- ---------------------------------------------------------------------------
RegisterNetEvent('forger:server:createCharacter', function(data)
    local src = source
    if type(data) ~= 'table' then return end

    if not nameAllowed(data.firstname) or not nameAllowed(data.lastname) then
        return TriggerClientEvent('forger:client:actionResult', src, {
            action = 'create', ok = false, err = Locales['en']['err_invalid_name'],
        })
    end

    local used = characterCount(src)
    Slots.resolve(src, function(maxSlots)
        maxSlots = clampToFrameworkCeiling(maxSlots)
        if used >= maxSlots then
            return TriggerClientEvent('forger:client:actionResult', src, {
                action = 'create', ok = false, err = Locales['en']['err_slots_full'],
            })
        end

        local payload = {
            firstname = data.firstname,
            lastname = data.lastname,
            birthdate = tostring(data.birthdate or '2000-01-01'),
            gender = tonumber(data.gender) == 1 and 1 or 0,
            nationality = tostring(data.nationality or 'Unknown'),
            backstory = type(data.backstory) == 'string' and data.backstory:sub(1, 300) or '',
        }

        local ok, err, gender = FW.Create(src, payload, used + 1)
        if ok then TriggerEvent('forger:server:characterSelected', src) end
        TriggerClientEvent('forger:client:actionResult', src, {
            action = 'create', ok = ok, gender = gender or payload.gender,
            err = ok and nil or (err or Locales['en']['err_generic']),
        })
    end)
end)

-- ---------------------------------------------------------------------------
-- net: delete a character
-- ---------------------------------------------------------------------------
RegisterNetEvent('forger:server:deleteCharacter', function(citizenid)
    local src = source

    if not Config.Deletion.enabled then
        return TriggerClientEvent('forger:client:actionResult', src, {
            action = 'delete', ok = false, err = Locales['en']['err_delete_disabled'],
        })
    end

    if not FW.OwnsCharacter(src, citizenid) then
        return TriggerClientEvent('forger:client:actionResult', src, {
            action = 'delete', ok = false, err = Locales['en']['err_not_your_char'],
        })
    end

    -- Remove the character's main row (framework-aware).
    FW.DeleteCharacter(citizenid)

    -- Common owned-data cleanup, wrapped so a missing table never errors. Extend
    -- this with any per-character tables your server uses. The key column is the
    -- character id (citizenid on QB/Qbox, identifier on ESX).
    local cleanup = {
        'DELETE FROM player_vehicles WHERE citizenid = ?',
        'DELETE FROM player_houses WHERE citizenid = ?',
        'DELETE FROM playerskins WHERE citizenid = ?',
        'DELETE FROM owned_vehicles WHERE owner = ?',       -- ESX
        'DELETE FROM user_licenses WHERE owner = ?',        -- ESX
    }
    for _, q in ipairs(cleanup) do
        pcall(function() MySQL.query.await(q, { citizenid }) end)
    end

    -- Let other resources react (e.g. custom cleanup).
    TriggerEvent('forger:server:characterDeleted', src, citizenid)

    -- send back the fresh list + confirm the delete
    sendCharacterList(src, function()
        TriggerClientEvent('forger:client:actionResult', src, { action = 'delete', ok = true })
    end)
end)

-- ---------------------------------------------------------------------------
-- /logout : log out of the current character and re-open the selector.
-- The framework's Logout saves the character's position + data first, so the
-- next login (and "Last Location") is correct. Same net effect as qbx_core's
-- built-in logout, which is what mil-multichar relies on.
-- ---------------------------------------------------------------------------
if Config.Logout and Config.Logout.enabled ~= false then
    local L = Config.Logout
    local lastLogout = {}  -- [src] = GetGameTimer() of last use (cooldown)

    RegisterCommand(L.command or 'logout', function(src)
        if src == 0 then
            print('[forger-multicharacter] /logout must be run by a player, not the console.')
            return
        end

        -- permission
        if L.restricted and not IsPlayerAceAllowed(src, L.ace or 'forger.logout') then
            TriggerClientEvent('forger:client:actionResult', src, {
                action = 'logout', ok = false, reason = 'no_permission',
            })
            return
        end

        -- cooldown
        local cd = tonumber(L.cooldown) or 0
        if cd > 0 then
            local now = GetGameTimer()
            local last = lastLogout[src]
            if last and (now - last) < (cd * 1000) then return end
            lastLogout[src] = now
        end

        -- Log the current character out (this saves their position + data), then
        -- re-open the selector. FW.Logout is a safe no-op if nothing is loaded, and
        -- openSelector() on the client guards against double-opening.
        FW.Logout(src)
        Wait(300)  -- Logout saves + unregisters (qbx waits ~200ms internally)
        TriggerClientEvent('forger:client:open', src)
    end, false)  -- restricted = false here; the ace check above is config-driven

    AddEventHandler('playerDropped', function()
        lastLogout[source] = nil
    end)
end
