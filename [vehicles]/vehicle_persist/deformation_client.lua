-- Adapted from Kiminaze/VehicleDeformation. See THIRD_PARTY_LICENSES/VehicleDeformation-LICENSE.md.
local deformationOffsets = {}
local applyGenerations = {}
local applyingVehicles = {}
local damageUpdates = {}
local locallyPublished = {}

local function getOption(key, fallback)
    local config = Config and Config.Deformation
    local value = type(config) == 'table' and config[key] or nil

    if value == nil then
        return fallback
    end

    return value
end

local function isEnabled()
    return getOption('Enabled', true) == true
end

local function isBlacklisted(vehicle)
    local blacklist = getOption('BlacklistedTypes', {})
    return type(blacklist) == 'table' and blacklist[GetVehicleType(vehicle)] == true
end

local function vectorLength(x, y, z)
    return math.sqrt(x * x + y * y + z * z)
end

local function clampVectorAlongAxis(value, axis)
    local axisLength = vectorLength(axis.x, axis.y, axis.z)

    if axisLength <= 0.000001 then
        return vector3(0.0, 0.0, 0.0)
    end

    local nx = axis.x / axisLength
    local ny = axis.y / axisLength
    local nz = axis.z / axisLength
    local projection = value.x * nx + value.y * ny + value.z * nz
    return vector3(nx * projection, ny * projection, nz * projection)
end

local function isPointTooFarFromVehicle(point, vehicle)
    local vehicleCoords = GetEntityCoords(vehicle)
    local worldPoint = GetOffsetFromEntityInWorldCoords(vehicle, point.x, point.y, point.z)
    local _, hit, position, normal, hitEntity = GetShapeTestResult(
        StartExpensiveSynchronousShapeTestLosProbe(
            worldPoint.x,
            worldPoint.y,
            worldPoint.z,
            vehicleCoords.x,
            vehicleCoords.y,
            vehicleCoords.z,
            2,
            0,
            0
        )
    )

    if not hit or hitEntity ~= vehicle then
        return true
    end

    local direction = worldPoint - position
    local directionLength = #direction
    local normalLength = #normal

    if directionLength <= 0.000001 or normalLength <= 0.000001 then
        return false
    end

    local dot = (direction.x * normal.x + direction.y * normal.y + direction.z * normal.z)
        / (directionLength * normalLength)
    return 1.0 - dot > (tonumber(getOption('AngleThreshold', 0.5)) or 0.5)
end

local function getDeformationOffsets(vehicle)
    local model = GetEntityModel(vehicle)

    if deformationOffsets[model] then
        return deformationOffsets[model]
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local temporaryVehicle = CreateVehicle(model, playerCoords.x, playerCoords.y, playerCoords.z - 50.0, 0.0, false, false)

    if temporaryVehicle == 0 or not DoesEntityExist(temporaryVehicle) then
        return {}
    end

    FreezeEntityPosition(temporaryVehicle, true)
    SetEntityCollision(temporaryVehicle, false, false)
    SetEntityAlpha(temporaryVehicle, 0, false)

    local minimum, maximum = GetModelDimensions(model)
    local points = {}

    for x = -1, 1, 0.25 do
        for y = 1, -1, -0.25 do
            for z = -1, 1, 0.5 do
                if (y < -0.55 or y > 0.55) and z > -0.6 then
                    points[#points + 1] = vector3(
                        (maximum.x - minimum.x) * x * 0.5 + (maximum.x + minimum.x) * 0.5,
                        (maximum.y - minimum.y) * y * 0.5 + (maximum.y + minimum.y) * 0.5,
                        (maximum.z - minimum.z) * z * 0.5 + (maximum.z + minimum.z) * 0.5
                    )
                end
            end
        end
    end

    for index = #points, 1, -1 do
        if isPointTooFarFromVehicle(points[index], temporaryVehicle) then
            table.remove(points, index)
        end
    end

    SetEntityAsMissionEntity(temporaryVehicle, true, true)
    DeleteVehicle(temporaryVehicle)
    deformationOffsets[model] = points
    return points
end

local function getVehicleDeformation(vehicle)
    if not isEnabled() or vehicle == 0 or not DoesEntityExist(vehicle) or isBlacklisted(vehicle) then
        return {}
    end

    local threshold = tonumber(getOption('DamageThreshold', 0.05)) or 0.05
    local points = {}

    for _, offset in ipairs(getDeformationOffsets(vehicle)) do
        local nativeValue = GetVehicleDeformationAtPos(vehicle, offset.x, offset.y, offset.z)
        local projected = clampVectorAlongAxis(nativeValue, -offset)

        if #projected > threshold then
            points[#points + 1] = {
                offset.x,
                offset.y,
                offset.z,
                projected.x,
                projected.y,
                projected.z,
            }
        end
    end

    return VehiclePersistDeformation.Normalize(points) or {}
end

local function cancelApply(vehicle)
    applyGenerations[vehicle] = (applyGenerations[vehicle] or 0) + 1
    applyingVehicles[vehicle] = nil
    return applyGenerations[vehicle]
end

