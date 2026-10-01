local propModel = `p_ld_stinger_s`
local nearbySpikes = {}
local activeSpikes = {}
local localSpikeObjects = {}
local pendingPlacementNetIds = {}
local placementPending = false
local previousWheelPositions = {}
local previousWheelSampleAt = 0
local cachedVehicle = 0
local cachedWheels = {}
local cachedVehicleMinZ = 0.0
local reportedWheelHits = {}
local crossingSessions = {}
local acknowledgedBurstSequences = {}

local wheelDefinitions = {
    {bones = {'wheel_lf', 'wheel_f'}, tyreIndex = 0},
    {bones = {'wheel_rf'}, tyreIndex = 1},
    {bones = {'wheel_lm1', 'wheel_lm'}, tyreIndex = 2},
    {bones = {'wheel_rm1', 'wheel_rm'}, tyreIndex = 3},
    {bones = {'wheel_lr', 'wheel_r'}, tyreIndex = 4},
    {bones = {'wheel_rr'}, tyreIndex = 5},
    {bones = {'wheel_lm2'}, tyreIndex = 45},
    {bones = {'wheel_rm2'}, tyreIndex = 47},
}

local function resetVehicleTracking()
    previousWheelPositions = {}
    previousWheelSampleAt = 0
    cachedVehicle = 0
    cachedWheels = {}
    cachedVehicleMinZ = 0.0
    reportedWheelHits = {}
    crossingSessions = {}
end

local function getLocalOffsetFromHeading(origin, heading, worldCoords)
    local headingRad = math.rad(heading or 0.0)
    local delta = worldCoords - origin
    local rightX, rightY = math.cos(headingRad), math.sin(headingRad)
    local forwardX, forwardY = -math.sin(headingRad), math.cos(headingRad)

    return vector3(
        delta.x * rightX + delta.y * rightY,
        delta.x * forwardX + delta.y * forwardY,
        delta.z
    )
end

local function getSpikeObject(netId)
    local obj = localSpikeObjects[netId]
    if obj and DoesEntityExist(obj) and GetEntityModel(obj) == propModel then
        return obj
    end

    if NetworkDoesEntityExistWithNetworkId(netId) then
        obj = NetToObj(netId)
        if obj ~= 0 and DoesEntityExist(obj) and GetEntityType(obj) == 3
            and GetEntityModel(obj) == propModel then
            return obj
        end
    end

    return 0
end

local function getSpikeLocalPosition(spike, worldCoords)
    local obj = getSpikeObject(spike.netId)
    if obj ~= 0 then
        return GetOffsetFromEntityGivenWorldCoords(obj, worldCoords.x, worldCoords.y, worldCoords.z)
    end

    return getLocalOffsetFromHeading(spike.coords, spike.heading, worldCoords)
end

local function segmentIntersectsBounds(from, to, bounds)
    local tMin, tMax = 0.0, 1.0

    local function clipAxis(startValue, endValue, minValue, maxValue)
        local delta = endValue - startValue
        if math.abs(delta) < 0.0001 then
            return startValue >= minValue and startValue <= maxValue
        end

        local t1 = (minValue - startValue) / delta
        local t2 = (maxValue - startValue) / delta
        if t1 > t2 then
            t1, t2 = t2, t1
        end

        tMin = math.max(tMin, t1)
        tMax = math.min(tMax, t2)
        return tMin <= tMax
    end

    return clipAxis(from.x, to.x, bounds.minX, bounds.maxX)
        and clipAxis(from.y, to.y, bounds.minY, bounds.maxY)
        and clipAxis(from.z, to.z, bounds.minZ, bounds.maxZ)
end

