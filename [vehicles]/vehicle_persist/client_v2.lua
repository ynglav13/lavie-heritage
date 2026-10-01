local activeVehicle = 0
local trackingGeneration = 0
local lastSnapshots = {}

local function getConfig(path, fallback)
    local value = Config

    for _, key in ipairs(path) do
        if type(value) ~= 'table' then
            return fallback
        end

        value = value[key]
    end

    if value == nil then
        return fallback
    end

    return value
end

local function isNetworkedVehicle(vehicle)
    return vehicle ~= 0
        and DoesEntityExist(vehicle)
        and IsEntityAVehicle(vehicle)
        and NetworkGetEntityIsNetworked(vehicle)
end

local function isVehicleClassBlacklisted(vehicle)
    local classes = getConfig({ 'Blacklist', 'Classes' }, {})

    if type(classes) ~= 'table' then
        return false
    end

    local class = GetVehicleClass(vehicle)

    if type(class) ~= 'number' then
        return false
    end

    if classes[class] == true or classes[tostring(class)] == true then
        return true
    end

    for key, value in pairs(classes) do
        if type(key) == 'number' and tonumber(value) == class then
            return true
        end
    end

    return false
end

local function normalizePlate(value)
    if type(value) ~= 'string' then
        return nil
    end

    local plate = value:match('^%s*(.-)%s*$')

    if not plate or plate == '' then
        return nil
    end

    return plate:upper()
end

local function isModelBlacklisted(model)
    local models = getConfig({ 'Blacklist', 'Models' }, {})

    if type(models) ~= 'table' then
        return false
    end

    for key, configured in pairs(models) do
        local entry
        local enabled

        if type(key) == 'number' and configured == true then
            entry = key
            enabled = true
        elseif type(key) == 'number' then
            entry = configured
            enabled = true
        else
            entry = key
            enabled = configured == true
        end

        if enabled then
            if type(entry) == 'number' and entry == model then
                return true
            end

            if type(entry) == 'string' and (tonumber(entry) == model or joaat(entry) == model) then
                return true
            end
        end
    end

    return false
end

local function isPlateBlacklisted(plate)
    local plates = getConfig({ 'Blacklist', 'Plates' }, {})

    if type(plates) ~= 'table' or not plate then
        return false
    end

    for key, configured in pairs(plates) do
        local entry = type(key) == 'number' and configured or key
        local enabled = type(key) == 'number' or configured == true

        if enabled and type(entry) == 'string' then
            local normalized = normalizePlate(entry)

            if normalized and normalized == plate then
                return true
            end

            if entry:find('*', 1, true) then
                local pattern = '^' .. entry:upper():gsub('([^%w%*])', '%%%1'):gsub('%*', '.*') .. '$'

                if plate:match(pattern) then
                    return true
                end
            end
        end
    end

    return false
end

local function isVehicleBlacklisted(vehicle)
    return isVehicleClassBlacklisted(vehicle)
        or isModelBlacklisted(GetEntityModel(vehicle))
        or isPlateBlacklisted(normalizePlate(GetVehicleNumberPlateText(vehicle)))
end

local function callVehicleNative(name, ...)
    local native = _G[name]

    if type(native) ~= 'function' then
        return false
    end

    return pcall(native, ...)
end

local function getVehicleRuntime(vehicle)
    local runtime =
    {
        engineOn = GetIsVehicleEngineRunning(vehicle) == true
    }

    local ok, value = callVehicleNative('GetLandingGearState', vehicle)

    if ok and type(value) == 'number' then
        runtime.landingGear = math.floor(value)
    end

    ok, value = callVehicleNative('GetVehicleVtolPosition', vehicle)

    if ok and type(value) == 'number' then
        runtime.vtolPosition = value
    end

    ok, value = callVehicleNative('IsBoatAnchoredAndFrozen', vehicle)

    if ok and type(value) == 'boolean' then
        runtime.boatAnchored = value
    end

    ok, value = callVehicleNative('GetConvertibleRoofState', vehicle)

    if ok and type(value) == 'number' then
        runtime.convertibleRoof = math.floor(value)
    end

    return runtime
