local targetNames =
{
    'lv_musicbox_open',
    'lv_musicbox_back',
    'lv_musicbox_drop',
    'lv_musicbox_pickup'
}
local vehicleTargetName = 'lv_musicbox_vehicle'
local registeredTargets = {}
local vehicleTargetRegistered = false

local function targetReady()
    return Config.Target.enabled and GetResourceState('ox_target') == 'started'
end

local function currentServerId()
    return GetPlayerServerId(PlayerId())
end

local function getItemName(data)
    if type(data) == 'table' then
        return data.name or data.item or data[1]
    end
    return data
end

local function createPlacedObject(itemName)
    local itemConfig = Config.BoomboxItems[itemName]

    if not itemConfig then
        LVMusic.Notify(LVMusic.L('invalid_item'), 'error')
        return nil
    end

    local modelHash = LVMusic.RequestModel(itemConfig.model)

    if not modelHash then
        LVMusic.Notify(LVMusic.L('action_failed'), 'error')
        return nil
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local heading = GetEntityHeading(ped)
    local spawnCoords = coords + (forward * 0.85)

    local object = CreateObject(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z - 0.75, true, true, false)

    if not object or object == 0 then
        SetModelAsNoLongerNeeded(modelHash)

        LVMusic.Notify(LVMusic.L('action_failed'), 'error')
        return nil
    end

    SetEntityHeading(object, heading)

    PlaceObjectOnGroundProperly(object)

    SetEntityAsMissionEntity(object, true, true)

    local netId = ObjToNet(object)

    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, true)

    SetModelAsNoLongerNeeded(modelHash)
    return object, netId
end

function LVMusic.PlaceBoombox(itemName)
    itemName = getItemName(itemName)

    if not itemName or not Config.BoomboxItems[itemName] then
        LVMusic.Notify(LVMusic.L('invalid_item'), 'error')
        return
    end

    if IsPedInAnyVehicle(PlayerPedId(), false) then
        LVMusic.Notify(LVMusic.L('in_vehicle_place'), 'error')
        return
    end

    local success = lib.progressBar(
    {
        duration = Config.PlaceDuration,
        label = LVMusic.L('placing'),
        useWhileDead = false,
        canCancel = true,
        disable =
        {
            move = true,
            car = true,
            combat = true
        },
        anim =
        {
            dict = 'pickup_object',
            clip = 'pickup_low'
        }
    })

    if not success then
        return

    end

    local object, netId = createPlacedObject(itemName)

    if not object then
        return
    end

    TriggerServerEvent('lv_musicbox:server:registerDevice',
    {
        item = itemName,
        netId = netId,
        coords = LVMusic.FromVec3(GetEntityCoords(object)),
        heading = GetEntityHeading(object)
    })
end

exports('useBoombox', function(data, slot)
    CreateThread(function()
        LVMusic.PlaceBoombox(getItemName(data) or getItemName(slot))
    end)
end)

local function attachDevice(sourceData, attachmentName)
    local object = LVMusic.GetSourceEntity(sourceData)

    if object == 0 or not DoesEntityExist(object) then
        LVMusic.Notify(LVMusic.L('action_failed'), 'error')
        return false
    end

    if not LVMusic.RequestControl(object) then
        LVMusic.Notify(LVMusic.L('action_failed'), 'error')
        return false
    end

    local attachment = Config.Attachments[attachmentName]
    local ped = PlayerPedId()

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
    return true
end

local function dropDevice(sourceData)
    local object = LVMusic.GetSourceEntity(sourceData)

    if object == 0 or not DoesEntityExist(object) then
        LVMusic.Notify(LVMusic.L('action_failed'), 'error')
        return false
    end

    if not LVMusic.RequestControl(object) then
        LVMusic.Notify(LVMusic.L('action_failed'), 'error')
        return false
    end

    DetachEntity(object, true, true)

    SetEntityCollision(object, true, true)

    PlaceObjectOnGroundProperly(object)
    return true, LVMusic.FromVec3(GetEntityCoords(object)), GetEntityHeading(object)
end

