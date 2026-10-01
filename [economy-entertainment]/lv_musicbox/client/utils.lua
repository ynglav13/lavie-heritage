local function getLocalePack()
    return Locales[Config.Locale] or Locales.en or {}
end

function LVMusic.L(key, ...)
    local pack = getLocalePack()
    local fallback = Locales.en or {}
    local text = pack[key] or fallback[key] or key

    if select('#', ...) > 0 then
        return text:format(...)
    end
    return text
end

function LVMusic.Notify(message, notifyType)
    if Config.Notification.useLvNotify and GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(
        {
            title = Config.Notification.title,
            message = message,
            type = notifyType or 'inform'
        })
        return
    end

    lib.notify(
    {
        title = Config.Notification.title,
        description = message,
        type = notifyType or 'inform'
    })
end

function LVMusic.Debug(...)
    if Config.Debug then
        print(('[%s]'):format(GetCurrentResourceName()), ...)
    end
end

function LVMusic.Clamp(value, min, max)
    value = tonumber(value) or min

    if value < min then
        return min
    end

    if value > max then
        return max
    end
    return value
end

function LVMusic.ToVec3(coords)
    if not coords then
        return nil
    end
    return vector3(
        tonumber(coords.x) or 0.0,
        tonumber(coords.y) or 0.0,
        tonumber(coords.z) or 0.0
    )
end

function LVMusic.FromVec3(coords)
    if not coords then
        return nil
    end
    return
    {
        x = coords.x + 0.0,
        y = coords.y + 0.0,
        z = coords.z + 0.0
    }
end

function LVMusic.RequestModel(model)
    local modelHash = type(model) == 'number' and model or joaat(model)

    if not IsModelInCdimage(modelHash) then
        return false
    end

    RequestModel(modelHash)

    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(modelHash) do
        Wait(10)

        if GetGameTimer() > timeout then
            return false
        end
    end
    return modelHash
end

function LVMusic.RequestControl(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    if not NetworkGetEntityIsNetworked(entity) then
        return true
    end

    local timeout = GetGameTimer() + 1500

    NetworkRequestControlOfEntity(entity)

    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
        Wait(10)

        NetworkRequestControlOfEntity(entity)
    end
    return NetworkHasControlOfEntity(entity)
end

function LVMusic.RotationToDirection(rotation)
    local z = math.rad(rotation.z)
    local x = math.rad(rotation.x)
    local cosX = math.abs(math.cos(x))
    return vector3(
        -math.sin(z) * cosX,
        math.cos(z) * cosX,
        math.sin(x)
    )
end

function LVMusic.LocalePayload()
    local pack = getLocalePack()
    local fallback = Locales.en or {}
    local payload = {}

    for key, value in pairs(fallback) do
        payload[key] = value
    end

    for key, value in pairs(pack) do
        payload[key] = value
    end
    return payload
end