end

local function restoreVehicleRuntime(vehicle, runtime)
    if type(runtime) ~= 'table' then
        return
    end

    if runtime.engineOn ~= nil then
        SetVehicleEngineOn(vehicle, runtime.engineOn == true, true, true)
    end

    local landingGear = tonumber(runtime.landingGear)

    if landingGear and landingGear >= 0 and landingGear <= 3 then
        callVehicleNative('ControlLandingGear', vehicle, math.floor(landingGear))
    end

    local vtolPosition = tonumber(runtime.vtolPosition)

    if vtolPosition then
        callVehicleNative('SetVehicleVtolPosition', vehicle, vtolPosition)
    end

    if type(runtime.boatAnchored) == 'boolean' then
        callVehicleNative('SetBoatAnchor', vehicle, runtime.boatAnchored)
    end

    local convertibleRoof = tonumber(runtime.convertibleRoof)

    if convertibleRoof then
        if convertibleRoof >= 2 then
            callVehicleNative('LowerConvertibleRoof', vehicle, true)
        else
            callVehicleNative('RaiseConvertibleRoof', vehicle, true)
        end
    end
end

local function getPersistedStateBags(vehicle)
    local keys = getConfig({ 'Tracking', 'PersistedStateBagKeys' }, {})

    if type(keys) ~= 'table' then
        return nil
    end

    local state = Entity(vehicle).state
    local output = {}

    for key, configured in pairs(keys) do
        local stateKey = type(key) == 'number' and configured or key
        local enabled = type(key) == 'number' or configured == true

        if enabled and type(stateKey) == 'string' and stateKey ~= '' then
            local value = state[stateKey]

            if value ~= nil then
                local ok, encoded = pcall(json.encode, value)

                if ok and #encoded <= 8192 then
                    output[stateKey] = value
                end
            end
        end
    end

    return next(output) and output or nil
end

local function getAttachedTrailer(vehicle)
    local ok, hasTrailer, trailer = callVehicleNative('GetVehicleTrailer', vehicle)

    if not ok then
        return false, 0
    end

    if isNetworkedVehicle(hasTrailer) and trailer == nil then
        return true, hasTrailer
    end

    if not hasTrailer or not isNetworkedVehicle(trailer) then
        return false, 0
    end

    return true, trailer
end

local function getAttachedTrailerNetId(vehicle)
    local hasTrailer, trailer = getAttachedTrailer(vehicle)

    if not hasTrailer then
        return 0
    end

    local netId = VehToNet(trailer)
    return netId > 0 and netId or 0
end

local function getTrailerSnapshot(vehicle)
    local hasTrailer, trailer = getAttachedTrailer(vehicle)

    if not hasTrailer or isVehicleBlacklisted(trailer) then
        return nil
    end

    local props = lib.getVehicleProperties(trailer)

    if type(props) ~= 'table' then
        return nil
    end

    local coords = GetEntityCoords(trailer)

    local netId = VehToNet(trailer)

    if netId == 0 then
        return nil
    end

    local runtime = getVehicleRuntime(trailer)

    return
    {
        netId = netId,
        plate = GetVehicleNumberPlateText(trailer),
        model = GetEntityModel(trailer),
        vehicleClass = GetVehicleClass(trailer),
        coords =
        {
            x = coords.x,
            y = coords.y,
            z = coords.z
        },
        heading = GetEntityHeading(trailer),
        props = props,
        stateBags = getPersistedStateBags(trailer),
        engineOn = runtime.engineOn,
        runtime = runtime
    }
end

local function canSnapshot(vehicle, reason, state)
    if not isNetworkedVehicle(vehicle) then
        return false
    end

    if isVehicleBlacklisted(vehicle) then
        return false
    end

    local stateBag = Entity(vehicle).state

    if stateBag.vehiclePersistIgnore == true or stateBag.vehiclePersistSpawning == true then
        return false
    end

    local ped = PlayerPedId()
    local isDriver = GetPedInVehicleSeat(vehicle, -1) == ped
    local isNetworkOwner = NetworkGetEntityOwner(vehicle) == cache.playerId
    local wasDriver = state and state.wasDriver == true

    if getConfig({ 'Tracking', 'RequireDriver' }, false)
        and not isDriver
        and not (reason == 'exit' and wasDriver) then
        return false
    end

    return true, isDriver, isNetworkOwner