function LVMusic.HandleDeviceAction(payload)
    if type(payload) ~= 'table' then
        return
    end

    local sourceId = tostring(payload.sourceId or '')
    local sourceData = LVMusic.sources[sourceId]

    if not sourceData or sourceData.type == 'vehicle' then
        return
    end

    local action = tostring(payload.action or '')

    if action == 'carry' then
        if attachDevice(sourceData, 'hand') then
            TriggerServerEvent('lv_musicbox:server:deviceAction',
            {
                sourceId = sourceId,
                action = 'carry'
            })
        end
    elseif action == 'back' then
        if attachDevice(sourceData, 'back') then
            TriggerServerEvent('lv_musicbox:server:deviceAction',
            {
                sourceId = sourceId,
                action = 'back'
            })
        end
    elseif action == 'drop' then
        local ok, coords, heading = dropDevice(sourceData)

        if ok then
            TriggerServerEvent('lv_musicbox:server:deviceAction',
            {
                sourceId = sourceId,
                action = 'drop',
                coords = coords,
                heading = heading
            })
        end
    elseif action == 'pickup' then
        TriggerServerEvent('lv_musicbox:server:pickup',
        {
            sourceId = sourceId
        })
    end
end

RegisterNetEvent('lv_musicbox:client:deleteNetEntity', function(netId)
    local object = 0

    netId = tonumber(netId)

    if netId and NetworkDoesNetworkIdExist(netId) then
        object = NetToObj(netId)
    end

    if object ~= 0 and DoesEntityExist(object) then
        if LVMusic.RequestControl(object) then
            SetEntityAsMissionEntity(object, true, true)

            DeleteEntity(object)
        end
    end
end)

local function sourceTargetOptions(sourceId)
    local function getSource()
        return LVMusic.sources[sourceId]
    end

    local function isPlacedBoombox()
        local sourceData = getSource()
        return sourceData and sourceData.type == 'boombox' and sourceData.mode == 'placed' and not sourceData.holder
    end

    local function isHeldByPlayer()
        local sourceData = getSource()
        return sourceData and sourceData.holder == currentServerId()
    end

    local function isPlacedDevice()
        local sourceData = getSource()
        return sourceData and sourceData.type ~= 'vehicle' and sourceData.mode == 'placed' and not sourceData.holder
    end

    local function isOwner()
        local sourceData = getSource()
        return sourceData and sourceData.owner == currentServerId()
    end
    return
    {
        {
            name = 'lv_musicbox_open',
            icon = 'fas fa-music',
            label = LVMusic.L('open_musicbox'),
            distance = Config.Target.distance,
            canInteract = function()
                return getSource() ~= nil and isOwner()
            end,
            onSelect = function()
                if not getSource() then
                    return
                end

                LVMusic.selectedSourceId = sourceId
                LVMusic.OpenUi()
            end
        },
        {
            name = 'lv_musicbox_back',
            icon = 'fas fa-user',
            label = LVMusic.L('back'),
            distance = Config.Target.distance,
            canInteract = function()
                return isPlacedBoombox() and isOwner()
            end,
            onSelect = function()
                LVMusic.HandleDeviceAction(
                {
                    sourceId = sourceId,
                    action = 'back'
                })
            end
        },
        {
            name = 'lv_musicbox_drop',
            icon = 'fas fa-arrow-down',
            label = LVMusic.L('drop'),
            distance = Config.Target.distance,
            canInteract = function()
                return isHeldByPlayer() and isOwner()
            end,
            onSelect = function()
                LVMusic.HandleDeviceAction(
                {
                    sourceId = sourceId,
                    action = 'drop'
                })
            end
        },
        {
            name = 'lv_musicbox_pickup',
            icon = 'fas fa-box',
            label = LVMusic.L('pickup'),
            distance = Config.Target.distance,
            canInteract = function()
                return isPlacedDevice() and isOwner()
            end,
            onSelect = function()
                LVMusic.HandleDeviceAction(
                {
                    sourceId = sourceId,
                    action = 'pickup'
                })
            end
        },
        {
            name = 'lv_musicbox_mute',
            icon = 'fas fa-volume-mute',
            label = 'Tắt/Bật tiếng (Local)',
            distance = Config.Target.distance,
            canInteract = function()
                return isPlacedDevice()
            end,
            onSelect = function()
                LVMusic.ToggleMuteSource(sourceId)
            end
        }
    }
end

local function removeSourceTarget(sourceId)
    local netId = registeredTargets[sourceId]

    if not netId or not targetReady() then
        registeredTargets[sourceId] = nil
        return
    end

    exports.ox_target:removeEntity(netId, targetNames)

    registeredTargets[sourceId] = nil
