-- Server core: lists, creates, deletes and selects characters.
-- All destructive / selecting actions verify the character belongs to the
-- requesting player's license before doing anything.

local DB = Config.DB

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function getLicense(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'license:' then
            return id
        end
    end
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 9) == 'license2:' then
            return id
        end
    end
    return nil
end

-- Every license-style identifier the player carries. Servers store either
-- 'license:...' or 'license2:...' in the players table depending on setup, so we
-- match against all of them to be safe.
local function getLicenses(src)
    local out = {}
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 7) == 'license' then out[#out + 1] = id end
    end
    return out
end

local function safeDecode(str)
    if type(str) ~= 'string' then return str or {} end
    local ok, res = pcall(json.decode, str)
    if ok and type(res) == 'table' then return res end
    return {}
end

local function minutesToLabel(mins)
    mins = tonumber(mins) or 0
    if mins <= 0 then return '0m' end
    local h = math.floor(mins / 60)
    local m = mins % 60
    if h > 0 then return ('%dh %dm'):format(h, m) end
    return ('%dm'):format(m)
end

local function nameAllowed(name)
    if type(name) ~= 'string' then return false end
    local len = #name
    if len < Config.Creation.minNameLength or len > Config.Creation.maxNameLength then
        return false
    end
    local pattern = Config.Creation.allowNumbersInName and "^[%w%s'%-]+$" or "^[%a%s'%-]+$"
    return name:match(pattern) ~= nil
end

-- ---------------------------------------------------------------------------
-- read
-- ---------------------------------------------------------------------------
local function fetchCharacters(licenses)
    if type(licenses) == 'string' then licenses = { licenses } end
    if not licenses or #licenses == 0 then return {} end

    local placeholders = {}
    for i = 1, #licenses do placeholders[i] = '?' end
    local rows = MySQL.query.await(
        ('SELECT * FROM %s WHERE %s IN (%s)'):format(
            DB.table, DB.columnLicense, table.concat(placeholders, ', ')),
        licenses
    ) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local charinfo = safeDecode(row[DB.columnCharInfo])
        local money = safeDecode(row[DB.columnMoney])
        local job = safeDecode(row[DB.columnJob])
        local meta = safeDecode(row.metadata)

        -- saved appearance (active skin) so the selection preview shows the
        -- character's real clothing/face, not a default ped
        local appearance
        local A = Config.Appearance
        if A and A.skinTable then
            local q = ('SELECT %s FROM %s WHERE %s = ?'):format(A.skinColumn, A.skinTable, A.skinIdColumn)
            local args = { row[DB.columnCitizenId] }
            if A.skinActiveColumn then
                q = q .. (' AND %s = ?'):format(A.skinActiveColumn)
                args[#args + 1] = 1
            end
            local oks, srow = pcall(function() return MySQL.single.await(q, args) end)
            if oks and srow and srow[A.skinColumn] then
                local okd, dec = pcall(json.decode, srow[A.skinColumn])
                if okd and type(dec) == 'table' then appearance = dec end
            end
        end

        out[#out + 1] = {
            citizenid = row[DB.columnCitizenId],
            firstname = charinfo.firstname or 'Unknown',
            lastname = charinfo.lastname or '',
            gender = tonumber(charinfo.gender) or 0,
            nationality = charinfo.nationality or 'Unknown',
            birthdate = charinfo.birthdate or '',
            backstory = charinfo.backstory or '',
            job = {
                label = (job.label) or (job.name) or 'Unemployed',
                grade = (job.grade and (job.grade.name or job.grade.label)) or '',
            },
            cash = math.floor(tonumber(money.cash) or 0),
            bank = math.floor(tonumber(money.bank) or 0),
            playtime = minutesToLabel(meta.playtime or meta.playTime or 0),
            appearance = appearance,
            scene = (SceneMaker and SceneMaker.getForCitizen) and SceneMaker.getForCitizen(row[DB.columnCitizenId]) or nil,
        }
    end
    return out
end

local function ownsCharacter(licenses, citizenid)
    if type(licenses) == 'string' then licenses = { licenses } end
    if not licenses or #licenses == 0 or not citizenid then return false end
    local placeholders = {}
    local params = {}
    for i = 1, #licenses do placeholders[i] = '?'; params[i] = licenses[i] end
    params[#params + 1] = citizenid
    local row = MySQL.single.await(
        ('SELECT %s FROM %s WHERE %s IN (%s) AND %s = ?'):format(
            DB.columnCitizenId, DB.table, DB.columnLicense,
            table.concat(placeholders, ', '), DB.columnCitizenId),
        params
    )
    return row ~= nil
end

-- ---------------------------------------------------------------------------
-- net: request character list + slot allowance
-- ---------------------------------------------------------------------------
RegisterNetEvent('forger:server:requestCharacters', function()
    local src = source
    local licenses = getLicenses(src)
    local characters = fetchCharacters(licenses)

    if #characters == 0 then
        print(('^3[forger-multicharacter] 0 characters for %s. Matched against %s in `%s.%s`. If this player has characters, that column holds a different value.^0')
            :format(GetPlayerName(src) or ('src ' .. src), '{' .. table.concat(licenses, ', ') .. '}', Config.DB.table, Config.DB.columnLicense))
    end

    Slots.resolve(src, function(maxSlots)
        TriggerClientEvent('forger:client:setCharacters', src, {
            characters = characters,
            maxSlots = maxSlots,
            used = #characters,
            settings = Config.DefaultSettings,
            brand = Config.Brand,
            partnerEnabled = Config.Partner.enabled ~= false,
            weatherOptions = Config.WeatherOptions,
            nationalities = Config.Creation.nationalities,
            locations = (function()
                local l = {}
                for _, loc in ipairs(Config.Locations) do l[#l + 1] = loc.label end
                return l
            end)(),
        })
    end)
end)

-- ---------------------------------------------------------------------------
-- net: select (play) an existing character
-- ---------------------------------------------------------------------------
-- Last-position protection. After FW.Login the player is LOGGED IN while their
-- (hidden) real ped is still parked at showcase / spawn-preview coords. Any
-- framework save that fires in that window (periodic save, restart save, a
-- crash or quit at the spawn picker) writes those parked coords into the
-- position column - which is exactly the "last location spawned me at the
-- selector spot" bug. We stash the REAL last position at select time; when the
-- client confirms it has actually placed the player, we write the true spawn
-- position back (healing any poisoned save), and if the player drops before
-- ever spawning we restore the stashed original.
local pendingPlace = {}  -- src -> { citizenid = ..., coords = original DB coords or nil }

local function writePosition(citizenid, c)
    MySQL.update.await(
        ('UPDATE %s SET %s = ? WHERE %s = ?'):format(Config.DB.table, Config.DB.columnPosition, Config.DB.columnCitizenId),
        { json.encode({ x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0, w = (c.w or 0.0) + 0.0 }), citizenid })
end

RegisterNetEvent('forger:server:selectCharacter', function(citizenid)
    local src = source
    local license = getLicenses(src)

    if not ownsCharacter(license, citizenid) then
        return TriggerClientEvent('forger:client:actionResult', src, {
            action = 'select', ok = false, err = Locales['en']['err_not_your_char'],
        })
    end

    local ok, err = FW.Login(src, citizenid)
    if ok then
        TriggerEvent('forger:server:characterSelected', src)

        local A = Config.Appearance
        local coords, gender, appearance
        -- gender + last position from the players row
        local prow = MySQL.single.await(
            ('SELECT %s, %s FROM %s WHERE %s = ?'):format(Config.DB.columnCharInfo, Config.DB.columnPosition, Config.DB.table, Config.DB.columnCitizenId),
            { citizenid })
        if prow then
            if prow[Config.DB.columnPosition] then
                local okp, pos = pcall(json.decode, prow[Config.DB.columnPosition])
                if okp and type(pos) == 'table' and (pos.x or pos[1]) then
                    coords = { x = pos.x or pos[1], y = pos.y or pos[2], z = pos.z or pos[3], w = pos.w or pos.h or pos[4] or 0.0 }
                end
            end
            if prow[Config.DB.columnCharInfo] then
                local okc, ci = pcall(json.decode, prow[Config.DB.columnCharInfo])
                if okc and type(ci) == 'table' and (ci.gender == 1 or ci.gender == '1') then gender = 1 end
            end
        end
        -- saved appearance from the clothing/skin table (active skin only)
        if A.skinTable then
            local q = ('SELECT %s FROM %s WHERE %s = ?'):format(A.skinColumn, A.skinTable, A.skinIdColumn)
            local args = { citizenid }
            if A.skinActiveColumn then
                q = q .. (' AND %s = ?'):format(A.skinActiveColumn)
                args[#args + 1] = 1
            end
            local oks, srow = pcall(function()
                return MySQL.single.await(q, args)
            end)
            if oks and srow and srow[A.skinColumn] then
                local okd, dec = pcall(json.decode, srow[A.skinColumn])
                appearance = okd and dec or srow[A.skinColumn]
            end
        end

        pendingPlace[src] = { citizenid = citizenid, coords = coords }

        return TriggerClientEvent('forger:client:actionResult', src, {
            action = 'select', ok = true, coords = coords, gender = gender or 0, appearance = appearance,
        })
    end
    TriggerClientEvent('forger:client:actionResult', src, {
        action = 'select', ok = false, err = err or Locales['en']['err_generic'],
    })
end)

-- Client confirms the player has been physically placed at their spawn. Write
-- that position as the character's last position - this overwrites any parked
-- showcase/picker coords a framework save may have written in the meantime.
RegisterNetEvent('forger:server:spawnPlaced', function(pos)
    local src = source
    local p = pendingPlace[src]
    if not p then return end
    pendingPlace[src] = nil
    if type(pos) ~= 'table' then return end
    local x, y, z = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z)
    if not (x and y and z) then return end
    -- sanity clamp to the playable map so a bad client can't write junk
    if x < -8000.0 or x > 8000.0 or y < -8000.0 or y > 9000.0 or z < -300.0 or z > 2000.0 then return end
    writePosition(p.citizenid, { x = x, y = y, z = z, w = tonumber(pos.w) or 0.0 })
end)

-- Player dropped after logging in but BEFORE ever being placed in the world
-- (quit or crashed at the spawn picker). The framework's drop-save has just
-- written the parked showcase coords as their position; restore the true last
-- position we stashed at select time. Delayed so our write lands after the
-- framework's own drop-save.
AddEventHandler('playerDropped', function()
    local src = source
    local p = pendingPlace[src]
    if not p then return end
    pendingPlace[src] = nil
    if not (p.coords and p.coords.x) then return end  -- nothing to restore (new char)
    SetTimeout(2500, function()
        writePosition(p.citizenid, p.coords)
    end)
end)

-- ---------------------------------------------------------------------------
-- net: create a new character
-- ---------------------------------------------------------------------------
RegisterNetEvent('forger:server:createCharacter', function(data)
    local src = source
    local license = getLicenses(src)
    if type(data) ~= 'table' then return end

    -- validate names
    if not nameAllowed(data.firstname) or not nameAllowed(data.lastname) then
        return TriggerClientEvent('forger:client:actionResult', src, {
            action = 'create', ok = false, err = Locales['en']['err_invalid_name'],
        })
    end

    -- enforce slots (async because of Discord lookups)
    local existing = fetchCharacters(license)
    Slots.resolve(src, function(maxSlots)
        if #existing >= maxSlots then
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

        local ok, err = FW.CreateAndLogin(src, payload, #existing + 1)
        if ok then TriggerEvent('forger:server:characterSelected', src) end
        TriggerClientEvent('forger:client:actionResult', src, {
            action = 'create', ok = ok, gender = payload.gender,
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

    local license = getLicenses(src)
    if not ownsCharacter(license, citizenid) then
        return TriggerClientEvent('forger:client:actionResult', src, {
            action = 'delete', ok = false, err = Locales['en']['err_not_your_char'],
        })
    end

    -- Remove the main row. Extend this list with any per-character tables your
    -- server uses (owned vehicles, houses, inventory, etc.).
    MySQL.query.await(('DELETE FROM %s WHERE %s = ?'):format(DB.table, DB.columnCitizenId), { citizenid })

    -- Common owned-data cleanup, wrapped so a missing table never errors.
    local cleanup = {
        'DELETE FROM player_vehicles WHERE citizenid = ?',
        'DELETE FROM player_houses WHERE citizenid = ?',
        'DELETE FROM playerskins WHERE citizenid = ?',
        'DELETE FROM bank_accounts_new WHERE id = ?',
    }
    for _, q in ipairs(cleanup) do
        pcall(function() MySQL.query.await(q, { citizenid }) end)
    end

    -- Let other resources react (e.g. custom cleanup).
    TriggerEvent('forger:server:characterDeleted', src, citizenid)

    -- send back the fresh list
    local characters = fetchCharacters(license)
    Slots.resolve(src, function(maxSlots)
        TriggerClientEvent('forger:client:setCharacters', src, {
            characters = characters,
            maxSlots = maxSlots,
            used = #characters,
            settings = Config.DefaultSettings,
            brand = Config.Brand,
            partnerEnabled = Config.Partner.enabled ~= false,
            weatherOptions = Config.WeatherOptions,
            nationalities = Config.Creation.nationalities,
            locations = (function()
                local l = {}
                for _, loc in ipairs(Config.Locations) do l[#l + 1] = loc.label end
                return l
            end)(),
        })
        TriggerClientEvent('forger:client:actionResult', src, {
            action = 'delete', ok = true,
        })
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
