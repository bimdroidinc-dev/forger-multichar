-- Emote menus animate the LOCAL PLAYER ped only, and this resource previews on a
-- separate ped. So an { animName = 'x' } emote is resolved via
-- Config.Emotes.aliases first, then the export if the target IS the player ped,
-- and otherwise falls back to a random Config.Emotes.list entry.
local EMOTE_RESOURCES = {
    { name = 'rpemotes-reborn',   export = 'EmoteCommandStart', cancel = 'EmoteCancel' },
    { name = 'rpemotes',          export = 'EmoteCommandStart', cancel = 'EmoteCancel' },
    { name = 'scully_emotemenu',  export = 'playEmoteByCommand', cancel = 'cancelEmote' },
}

local activeEmote = nil
local warned = {}

local function detectEmoteResource()
    local forced = (Config.Emotes and Config.Emotes.resource) or 'auto'
    if forced ~= 'auto' and forced ~= 'native' then
        for _, r in ipairs(EMOTE_RESOURCES) do
            if r.name == forced then return r end
        end
        return nil
    end
    if forced == 'native' then return nil end
    for _, r in ipairs(EMOTE_RESOURCES) do
        if GetResourceState(r.name) == 'started' then return r end
    end
    return nil
end

local emoteResource = nil
CreateThread(function()
    Wait(500)
    emoteResource = detectEmoteResource()
end)

function ForgerEmoteResourceName()
    return emoteResource and emoteResource.name or 'native'
end

local function emoteList()
    return (Config.Emotes and Config.Emotes.list) or {}
end

function ForgerRandomEmote()
    local list = emoteList()
    if #list == 0 then return nil end
    return list[math.random(#list)]
end

function ForgerEmoteForLocation(loc)
    if loc and type(loc.emote) == 'table' then return loc.emote end
    if Config.Emotes and Config.Emotes.randomOnLoad == false then
        local list = emoteList()
        return list[1]
    end
    return ForgerRandomEmote()
end

local function resolveNamed(name)
    local aliases = (Config.Emotes and Config.Emotes.aliases) or {}
    local a = aliases[name]
    if type(a) == 'table' then return a end
    return nil
end

function ForgerPlayEmote(ped, emote)
    if not ped or not DoesEntityExist(ped) then return nil end
    if type(emote) ~= 'table' then return nil end

    if emote.scenario then
        ClearPedTasksImmediately(ped)
        SetPedCanRagdoll(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, true)
        local c = GetEntityCoords(ped)
        local h = GetEntityHeading(ped)
        FreezeEntityPosition(ped, false)
        SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
        SetEntityHeading(ped, h)
        TaskStartScenarioInPlace(ped, emote.scenario, 0, true)
        SetPedKeepTask(ped, true)
        activeEmote = emote
        return emote
    end

    if emote.dict and emote.anim then
        RequestAnimDict(emote.dict)
        local dl = GetGameTimer() + 5000
        while not HasAnimDictLoaded(emote.dict) and GetGameTimer() < dl do Wait(0) end
        if not HasAnimDictLoaded(emote.dict) then
            if not warned[emote.dict] then
                warned[emote.dict] = true
                print(('^3[forger-multicharacter] anim dict "%s" never loaded (is it a base-game dict?).^0'):format(emote.dict))
            end
            return nil
        end
        ClearPedTasksImmediately(ped)
        local blend = Config.EmoteBlendIn or 1.5
        TaskPlayAnim(ped, emote.dict, emote.anim, blend, 4.0, -1, emote.flag or 1, 0, false, false, false)
        SetPedKeepTask(ped, true)
        activeEmote = emote
        return emote
    end

    if emote.animName then
        local alias = resolveNamed(emote.animName)
        if alias then
            return ForgerPlayEmote(ped, alias)
        end
        if ped == PlayerPedId() and emoteResource then
            local ok = pcall(function()
                local proxy = exports[emoteResource.name]
                proxy[emoteResource.export](proxy, emote.animName)
            end)
            if ok then
                activeEmote = emote
                return emote
            end
        elseif ped == PlayerPedId() then
            ExecuteCommand(('e %s'):format(emote.animName))
            activeEmote = emote
            return emote
        end
        if not warned[emote.animName] then
            warned[emote.animName] = true
            print(('^3[forger-multicharacter] emote "%s" has no Config.Emotes.aliases entry, so it cannot play on the preview ped. Falling back to a random emote. Add it to Config.Emotes.aliases as { dict = ..., anim = ... } to use it.^0')
                :format(tostring(emote.animName)))
        end
        local fallback = ForgerRandomEmote()
        if fallback and fallback ~= emote then
            return ForgerPlayEmote(ped, fallback)
        end
    end

    return nil
end

function ForgerCancelEmote(ped)
    if not ped or not DoesEntityExist(ped) then return end

    if ped == PlayerPedId() and emoteResource then
        pcall(function()
            local proxy = exports[emoteResource.name]
            proxy[emoteResource.cancel](proxy, true)
        end)
    end

    if IsPedUsingAnyScenario(ped) then
        SetPedShouldPlayImmediateScenarioExit(ped)
        ClearPedTasksImmediately(ped)
    else
        ClearPedTasks(ped)
    end
    activeEmote = nil
end

function ForgerIsPlayingEmote(ped, emote)
    if not (ped and DoesEntityExist(ped) and type(emote) == 'table') then return false end
    if emote.scenario then return IsPedUsingScenario(ped, emote.scenario) end
    if emote.dict and emote.anim then return IsEntityPlayingAnim(ped, emote.dict, emote.anim, 3) end
    return true
end

function ForgerActiveEmote() return activeEmote end