local function resolveVehicleWheels(vehicle)
    if cachedVehicle == vehicle then
        return cachedWheels
    end

    resetVehicleTracking()
    cachedVehicle = vehicle
    local modelMin = GetModelDimensions(GetEntityModel(vehicle))
    cachedVehicleMinZ = modelMin.z

    for _, definition in ipairs(wheelDefinitions) do
        local boneIndex = -1

        for _, boneName in ipairs(definition.bones) do
            boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
            if boneIndex ~= -1 then
                break
            end
        end

        if boneIndex ~= -1 then
            cachedWheels[#cachedWheels + 1] = {
                boneIndex = boneIndex,
                tyreIndex = definition.tyreIndex
            }
        end
    end

    return cachedWheels
end

local function getWheelContactPosition(vehicle, wheel)
    local hubPosition = GetWorldPositionOfEntityBone(vehicle, wheel.boneIndex)
    local foundGround, groundZ = GetGroundZFor_3dCoord(
        hubPosition.x,
        hubPosition.y,
        hubPosition.z + 1.0,
        false
    )

    local groundDistance = foundGround and hubPosition.z - groundZ or nil
    if groundDistance and groundDistance >= -0.1
        and groundDistance <= Config.MaximumWheelGroundDistance then
        return vector3(hubPosition.x, hubPosition.y, groundZ + Config.WheelContactHeight)
    end

    local hubOffset = GetOffsetFromEntityGivenWorldCoords(
        vehicle,
        hubPosition.x,
        hubPosition.y,
        hubPosition.z
    )

    return GetOffsetFromEntityInWorldCoords(
        vehicle,
        hubOffset.x,
        hubOffset.y,
        cachedVehicleMinZ + Config.WheelContactHeight
    )
end

local function isLocalVehicleOwner(vehicle)
    return not NetworkGetEntityIsNetworked(vehicle)
        or NetworkGetEntityOwner(vehicle) == PlayerId()
end

local function applyBurstTyres(vehicle, payload)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        return false
    end

    if not isLocalVehicleOwner(vehicle) then
        return false
    end

    local tyres = payload and payload.tyres
    if type(tyres) ~= 'table' then
        return false
    end

    local allBurst = true

    for tyreIndex, shouldBurst in pairs(tyres) do
        tyreIndex = tonumber(tyreIndex)
        if shouldBurst and tyreIndex and not IsVehicleTyreBurst(vehicle, tyreIndex, false) then
            SetVehicleTyreBurst(vehicle, tyreIndex, true, 1000.0)
        end

        if shouldBurst and tyreIndex and not IsVehicleTyreBurst(vehicle, tyreIndex, false) then
            allBurst = false
        end
    end

    local sequence = tonumber(payload.sequence)
    if allBurst and sequence and not acknowledgedBurstSequences[sequence] then
        acknowledgedBurstSequences[sequence] = GetGameTimer()
        TriggerServerEvent('V.Spike:BurstAck', VehToNet(vehicle), sequence)
    end

    return allBurst
end

RegisterNetEvent('V.Spike:BurstTyre', function(vehicleNetId, payload)
    vehicleNetId = tonumber(vehicleNetId)
    if not vehicleNetId or type(payload) ~= 'table' then return end

    CreateThread(function()
        local timeout = GetGameTimer() + Config.BurstApplyRetry

        while GetGameTimer() < timeout do
            if NetworkDoesEntityExistWithNetworkId(vehicleNetId) then
                local vehicle = NetToVeh(vehicleNetId)
                if vehicle ~= 0 and DoesEntityExist(vehicle) then
                    if not isLocalVehicleOwner(vehicle) then return end
                    if applyBurstTyres(vehicle, payload) then
                        return
                    end
                end
            end

            Wait(100)
        end
    end)
end)

AddStateBagChangeHandler('vSpikeBurstTyres', nil, function(bagName, _, value)
    if type(value) ~= 'table' then return end

    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle == 0 or not DoesEntityExist(vehicle) or not isLocalVehicleOwner(vehicle) then
        return
    end

    CreateThread(function()
        local timeout = GetGameTimer() + Config.BurstApplyRetry

        while GetGameTimer() < timeout do
            if not DoesEntityExist(vehicle) or not isLocalVehicleOwner(vehicle) then return end
            if applyBurstTyres(vehicle, value) then return end

            Wait(100)
        end
    end)
end)

