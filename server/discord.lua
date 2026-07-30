Discord = {}

local cache = {}

local function getDiscordId(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'discord:' then
            return id:sub(9)
        end
    end
    return nil
end

function Discord.getRoles(src, cb)
    if not Config.Discord.enabled then return cb({}) end

    local guildId = Config.Discord.guildId
    local token = GetConvar(Config.Discord.tokenConvar, '')
    if guildId == '' or token == '' then
        print('^3[forger-multicharacter] Discord enabled but guildId or bot token is missing.^0')
        return cb({})
    end

    local discordId = getDiscordId(src)
    if not discordId then return cb({}) end

    local cached = cache[discordId]
    if cached and cached.expires > os.time() then
        return cb(cached.roles)
    end

    local url = ('https://discord.com/api/v10/guilds/%s/members/%s'):format(guildId, discordId)
    PerformHttpRequest(url, function(status, body)
        local roles = {}
        if status == 200 and body then
            local ok, data = pcall(json.decode, body)
            if ok and data and data.roles then
                for _, roleId in ipairs(data.roles) do
                    roles[roleId] = true
                end
            end
        elseif status == 429 then
            print('^3[forger-multicharacter] Discord API rate limited (429). Increase cacheSeconds.^0')
        elseif status ~= 404 then
            print(('^3[forger-multicharacter] Discord API returned status %s.^0'):format(tostring(status)))
        end
        cache[discordId] = { roles = roles, expires = os.time() + Config.Discord.cacheSeconds }
        cb(roles)
    end, 'GET', '', {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = 'Bot ' .. token,
    })
end