local function applyDeformation(vehicle, input, callback)
    local points = VehiclePersistDeformation.Normalize(input)

    if not points or vehicle == 0 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then
        return false
    end

    local generation = cancelApply(vehicle)

    if #points == 0 then
        SetVehicleDeformationFixed(vehicle)

        if callback then
            callback(true)
        end

        return true
    end

    applyingVehicles[vehicle] = generation

    CreateThread(function()
        local forces = {}
        local initialDamage = tonumber(getOption('InitialDamage', 50.0)) or 50.0
        local increment = tonumber(getOption('DamageIncrement', 5.0)) or 5.0
        local maxIterations = math.max(1, math.floor(tonumber(getOption('MaxApplyIterations', 50)) or 50))

        for iteration = 1, maxIterations do
            if applyGenerations[vehicle] ~= generation or not DoesEntityExist(vehicle) then
                return
            end

            local needsMore = false

            for index = 1, #points do
                if applyGenerations[vehicle] ~= generation or not DoesEntityExist(vehicle) then
                    return
                end

                local point = points[index]
                local offset = vector3(point[1], point[2], point[3])
                local current = GetVehicleDeformationAtPos(vehicle, point[1], point[2], point[3])
                local clamped = clampVectorAlongAxis(current, -offset)
                local targetLength = vectorLength(point[4], point[5], point[6])

                if #clamped + 0.0001 < targetLength then
                    forces[index] = (forces[index] or initialDamage - increment) + increment
                    SetVehicleDamage(vehicle, point[1], point[2], point[3], forces[index], forces[index], true)
                    needsMore = true
                    Wait(0)
                end
            end

            if not needsMore then
                break
            end

            Wait(0)
        end

        if applyGenerations[vehicle] == generation then
            applyingVehicles[vehicle] = nil

            if callback then
                callback(true)
            end
        end
    end)

    return true
end

local function publishDeformation(vehicle, points)
    if not NetworkGetEntityIsNetworked(vehicle) then
        return false
    end

    local canonical, signature = VehiclePersistDeformation.Normalize(points)

    if not canonical then
        return false
    end

    if VehiclePersistDeformation.Signature(Entity(vehicle).state.deformation) == signature then
        locallyPublished[vehicle] = nil
        return true
    end

    locallyPublished[vehicle] = signature
    Entity(vehicle).state:set('deformation', #canonical > 0 and canonical or nil, true)
    return true
end

local function setVehicleDeformation(vehicle, input, callback)
    local points = VehiclePersistDeformation.Normalize(input)

    if not points or not applyDeformation(vehicle, points, callback) then
        return false
    end

    if not isBlacklisted(vehicle) then
        publishDeformation(vehicle, points)
    end

    return true
end

local function requestControl(vehicle)
    if not NetworkGetEntityIsNetworked(vehicle) then
        return false
    end

    local timeout = GetGameTimer() + 1000
    NetworkRequestControlOfEntity(vehicle)

    while NetworkGetEntityOwner(vehicle) ~= PlayerId() and GetGameTimer() < timeout do
        Wait(0)
        NetworkRequestControlOfEntity(vehicle)
    end

    return NetworkGetEntityOwner(vehicle) == PlayerId()
end

local function fixVehicleDeformation(vehicle)
    if not isEnabled() or vehicle == 0 or not DoesEntityExist(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then
        return false
    end

    requestControl(vehicle)
    cancelApply(vehicle)
    SetVehicleDeformationFixed(vehicle)
    publishDeformation(vehicle, {})
    TriggerServerEvent('vehicle_persist:server:fixDeformation', VehToNet(vehicle))
    return true
end

AddStateBagChangeHandler('deformation', '', function(bagName, _, value)
    CreateThread(function()
        local vehicle = 0
        local timeout = GetGameTimer() + 5000

        while (vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeout do
            vehicle = GetEntityFromStateBagName(bagName)
            Wait(100)
        end

        if vehicle == 0 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then
            return
        end

        local points, signature = VehiclePersistDeformation.Normalize(value)

        if not points then
            return
        end

        if VehiclePersistDeformation.Signature(Entity(vehicle).state.deformation) ~= signature then
            return
        end

        if locallyPublished[vehicle] == signature then
            locallyPublished[vehicle] = nil
            return
        end

        applyDeformation(vehicle, points)
    end)
end)

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not isEnabled() then
        return
    end

    local vehicle = args[1]

    if vehicle == 0 or not IsEntityAVehicle(vehicle) or isBlacklisted(vehicle) or applyingVehicles[vehicle] then
        return
    end

    local deadline = GetGameTimer() + math.max(0, tonumber(getOption('CaptureDelay', 1000)) or 1000)
    damageUpdates[vehicle] = deadline

    CreateThread(function()
        while damageUpdates[vehicle] and damageUpdates[vehicle] > GetGameTimer() do
            Wait(50)
        end

        if damageUpdates[vehicle] ~= deadline then
            return
        end

        damageUpdates[vehicle] = nil

        if DoesEntityExist(vehicle)
            and NetworkGetEntityOwner(vehicle) == PlayerId()
            and not applyingVehicles[vehicle] then
            publishDeformation(vehicle, getVehicleDeformation(vehicle))
        end
    end)
end)

exports('GetVehicleDeformation', getVehicleDeformation)
exports('SetVehicleDeformation', setVehicleDeformation)
exports('FixVehicleDeformation', fixVehicleDeformation)
exports('IsDeformationWorse', VehiclePersistDeformation.IsWorse)
exports('IsDeformationEqual', VehiclePersistDeformation.IsEqual)
exports('GetDeformationOffsets', getDeformationOffsets)
