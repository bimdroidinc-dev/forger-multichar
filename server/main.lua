local DB = Config.DB

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
        local gang = safeDecode(row.gang)
        local meta = safeDecode(row.metadata)

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
            jobName = job.name or nil,
            gangName = (type(gang) == 'table' and gang.name) or nil,
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

-- Last-position protection. After FW.Login the player is LOGGED IN while their
-- hidden ped is still parked at showcase / spawn-preview coords, so any framework
-- save in that window writes those coords as the last position. We stash the real
-- one at select time, write the true spawn position once the client confirms
-- placement, and restore the stash if the player drops before ever spawning.
local pendingPlace = {}

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
        local P = Config.PostLogin or {}
        if not FW.WaitForLoaded(src, P.loadTimeoutMs or 10000) then
            print(('^3[forger-multicharacter] %s (%s): the core never fired its PlayerLoaded event within %dms. Continuing anyway - check that qbx_core/qb-core is healthy.^0')
                :format(GetPlayerName(src) or ('src ' .. src), tostring(citizenid), P.loadTimeoutMs or 10000))
        end

        FW.RefreshCommands(src)
        TriggerEvent('forger:server:characterSelected', src)

        local A = Config.Appearance
        local coords, gender, appearance
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

RegisterNetEvent('forger:server:spawnPlaced', function(pos)
    local src = source
    local p = pendingPlace[src]
    if not p then return end
    pendingPlace[src] = nil
    if type(pos) ~= 'table' then return end
    local x, y, z = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z)
    if not (x and y and z) then return end
    if x < -8000.0 or x > 8000.0 or y < -8000.0 or y > 9000.0 or z < -300.0 or z > 2000.0 then return end
    writePosition(p.citizenid, { x = x, y = y, z = z, w = tonumber(pos.w) or 0.0 })
end)

RegisterNetEvent('forger:server:playerSpawned', function()
    local src = source
    local P = Config.PostLogin or {}

    local player = FW.GetPlayer(src)
    if not (player and player.PlayerData and player.PlayerData.citizenid) then return end

    FW.RefreshCommands(src)

    if P.resetRoutingBucket ~= false then
        pcall(function()
            if GetPlayerRoutingBucket(tostring(src)) ~= 0 then
                SetPlayerRoutingBucket(src, 0)
            end
        end)
    end

    TriggerEvent('forger:server:playerLoaded', src, player.PlayerData.citizenid)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local p = pendingPlace[src]
    if not p then return end
    pendingPlace[src] = nil
    if not (p.coords and p.coords.x) then return end
    SetTimeout(2500, function()
        writePosition(p.citizenid, p.coords)
    end)
end)

RegisterNetEvent('forger:server:createCharacter', function(data)
    local src = source
    local license = getLicenses(src)
    if type(data) ~= 'table' then return end

    if not nameAllowed(data.firstname) or not nameAllowed(data.lastname) then
        return TriggerClientEvent('forger:client:actionResult', src, {
            action = 'create', ok = false, err = Locales['en']['err_invalid_name'],
        })
    end

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
        if ok then
            local P = Config.PostLogin or {}
            if not FW.WaitForLoaded(src, P.loadTimeoutMs or 10000) then
                print(('^3[forger-multicharacter] %s: the core never fired its PlayerLoaded event for the new character within %dms. Continuing anyway.^0')
                    :format(GetPlayerName(src) or ('src ' .. src), P.loadTimeoutMs or 10000))
            end
            FW.RefreshCommands(src)
            if StarterItems then StarterItems.give(src) end
            TriggerEvent('forger:server:characterSelected', src)
        end
        TriggerClientEvent('forger:client:actionResult', src, {
            action = 'create', ok = ok, gender = payload.gender,
            err = ok and nil or (err or Locales['en']['err_generic']),
        })
    end)
end)

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

    MySQL.query.await(('DELETE FROM %s WHERE %s = ?'):format(DB.table, DB.columnCitizenId), { citizenid })

    local cleanup = {
        'DELETE FROM player_vehicles WHERE citizenid = ?',
        'DELETE FROM player_houses WHERE citizenid = ?',
        'DELETE FROM playerskins WHERE citizenid = ?',
        'DELETE FROM bank_accounts_new WHERE id = ?',
    }
    for _, q in ipairs(cleanup) do
        pcall(function() MySQL.query.await(q, { citizenid }) end)
    end

    TriggerEvent('forger:server:characterDeleted', src, citizenid)

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

if Config.Logout and Config.Logout.enabled ~= false then
    local L = Config.Logout
    local lastLogout = {}

    RegisterCommand(L.command or 'logout', function(src)
        if src == 0 then
            print('[forger-multicharacter] /logout must be run by a player, not the console.')
            return
        end

        if L.restricted and not IsPlayerAceAllowed(src, L.ace or 'forger.logout') then
            TriggerClientEvent('forger:client:actionResult', src, {
                action = 'logout', ok = false, reason = 'no_permission',
            })
            return
        end

        local cd = tonumber(L.cooldown) or 0
        if cd > 0 then
            local now = GetGameTimer()
            local last = lastLogout[src]
            if last and (now - last) < (cd * 1000) then return end
            lastLogout[src] = now
        end

        FW.Logout(src)
        Wait(300)
        TriggerClientEvent('forger:client:open', src)
    end, false)

    AddEventHandler('playerDropped', function()
        lastLogout[source] = nil
    end)
end
