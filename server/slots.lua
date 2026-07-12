-- Resolves how many character slots a given player is allowed.
-- default -> identifier overrides -> ace overrides -> discord role overrides,
-- combined with Config.Slots.resolution and clamped to absoluteMax.

Slots = {}

local function combine(current, candidate)
    if Config.Slots.resolution == 'sum' then
        return current + candidate
    end
    -- 'highest'
    if candidate > current then return candidate end
    return current
end

local function identifierOverride(src)
    local best = 0
    local ids = GetPlayerIdentifiers(src) or {}
    for _, id in ipairs(ids) do
        local grant = Config.Overrides.identifiers[id]
        if grant then best = combine(best, grant) end
    end
    return best
end

local function aceOverride(src)
    local best = 0
    for ace, grant in pairs(Config.Overrides.aces) do
        if IsPlayerAceAllowed(src, ace) then
            best = combine(best, grant)
        end
    end
    return best
end

local function discordOverride(roles)
    local best = 0
    for roleId, grant in pairs(Config.Overrides.discordRoles) do
        if roles[roleId] then
            best = combine(best, grant)
        end
    end
    return best
end

-- Async because Discord lookups are async. cb(number).
function Slots.resolve(src, cb)
    Discord.getRoles(src, function(roles)
        local allowed = Config.Slots.default

        allowed = combine(allowed, identifierOverride(src))
        allowed = combine(allowed, aceOverride(src))
        allowed = combine(allowed, discordOverride(roles))

        if allowed > Config.Slots.absoluteMax then
            allowed = Config.Slots.absoluteMax
        end
        if allowed < 1 then allowed = 1 end

        cb(allowed)
    end)
end
