local function getCurrentVehicleEntry(existingIds)
    if not Config.Vehicle.enabled then return nil end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local netId

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        netId = VehToNet(vehicle)

        LVMusic.targetVehicleNetId = netId
    elseif LVMusic.targetVehicleNetId and NetworkDoesNetworkIdExist(LVMusic.targetVehicleNetId) then
        vehicle = NetToVeh(LVMusic.targetVehicleNetId)

        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            local playerCoords = GetEntityCoords(ped)
            local vehicleCoords = GetEntityCoords(vehicle)

            if #(playerCoords - vehicleCoords) <= Config.UiSourceDistance then
                netId = LVMusic.targetVehicleNetId
            else
                LVMusic.targetVehicleNetId = nil
            end
        else
            LVMusic.targetVehicleNetId = nil
        end
    end

    if not netId or netId == 0 then
        return nil

    end

    for sourceId, sourceData in pairs(LVMusic.sources) do
        if tonumber(sourceData.vehicleNetId) == tonumber(netId) then
            existingIds[sourceId] = true
            return nil
        end
    end
    return
    {
        id = ('vehicle:%s'):format(netId),
        virtual = true,
        targetType = 'vehicle',
        vehicleNetId = netId,
        type = 'vehicle',
        label = Config.Vehicle.label,
        title = LVMusic.L('idle'),
        status = LVMusic.L('idle'),
        mode = 'vehicle',
        distance = 0.0,
        volume = Config.Vehicle.volume,
        loop = false,
        paused = false,
        queue = {}
    }
end

local function sourceStatus(sourceData)
    if not sourceData.url then
        return LVMusic.L('idle')
    end

    if sourceData.paused then
        return LVMusic.L('pause')
    end
    return LVMusic.L('now_playing')
end

