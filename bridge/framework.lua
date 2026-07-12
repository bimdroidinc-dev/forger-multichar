-- ---------------------------------------------------------------------------
-- Server framework bridge  (QBCore / Qbox / ESX Legacy)
-- ---------------------------------------------------------------------------
-- This is the ONLY place that knows the differences between the supported
-- frameworks. server/main.lua talks to characters through the normalized API
-- below, so it never has to branch on the framework itself.
--
-- Supported:
--   qbx - Qbox        (qbx_core)          characters in `players` (JSON columns)
--   qb  - QBCore      (qb-core)           characters in `players` (JSON columns)
--   esx - ESX Legacy  (es_extended)       characters in `users`  (flat columns)
--
-- ESX note: character LOADING reuses ESX's own flow (esx:onPlayerJoined), which
-- requires `Config.Multichar = true` in es_extended.
-- ---------------------------------------------------------------------------

FW = { name = 'unknown', core = nil, esx = nil }

-- ---------------------------------------------------------------------------
-- detection
-- ---------------------------------------------------------------------------
local function detect()
    local forced = Config.Framework
    local hasQbx = GetResourceState('qbx_core') == 'started'
    local hasQb = GetResourceState('qb-core') == 'started'
    local hasEsx = GetResourceState('es_extended') == 'started'

    if forced == 'qbx' or (forced == 'auto' and hasQbx) then
        FW.name = 'qbx'
    elseif forced == 'qb' or (forced == 'auto' and hasQb) then
        FW.name = 'qb'
        FW.core = exports['qb-core']:GetCoreObject()
    elseif forced == 'esx' or (forced == 'auto' and hasEsx) then
        FW.name = 'esx'
        local ok, esx = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok then FW.esx = esx end
        if not FW.esx then
            print('^1[forger-multicharacter] es_extended detected but getSharedObject() failed.^0')
        end
    else
        FW.name = 'unknown'
        print('^1[forger-multicharacter] No supported framework detected (qbx_core / qb-core / es_extended).^0')
    end
    print(('^2[forger-multicharacter]^0 framework resolved to: %s'):format(FW.name))
end

CreateThread(function()
    Wait(500) -- give cores a moment to start
    detect()
end)

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function decode(str)
    if type(str) == 'table' then return str end
    if type(str) ~= 'string' then return {} end
    local ok, res = pcall(json.decode, str)
    if ok and type(res) == 'table' then return res end
    return {}
end

