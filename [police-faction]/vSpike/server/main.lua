ESX = exports["es_extended"]:getSharedObject()

local spikeItems = {
    'spike_strip'
}

local serverSpikes = {}
local triggeredGroups = {}
local vehicleBurstSync = {}
local pendingPlacements = {}
local burstSequence = 0
local spikeModel = joaat('p_ld_stinger_s')

local REGISTER_RESOLVE_TIMEOUT = 1500
local REGISTER_REPORTED_TOLERANCE = 2.0
local REGISTER_PLAYER_DISTANCE = 20.0

local allowedSpikeItems = {}
for _, itemName in ipairs(spikeItems) do
    allowedSpikeItems[itemName] = true
end

local allowedTyreIndexes = {
    [0] = true,
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [45] = true,
    [47] = true
}

local function getGroupId(spikeData, fallback)
    return spikeData.groupId or (spikeData.related and spikeData.related[1]) or fallback
end

local function getDriverVehicle(src, vehicleNetId)
    vehicleNetId = tonumber(vehicleNetId)
    if not vehicleNetId or vehicleNetId <= 0 then return nil end

    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil end
    if not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return nil end
    if NetworkGetNetworkIdFromEntity(vehicle) ~= vehicleNetId then return nil end

    return vehicle, vehicleNetId
end

local function isVehicleNearSpike(vehicle, spikeData, maxDistance)
    local vehicleCoords = GetEntityCoords(vehicle)
    local spikeCoords = spikeData.coords
    local dx = vehicleCoords.x - spikeCoords.x
    local dy = vehicleCoords.y - spikeCoords.y
    local dz = vehicleCoords.z - spikeCoords.z
    maxDistance = maxDistance or Config.ServerValidationDistance

    return dx * dx + dy * dy + dz * dz <= maxDistance * maxDistance
end

local function clearBurstSync(key, sequence)
    local record = vehicleBurstSync[key]
    if not record or record.sequence ~= sequence then return end

    local entity = NetworkGetEntityFromNetworkId(record.vehicleNetId)
    if entity ~= 0 and DoesEntityExist(entity) and entity == record.entity then
        local state = Entity(entity).state
        local currentPayload = state.vSpikeBurstTyres
        if currentPayload and currentPayload.sequence == sequence then
            state:set('vSpikeBurstTyres', nil, true)
        end
    end

    vehicleBurstSync[key] = nil
end

local function syncBurstTyre(vehicle, vehicleNetId, tyreIndex, sourcePlayer)
    local key = tostring(vehicleNetId)
    local record = vehicleBurstSync[key]

    if not record or record.entity ~= vehicle then
        record = {
            entity = vehicle,
            vehicleNetId = vehicleNetId,
            tyres = {}
        }
        vehicleBurstSync[key] = record
    end

    record.tyres[tostring(tyreIndex)] = true
    burstSequence = burstSequence + 1
    record.sequence = burstSequence
    record.acknowledged = false

    local payloadTyres = {}
    for syncedTyreIndex, shouldBurst in pairs(record.tyres) do
        payloadTyres[syncedTyreIndex] = shouldBurst
    end

    local payload = {
        sequence = record.sequence,
        tyres = payloadTyres
    }

    Entity(vehicle).state:set('vSpikeBurstTyres', payload, true)

    local owner = NetworkGetEntityOwner(vehicle)
    if owner and owner > 0 then
        TriggerClientEvent('V.Spike:BurstTyre', owner, vehicleNetId, payload)
    end

    if not owner or owner <= 0 or owner ~= sourcePlayer then
        TriggerClientEvent('V.Spike:BurstTyre', sourcePlayer, vehicleNetId, payload)
    end

    local sequence = record.sequence
    SetTimeout(Config.BurstSyncDuration, function()
        clearBurstSync(key, sequence)
    end)
end

RegisterNetEvent('V.Spike:BurstAck', function(vehicleNetId, sequence)
    local src = source
    vehicleNetId = tonumber(vehicleNetId)
    sequence = tonumber(sequence)
    if not vehicleNetId or not sequence then return end

    local key = tostring(vehicleNetId)
    local record = vehicleBurstSync[key]
    if not record or record.sequence ~= sequence or record.acknowledged then return end

    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) or vehicle ~= record.entity then return end
    if NetworkGetEntityOwner(vehicle) ~= src then return end

    record.acknowledged = true
end)

local function refundPendingPlacement(src, pending)
    if pendingPlacements[src] ~= pending then return false end

    pendingPlacements[src] = nil
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer and xPlayer.canCarryItem(pending.item, 1) then
        xPlayer.addInventoryItem(pending.item, 1)
        return true
    end

    return false
