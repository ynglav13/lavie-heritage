-- Adapted from Kiminaze/VehicleDeformation. See THIRD_PARTY_LICENSES/VehicleDeformation-LICENSE.md.
VehiclePersistDeformation = VehiclePersistDeformation or {}

local function getOption(key, fallback)
    local config = Config and Config.Deformation
    local value = type(config) == 'table' and config[key] or nil

    if value == nil then
        return fallback
    end

    return value
end

local function isFinite(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function round(value)
    local decimals = math.max(0, math.floor(tonumber(getOption('DecimalPlaces', 4)) or 4))
    local multiplier = 10 ^ decimals

    if value >= 0 then
        return math.floor(value * multiplier + 0.5) / multiplier
    end

    return math.ceil(value * multiplier - 0.5) / multiplier
end

local function readVector(value)
    if value == nil then
        return nil
    end

    local valueType = type(value)

    if valueType ~= 'table'
        and valueType ~= 'vector2'
        and valueType ~= 'vector3'
        and valueType ~= 'vector4' then
        return nil
    end

    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    local maxComponent = tonumber(getOption('MaxVectorComponent', 50.0)) or 50.0

    if not isFinite(x) or not isFinite(y) or not isFinite(z)
        or math.abs(x) > maxComponent
        or math.abs(y) > maxComponent
        or math.abs(z) > maxComponent then
        return nil
    end

    return round(x), round(y), round(z)
end

local function normalizePoint(point)
    if type(point) ~= 'table' then
        return nil
    end

    if point[6] ~= nil then
        local x, y, z = readVector(point)
        local dx = tonumber(point[4])
        local dy = tonumber(point[5])
        local dz = tonumber(point[6])
        local maxComponent = tonumber(getOption('MaxVectorComponent', 50.0)) or 50.0

        if not x or not isFinite(dx) or not isFinite(dy) or not isFinite(dz)
            or math.abs(dx) > maxComponent
            or math.abs(dy) > maxComponent
            or math.abs(dz) > maxComponent then
            return nil
        end

        return { x, y, z, round(dx), round(dy), round(dz) }
    end

    local x, y, z = readVector(point[1])
    local dx, dy, dz = readVector(point[2])

    if not x or not dx then
        return nil
    end

    return { x, y, z, dx, dy, dz }
end

function VehiclePersistDeformation.Normalize(input)
    if input == nil then
        return {}
    end

    if type(input) ~= 'table' then
        return nil
    end

    local maxPoints = math.max(1, math.floor(tonumber(getOption('MaxPoints', 128)) or 128))

    if #input > maxPoints then
        return nil
    end

    local output = {}

    for index = 1, #input do
        local point = normalizePoint(input[index])

        if not point then
            return nil
        end

        output[#output + 1] = point
    end

    local ok, encoded = pcall(json.encode, output)
    local maxBytes = math.max(256, tonumber(getOption('MaxEncodedBytes', 8192)) or 8192)

    if not ok or #encoded > maxBytes then
        return nil
    end

    return output, encoded
end

function VehiclePersistDeformation.Signature(input)
    local normalized, encoded = VehiclePersistDeformation.Normalize(input)
    return normalized and encoded or nil
end

local function magnitudeSquared(point)
    return point[4] * point[4] + point[5] * point[5] + point[6] * point[6]
end

local function pointKey(point)
    return ('%.4f:%.4f:%.4f'):format(point[1], point[2], point[3])
end

function VehiclePersistDeformation.IsWorse(newValue, oldValue)
    local newPoints = VehiclePersistDeformation.Normalize(newValue)
    local oldPoints = VehiclePersistDeformation.Normalize(oldValue)

    if not newPoints or not oldPoints then
        return false
    end

    local oldByPosition = {}

    for index = 1, #oldPoints do
        local point = oldPoints[index]
        oldByPosition[pointKey(point)] = magnitudeSquared(point)
    end

    for index = 1, #newPoints do
        local point = newPoints[index]
        local oldMagnitude = oldByPosition[pointKey(point)]

        if not oldMagnitude or magnitudeSquared(point) > oldMagnitude + 0.000001 then
            return true
        end
    end

    return false
end

function VehiclePersistDeformation.IsEqual(firstValue, secondValue)
    local firstSignature = VehiclePersistDeformation.Signature(firstValue)
    local secondSignature = VehiclePersistDeformation.Signature(secondValue)
    return firstSignature ~= nil and firstSignature == secondSignature
end