end

local function sendSnapshot(vehicle, reason, forceFullState, respectRateLimit)
    local state = lastSnapshots[vehicle] or {}
    local canSend, isDriver, isNetworkOwner = canSnapshot(vehicle, reason, state)

    if not canSend then
        return false
    end

    local now = GetGameTimer()
    local minInterval = getConfig({ 'Tracking', 'SnapshotMinInterval' }, 5000)

    if (not forceFullState or respectRateLimit) and state.lastAttempt and now - state.lastAttempt < minInterval then
        return false
    end

    if isDriver then
        state.wasDriver = true
    end

    if isNetworkOwner then
        state.wasNetworkOwner = true
    end

    local fullInterval = getConfig({ 'Tracking', 'FullPropertiesInterval' }, 120000)
    local retryInterval = getConfig({ 'Tracking', 'FullSnapshotRetryInterval' }, 15000)
    local firstFullState = not state.lastFull and not state.fullPendingAt
    local retryFullState = state.fullPendingAt and now - state.fullPendingAt >= retryInterval
    local scheduledFullState = state.lastFull and now - state.lastFull >= fullInterval
    local canSendFullState = isDriver
        or isNetworkOwner
        or (reason == 'exit' and (state.wasDriver == true or state.wasNetworkOwner == true))
    local fullState = canSendFullState
        and (forceFullState or firstFullState or retryFullState or scheduledFullState)
    local hasTrailer, trailer = getAttachedTrailer(vehicle)
    local trailerNetId = hasTrailer and VehToNet(trailer) or 0

    if trailerNetId == 0 then
        hasTrailer = false
    end

    local hasPersistableTrailer = hasTrailer and not isVehicleClassBlacklisted(trailer)
    local payload =
    {
        netId = VehToNet(vehicle),
        reason = reason,
        fullState = fullState,
        vehicleClass = GetVehicleClass(vehicle),
        hasTrailer = hasPersistableTrailer
    }

    if payload.netId == 0 then
        return false
    end

    if fullState then
        local props = lib.getVehicleProperties(vehicle)

        if type(props) ~= 'table' then
            state.lastAttempt = now
            lastSnapshots[vehicle] = state
            return false
        end

        local runtime = getVehicleRuntime(vehicle)

        payload.props = props
        payload.stateBags = getPersistedStateBags(vehicle)
        payload.engineOn = runtime.engineOn
        payload.runtime = runtime
        payload.trailer = getTrailerSnapshot(vehicle)

        local ok, encoded = pcall(json.encode, payload)
        local maxBytes = getConfig({ 'Tracking', 'SnapshotMaxBytes' }, 60000)

        if not ok or #encoded > maxBytes then
            state.lastAttempt = now
            lastSnapshots[vehicle] = state
            return false
        end

        state.fullPendingAt = now
        state.trailerNetId = trailerNetId
    end

    local coords = GetEntityCoords(vehicle)
    state.netId = payload.netId
    state.lastAttempt = now
    state.lastSent = now
    state.coords =
    {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }
    lastSnapshots[vehicle] = state

    TriggerServerEvent('vehicle_persist:server:saveVehicleSnapshot', payload)
    return true, fullState
end