end

local function expirePendingPlacement(src, pending)
    if pendingPlacements[src] ~= pending then return end

    if pending.validating and GetGameTimer() < (pending.validationDeadline or 0) then
        SetTimeout(REGISTER_RESOLVE_TIMEOUT + 250, function()
            expirePendingPlacement(src, pending)
        end)
        return
    end

    pending.validating = false
    local refunded = refundPendingPlacement(src, pending)
    exports['lv_notify']:Notify(src, {
        title = 'V-Spike System',
        message = refunded and 'Đặt spike quá thời gian, vật phẩm đã được hoàn lại'
            or 'Đặt spike quá thời gian, túi đồ đầy nên không thể hoàn vật phẩm',
        type = refunded and 'success' or 'error'
    })
    TriggerClientEvent('V.Spike:RegisterRejected', src)
end

for _, itemName in ipairs(spikeItems) do
    ESX.RegisterUsableItem(itemName, function(source)
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer.getInventoryItem(itemName).count > 0 then
            TriggerClientEvent('spike_strip:use', source, itemName)
        else
            exports['lv_notify']:Notify(source, {
                title = 'V-Spike System',
                message = 'Bạn không có spike trong người',
                type = 'error'
            })
        end
    end)
end

RegisterNetEvent('spike_strip:removeItem', function(itemName)
    local src = source
    if not allowedSpikeItems[itemName] or pendingPlacements[src] then return end

    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer and xPlayer.getInventoryItem(itemName).count > 0 then
        xPlayer.removeInventoryItem(itemName, 1)

        local pending = {item = itemName}
        pendingPlacements[src] = pending
        SetTimeout(10000, function()
            expirePendingPlacement(src, pending)
        end)
    end
end)

local function syncSpikes(target)
    if target then
        TriggerClientEvent('V.Spike:Sync', target, serverSpikes)
    else
        TriggerClientEvent('V.Spike:Sync', -1, serverSpikes)
    end
end

RegisterNetEvent('V.Spike:RequestSync', function()
    syncSpikes(source)
end)

local function removeSpikeGroup(netIds)
    local removeData = {}
    local firstSpike = netIds and serverSpikes[netIds[1]]

    if firstSpike then
        triggeredGroups[tostring(getGroupId(firstSpike, netIds[1]))] = nil
    end

    for _, netId in ipairs(netIds) do
        if serverSpikes[netId] then
            removeData[netId] = {
                coords = serverSpikes[netId].coords,
                heading = serverSpikes[netId].heading,
                groupId = getGroupId(serverSpikes[netId], netId),
                related = serverSpikes[netId].related
            }
        end
    end

    for _, netId in ipairs(netIds) do
        serverSpikes[netId] = nil
    end

    syncSpikes()
    TriggerClientEvent('V.Spike:Remove', -1, netIds, removeData)
end

local function returnTriggeredSpike(spikeData)
    local groupKey = tostring(getGroupId(spikeData))
    local groupState = triggeredGroups[groupKey]
    if not groupState or groupState.refunded then return end

    groupState.refunded = true
    local xPlayer = ESX.GetPlayerFromId(spikeData.owner)
    if not xPlayer then return end

    if xPlayer.canCarryItem(spikeData.item, 1) then
        xPlayer.addInventoryItem(spikeData.item, 1)
        exports['lv_notify']:Notify(spikeData.owner, {
            title = 'V-Spike System',
            message = 'Spike đã được thu hồi vào túi đồ',
            type = 'success'
        })
    else
        exports['lv_notify']:Notify(spikeData.owner, {
            title = 'V-Spike System',
            message = 'Túi đồ đầy, spike đã bị hỏng',
            type = 'error'
        })
    end
end

local function extendCrossingDeadline(spikeData, currentTime)
    for _, relatedId in ipairs(spikeData.related) do
        if serverSpikes[relatedId] then
            serverSpikes[relatedId].triggered = true
        end
    end
end

local function scheduleTriggeredGroupRemoval(groupKey)
end

local function rejectPlacement(src, pending, verifiedCleanupIds)
    local refunded = pending and refundPendingPlacement(src, pending) or false
    local message = 'Không thể đồng bộ spike'

    if pending then
        message = refunded and 'Không thể đồng bộ spike, vật phẩm đã được hoàn lại'
            or 'Không thể đồng bộ spike, túi đồ đầy nên không thể hoàn vật phẩm'
    end

    exports['lv_notify']:Notify(src, {
        title = 'V-Spike System',
        message = message,
        type = 'error'
    })
    TriggerClientEvent('V.Spike:RegisterRejected', src)

    if verifiedCleanupIds and #verifiedCleanupIds > 0 then
        TriggerClientEvent('V.Spike:Remove', src, verifiedCleanupIds)
    end