-- Every license-style identifier the player carries.
function FW.GetLicenses(src)
    local out = {}
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 7) == 'license' then out[#out + 1] = id end
    end
    return out
end

function FW.PrimaryLicense(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 9) == 'license2:' then return id end
    end
    return nil
end

-- ESX base identifier (what es_extended prepends the char prefix to).
local function esxBaseId(src)
    if FW.esx and FW.esx.GetIdentifier then
        local ok, id = pcall(function() return FW.esx.GetIdentifier(src) end)
        if ok and id then return id end
    end
    return FW.PrimaryLicense(src)
end

local function minutesToLabel(mins)
    mins = tonumber(mins) or 0
    if mins <= 0 then return '0m' end
    local h = math.floor(mins / 60)
    local m = mins % 60
    if h > 0 then return ('%dh %dm'):format(h, m) end
    return ('%dm'):format(m)
end

-- ---------------------------------------------------------------------------
-- appearance read (framework/clothing agnostic)
-- ---------------------------------------------------------------------------
-- charId  = citizenid (qb/qbx) or identifier (esx)
-- inline  = the raw skin value already on the character row (esx users.skin) or
--           nil; used when Config.Appearance.read.source == 'inline'.
local function readAppearance(charId, inline)
    local A = Config.Appearance or {}
    local R = A.read or {}
    if R.source == 'none' or not R.source then return nil end

    if R.source == 'inline' then
        if inline == nil or inline == '' then return nil end
        local dec = decode(inline)
        if next(dec) ~= nil then return dec end
        return nil
    end

    -- source == 'table'
    if not R.table then return nil end
    local q = ('SELECT %s FROM %s WHERE %s = ?'):format(R.column, R.table, R.idColumn)
    local args = { charId }
    if R.activeColumn then
        q = q .. (' AND %s = ?'):format(R.activeColumn)
        args[#args + 1] = 1
    end
    local ok, row = pcall(function() return MySQL.single.await(q, args) end)
    if ok and row and row[R.column] then
        local dec = decode(row[R.column])
        if next(dec) ~= nil then return dec end
    end
    return nil
end

-- ===========================================================================
-- QB / Qbox data layer (players table, JSON columns)
-- ===========================================================================
local function qbFetch(src)
    local DB = Config.DB
    local licenses = FW.GetLicenses(src)
    if #licenses == 0 then return {} end

    local placeholders = {}
    for i = 1, #licenses do placeholders[i] = '?' end
    local rows = MySQL.query.await(
        ('SELECT * FROM %s WHERE %s IN (%s)'):format(DB.table, DB.columnLicense, table.concat(placeholders, ', ')),
        licenses) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local charinfo = decode(row[DB.columnCharInfo])
        local money = decode(row[DB.columnMoney])
        local job = decode(row[DB.columnJob])
        local meta = decode(row.metadata)
        local cid = row[DB.columnCitizenId]

        out[#out + 1] = {
            id = cid,
            firstname = charinfo.firstname or 'Unknown',
            lastname = charinfo.lastname or '',
            gender = (tonumber(charinfo.gender) == 1) and 1 or 0,
            nationality = charinfo.nationality or 'Unknown',
            birthdate = charinfo.birthdate or '',
            backstory = charinfo.backstory or '',
            jobLabel = (job.label) or (job.name) or 'Unemployed',
            jobGrade = (job.grade and (job.grade.name or job.grade.label)) or '',
            cash = math.floor(tonumber(money.cash) or 0),
            bank = math.floor(tonumber(money.bank) or 0),
            playtime = minutesToLabel(meta.playtime or meta.playTime or 0),
            appearance = readAppearance(cid, nil),
        }
    end
    return out
end

local function qbSpawnData(src, id)
    local DB = Config.DB
    local coords, gender
    local prow = MySQL.single.await(
        ('SELECT %s, %s FROM %s WHERE %s = ?'):format(DB.columnCharInfo, DB.columnPosition, DB.table, DB.columnCitizenId),
        { id })
    if prow then
        if prow[DB.columnPosition] then
            local okp, pos = pcall(json.decode, prow[DB.columnPosition])
            if okp and type(pos) == 'table' and (pos.x or pos[1]) then
                coords = { x = pos.x or pos[1], y = pos.y or pos[2], z = pos.z or pos[3], w = pos.w or pos.h or pos[4] or 0.0 }
            end
        end
        if prow[DB.columnCharInfo] then
            local okc, ci = pcall(json.decode, prow[DB.columnCharInfo])
            if okc and type(ci) == 'table' and (ci.gender == 1 or ci.gender == '1') then gender = 1 end
        end
    end
    return { coords = coords, gender = gender or 0, appearance = readAppearance(id, nil) }
end

local function qbOwns(src, id)
    local DB = Config.DB
    local licenses = FW.GetLicenses(src)
    if #licenses == 0 or not id then return false end
    local placeholders, params = {}, {}
    for i = 1, #licenses do placeholders[i] = '?'; params[i] = licenses[i] end
    params[#params + 1] = id
    local row = MySQL.single.await(
        ('SELECT %s FROM %s WHERE %s IN (%s) AND %s = ?'):format(
            DB.columnCitizenId, DB.table, DB.columnLicense, table.concat(placeholders, ', '), DB.columnCitizenId),
        params)
    return row ~= nil
end

local function qbCurrentId(src)
    if FW.name == 'qbx' then
        local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        if ok and p and p.PlayerData then return p.PlayerData.citizenid end
    elseif FW.name == 'qb' and FW.core then
        local p = FW.core.Functions.GetPlayer(src)
        if p and p.PlayerData then return p.PlayerData.citizenid end
    end
    return nil
end

local function qbLogout(src)
    if FW.name == 'qbx' then
        pcall(function() exports.qbx_core:Logout(src) end)
    elseif FW.name == 'qb' and FW.core then
        pcall(function() FW.core.Player.Logout(src) end)
    end
end

local function qbLogin(src, id)
    if qbCurrentId(src) == id then return true, nil end
    if qbCurrentId(src) then qbLogout(src); Wait(200) end

    if FW.name == 'qbx' then
        -- Log in through the qb-core BRIDGE so 'QBCore:Client:OnPlayerLoaded'
        -- fires (some clothing resources listen for it). Requires the qbx bridge:
        -- setr qbx:enablebridge true
        local ok, success = pcall(function()
            local core = exports['qb-core']:GetCoreObject()
            return core.Player.Login(src, id) and true or false
        end)
        if ok then return success == true, nil end
        local ok2, reason = exports.qbx_core:Login(src, id)
        return ok2 == true, reason
    elseif FW.name == 'qb' then
        if not FW.core then return false, 'core missing' end
        local ok = FW.core.Player.Login(src, id)
        return ok == true, nil
    end
    return false, 'no framework'
end

local function qbCreate(src, data, slot)
    local charinfo = {
        firstname = data.firstname, lastname = data.lastname,
        birthdate = data.birthdate, gender = data.gender,
        nationality = data.nationality, backstory = data.backstory,
        phone = nil, account = nil,
    }
    if FW.name == 'qbx' then
        local ok, reason = exports.qbx_core:Login(src, nil, {
            charinfo = charinfo,
            money = { cash = Config.Creation.startingMoney.cash, bank = Config.Creation.startingMoney.bank },
        })
        return ok == true, reason, data.gender
    elseif FW.name == 'qb' then
        if not FW.core then return false, 'core missing', data.gender end
        local ok = FW.core.Player.Login(src, false, {
            cid = slot,
            charinfo = charinfo,
            money = { cash = Config.Creation.startingMoney.cash, bank = Config.Creation.startingMoney.bank, crypto = 0 },
        })
        return ok == true, nil, data.gender
    end
    return false, 'no framework', data.gender
end

local function qbDelete(id)
    local DB = Config.DB
    MySQL.query.await(('DELETE FROM %s WHERE %s = ?'):format(DB.table, DB.columnCitizenId), { id })
end

-- ===========================================================================
-- ESX data layer (users table, flat columns; esx_multicharacter identifiers)
-- ===========================================================================
local function esxSexToGender(sex)
    if sex == 1 or sex == '1' or sex == 'f' or sex == 'F' then return 1 end
    return 0
end
local function esxGenderToSex(gender) return (tonumber(gender) == 1) and 'f' or 'm' end

-- Pull cash + bank out of the ESX accounts JSON (object or array forms).
local function esxAccounts(raw)
    local acc = decode(raw)
    local cash, bank = 0, 0
    if acc.money ~= nil or acc.bank ~= nil then
        cash = tonumber(acc.money) or 0
        bank = tonumber(acc.bank) or 0
    else
        for _, a in ipairs(acc) do
            if a.name == 'money' then cash = tonumber(a.money) or cash
            elseif a.name == 'bank' then bank = tonumber(a.money) or bank end
        end
    end
    return math.floor(cash), math.floor(bank)
end

local function esxSlotOf(identifier, base)
    -- identifier is like 'char3:license:xxxx'; return the numeric slot.
    local n = identifier:match('^' .. (Config.ESX.prefix or 'char') .. '(%d+):')
    return tonumber(n)
end

local function esxFetch(src)
    local E = Config.ESX
    local base = esxBaseId(src)
    if not base then return {} end

    local rows = MySQL.query.await(
        ('SELECT * FROM %s WHERE %s LIKE ?'):format(E.table, E.columnIdentifier),
        { (E.prefix or 'char') .. '%:' .. base }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local identifier = row[E.columnIdentifier]
        local cash, bank = esxAccounts(row[E.columnAccounts])
        local meta = decode(row[E.columnMetadata])
        out[#out + 1] = {
            id = identifier,
            slot = esxSlotOf(identifier, base),
            firstname = row[E.columnFirstname] or 'Unknown',
            lastname = row[E.columnLastname] or '',
            gender = esxSexToGender(row[E.columnSex]),
            nationality = 'Unknown',
            birthdate = tostring(row[E.columnDob] or ''),
            backstory = '',
            jobLabel = row[E.columnJob] or 'unemployed',
            jobGrade = tostring(row[E.columnJobGrade] or ''),
            cash = cash, bank = bank,
            playtime = minutesToLabel(meta.playtime or meta.playTime or 0),
            appearance = readAppearance(identifier, row[E.columnSkin]),
        }
    end
    table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return out
end

local function esxSpawnData(src, id)
    local E = Config.ESX
    local coords, gender, skin
    local row = MySQL.single.await(
        ('SELECT %s, %s, %s FROM %s WHERE %s = ?'):format(E.columnPosition, E.columnSex, E.columnSkin, E.table, E.columnIdentifier),
        { id })
    if row then
        gender = esxSexToGender(row[E.columnSex])
        skin = row[E.columnSkin]
        if row[E.columnPosition] then
            local okp, pos = pcall(json.decode, row[E.columnPosition])
            if okp and type(pos) == 'table' and (pos.x or pos[1]) then
                coords = { x = pos.x or pos[1], y = pos.y or pos[2], z = pos.z or pos[3], w = pos.w or pos.heading or pos[4] or 0.0 }
            end
        end
    end
    return { coords = coords, gender = gender or 0, appearance = readAppearance(id, skin) }
end

local function esxOwns(src, id)
    local base = esxBaseId(src)
    if not base or type(id) ~= 'string' then return false end
    -- id must be one of this player's own char identifiers
    return id:sub(-#base) == base and id:sub(1, #(Config.ESX.prefix or 'char')) == (Config.ESX.prefix or 'char')
end

local function esxCurrentId(src)
    if FW.esx then
        local ok, xp = pcall(function() return FW.esx.GetPlayerFromId(src) end)
        if ok and xp and xp.identifier then return xp.identifier end
    end
    return nil
end

local function esxLogout(src)
    -- Vanilla es_extended has no public "unload the current character but stay
    -- connected" call (esx_multicharacter does its relog through internal calls).
    -- We save the loaded xPlayer so their position/data is persisted, then clear
    -- them from ESX.Players so a subsequent esx:onPlayerJoined can load another
    -- character. If your es_extended fork exposes a cleaner logout/relog, call it
    -- here instead.
    if not FW.esx then return end
    pcall(function()
        local xp = FW.esx.GetPlayerFromId and FW.esx.GetPlayerFromId(src)
        if xp then
            if xp.save then xp.save() end
            if FW.esx.Players then FW.esx.Players[src] = nil end
        end
    end)
end

local function esxLogin(src, id)
    -- id is the full users.identifier ('char3:license:xxx'); ESX rebuilds it as
    -- prefix..slot + ':' + GetIdentifier(src), so we pass just prefix..slot.
    if esxCurrentId(src) == id then return true, nil end
    -- switching from a different loaded character: unload it first
    if esxCurrentId(src) then esxLogout(src); Wait(200) end

    local slot = id:match('^(' .. (Config.ESX.prefix or 'char') .. '%d+):')
    if not slot then return false, 'bad identifier' end
    -- esx:onPlayerJoined(src, 'charN') -> loads users where identifier = 'charN:'..base
    TriggerEvent('esx:onPlayerJoined', src, slot)
    return true, nil
end

local function esxCreate(src, data, slot)
    local E = Config.ESX
    local base = esxBaseId(src)
    if not base then return false, 'no identifier', data.gender end
    local charTag = (E.prefix or 'char') .. slot

    -- Hand off to ESX's create flow with the identity payload it expects. ESX
    -- (with Config.Multichar = true) inserts the new users row for this
    -- character identifier and loads it.
    local sex = esxGenderToSex(data.gender)
    TriggerEvent('esx:onPlayerJoined', src, charTag, {
        firstname = data.firstname,
        lastname = data.lastname,
        dateofbirth = data.birthdate,
        sex = sex,
        height = 180,
    })
    return true, nil, data.gender
end

local function esxDelete(id)
    local E = Config.ESX
    MySQL.query.await(('DELETE FROM %s WHERE %s = ?'):format(E.table, E.columnIdentifier), { id })
end

-- ===========================================================================
-- Normalized public API  (server/main.lua uses only these)
-- ===========================================================================
function FW.FetchCharacters(src)
    if FW.name == 'esx' then return esxFetch(src) end
    return qbFetch(src)
end

function FW.GetSpawnData(src, id)
    if FW.name == 'esx' then return esxSpawnData(src, id) end
    return qbSpawnData(src, id)
end

function FW.OwnsCharacter(src, id)
    if FW.name == 'esx' then return esxOwns(src, id) end
    return qbOwns(src, id)
end

function FW.Login(src, id)
    if FW.name == 'esx' then return esxLogin(src, id) end
    return qbLogin(src, id)
end

-- Create a new character then log into it. slot = next free slot (1-based).
function FW.Create(src, data, slot)
    if FW.name == 'esx' then return esxCreate(src, data, slot) end
    return qbCreate(src, data, slot)
end

function FW.Logout(src)
    if FW.name == 'esx' then return esxLogout(src) end
    return qbLogout(src)
end

function FW.DeleteCharacter(id)
    if FW.name == 'esx' then return esxDelete(id) end
    return qbDelete(id)
end

-- Hard ceiling the framework itself enforces on slots (used with Config.Slots).
function FW.FrameworkSlotCeiling()
    if FW.name == 'esx' then return Config.ESX.maxSlots or 4 end
    return nil
end