local function startVehicleTracking(vehicle)
    if not isNetworkedVehicle(vehicle)
        or isVehicleBlacklisted(vehicle)
        or Entity(vehicle).state.vehiclePersistIgnore == true then
        return
    end

    trackingGeneration = trackingGeneration + 1
    local generation = trackingGeneration
    activeVehicle = vehicle

    CreateThread(function()
        Wait(300)

        local spawnTransitionDeadline = GetGameTimer() + 15000

        while isNetworkedVehicle(vehicle)
            and Entity(vehicle).state.vehiclePersistSpawning == true
            and GetGameTimer() < spawnTransitionDeadline do
            Wait(100)
        end

        if generation ~= trackingGeneration or activeVehicle ~= vehicle or not isNetworkedVehicle(vehicle) then
            return
        end

        if Entity(vehicle).state.vehiclePersistSpawning == true
            or Entity(vehicle).state.vehiclePersistIgnore == true then
            return
        end

        sendSnapshot(vehicle, 'enter', true)

        local interval = getConfig({ 'Tracking', 'ClientSnapshotInterval' }, 30000)
        local movementInterval = getConfig({ 'Tracking', 'PositionSnapshotInterval' }, 10000)
        local minDistance = getConfig({ 'Tracking', 'PositionDistance' }, 25.0)
        local minDistanceSquared = minDistance * minDistance

        while generation == trackingGeneration and activeVehicle == vehicle and cache.vehicle == vehicle do
            Wait(1000)

            if not isNetworkedVehicle(vehicle) or Entity(vehicle).state.vehiclePersistIgnore == true then
                break
            end

            local snapshot = lastSnapshots[vehicle]
            local now = GetGameTimer()
            local coords = GetEntityCoords(vehicle)
            local moved = false

            if snapshot and snapshot.coords then
                local x = coords.x - snapshot.coords.x
                local y = coords.y - snapshot.coords.y
                local z = coords.z - snapshot.coords.z
                moved = x * x + y * y + z * z >= minDistanceSquared
            else
                moved = true
            end

            local lastSent = snapshot and snapshot.lastSent or 0
            local regularDue = not snapshot or now - lastSent >= interval
            local movementDue = moved and (not snapshot or now - lastSent >= movementInterval)
            local fullRetryDue = snapshot
                and snapshot.fullPendingAt
                and now - snapshot.fullPendingAt >= getConfig({ 'Tracking', 'FullSnapshotRetryInterval' }, 15000)
            local trailerChanged = snapshot
                and snapshot.trailerNetId ~= nil
                and snapshot.trailerNetId ~= getAttachedTrailerNetId(vehicle)
            local canRefreshTrailer = GetPedInVehicleSeat(vehicle, -1) == PlayerPedId()
                or NetworkGetEntityOwner(vehicle) == cache.playerId

            if trailerChanged and canRefreshTrailer then
                sendSnapshot(vehicle, 'trailer', true, true)
            elseif regularDue or movementDue or fullRetryDue then
                sendSnapshot(vehicle, 'position', false)
            end
        end
    end)
end

lib.onCache('vehicle', function(vehicle)
    local previousVehicle = activeVehicle

    if previousVehicle ~= 0 and previousVehicle ~= vehicle and DoesEntityExist(previousVehicle) then
        sendSnapshot(previousVehicle, 'exit', true)
        lastSnapshots[previousVehicle] = nil
    end

    if vehicle and vehicle ~= 0 then
        startVehicleTracking(vehicle)
    else
        trackingGeneration = trackingGeneration + 1
        activeVehicle = 0
    end
end)

RegisterNetEvent('vehicle_persist:client:snapshotAccepted', function(netId)
    netId = tonumber(netId)

    if not netId or netId <= 0 then
        return
    end

    local now = GetGameTimer()

    for _, state in pairs(lastSnapshots) do
        if state.netId == netId then
            state.lastFull = now
            state.fullPendingAt = nil
        end
    end
end)

CreateThread(function()
    Wait(1000)

    if cache.vehicle and cache.vehicle ~= 0 then
        startVehicleTracking(cache.vehicle)
    end
end)

local function getVehiclePosition(vehicle)
    if type(vehicle) ~= 'number' then
        vehicle = cache.vehicle
    end

    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local coords = GetEntityCoords(vehicle)

        return
        {
            x = coords.x,
            y = coords.y,
            z = coords.z,
            heading = GetEntityHeading(vehicle)
        }
    end
end

exports('UpdateVehicle', function(vehicle)
    vehicle = vehicle or cache.vehicle
    return sendSnapshot(vehicle, 'export', true)
end)

exports('GetVehiclePosition', getVehiclePosition)
exports('GetVehicleCoords', getVehiclePosition)