local function buildUiSources()
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local list = {}
    local existingIds = {}

    for sourceId, sourceData in pairs(LVMusic.sources) do
        local coords = LVMusic.GetSourcePosition(sourceData)
        local distance = coords and #(playerCoords - coords) or 9999.0

        if distance <= Config.UiSourceDistance or LVMusic.selectedSourceId == sourceId then
            existingIds[sourceId] = true

            list[#list + 1] =
            {
                id = sourceId,
                type = sourceData.type,
                label = sourceData.label or sourceData.id,
                title = sourceData.title or sourceData.input or LVMusic.L('idle'),
                status = sourceStatus(sourceData),
                mode = sourceData.mode,
                distance = distance,
                volume = sourceData.volume or 0.75,
                loop = sourceData.loop == true,
                paused = sourceData.paused == true,
                input = sourceData.input,
                videoId = sourceData.videoId,
                url = sourceData.url,
                duration = sourceData.duration,
                queue = sourceData.queue or {},
                canMove = sourceData.type ~= 'vehicle'
            }
        end
    end

    table.sort(list, function(a, b)
        return (a.distance or 9999.0) < (b.distance or 9999.0)
    end)

    local vehicleEntry = getCurrentVehicleEntry(existingIds)

    if vehicleEntry then
        table.insert(list, 1, vehicleEntry)
    end

    local selectedFound = false

    for _, sourceData in ipairs(list) do
        if sourceData.id == LVMusic.selectedSourceId then
            selectedFound = true
            break
        end
    end

    if not selectedFound then
        LVMusic.selectedSourceId = list[1] and list[1].id or nil
    end
    return list
end

function LVMusic.SendUiContext()
    SendNUIMessage(
    {
        app = 'lv_musicbox',
        action = 'uiContext',
        visible = LVMusic.uiOpen,
        sources = buildUiSources(),
        selectedSourceId = LVMusic.selectedSourceId,
        library = LVMusic.library,
        strings = LVMusic.LocalePayload()
    })
end

function LVMusic.OpenUi()
    LVMusic.uiOpen = true

    SetNuiFocus(true, true)

    LVMusic.SendUiContext()

    TriggerServerEvent('lv_musicbox:server:requestLibrary')
    TriggerServerEvent('lv_musicbox:server:requestSync')
end

function LVMusic.OpenVehicleUi(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return

    end

    local netId = VehToNet(vehicle)

    if not netId or netId == 0 then
        return
    end

    LVMusic.targetVehicleNetId = netId
    LVMusic.selectedSourceId = ('vehicle:%s'):format(netId)

    for sourceId, sourceData in pairs(LVMusic.sources) do
        if tonumber(sourceData.vehicleNetId) == tonumber(netId) then
            LVMusic.selectedSourceId = sourceId
            break
        end
    end

    LVMusic.OpenUi()
end

function LVMusic.CloseUi()
    LVMusic.uiOpen = false

    SetNuiFocus(false, false)

    LVMusic.SendUiContext()
end

local function toggleUi(source, args)
    local subCommand = args and args[1]

    if subCommand == 'drop' or subCommand == 'pickup' then
        local myServerId = GetPlayerServerId(PlayerId())
        local heldSourceId = nil

        for sourceId, sourceData in pairs(LVMusic.sources) do
            if sourceData.holder == myServerId then
                heldSourceId = sourceId
                break
            end
        end

        if heldSourceId then
            LVMusic.HandleDeviceAction(
            {
                sourceId = heldSourceId,
                action = subCommand
            })
        else
            if subCommand == 'pickup' then
                local closestId = LVMusic.GetClosestSource(Config.InteractionDistance)
                
                if closestId then
                    LVMusic.HandleDeviceAction(
                    {
                        sourceId = closestId,
                        action = 'pickup'
                    })
                else
                    LVMusic.Notify(LVMusic.L('no_source'), 'error')
                end
            else
                LVMusic.Notify(LVMusic.L('action_failed'), 'error')
            end
        end
        return
    end

    if LVMusic.uiOpen then
        LVMusic.CloseUi()
    else
        local closestId = LVMusic.GetClosestSource(Config.InteractionDistance)

        if closestId then
            LVMusic.selectedSourceId = closestId
        end

        LVMusic.OpenUi()
    end
end

local function getVehiclePayload(data)
    local netId = tonumber(data.vehicleNetId)
    local vehicle = 0

    if netId and NetworkDoesNetworkIdExist(netId) then
        vehicle = NetToVeh(netId)
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return {}
    end
    return
    {
        vehicleNetId = VehToNet(vehicle),
        coords = LVMusic.FromVec3(GetEntityCoords(vehicle)),
        heading = GetEntityHeading(vehicle)
    }
end

RegisterCommand(Config.Command, toggleUi, false)

if Config.DefaultKey and Config.DefaultKey ~= '' then
    RegisterKeyMapping(Config.Command, 'Open SpityFork', 'keyboard', Config.DefaultKey)
end

RegisterNUICallback('ready', function(_, cb)
    if LVMusic.SetAudioReady then
        LVMusic.SetAudioReady()
    end

    LVMusic.SendUiContext()

    TriggerServerEvent('lv_musicbox:server:requestSync')
    TriggerServerEvent('lv_musicbox:server:requestLibrary')

    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('close', function(_, cb)
    LVMusic.CloseUi()

    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('selectSource', function(data, cb)
    if type(data) == 'table' then
        LVMusic.selectedSourceId = data.sourceId
        LVMusic.SendUiContext()
    end

    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('play', function(data, cb)
    if type(data) ~= 'table' then
        cb(
        {
            ok = false
        })
        return
    end

    local payload =
    {
        input = data.input,
        volume = data.volume,
        loop = data.loop == true,
        requestId = data.requestId
    }

    if data.targetType == 'vehicle' then
        local vehiclePayload = getVehiclePayload(data)

        payload.targetType = 'vehicle'
        payload.vehicleNetId = vehiclePayload.vehicleNetId
        payload.coords = vehiclePayload.coords
        payload.heading = vehiclePayload.heading
    else
        payload.sourceId = data.sourceId
    end

    TriggerServerEvent('lv_musicbox:server:play', payload)

    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('control', function(data, cb)
    if type(data) == 'table' then
        TriggerServerEvent('lv_musicbox:server:control', data)
    end

    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('favorite', function(data, cb)
    if type(data) == 'table' then
        TriggerServerEvent('lv_musicbox:server:favorite', data)
    end

    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('queueAction', function(data, cb)
    if type(data) == 'table' then
        TriggerServerEvent('lv_musicbox:server:queueAction', data)
    end

    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('deviceAction', function(data, cb)
    LVMusic.HandleDeviceAction(data)

    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('requestContext', function(_, cb)
    LVMusic.SendUiContext()
    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('audioError', function(data, cb)
    if Config.Debug and type(data) == 'table' then
        LVMusic.Debug('audio error', data.id, data.message)
    end

    cb(
    {
        ok = true
    })
end)

RegisterNetEvent('lv_musicbox:client:syncSources', function(payload)
    local receivedAt = GetGameTimer()
    local normalized = {}

    for sourceId, sourceData in pairs(payload or {}) do
        sourceData.id = sourceData.id or sourceId
        sourceData.receivedAt = receivedAt

        normalized[sourceId] = sourceData
    end

    LVMusic.sources = normalized

    local myServerId = GetPlayerServerId(PlayerId())

    for _, sourceData in pairs(normalized) do
        if sourceData.holder == myServerId and sourceData.netId then
            local attachmentName = sourceData.mode

            if attachmentName == 'carry' then
                attachmentName = 'hand'
            end

            local attachment = Config.Attachments[attachmentName]

            if attachment then
                local netId = tonumber(sourceData.netId)

                if netId and NetworkDoesNetworkIdExist(netId) then
                    local object = NetToObj(netId)

                    if object ~= 0 and DoesEntityExist(object) then
                        local ped = PlayerPedId()

                        if not IsEntityAttachedToEntity(object, ped) then
                            AttachEntityToEntity(
                                object,
                                ped,
                                GetPedBoneIndex(ped, attachment.bone),
                                attachment.offset.x,
                                attachment.offset.y,
                                attachment.offset.z,
                                attachment.rotation.x,
                                attachment.rotation.y,
                                attachment.rotation.z,
                                true,
                                true,
                                false,
                                true,
                                1,
                                true
                            )

                            SetEntityCollision(object, false, false)
                        end
                    end
                end
            end
        end
    end

    if LVMusic.RefreshTargets then
        LVMusic.RefreshTargets()
    end

    if LVMusic.uiOpen then
        LVMusic.SendUiContext()
    end
end)

RegisterNetEvent('lv_musicbox:client:library', function(payload)
    LVMusic.library = payload or
    {
        favorites = {},
        recent = {}
    }

    LVMusic.library.favorites = LVMusic.library.favorites or {}
    LVMusic.library.recent = LVMusic.library.recent or {}

    if LVMusic.uiOpen then
        LVMusic.SendUiContext()
    end
end)

RegisterNetEvent('lv_musicbox:client:playStatus', function(payload)
    if type(payload) ~= 'table' then
        return

    end

    SendNUIMessage(
    {
        app = 'lv_musicbox',
        action = 'playStatus',
        requestId = payload.requestId,
        state = payload.state,
        message = payload.message,
        sourceId = payload.sourceId
    })
end)

CreateThread(function()
    Wait(1000)

    TriggerServerEvent('lv_musicbox:server:requestSync')
    TriggerServerEvent('lv_musicbox:server:requestLibrary')
end)

CreateThread(function()
    while true do
        Wait(1000)
        
        if LVMusic.uiOpen then
            LVMusic.SendUiContext()
        end
    end
end)
