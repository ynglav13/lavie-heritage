local activeAudio = {}
local nuiAudioReady = false

local function sendAudio(action, payload)
    payload = payload or {}
    payload.app = 'lv_musicbox'
    payload.action = action
    SendNUIMessage(payload)
end

local function getNetEntity(netId, kind)
    netId = tonumber(netId)
    if not netId or not NetworkDoesNetworkIdExist(netId) then
        return 0
    end

    if kind == 'vehicle' then
        return NetToVeh(netId)
    end
    return NetToObj(netId)
end

function LVMusic.GetSourceEntity(sourceData)
    if not sourceData then
        return 0

    end

    if sourceData.vehicleNetId then
        return getNetEntity(sourceData.vehicleNetId, 'vehicle')
    end

    if sourceData.netId then
        return getNetEntity(sourceData.netId, 'object')
    end
    return 0
end

function LVMusic.GetSourcePosition(sourceData)
    if not sourceData then
        return nil
    end

    if sourceData.holder then
        local player = GetPlayerFromServerId(sourceData.holder)

        if player ~= -1 then
            local ped = GetPlayerPed(player)

            if ped ~= 0 and DoesEntityExist(ped) then
                return GetEntityCoords(ped)
            end
        end
    end

    local entity = LVMusic.GetSourceEntity(sourceData)

    if entity ~= 0 and DoesEntityExist(entity) then
        return GetEntityCoords(entity)
    end
    return LVMusic.ToVec3(sourceData.coords)
end

local function getSourceInterior(sourceData, position)
    local entity = LVMusic.GetSourceEntity(sourceData)

    if entity ~= 0 and DoesEntityExist(entity) then
        return GetInteriorFromEntity(entity)
    end

    if position then
        return GetInteriorAtCoords(position.x, position.y, position.z)
    end
    return 0
end

local function applyMuffle(effect, strength, volumeMultiplier)
    effect.muffle = math.max(effect.muffle, strength or 0.0)
    effect.volumeMultiplier = effect.volumeMultiplier * (volumeMultiplier or 1.0)
end

local function getAudioEffect(sourceData, position)
    local effect =
    {
        muffle = 0.0,
        echo = 0.0,
        volumeMultiplier = 1.0
    }

    local ped = PlayerPedId()
    local listenerInterior = GetInteriorFromEntity(ped)
    local sourceInterior = getSourceInterior(sourceData, position)

    if sourceData.type == 'vehicle' and Config.Effects.vehicleMuffle.enabled then
        local sourceVehicle = LVMusic.GetSourceEntity(sourceData)
        local playerVehicle = GetVehiclePedIsIn(ped, false)

        if sourceVehicle == 0 or playerVehicle ~= sourceVehicle then
            applyMuffle(effect, Config.Effects.vehicleMuffle.strength, Config.Effects.vehicleMuffle.volumeMultiplier)
        end
    end

    if Config.Effects.interiorMuffle.enabled then
        local listenerInside = listenerInterior and listenerInterior ~= 0
        local sourceInside = sourceInterior and sourceInterior ~= 0

        if listenerInterior ~= sourceInterior and (listenerInside or sourceInside) then
            applyMuffle(effect, Config.Effects.interiorMuffle.strength, Config.Effects.interiorMuffle.volumeMultiplier)
        end
    end

    if Config.Effects.realisticEcho.enabled and listenerInterior ~= 0 and listenerInterior == sourceInterior then
        effect.echo = Config.Effects.realisticEcho.amount
    end

    effect.volumeMultiplier = LVMusic.Clamp(effect.volumeMultiplier, 0.0, 1.0)
    effect.muffle = LVMusic.Clamp(effect.muffle, 0.0, 1.0)
    effect.echo = LVMusic.Clamp(effect.echo, 0.0, 1.0)
    return effect
end

local function getPlaybackPosition(sourceData)
    local base = tonumber(sourceData.position) or 0.0

    if sourceData.paused then
        return base
    end

    local receivedAt = sourceData.receivedAt or GetGameTimer()
    local current = base + ((GetGameTimer() - receivedAt) / 1000.0)
    local duration = tonumber(sourceData.duration) or 0

    if duration > 0 then
        if sourceData.loop then
            return current % duration
        elseif current > duration then
            return duration
        end
    end
    return current
end

-- doi nui load xong moi cache am thanh
function LVMusic.SetAudioReady()
    nuiAudioReady = true
    activeAudio = {}
end

local function sendListener()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local rotation = GetGameplayCamRot(2)
    local forward = LVMusic.RotationToDirection(rotation)

    sendAudio('audioListener',
    {
        listener =
        {
            x = coords.x,
            y = coords.y,
            z = coords.z,
            forwardX = forward.x,
            forwardY = forward.y,
            forwardZ = forward.z,
            upX = 0.0,
            upY = 0.0,
            upZ = 1.0
        }
    })
end

local function shouldPlaySource(sourceData, listenerCoords, sourceCoords)
    if not sourceData.url or not sourceCoords then
        return false

    end

    local distance = #(listenerCoords - sourceCoords)
    local maxDistance = (tonumber(sourceData.distance) or 25.0) + Config.Audio.preloadDistance
    return distance <= maxDistance