local fadingEntities = {}

local function fadeEntityIn(entity, options)
    if entity == 0 or not DoesEntityExist(entity) then
        return
    end

    local startAlpha = math.floor(tonumber(options and options.startAlpha) or 190)
    local duration = math.floor(tonumber(options and options.duration) or 450)
    local step = math.floor(tonumber(options and options.step) or 25)

    startAlpha = math.max(0, math.min(254, startAlpha))
    duration = math.max(250, duration)
    step = math.max(1, step)

    local token = (fadingEntities[entity] or 0) + 1
    fadingEntities[entity] = token

    CreateThread(function()
        local alpha = startAlpha
        local waitTime = math.max(16, math.floor(duration / math.max(1, math.ceil((255 - startAlpha) / step))))

        SetEntityAlpha(entity, alpha, false)

        while fadingEntities[entity] == token and DoesEntityExist(entity) and alpha < 255 do
            Wait(waitTime)
            alpha = math.min(255, alpha + step)
            SetEntityAlpha(entity, alpha, false)
        end

        if fadingEntities[entity] == token then
            fadingEntities[entity] = nil
        end

        if DoesEntityExist(entity) then
            ResetEntityAlpha(entity)
        end
    end)
end

local function fadeEntityOut(entity, options)
    if entity == 0 or not DoesEntityExist(entity) then
        return
    end

    local endAlpha = math.floor(tonumber(options and options.endAlpha) or 0)
    local duration = math.floor(tonumber(options and options.duration) or 700)
    local step = math.floor(tonumber(options and options.step) or 35)

    endAlpha = math.max(0, math.min(254, endAlpha))
    duration = math.max(250, duration)
    step = math.max(1, step)

    local token = (fadingEntities[entity] or 0) + 1
    fadingEntities[entity] = token

    CreateThread(function()
        local alpha = 255
        local waitTime = math.max(16, math.floor(duration / math.max(1, math.ceil((255 - endAlpha) / step))))

        SetEntityAlpha(entity, alpha, false)

        while fadingEntities[entity] == token and DoesEntityExist(entity) and alpha > endAlpha do
            Wait(waitTime)
            alpha = math.max(endAlpha, alpha - step)
            SetEntityAlpha(entity, alpha, false)
        end

        if fadingEntities[entity] == token then
            fadingEntities[entity] = nil
        end
    end)
end

AddStateBagChangeHandler('vehiclePersistFadeIn', '', function(bagName, _, value)
    if value ~= nil and type(value) ~= 'table' then
        return
    end

    CreateThread(function()
        local entity = 0

        for _ = 1, 50 do
            entity = GetEntityFromStateBagName(bagName)

            if entity ~= 0 and DoesEntityExist(entity) then
                break
            end

            Wait(100)
        end

        if entity ~= 0 and DoesEntityExist(entity) and value ~= nil then
            fadeEntityIn(entity, value)
        end
    end)
end)

AddStateBagChangeHandler('vehiclePersistFadeOut', '', function(bagName, _, value)
    if value ~= nil and type(value) ~= 'table' then
        return
    end

    CreateThread(function()
        local entity = 0

        for _ = 1, 30 do
            entity = GetEntityFromStateBagName(bagName)

            if entity ~= 0 and DoesEntityExist(entity) then
                break
            end

            Wait(100)
        end

        if entity ~= 0 and DoesEntityExist(entity) and value ~= nil then
            fadeEntityOut(entity, value)
        end
    end)
end)

RegisterNetEvent('vehicle_persist:client:setWaypoint', function(coords)
    if type(coords) ~= 'table' then
        return
    end

    local x = tonumber(coords.x or coords[1])
    local y = tonumber(coords.y or coords[2])

    if not x or not y then
        return
    end

    SetNewWaypoint(x, y)
end)

local function getVehicleModelLabel(model)
    if type(model) == 'string' then
        model = tonumber(model) or joaat(model)
    end

    if type(model) ~= 'number' or model == 0 then
        return 'Unknown'
    end

    local displayName = GetDisplayNameFromVehicleModel(model)

    if type(displayName) ~= 'string' or displayName == '' or displayName == 'CARNOTFOUND' then
        return tostring(model)
    end

    local label = GetLabelText(displayName)

    if type(label) == 'string' and label ~= '' and label ~= 'NULL' then
        return label
    end

    return displayName
