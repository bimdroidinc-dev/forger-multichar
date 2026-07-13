-- Client side of the persistent partner system. Forwards NUI actions to the
-- server, relays server events to the NUI, and shows/hides the partner scene.

local pair = nil -- { mode, emoteIndex, selfRole, partnerGender, appearance }

local function emoteFor(mode, index)
    local list = Config.Partner.emotes[mode]
    if not list then return nil end
    return list[index]
end

local function otherRole(role)
    return role == 'a' and 'b' or 'a'
end

local function startScene()
    if not pair then return end
    local emote = emoteFor(pair.mode, pair.emoteIndex)
    if emote and ForgerStartPairScene then
        ForgerStartPairScene(emote, pair.selfRole, otherRole(pair.selfRole), pair.partnerGender, pair.appearance)
    end
end

-- ---------------------------------------------------------------------------
-- NUI -> server
-- ---------------------------------------------------------------------------
RegisterNUICallback('partnerSetChar', function(data, cb)
    TriggerServerEvent('forger:server:partnerSetChar', {
        citizenid = data.citizenid, name = data.name, gender = data.gender,
    })
    cb('ok')
end)

RegisterNUICallback('partnerSearch', function(data, cb)
    TriggerServerEvent('forger:server:partnerSearch', data.query or '')
    cb('ok')
end)

RegisterNUICallback('partnerInvite', function(data, cb)
    TriggerServerEvent('forger:server:partnerInvite', { targetId = data.targetId, mode = data.mode })
    cb('ok')
end)

RegisterNUICallback('partnerRespond', function(data, cb)
    TriggerServerEvent('forger:server:partnerRespond', { fromId = data.fromId, accept = data.accept })
    cb('ok')
end)

RegisterNUICallback('partnerCancel', function(data, cb)
    TriggerServerEvent('forger:server:partnerCancel', { targetId = data.targetId })
    cb('ok')
end)

RegisterNUICallback('partnerEmote', function(data, cb)
    if data.index then
        TriggerServerEvent('forger:server:partnerEmote', { index = tonumber(data.index) })
    else
        TriggerServerEvent('forger:server:partnerEmote', { delta = tonumber(data.delta) or 1 })
    end
    cb('ok')
end)

RegisterNUICallback('partnerUnpair', function(_, cb)
    TriggerServerEvent('forger:server:partnerUnpair')
    cb('ok')
end)

-- ---------------------------------------------------------------------------
-- server -> client
-- ---------------------------------------------------------------------------
RegisterNetEvent('forger:client:partnerYourId', function(data)
    SendNUIMessage({ action = 'partnerYourId', id = data.id })
end)

RegisterNetEvent('forger:client:partnerLists', function(data)
    SendNUIMessage({ action = 'partnerLists', incoming = data.incoming, sent = data.sent })
end)

RegisterNetEvent('forger:client:partnerSearchResults', function(data)
    SendNUIMessage({ action = 'partnerSearchResults', results = data.results })
end)

-- direct confirmation prompt (replaces the old passive notification)
RegisterNetEvent('forger:client:partnerPrompt', function(data)
    SendNUIMessage({ action = 'partnerPrompt', fromId = data.fromId, name = data.name, mode = data.mode })
end)

RegisterNetEvent('forger:client:partnerDeclined', function(data)
    SendNUIMessage({ action = 'partnerToast', text = (data.name or 'Player') .. ' declined your request.', kind = 'err' })
end)

RegisterNetEvent('forger:client:partnerMatched', function(data)
    SendNUIMessage({ action = 'partnerMatched', mode = data.mode })
end)

-- show / clone the partner for the current character
RegisterNetEvent('forger:client:partnerShow', function(data)
    pair = {
        mode = data.mode,
        emoteIndex = data.emoteIndex or 1,
        selfRole = data.selfRole or 'a',
        partnerGender = data.gender or 0,
        appearance = data.appearance,
    }
    startScene()
    local emote = emoteFor(pair.mode, pair.emoteIndex)
    SendNUIMessage({
        action = 'partnerActive',
        partner = { name = data.name },
        mode = pair.mode,
        emote = emote and emote.label or '',
        emoteIndex = pair.emoteIndex,
        emoteTotal = #(Config.Partner.emotes[pair.mode] or {}),
    })
end)

RegisterNetEvent('forger:client:partnerHide', function()
    pair = nil
    if ForgerStopPairScene then ForgerStopPairScene() end
    SendNUIMessage({ action = 'partnerInactive' })
end)

RegisterNetEvent('forger:client:partnerEmote', function(data)
    if not pair then return end
    pair.emoteIndex = data.emoteIndex or pair.emoteIndex
    pair.mode = data.mode or pair.mode
    startScene()
    local emote = emoteFor(pair.mode, pair.emoteIndex)
    SendNUIMessage({
        action = 'partnerEmoteChanged',
        emote = emote and emote.label or '',
        emoteIndex = pair.emoteIndex,
        emoteTotal = #(Config.Partner.emotes[pair.mode] or {}),
    })
end)

RegisterNetEvent('forger:client:partnerEnded', function(data)
    pair = nil
    if ForgerStopPairScene then ForgerStopPairScene() end
    SendNUIMessage({ action = 'partnerEnded', reason = data and data.reason })
end)