CreateThread(function()
    while true do
        Wait(250)

        local now = GetGameTimer()
        for sequence, acknowledgedAt in pairs(acknowledgedBurstSequences) do
            if now - acknowledgedAt > Config.BurstSyncDuration * 2 then
                acknowledgedBurstSequences[sequence] = nil
            end
        end

        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == playerPed then
            applyBurstTyres(vehicle, Entity(vehicle).state.vSpikeBurstTyres)
        end
    end
end)

local function deleteSpikeObject(netId, coords)
    local obj = localSpikeObjects[netId]
    if obj and DoesEntityExist(obj) and GetEntityModel(obj) ~= propModel then
        obj = nil
    end

    if (not obj or not DoesEntityExist(obj)) and NetworkDoesEntityExistWithNetworkId(netId) then
        local networkObject = NetToObj(netId)
        if networkObject ~= 0 and DoesEntityExist(networkObject) and GetEntityType(networkObject) == 3
            and GetEntityModel(networkObject) == propModel then
            obj = networkObject
        end
    end

    if (not obj or not DoesEntityExist(obj)) and coords then
        obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, 1.5, propModel, false, false, false)
    end

    if obj and obj ~= 0 and DoesEntityExist(obj) then
        SetEntityAsMissionEntity(obj, true, true)

        if NetworkGetEntityIsNetworked(obj) then
            local attempts = 0
            while not NetworkHasControlOfEntity(obj) and attempts < 20 do
                NetworkRequestControlOfEntity(obj)
                attempts = attempts + 1
                Wait(25)
            end
        end

        DeleteEntity(obj)
    end

    localSpikeObjects[netId] = nil
end

RegisterNetEvent('V.Spike:Sync', function(spikes)
    activeSpikes = spikes or {}
end)

RegisterNetEvent('V.Spike:CrossingAccepted', function(groupId, vehicleNetId)
    local groupKey = tostring(groupId)
    local session = crossingSessions[groupKey]
    if session and session.vehicleNetId == tonumber(vehicleNetId) then
        crossingSessions[groupKey] = nil
    end
end)

RegisterNetEvent('V.Spike:HitAccepted', function(groupId, vehicleNetId, tyreIndex)
    local groupHits = reportedWheelHits[tostring(groupId)]
    local vehicleHits = groupHits and groupHits[tonumber(vehicleNetId)]
    local hit = vehicleHits and vehicleHits[tonumber(tyreIndex)]

    if hit then
        hit.accepted = true
    end
end)

RegisterNetEvent('V.Spike:RegisterAccepted', function()
    pendingPlacementNetIds = {}
    placementPending = false
    exports['lv_notify']:Notify({
        title = 'V-Spike System',
        message = 'Spike đã được đặt ra',
        type = 'success'
    })
end)

RegisterNetEvent('V.Spike:RegisterRejected', function()
    local netIds = pendingPlacementNetIds
    pendingPlacementNetIds = {}
    placementPending = false

    CreateThread(function()
        for _, netId in ipairs(netIds) do
            deleteSpikeObject(netId)
        end
    end)
end)

CreateThread(function()
    TriggerServerEvent('V.Spike:RequestSync')
end)

CreateThread(function()
    while true do
        Wait(Config.NearbyRefresh)
        local playerPed = PlayerPedId()
        local coords = GetEntityCoords(playerPed)
        
        nearbySpikes = {}
        for netId, spikeData in pairs(activeSpikes) do
            local spikeCoords = vector3(spikeData.coords.x, spikeData.coords.y, spikeData.coords.z)
            if #(coords - spikeCoords) < 100.0 then
                table.insert(nearbySpikes, {
                    netId = tonumber(netId) or netId,
                    coords = spikeCoords,
                    heading = spikeData.heading or 0.0,
                    groupId = spikeData.groupId or (spikeData.related and spikeData.related[1]) or netId
                })
            end
        end
    end
end)