end

RegisterNetEvent('vehicle_persist:client:showVehiclesMenu', function(vehicles, isForAdmin)
    if type(vehicles) ~= 'table' or #vehicles == 0 then
        lib.notify({
            type = 'error',
            description = isForAdmin and 'Người chơi này không có xe' or 'Bạn không có xe'
        })
        return
    end

    local options = {}

    for _, vehicle in ipairs(vehicles) do
        local plate = normalizePlate(vehicle.plate)

        if plate then
            options[#options + 1] = {
                title = ('%s - %s'):format(plate, getVehicleModelLabel(vehicle.model or vehicle.modelName)),
                description = tostring(vehicle.status or 'Không rõ trạng thái'),
                onSelect = function()
                    if isForAdmin then
                        TriggerServerEvent('vehicle_persist:server:bringVehicleByPlate', plate)
                    else
                        TriggerServerEvent('vehicle_persist:server:locateVehicleByPlate', plate)
                    end
                end
            }
        end
    end

    if #options == 0 then
        return
    end

    local contextId = isForAdmin and 'vehicle_persist_admin_vehicles' or 'vehicle_persist_owned_vehicles'

    lib.registerContext({
        id = contextId,
        title = isForAdmin and 'Xe của người chơi' or 'Xe của bạn',
        options = options
    })

    lib.showContext(contextId)
end)

AddStateBagChangeHandler('vehiclePersistRestore', '', function(bagName, _, value)
    if type(value) ~= 'table' then
        return
    end

    CreateThread(function()
        local vehicle = 0

        for _ = 1, 50 do
            vehicle = GetEntityFromStateBagName(bagName)

            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                break
            end

            Wait(100)
        end

        if vehicle == 0 or not DoesEntityExist(vehicle) then
            return
        end

        for _ = 1, 20 do
            if NetworkGetEntityOwner(vehicle) == cache.playerId then
                local state = Entity(vehicle).state
                local propertiesTimeout = GetGameTimer() + 5000

                while state['ox_lib:setVehicleProperties'] ~= nil and GetGameTimer() < propertiesTimeout do
                    Wait(100)
                end

                if type(value.stateBags) == 'table' then
                    local deformation

                    for key, stateValue in pairs(value.stateBags) do
                        if type(key) == 'string' then
                            if key == 'deformation' then
                                deformation = stateValue
                            else
                                state:set(key, stateValue, true)
                            end
                        end
                    end

                    if deformation ~= nil then
                        state:set('deformation', deformation, true)
                    end
                end

                local runtime = type(value.runtime) == 'table' and value.runtime or
                {
                    engineOn = value.engineOn
                }

                restoreVehicleRuntime(vehicle, runtime)

                Entity(vehicle).state:set('vehiclePersistRestore', nil, true)
                break
            end

            Wait(100)
        end
    end)
end)

AddStateBagChangeHandler('vehiclePersistAttachTrailer', '', function(bagName, _, rootNetId)
    if type(rootNetId) ~= 'number' or rootNetId <= 0 then
        return
    end

    CreateThread(function()
        local trailer = 0
        local root = 0

        for _ = 1, 50 do
            trailer = GetEntityFromStateBagName(bagName)
            root = NetToVeh(rootNetId)

            if trailer ~= 0 and root ~= 0 and DoesEntityExist(trailer) and DoesEntityExist(root) then
                break
            end

            Wait(100)
        end

        if trailer == 0 or root == 0 or not DoesEntityExist(trailer) or not DoesEntityExist(root) then
            return
        end

        for _ = 1, 20 do
            if NetworkGetEntityOwner(trailer) == cache.playerId then
                AttachVehicleToTrailer(root, trailer, 3.0)
                Entity(trailer).state:set('vehiclePersistAttachTrailer', nil, true)
                break
            end

            Wait(100)
        end
    end)
end)