end

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

RegisterNetEvent('V.Spike:Register', function(netIds, itemName, coordsList, heading)
    local src = source
    local pending = pendingPlacements[src]

    if pending and pending.validating then return end

    if not pending or pending.item ~= itemName or not allowedSpikeItems[itemName]
        or type(netIds) ~= 'table' or type(coordsList) ~= 'table'
        or #netIds ~= 3 or #coordsList ~= 3 then
        rejectPlacement(src, pending)
        return
    end

    local cleanNetIds = {}
    local cleanCoords = {}
    local seenNetIds = {}

    for i = 1, 3 do
        local netId = tonumber(netIds[i])
        local coords = coordsList[i]

        if not netId or netId <= 0 or netId ~= math.floor(netId)
            or seenNetIds[netId] or serverSpikes[netId]
            or not coords or not isFiniteNumber(coords.x)
            or not isFiniteNumber(coords.y) or not isFiniteNumber(coords.z) then
            rejectPlacement(src, pending)
            return
        end

        seenNetIds[netId] = true
        cleanNetIds[i] = netId
        cleanCoords[i] = {
            x = coords.x,
            y = coords.y,
            z = coords.z
        }
    end

    pending.validating = true
    pending.validationDeadline = GetGameTimer() + REGISTER_RESOLVE_TIMEOUT + 500

    CreateThread(function()
        local entities = {}
        local verifiedCleanupIds = {}
        local verifiedNetIds = {}
        local resolveDeadline = GetGameTimer() + REGISTER_RESOLVE_TIMEOUT

        local function rejectCurrentPlacement(cleanupIds)
            if pendingPlacements[src] ~= pending then return end
            rejectPlacement(src, pending, cleanupIds)
        end

        if pendingPlacements[src] ~= pending then return end

        while GetGameTimer() <= resolveDeadline do
            if pendingPlacements[src] ~= pending then return end

            local allResolved = true

            for i, netId in ipairs(cleanNetIds) do
                if not entities[i] then
                    local entity = NetworkGetEntityFromNetworkId(netId)

                    if entity ~= 0 and DoesEntityExist(entity) then
                        if GetEntityType(entity) ~= 3 or GetEntityModel(entity) ~= spikeModel
                            or NetworkGetEntityOwner(entity) ~= src then
                            rejectCurrentPlacement(verifiedCleanupIds)
                            return
                        end

                        entities[i] = entity
                        verifiedNetIds[netId] = true
                        verifiedCleanupIds[#verifiedCleanupIds + 1] = netId
                    else
                        allResolved = false
                    end
                end
            end

            if allResolved then break end
            Wait(50)
        end

        if #verifiedCleanupIds ~= 3 then
            rejectCurrentPlacement(verifiedCleanupIds)
            return
        end

        if pendingPlacements[src] ~= pending then return end

        local playerPed = GetPlayerPed(src)
        if playerPed == 0 or not DoesEntityExist(playerPed) then
            rejectCurrentPlacement(verifiedCleanupIds)
            return
        end

        local playerCoords = GetEntityCoords(playerPed)
        local actualCoords = {}
        local actualHeadings = {}
        local reportedToleranceSquared = REGISTER_REPORTED_TOLERANCE * REGISTER_REPORTED_TOLERANCE
        local playerDistanceSquared = REGISTER_PLAYER_DISTANCE * REGISTER_PLAYER_DISTANCE

        for i, entity in ipairs(entities) do
            local netId = cleanNetIds[i]
            local mappedEntity = NetworkGetEntityFromNetworkId(netId)

            if mappedEntity ~= entity or not DoesEntityExist(entity)
                or GetEntityType(entity) ~= 3 or GetEntityModel(entity) ~= spikeModel
                or NetworkGetEntityOwner(entity) ~= src or serverSpikes[netId]
                or not verifiedNetIds[netId] then
                rejectCurrentPlacement(verifiedCleanupIds)
                return
            end

            local coords = GetEntityCoords(entity)
            local dxReported = coords.x - cleanCoords[i].x
            local dyReported = coords.y - cleanCoords[i].y
            local dzReported = coords.z - cleanCoords[i].z
            local dxPlayer = coords.x - playerCoords.x
            local dyPlayer = coords.y - playerCoords.y
            local dzPlayer = coords.z - playerCoords.z

            if dxReported * dxReported + dyReported * dyReported + dzReported * dzReported > reportedToleranceSquared
                or dxPlayer * dxPlayer + dyPlayer * dyPlayer + dzPlayer * dzPlayer > playerDistanceSquared then
                rejectCurrentPlacement(verifiedCleanupIds)
                return
            end

            actualCoords[i] = {
                x = coords.x,
                y = coords.y,
                z = coords.z
            }
            actualHeadings[i] = GetEntityHeading(entity)
        end

        if pendingPlacements[src] ~= pending then return end
        pendingPlacements[src] = nil

        local despawnTime = GetGameTimer() + (Config.DespawnTime * 1000)
        local groupId = cleanNetIds[1]

        for i, netId in ipairs(cleanNetIds) do
            serverSpikes[netId] = {
                owner = src,
                item = itemName,
                groupId = groupId,
                related = cleanNetIds,
                despawnTime = despawnTime,
                triggered = false,
                coords = actualCoords[i],
                heading = actualHeadings[i]
            }
        end
        syncSpikes()
        TriggerClientEvent('V.Spike:RegisterAccepted', src)
    end)
end)

RegisterNetEvent('V.Spike:Hit', function(netId, vehicleNetId, wheelIndex)
    local src = source
    netId = tonumber(netId) or netId
    wheelIndex = tonumber(wheelIndex)
    local spikeData = serverSpikes[netId]

    if not spikeData or not wheelIndex or not allowedTyreIndexes[wheelIndex] then return end

    local vehicle
    vehicle, vehicleNetId = getDriverVehicle(src, vehicleNetId)
    if not vehicle or not isVehicleNearSpike(vehicle, spikeData) then return end

    local groupId = getGroupId(spikeData, netId)
    local groupKey = tostring(groupId)
    local groupState = triggeredGroups[groupKey]

    if not groupState then
        groupState = {
            hitWheels = {},
            activeVehicles = {},
            activityVersion = 0,
            related = spikeData.related
        }
        triggeredGroups[groupKey] = groupState
    end

    local vehicleKey = tostring(vehicleNetId)
    local vehicleHits = groupState.hitWheels[vehicleKey]
    if not vehicleHits or vehicleHits.entity ~= vehicle then
        vehicleHits = {
            entity = vehicle,
            wheels = {}
        }
        groupState.hitWheels[vehicleKey] = vehicleHits
        groupState.activeVehicles[vehicleKey] = nil
    end
    local currentTime = GetGameTimer()

    if vehicleHits.wheels[wheelIndex] then
        local activeVehicle = groupState.activeVehicles[vehicleKey]
        if activeVehicle and activeVehicle.entity == vehicle and activeVehicle.source == src then
            activeVehicle.lastProgressAt = currentTime
            extendCrossingDeadline(spikeData, currentTime)
        end
        TriggerClientEvent('V.Spike:HitAccepted', src, groupId, vehicleNetId, wheelIndex)
        return
    end

    vehicleHits.wheels[wheelIndex] = true
    groupState.activeVehicles[vehicleKey] = {
        entity = vehicle,
        source = src,
        lastProgressAt = currentTime
    }
    groupState.activityVersion = groupState.activityVersion + 1

    extendCrossingDeadline(spikeData, currentTime)

    syncBurstTyre(vehicle, vehicleNetId, wheelIndex, src)
    TriggerClientEvent('V.Spike:HitAccepted', src, groupId, vehicleNetId, wheelIndex)
end)

RegisterNetEvent('V.Spike:CrossingProgress', function(netId, vehicleNetId)
    local src = source
    netId = tonumber(netId) or netId
    local spikeData = serverSpikes[netId]
    if not spikeData then return end

    local vehicle
    vehicle, vehicleNetId = getDriverVehicle(src, vehicleNetId)
    if not vehicle or not isVehicleNearSpike(vehicle, spikeData, Config.CrossingProgressDistance) then return end

    local groupKey = tostring(getGroupId(spikeData, netId))
    local groupState = triggeredGroups[groupKey]
    if not groupState then return end

    local activeVehicle = groupState.activeVehicles[tostring(vehicleNetId)]
    if not activeVehicle or activeVehicle.entity ~= vehicle or activeVehicle.source ~= src then return end

    local currentTime = GetGameTimer()
    activeVehicle.lastProgressAt = currentTime
    extendCrossingDeadline(spikeData, currentTime)
end)

RegisterNetEvent('V.Spike:CrossingComplete', function(netId, vehicleNetId)
    local src = source
    netId = tonumber(netId) or netId
    local spikeData = serverSpikes[netId]
    if not spikeData then return end

    local vehicle
    vehicle, vehicleNetId = getDriverVehicle(src, vehicleNetId)
    if not vehicle or not isVehicleNearSpike(vehicle, spikeData) then return end

    local groupKey = tostring(getGroupId(spikeData, netId))
    local groupState = triggeredGroups[groupKey]
    if not groupState then return end

    local vehicleKey = tostring(vehicleNetId)
    local activeVehicle = groupState.activeVehicles[vehicleKey]
    if not activeVehicle or activeVehicle.entity ~= vehicle or activeVehicle.source ~= src then return end

    groupState.activeVehicles[vehicleKey] = nil
    groupState.activityVersion = groupState.activityVersion + 1
    TriggerClientEvent('V.Spike:CrossingAccepted', src, getGroupId(spikeData, netId), vehicleNetId)
    scheduleTriggeredGroupRemoval(groupKey)
end)

RegisterNetEvent('spike_strip:pickup', function(netId)
    local src = source
    netId = tonumber(netId) or netId
    local spikeData = serverSpikes[netId]
    if spikeData then
        local groupKey = tostring(getGroupId(spikeData, netId))
        local groupState = triggeredGroups[groupKey]
        if groupState and next(groupState.activeVehicles) then
            exports['lv_notify']:Notify(src, {
                title = 'V-Spike System',
                message = 'Không thể thu hồi spike khi xe đang cán qua',
                type = 'error'
            })
            return
        end

        local ped = GetPlayerPed(src)
        if ped == 0 or GetVehiclePedIsIn(ped, false) ~= 0 then return end

        local pedCoords = GetEntityCoords(ped)
        local spikeCoords = spikeData.coords
        local dx = pedCoords.x - spikeCoords.x
        local dy = pedCoords.y - spikeCoords.y
        local dz = pedCoords.z - spikeCoords.z
        if dx * dx + dy * dy + dz * dz > 16.0 then return end

        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer or not xPlayer.canCarryItem(spikeData.item, 1) then
            exports['lv_notify']:Notify(src, {
                title = 'V-Spike System',
                message = 'Túi đồ không đủ chỗ để thu hồi spike',
                type = 'error'
            })
            return
        end

        xPlayer.addInventoryItem(spikeData.item, 1)
        local idsToRemove = spikeData.related
        removeSpikeGroup(idsToRemove)
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local currentTime = GetGameTimer()
        local toRemove = {}

        for netId, spikeData in pairs(serverSpikes) do
            if spikeData.despawnTime and currentTime >= spikeData.despawnTime then
                table.insert(toRemove, netId)
            end
        end

        for _, netId in ipairs(toRemove) do
            if serverSpikes[netId] then
                local spikeData = serverSpikes[netId]
                local ids = spikeData.related
                if spikeData.triggered then
                    returnTriggeredSpike(spikeData)
                end
                removeSpikeGroup(ids)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local pending = pendingPlacements[src]
    if pending then
        pending.validating = false
        refundPendingPlacement(src, pending)
    end
    local groups = {}
    local seenGroups = {}
    local groupsToSchedule = {}

    for groupKey, groupState in pairs(triggeredGroups) do
        local removedActiveVehicle = false

        for vehicleKey, activeVehicle in pairs(groupState.activeVehicles) do
            if activeVehicle.source == src then
                groupState.activeVehicles[vehicleKey] = nil
                removedActiveVehicle = true
            end
        end

        if removedActiveVehicle then
            groupState.activityVersion = groupState.activityVersion + 1
            if not next(groupState.activeVehicles) then
                groupsToSchedule[#groupsToSchedule + 1] = groupKey
            end
        end
    end

    for _, spikeData in pairs(serverSpikes) do
        if spikeData.owner == src then
            if spikeData.triggered then
                spikeData.owner = 0
            else
                local groupId = spikeData.related[1]
                if not seenGroups[groupId] then
                    seenGroups[groupId] = true
                    table.insert(groups, spikeData.related)
                end
            end
        end
    end

    for _, ids in ipairs(groups) do
        removeSpikeGroup(ids)
    end

    for _, groupKey in ipairs(groupsToSchedule) do
        scheduleTriggeredGroupRemoval(groupKey)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for _, record in pairs(vehicleBurstSync) do
        if record.entity and DoesEntityExist(record.entity) then
            Entity(record.entity).state:set('vSpikeBurstTyres', nil, true)
        end
    end
end)