end

LVMusic.mutedSources = {}

function LVMusic.ToggleMuteSource(sourceId)
    if LVMusic.mutedSources[sourceId] then
        LVMusic.mutedSources[sourceId] = nil
        exports.ox_lib:notify(
        {
            title = 'Musicbox',
            description = 'Đã bật lại âm thanh của loa này',
            type = 'success'
        })
    else
        LVMusic.mutedSources[sourceId] = true
        exports.ox_lib:notify(
        {
            title = 'Musicbox',
            description = 'Đã tắt âm thanh của loa này',
            type = 'success'
        })
    end
end

local function playOrUpdateSource(sourceId, sourceData, sourceCoords, keepWarm)
    local effect = getAudioEffect(sourceData, sourceCoords)
    local position = LVMusic.FromVec3(sourceCoords)
    local cached = activeAudio[sourceId]
    local desiredVolume = LVMusic.Clamp((tonumber(sourceData.volume) or 0.75), 0.0, 1.0)

    if keepWarm or LVMusic.mutedSources[sourceId] then
        desiredVolume = 0.0
    end

    local is2D = sourceData.is2D
    if is2D == nil then
        if sourceData.item and Config.BoomboxItems[sourceData.item] and Config.BoomboxItems[sourceData.item].is2D ~= nil then
            is2D = Config.BoomboxItems[sourceData.item].is2D
        elseif Config.Audio.is2D ~= nil then
            is2D = Config.Audio.is2D
        else
            is2D = true
        end
    end

    local playbackTime = getPlaybackPosition(sourceData)
    local duration = tonumber(sourceData.duration) or 0
    local payload =
    {
        id = sourceId,
        url = sourceData.url,
        title = sourceData.title or sourceData.input or sourceId,
        loop = sourceData.loop == true,
        paused = sourceData.paused == true,
        volume = desiredVolume,
        is2D = is2D,
        distance = tonumber(sourceData.distance) or 25.0,
        refDistance = Config.Audio.refDistance,
        rolloffFactor = Config.Audio.rolloffFactor,
        masterVolume = Config.Audio.masterVolume or 0.5,
        softSyncThreshold = Config.Audio.softSyncThreshold or 0.65,
        hardSyncThreshold = Config.Audio.hardSyncThreshold or 6.0,
        bufferTimeoutMs = Config.Audio.bufferTimeoutMs or 10000,
        maxRetries = Config.Audio.maxRetries or 3,
        position = position,
        effect = effect,
        time = playbackTime,
        duration = duration,
        ended = duration > 0 and sourceData.loop ~= true and playbackTime >= duration,
        version = sourceData.version or 0
    }

    if not cached or cached.url ~= sourceData.url or cached.version ~= sourceData.version then
        activeAudio[sourceId] =
        {
            url = sourceData.url,
            version = sourceData.version,
            paused = sourceData.paused == true,
            outOfRangeSince = cached and cached.outOfRangeSince or nil
        }

        sendAudio('audioPlay', payload)
        return
    end

    cached.paused = sourceData.paused == true

    if not keepWarm then
        cached.outOfRangeSince = nil
    end

    sendAudio('audioUpdate', payload)
end

local function destroySource(sourceId)
    if not activeAudio[sourceId] then
        return

    end

    activeAudio[sourceId] = nil

    sendAudio('audioDestroy',
    {
        id = sourceId
    })
end

CreateThread(function()
    while not nuiAudioReady do
        Wait(250)
    end

    while true do
        local sleep = Config.Audio.farUpdateMs
        local ped = PlayerPedId()
        local listenerCoords = GetEntityCoords(ped)
        local seen = {}
        local hasNearbyAudio = false
        local hasWarmAudio = false

        for sourceId, sourceData in pairs(LVMusic.sources) do
            seen[sourceId] = true

            if sourceData.url then
                local sourceCoords = LVMusic.GetSourcePosition(sourceData)

                if shouldPlaySource(sourceData, listenerCoords, sourceCoords) then
                    hasNearbyAudio = true

                    playOrUpdateSource(sourceId, sourceData, sourceCoords, false)
                else
                    local cached = activeAudio[sourceId]

                    if cached then
                        cached.outOfRangeSince = cached.outOfRangeSince or GetGameTimer()

                        local warmFor = GetGameTimer() - cached.outOfRangeSince

                        if warmFor <= (Config.Audio.warmCacheMs or 15000) and sourceCoords then
                            hasWarmAudio = true

                            playOrUpdateSource(sourceId, sourceData, sourceCoords, true)
                        else
                            destroySource(sourceId)
                        end
                    end
                end
            else
                destroySource(sourceId)
            end
        end

        for sourceId in pairs(activeAudio) do
            if not seen[sourceId] then
                destroySource(sourceId)
            end
        end

        if hasNearbyAudio or hasWarmAudio then
            sendListener()
        end

        if hasNearbyAudio then
            sleep = Config.Audio.updateMs
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= GetCurrentResourceName() then
        return

    end

    for sourceId in pairs(activeAudio) do
        sendAudio('audioDestroy',
        {
            id = sourceId
        })
    end
end)