end

local function addSourceTarget(sourceId, sourceData)
    if not targetReady() or sourceData.type == 'vehicle' or not sourceData.netId then
        return
    end

    local netId = tonumber(sourceData.netId)

    if not netId or registeredTargets[sourceId] == netId or not NetworkDoesNetworkIdExist(netId) then
        return
    end

    removeSourceTarget(sourceId)

    exports.ox_target:addEntity(netId, sourceTargetOptions(sourceId))
    
    registeredTargets[sourceId] = netId
end

local function addVehicleTarget()
    if vehicleTargetRegistered or not targetReady() or not Config.Vehicle.enabled then
        return
    end

    exports.ox_target:addGlobalVehicle(
    {
        {
            name = vehicleTargetName,
            icon = 'fas fa-volume-up',
            label = LVMusic.L('open_musicbox'),
            distance = Config.Target.distance,
            canInteract = function(entity)
                return DoesEntityExist(entity) and not IsEntityDead(entity)
            end,
            onSelect = function(data)
                if data.entity and DoesEntityExist(data.entity) then
                    LVMusic.OpenVehicleUi(data.entity)
                end
            end
        }
    })

    vehicleTargetRegistered = true
end

function LVMusic.RefreshTargets()
    if not targetReady() then
        return
    end

    addVehicleTarget()

    local seen = {}

    for sourceId, sourceData in pairs(LVMusic.sources) do
        if sourceData.type ~= 'vehicle' then
            seen[sourceId] = true
            addSourceTarget(sourceId, sourceData)
        end
    end

    for sourceId in pairs(registeredTargets) do
        if not seen[sourceId] then
            removeSourceTarget(sourceId)
        end
    end
end

function LVMusic.GetClosestSource(maxDistance)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closestId, closestSource, closestDistance

    maxDistance = maxDistance or Config.InteractionDistance

    for sourceId, sourceData in pairs(LVMusic.sources) do
        if sourceData.type ~= 'vehicle' then
            local sourceCoords = LVMusic.GetSourcePosition(sourceData)

            if sourceCoords then
                local distance = #(coords - sourceCoords)

                if distance <= maxDistance and (not closestDistance or distance < closestDistance) then
                    closestId = sourceId
                    closestSource = sourceData
                    closestDistance = distance
                end
            end
        end
    end
    return closestId, closestSource, closestDistance
end

CreateThread(function()
    while true do
        LVMusic.RefreshTargets()

        Wait(2000)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'ox_target' then
        return
    end

    SetTimeout(500, function()
        registeredTargets = {}

        vehicleTargetRegistered = false

        LVMusic.RefreshTargets()
    end)
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= GetCurrentResourceName() then
        return
    end

    if targetReady() then
        for sourceId in pairs(registeredTargets) do
            removeSourceTarget(sourceId)
        end

        if vehicleTargetRegistered then
            exports.ox_target:removeGlobalVehicle(vehicleTargetName)
        end
    end
end)

RegisterNetEvent('lv_musicbox:client:adminPickup', function()
    local closestId, closestSource, closestDistance = LVMusic.GetClosestSource(15.0)

    if closestId then
        TriggerServerEvent('lv_musicbox:server:adminPickup', closestId)
    else
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local models =
        {
            GetHashKey('prop_boombox_01'),
            GetHashKey('prop_tapeplayer_01'),
            GetHashKey('prop_speaker_01'),
            GetHashKey('prop_speaker_03')
        }

        local closestObj = 0
        local closestDist = 999.0

        for _, modelHash in ipairs(models) do
            local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, 15.0, modelHash, false, false, false)

            if DoesEntityExist(obj) and obj ~= 0 then
                local dist = #(coords - GetEntityCoords(obj))

                if dist < closestDist then
                    closestObj = obj
                    closestDist = dist
                end
            end
        end

        if DoesEntityExist(closestObj) and closestObj ~= 0 then
            local netId = NetworkGetNetworkIdFromEntity(closestObj)

            TriggerServerEvent('lv_musicbox:server:adminDeleteOrphanObject', netId)
        else
            exports.ox_lib:notify(
            {
                title = 'Musicbox',
                description = 'Không tìm thấy chiếc loa nào xung quanh đây (bán kính 15m)!',
                type = 'error'
            })
        end
    end
end)