local function getNearbyGroupSpikes(groupKey, fallbackSpike)
    local groupSpikes = {}

    for _, spike in ipairs(nearbySpikes) do
        if tostring(spike.groupId) == groupKey then
            groupSpikes[#groupSpikes + 1] = spike
        end
    end

    if #groupSpikes == 0 and fallbackSpike then
        groupSpikes[1] = fallbackSpike
    end

    return groupSpikes
end

local function getCrossingAxis(previousLocal, currentLocal)
    if math.abs(currentLocal.y - previousLocal.y) > math.abs(currentLocal.x - previousLocal.x) then
        return 'y'
    end

    return 'x'
end

local function sendWheelHit(hit, vehicleNetId, tyreIndex, currentTime)
    hit.lastSentAt = currentTime
    TriggerServerEvent('V.Spike:Hit', hit.spikeNetId, vehicleNetId, tyreIndex)
end

CreateThread(function()
    while true do
        Wait(Config.HitRetryInterval)

        local currentTime = GetGameTimer()
        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        local currentVehicleNetId = vehicle ~= 0
            and GetPedInVehicleSeat(vehicle, -1) == playerPed
            and VehToNet(vehicle) or 0

        for _, vehicleGroups in pairs(reportedWheelHits) do
            for vehicleNetId, wheelHits in pairs(vehicleGroups) do
                for tyreIndex, hit in pairs(wheelHits) do
                    if not hit.accepted then
                        if currentTime - hit.startedAt > Config.HitRetryDuration then
                            wheelHits[tyreIndex] = nil
                        elseif tonumber(vehicleNetId) == currentVehicleNetId
                            and currentTime - hit.lastSentAt >= Config.HitRetryInterval then
                            sendWheelHit(hit, vehicleNetId, tyreIndex, currentTime)
                        end
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    RequestModel(propModel)
    while not HasModelLoaded(propModel) do Wait(10) end

    local min, max = GetModelDimensions(propModel)
    local bounds = {
        minX = min.x - Config.DetectionRadius,
        maxX = max.x + Config.DetectionRadius,
        minY = min.y - Config.DetectionLengthPadding,
        maxY = max.y + Config.DetectionLengthPadding,
        minZ = min.z - 0.15,
        maxZ = max.z + Config.DetectionHeight
    }

    while true do
        local sleep = 50
        local sampleTime = GetGameTimer()
        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false)

        for groupKey, session in pairs(crossingSessions) do
            if sampleTime - session.lastActivityAt > Config.CrossingTimeout then
                crossingSessions[groupKey] = nil
            end
        end

        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == playerPed then
            if #nearbySpikes > 0 then
                sleep = 50
                local vehCoords = GetEntityCoords(vehicle)
                local vehicleNetId = VehToNet(vehicle)
                local wheelSamples = {}
                local wheels = resolveVehicleWheels(vehicle)
                local canDetectContact = not IsEntityInAir(vehicle)
                local sampleIsFresh = previousWheelSampleAt > 0
                    and sampleTime - previousWheelSampleAt <= Config.MaximumSampleAge
                local maximumWheelTravel = Config.MaximumWheelTravel

                if sampleIsFresh then
                    local sampleSeconds = (sampleTime - previousWheelSampleAt) / 1000.0
                    maximumWheelTravel = math.max(
                        maximumWheelTravel,
                        GetEntitySpeed(vehicle) * sampleSeconds + Config.WheelTravelTolerance
                    )
                end
                maximumWheelTravel = math.min(maximumWheelTravel, Config.AbsoluteMaximumWheelTravel)

                local checkDistance = Config.VehicleCheckDistance + maximumWheelTravel
                local nearestSpikeDistance = math.huge
                for _, spike in ipairs(nearbySpikes) do
                    nearestSpikeDistance = math.min(nearestSpikeDistance, #(vehCoords - spike.coords))
                end

                local shouldSampleWheels = nearestSpikeDistance < checkDistance
                if not shouldSampleWheels and nearestSpikeDistance < Config.ServerValidationDistance then
                    for _, session in pairs(crossingSessions) do
                        if session.vehicleNetId == vehicleNetId then
                            shouldSampleWheels = true
                            break
                        end
                    end
                end

                if shouldSampleWheels then
                    for _, wheel in ipairs(wheels) do
                        wheelSamples[#wheelSamples + 1] = {
                            tyreIndex = wheel.tyreIndex,
                            position = getWheelContactPosition(vehicle, wheel)
                        }
                    end
                end

                for _, spike in ipairs(nearbySpikes) do
                    local spikeCoords = spike.coords
                    if #(vehCoords - spikeCoords) < checkDistance then
                        sleep = 0
                        local groupKey = tostring(spike.groupId)
                        reportedWheelHits[groupKey] = reportedWheelHits[groupKey] or {}
                        reportedWheelHits[groupKey][vehicleNetId] = reportedWheelHits[groupKey][vehicleNetId] or {}

                        for _, wheel in ipairs(wheelSamples) do
                            local previousPosition = previousWheelPositions[wheel.tyreIndex]

                            if canDetectContact and sampleIsFresh and previousPosition then
                                local travelled = #(wheel.position - previousPosition)
                                if travelled <= maximumWheelTravel then
                                    local previousLocal = getSpikeLocalPosition(spike, previousPosition)
                                    local currentLocal = getSpikeLocalPosition(spike, wheel.position)

                                    if segmentIntersectsBounds(previousLocal, currentLocal, bounds) then
                                        local hit = reportedWheelHits[groupKey][vehicleNetId][wheel.tyreIndex]
                                        if not hit then
                                            hit = {
                                                spikeNetId = spike.netId,
                                                startedAt = sampleTime,
                                                lastSentAt = sampleTime - Config.HitRetryInterval
                                            }
                                            reportedWheelHits[groupKey][vehicleNetId][wheel.tyreIndex] = hit
                                        end

                                        if not crossingSessions[groupKey] then
                                            crossingSessions[groupKey] = {
                                                spike = spike,
                                                vehicleNetId = vehicleNetId,
                                                axis = getCrossingAxis(previousLocal, currentLocal),
                                                lastActivityAt = sampleTime
                                            }
                                        end

                                        crossingSessions[groupKey].lastActivityAt = sampleTime
                                        if not IsVehicleTyreBurst(vehicle, wheel.tyreIndex, false) then
                                            SetVehicleTyreBurst(vehicle, wheel.tyreIndex, true, 1000.0)
                                        end

                                        if not hit.accepted
                                            and sampleTime - hit.lastSentAt >= Config.HitRetryInterval then
                                            sendWheelHit(hit, vehicleNetId, wheel.tyreIndex, sampleTime)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                for groupKey, session in pairs(crossingSessions) do
                    if session.vehicleNetId == vehicleNetId then
                        local groupSpikes = getNearbyGroupSpikes(groupKey, session.spike)
                        local allWheelsBelow = #wheelSamples > 0 and #groupSpikes > 0
                        local allWheelsAbove = #wheelSamples > 0 and #groupSpikes > 0
                        local nearGroup = false

                        for _, spike in ipairs(groupSpikes) do
                            if #(vehCoords - spike.coords) < Config.CrossingProgressDistance then
                                nearGroup = true
                            end

                            for _, wheel in ipairs(wheelSamples) do
                                local localPosition = getSpikeLocalPosition(spike, wheel.position)
                                local position = session.axis == 'y' and localPosition.y or localPosition.x
                                local minBound = session.axis == 'y' and bounds.minY or bounds.minX
                                local maxBound = session.axis == 'y' and bounds.maxY or bounds.maxX

                                if position >= minBound - Config.ClearancePadding then
                                    allWheelsBelow = false
                                end
                                if position <= maxBound + Config.ClearancePadding then
                                    allWheelsAbove = false
                                end
                            end
                        end

                        if allWheelsBelow or allWheelsAbove then
                            if not session.completionRequestedAt
                                or sampleTime - session.completionRequestedAt >= 500 then
                                session.completionRequestedAt = sampleTime
                                TriggerServerEvent('V.Spike:CrossingComplete', session.spike.netId, vehicleNetId)
                            end
                        elseif nearGroup then
                            session.lastActivityAt = sampleTime
                            if not session.progressSentAt
                                or sampleTime - session.progressSentAt >= Config.CrossingProgressInterval then
                                session.progressSentAt = sampleTime
                                TriggerServerEvent('V.Spike:CrossingProgress', session.spike.netId, vehicleNetId)
                            end
                        end
                    end
                end

                if shouldSampleWheels and canDetectContact then
                    for _, wheel in ipairs(wheelSamples) do
                        previousWheelPositions[wheel.tyreIndex] = wheel.position
                    end
                    previousWheelSampleAt = sampleTime
                elseif not shouldSampleWheels or not canDetectContact then
                    previousWheelPositions = {}
                    previousWheelSampleAt = 0
                end
            else
                previousWheelPositions = {}
                previousWheelSampleAt = 0
            end
        elseif cachedVehicle ~= 0 then
            resetVehicleTracking()
        end

        Wait(sleep)
    end
end)

local function spawnSpikeStrip(itemName)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local forward = GetEntityForwardVector(playerPed)
    local heading = GetEntityHeading(playerPed)

    RequestModel(propModel)
    while not HasModelLoaded(propModel) do Wait(10) end

    local spawnedNets = {}
    local spawnedObjects = {}
    local coordsList = {}
    local seenNetIds = {}

    local min, max = GetModelDimensions(propModel)
    local propLength = max.y - min.y
    local startDistance = 0.3
    
    local offsets = {
        coords + forward * (startDistance + propLength / 2),
        coords + forward * (startDistance + propLength / 2 + propLength),
        coords + forward * (startDistance + propLength / 2 + propLength * 2)
    }

    for _, pos in ipairs(offsets) do
        local prop = CreateObject(propModel, pos.x, pos.y, pos.z - 1.0, true, true, true)
        if prop == 0 or not DoesEntityExist(prop) then break end

        spawnedObjects[#spawnedObjects + 1] = prop
        PlaceObjectOnGroundProperly(prop)
        SetEntityHeading(prop, heading)
        FreezeEntityPosition(prop, true)
        SetEntityAsMissionEntity(prop, true, true)

        local netId = ObjToNet(prop)
        local timeout = GetGameTimer() + 1000
        while netId == 0 and GetGameTimer() < timeout do
            Wait(25)
            netId = ObjToNet(prop)
        end

        if netId == 0 or seenNetIds[netId] then break end

        seenNetIds[netId] = true
        localSpikeObjects[netId] = prop
        table.insert(spawnedNets, netId)
        table.insert(coordsList, GetEntityCoords(prop))
    end

    if #spawnedNets ~= 3 then
        pendingPlacementNetIds = {}
        placementPending = false
        for _, prop in ipairs(spawnedObjects) do
            if DoesEntityExist(prop) then
                local netId = ObjToNet(prop)
                if netId ~= 0 then localSpikeObjects[netId] = nil end
                DeleteEntity(prop)
            end
        end

        TriggerServerEvent('V.Spike:Register', {}, itemName, {}, heading)
        exports['lv_notify']:Notify({
            title = 'V-Spike System',
            message = 'Không thể tạo spike, đang hoàn lại vật phẩm',
            type = 'error'
        })
        return
    end

    pendingPlacementNetIds = spawnedNets
    TriggerServerEvent('V.Spike:Register', spawnedNets, itemName, coordsList, heading)
end

RegisterNetEvent('spike_strip:use', function(itemName)
    local playerPed = PlayerPedId()

    if placementPending then
        exports['lv_notify']:Notify({
            type = 'error',
            message = 'Spike trước đó vẫn đang được đồng bộ'
        })
        return
    end

    if IsPedInAnyVehicle(playerPed, false) then
        exports['lv_notify']:Notify({
            type = 'error',
            message = 'Bạn không thể đặt spike strip khi đang ở trong xe'
        })
        return
    end

    placementPending = true
    local success = lib.progressBar({
        duration = Config.PlaceDuration,
        label = 'Đang đặt spike',
        useWhileDead = false,
        canCancel = true,
        anim = {
            dict = 'pickup_object',
            clip = 'pickup_low'
        },
    })

    if success then
        TriggerServerEvent('spike_strip:removeItem', itemName)
        spawnSpikeStrip(itemName)
    else
        placementPending = false
        exports['lv_notify']:Notify({
            type = 'error',
            message = 'Quá trình đặt spike đã bị hủy bỏ'
        })
    end
end)

RegisterNetEvent('V.Spike:Remove', function(netIds, removeData)
    local removeSet = {}
    local removedGroups = {}
    local deleteQueue = {}

    for _, netId in ipairs(netIds) do
        local netIdString = tostring(netId)
        local spikeData = activeSpikes[netId] or activeSpikes[netIdString] or (removeData and (removeData[netId] or removeData[netIdString]))

        if spikeData then
            local groupId = spikeData.groupId or (spikeData.related and spikeData.related[1]) or netId
            removedGroups[tostring(groupId)] = true
        end

        activeSpikes[netId] = nil
        activeSpikes[netIdString] = nil
        removeSet[netId] = true
        removeSet[netIdString] = true

        table.insert(deleteQueue, {
            netId = netId,
            coords = spikeData and spikeData.coords
        })
    end

    local filteredSpikes = {}
    for _, spike in ipairs(nearbySpikes) do
        if not removeSet[spike.netId] and not removeSet[tostring(spike.netId)] then
            table.insert(filteredSpikes, spike)
        end
    end
    nearbySpikes = filteredSpikes

    for groupKey in pairs(removedGroups) do
        reportedWheelHits[groupKey] = nil
        crossingSessions[groupKey] = nil
    end

    for _, spike in ipairs(deleteQueue) do
        if spike.coords then
            deleteSpikeObject(spike.netId, vector3(spike.coords.x, spike.coords.y, spike.coords.z))
        else
            deleteSpikeObject(spike.netId)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for netId, obj in pairs(localSpikeObjects) do
        if obj and DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
        localSpikeObjects[netId] = nil
    end
end)

local function GetClosestSpike()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local closestSpike = nil
    local minDist = 3.0

    for _, spike in ipairs(nearbySpikes) do
        local dist = #(coords - spike.coords)
        if dist < minDist then
            minDist = dist
            closestSpike = spike
        end
    end
    
    return closestSpike
end

local textUIOpen = false

CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        if not IsPedInAnyVehicle(playerPed, false) then
            Wait(0)
            local closestSpike = GetClosestSpike()
            if closestSpike then
                if not textUIOpen then
                    lib.showTextUI('[E] - Thu hồi Spike', { position = 'right-center' })
                    textUIOpen = true
                end

                if IsControlJustReleased(0, 38) then
                    local success = lib.progressBar({
                        duration = Config.PickupDuration,
                        label = 'Đang thu hồi spike',
                        useWhileDead = false,
                        canCancel = false,
                        anim = {
                            dict = 'pickup_object',
                            clip = 'pickup_low'
                        },
                    })

                    if success then
                        TriggerServerEvent('spike_strip:pickup', closestSpike.netId)
                    end
                end
            else
                if textUIOpen then
                    lib.hideTextUI()
                    textUIOpen = false
                end
                Wait(500)
            end
        else
            if textUIOpen then
                lib.hideTextUI()
                textUIOpen = false
            end
            Wait(1000)
        end
    end
end)

exports('useSpike', function(data, slot)
    TriggerEvent('spike_strip:use', data.name)
end)
