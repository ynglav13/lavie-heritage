local ESX = exports.es_extended:getSharedObject()
local STATE_TABLE = 'vehicle_persist_state_v2'
local META_TABLE = 'vehicle_persist_state_v2_meta'
local RESOURCE_NAME = GetCurrentResourceName()

local trackedVehicles = {}
local ownedKeysByPlate = {}
local vehicleLifecycle = {}
local garageTransitions = {}
local vehicleRecordCache = {}
local modelClassCache = {}
local dirtyVehicles = {}
local dirtyQueue = {}
local dirtyQueued = {}
local dirtyQueueHead = 1
local deleteTokens = {}
local deleteInProgress = {}
local inFlightWrites = {}
local stateEpochs = {}
local persistenceEpoch = 0
local lifecycleWriteCount = 0
local recentVehicleAccess = {}
local playerGrid = {}
local impoundedEntities = {}
local onlineOwners = {}
local disconnectedOwners = {}
local garageSpawnLeases = {}

local reconcileCursor = nil
local respawnCursor = nil
local vehicleHasOccupants

local initialized = false
local flushing = false
local clearingStates = false
local debugEnabled = Config.Debug == true
local lastDistantCleanup = 0

local UPSERT_PREFIX = ([[
    INSERT INTO `%s`
        (`storage_key`, `plate`, `model`, `vehicle_class`, `coords`, `heading`, `mods`, `state_bags`, `trailer`, `runtime`, `revision`, `is_owned`, `owner_identifier`)
    VALUES
]]):format(STATE_TABLE)

local UPSERT_UPDATE = [[
    ON DUPLICATE KEY UPDATE
        `plate` = IF(VALUES(`revision`) >= `revision`, VALUES(`plate`), `plate`),
        `model` = IF(VALUES(`revision`) >= `revision`, VALUES(`model`), `model`),
        `vehicle_class` = IF(VALUES(`revision`) >= `revision`, VALUES(`vehicle_class`), `vehicle_class`),
        `coords` = IF(VALUES(`revision`) >= `revision`, VALUES(`coords`), `coords`),
        `heading` = IF(VALUES(`revision`) >= `revision`, VALUES(`heading`), `heading`),
        `mods` = IF(VALUES(`revision`) >= `revision`, VALUES(`mods`), `mods`),
        `state_bags` = IF(VALUES(`revision`) >= `revision`, VALUES(`state_bags`), `state_bags`),
        `trailer` = IF(VALUES(`revision`) >= `revision`, VALUES(`trailer`), `trailer`),
        `runtime` = IF(VALUES(`revision`) >= `revision`, VALUES(`runtime`), `runtime`),
        `is_owned` = IF(VALUES(`revision`) >= `revision`, VALUES(`is_owned`), `is_owned`),
        `owner_identifier` = IF(VALUES(`revision`) >= `revision`, VALUES(`owner_identifier`), `owner_identifier`),
        `updated_at` = IF(VALUES(`revision`) >= `revision`, CURRENT_TIMESTAMP, `updated_at`),
        `revision` = GREATEST(`revision`, VALUES(`revision`))
]]

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

local function debugLog(message)
    if debugEnabled then
        print(('[Vehicle Persist V2] %s'):format(message))
    end
end

local function normalizePlate(value)
    if type(value) ~= 'string' then
        return nil
    end

    local plate = value:match('^%s*(.-)%s*$')

    if not plate or plate == '' or #plate > 12 then
        return nil
    end

    return plate:upper()
end

local function getDisplayPlate(entity)
    local plate = normalizePlate(GetVehicleNumberPlateText(entity))

    if plate then
        return plate
    end

    return 'NO PLATE'
end

local function isVehicleStored(value)
    return value == false or tonumber(value) == 0
end

local function isVehicleImpounded(value)
    return value == true or tonumber(value) == 1
end

local function validNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function getStateEpoch(key)
    return stateEpochs[key] or 0
end

local function invalidatePersistedKey(key)
    if not key then
        return 0
    end

    local nextEpoch = getStateEpoch(key) + 1
    stateEpochs[key] = nextEpoch
    return nextEpoch
end

local function stampTrackedVehicle(data)
    if not data or not data.key then
        return data
    end

    data.persistenceEpoch = persistenceEpoch
    data.stateEpoch = getStateEpoch(data.key)
    return data
end

local function isCurrentTrackedVehicle(data)
    return data ~= nil
        and data.key ~= nil
        and data.persistenceEpoch == persistenceEpoch
        and data.stateEpoch == getStateEpoch(data.key)
end

local function safeDecode(value)
    if type(value) == 'table' then
        return value
    end

    if type(value) ~= 'string' or value == '' then
        return nil
    end

    local ok, result = pcall(json.decode, value)

    if ok and type(result) == 'table' then
        return result
    end
end

local function safeEncode(value)
    if value == nil then
        return nil
    end

    local ok, encoded = pcall(json.encode, value)

    if ok then
        return encoded
    end
end

local function copyCoords(coords)
    if type(coords) ~= 'table' or not validNumber(coords.x) or not validNumber(coords.y) or not validNumber(coords.z) then
        return nil
    end

    return
    {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }
end

local function getOwnedKey(plate)
    return ('owned:%s'):format(plate)
end

local function isNetworkedVehicle(entity)
    return type(entity) == 'number'
        and entity ~= 0
        and DoesEntityExist(entity)
        and GetEntityType(entity) == 2
        and NetworkGetNetworkIdFromEntity(entity) ~= 0
end

local function getPlayerIdentifier(playerSource)
    local xPlayer = ESX.GetPlayerFromId(playerSource)
    return xPlayer and xPlayer.identifier or nil
end

local function getEntityDistanceSquared(first, second)
    local x = first.x - second.x
    local y = first.y - second.y
    local z = first.z - second.z
    return x * x + y * y + z * z
end

local function getGridSize()
    return math.max(1.0, tonumber(getConfig({ 'Persistence', 'RespawnDistance' }, 250.0)) or 250.0)
end

local function getGridCell(coords, size)
    return math.floor(coords.x / size), math.floor(coords.y / size)
end

local function getGridKey(x, y)
    return ('%s:%s'):format(x, y)
end

local function rebuildPlayerGrid()
    local size = getGridSize()
    playerGrid =
    {
        size = size,
        cells = {}
    }

    for _, playerId in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(playerId)

        if ped ~= 0 and DoesEntityExist(ped) then
            local coords = GetEntityCoords(ped)
            local cellX, cellY = getGridCell(coords, size)
            local key = getGridKey(cellX, cellY)
            local cell = playerGrid.cells[key]

            if not cell then
                cell = {}
                playerGrid.cells[key] = cell
            end

            cell[#cell + 1] =
            {
                x = coords.x,
                y = coords.y,
                z = coords.z
            }
        end
    end
end

local function playerIsNear(coords, distance)
    if type(coords) ~= 'table' then
        return false
    end

    if not playerGrid.size then
        rebuildPlayerGrid()
    end

    local size = playerGrid.size
    local cellX, cellY = getGridCell(coords, size)
    local cellRange = math.ceil(distance / size)
    local distanceSquared = distance * distance

    for x = cellX - cellRange, cellX + cellRange do
        for y = cellY - cellRange, cellY + cellRange do
            local cell = playerGrid.cells[getGridKey(x, y)]

            if cell then
                for _, playerCoords in ipairs(cell) do
                    if getEntityDistanceSquared(coords, playerCoords) <= distanceSquared then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function isListMatch(values, value, model)
    if type(values) ~= 'table' then
        return false
    end

    for key, configured in pairs(values) do
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
            if type(entry) == 'number' and (entry == value or (model and entry == model)) then
                return true
            end

            if type(entry) == 'string' then
                if entry:upper() == tostring(value):upper() then
                    return true
                end

                if model and joaat(entry) == model then
                    return true
                end
            end
        end
    end

    return false
end

local function isPlateMatch(values, plate)
    if type(values) ~= 'table' or not plate then
        return false
    end

    for key, configured in pairs(values) do
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

local function normalizeVehicleClass(value)
    value = tonumber(value)

    if validNumber(value) then
        value = math.floor(value)

        if value >= 0 and value <= 22 then
            return value
        end
    end
end

local function isVehicleClassMatch(values, vehicleClass)
    if type(values) ~= 'table' or vehicleClass == nil then
        return false
    end

    if values[vehicleClass] == true or values[tostring(vehicleClass)] == true then
        return true
    end

    for key, value in pairs(values) do
        if type(key) == 'number' and tonumber(value) == vehicleClass then
            return true
        end
    end

    return false
end

local function getServerVehicleClass(entity)
    if type(GetVehicleClass) ~= 'function' then
        return nil
    end

    local ok, vehicleClass = pcall(GetVehicleClass, entity)
    return ok and normalizeVehicleClass(vehicleClass) or nil
end

local function getServerModelVehicleClass(model)
    if model == nil then
        return nil
    end

    if modelClassCache[model] ~= nil then
        return modelClassCache[model] or nil
    end

    if type(GetVehicleClassFromName) ~= 'function' then
        modelClassCache[model] = false
        return nil
    end

    local ok, vehicleClass = pcall(GetVehicleClassFromName, model)
    vehicleClass = ok and normalizeVehicleClass(vehicleClass) or nil
    modelClassCache[model] = vehicleClass or false
    return vehicleClass
end

local function hasVehicleClassBlacklist(values)
    if type(values) ~= 'table' then
        return false
    end

    for key, value in pairs(values) do
        if (type(key) == 'number' and (value == true or tonumber(value) ~= nil))
            or (type(key) == 'string' and value == true and tonumber(key) ~= nil) then
            return true
        end
    end

    return false
end

local function isVehicleClassBlacklisted(model, serverVehicleClass)
    local classes = getConfig({ 'Blacklist', 'Classes' }, {})

    if not hasVehicleClassBlacklist(classes) then
        return false
    end

    local vehicleClass = normalizeVehicleClass(serverVehicleClass) or getServerModelVehicleClass(model)

    if vehicleClass == nil then
        return true
    end

    return isVehicleClassMatch(classes, vehicleClass)
end

local function isModelOrPlateBlacklisted(plate, model)
    local blacklist = getConfig({ 'Blacklist' }, {})

    if isListMatch(blacklist.Models, tostring(model), model) or isPlateMatch(blacklist.Plates, plate) then
        return true
    end

    return isVehicleClassBlacklisted(model)
end

local function isBlacklisted(entity, plate, model)
    local blacklist = getConfig({ 'Blacklist' }, {})

    if isListMatch(blacklist.Models, tostring(model), model) or isPlateMatch(blacklist.Plates, plate) then
        return true
    end

    return isVehicleClassBlacklisted(model, getServerVehicleClass(entity))
end

local function markManaged(entity, key)
    if not isNetworkedVehicle(entity) or Entity(entity).state.vehiclePersistIgnore == true then
        return
    end

    local state = Entity(entity).state
    local changed = false

    if state.vehiclePersistManaged ~= true then
        state:set('vehiclePersistManaged', true, true)
        changed = true
    end

    if state.vehiclePersistKey ~= key then
        state:set('vehiclePersistKey', key, true)
        changed = true
    end

    if changed and SetEntityOrphanMode then
        SetEntityOrphanMode(entity, 2)
    end
end

local function getTrailerKey(rootKey)
    return rootKey and (rootKey .. ':trailer') or nil
end

local function isManagedEntityForKey(entity, key)
    if not key or not isNetworkedVehicle(entity) then
        return false
    end

    local state = Entity(entity).state
    return state.vehiclePersistManaged == true and state.vehiclePersistKey == key
end

local function isVehiclePersistSpawning(entity)
    if not isNetworkedVehicle(entity) then
        return false
    end

    local netId = NetworkGetNetworkIdFromEntity(entity)
    local lease = netId > 0 and garageSpawnLeases[netId] or nil

    if lease then
        if lease.expiresAt > GetGameTimer() then
            return true
        end

        garageSpawnLeases[netId] = nil
    end

    return Entity(entity).state.vehiclePersistSpawning == true
end

local function isVehiclePersistIgnored(entity)
    return isNetworkedVehicle(entity) and Entity(entity).state.vehiclePersistIgnore == true
end

local function expireGarageSpawnLeases()
    local now = GetGameTimer()

    for netId, lease in pairs(garageSpawnLeases) do
        if lease.expiresAt <= now then
            garageSpawnLeases[netId] = nil
            local entity = NetworkGetEntityFromNetworkId(netId)

            if isNetworkedVehicle(entity) and Entity(entity).state.vehiclePersistSpawning == true then
                Entity(entity).state:set('vehiclePersistSpawning', false, true)
            end
        end
    end
end

local function auditVehicleDelete(action, entity, key, reason)
    if getConfig({ 'Diagnostics', 'VehicleDeletes' }, false) ~= true then
        return
    end

    local plate = isNetworkedVehicle(entity) and normalizePlate(GetVehicleNumberPlateText(entity)) or nil
    local model = isNetworkedVehicle(entity) and GetEntityModel(entity) or 0
    local netId = isNetworkedVehicle(entity) and NetworkGetNetworkIdFromEntity(entity) or 0
    local owner = isNetworkedVehicle(entity) and NetworkGetEntityOwner(entity) or 0

    print(('[vehicle_persist][delete-audit] action=%s reason=%s entity=%s netId=%s owner=%s plate=%s model=%s key=%s'):format(
        tostring(action),
        tostring(reason or 'unspecified'),
        tostring(entity or 0),
        tostring(netId or 0),
        tostring(owner or 0),
        tostring(plate or ''),
        tostring(model or 0),
        tostring(key or '')
    ))
end

local function findManagedEntityForKey(key)
    if not key then
        return 0
    end

    for _, entity in ipairs(GetAllVehicles() or {}) do
        if isManagedEntityForKey(entity, key) then
            return entity
        end
    end

    return 0
end

local function getManagedEntityForKey(entity, key)
    if isManagedEntityForKey(entity, key) then
        return entity
    end

    return findManagedEntityForKey(key)
end

local function deleteManagedEntityForKey(entity, key, reason)
    if not isManagedEntityForKey(entity, key) then
        return false
    end

    if isVehiclePersistIgnored(entity) then
        auditVehicleDelete('skip', entity, key, reason or 'ignored_entity')
        return false
    end

    if isVehiclePersistSpawning(entity) then
        auditVehicleDelete('skip', entity, key, reason or 'spawn_transition')
        return false
    end

    auditVehicleDelete('delete', entity, key, reason)
    DeleteEntity(entity)
    return true
end

local function doesEntityMatchTrackedModel(data, entity)
    local expectedModel = tonumber(data and data.model)

    return validNumber(expectedModel)
        and isNetworkedVehicle(entity)
        and math.floor(expectedModel) == GetEntityModel(entity)
end

local function isTrackedRootEntity(data)
    local entity = data and data.entity or 0

    if not isCurrentTrackedVehicle(data)
        or isVehiclePersistIgnored(entity)
        or not doesEntityMatchTrackedModel(data, entity) then
        return false
    end

    if isManagedEntityForKey(entity, data.key) then
        return true
    end

    return data.isOwned
        and Entity(entity).state.vehiclePersistKey == nil
        and normalizePlate(GetVehicleNumberPlateText(entity)) == data.plate
end

local function clearManagedEntityForKey(entity, key)
    if not isManagedEntityForKey(entity, key) then
        return false
    end

    local state = Entity(entity).state
    state:set('vehiclePersistAttachTrailer', nil, true)
    state:set('vehiclePersistManaged', nil, true)
    state:set('vehiclePersistKey', nil, true)
    return true
end

local function getTrackedTrailerEntity(data)
    if not data or not data.key then
        return 0
    end

    local trailerKey = getTrailerKey(data.key)
    local entity = getManagedEntityForKey(data.trailerEntity or 0, trailerKey)
    data.trailerEntity = entity
    return entity
end

local function deleteTrackedTrailer(data)
    if not data or not data.key then
        return false
    end

    local entity = getTrackedTrailerEntity(data)
    data.trailerEntity = 0
    return entity ~= 0 and deleteManagedEntityForKey(entity, getTrailerKey(data.key))
end

local function releaseTrackedTrailer(data, exceptEntity)
    if not data or not data.key then
        return false
    end

    local entity = getTrackedTrailerEntity(data)
    data.trailerEntity = 0

    if entity == 0 or entity == exceptEntity then
        return false
    end

    return clearManagedEntityForKey(entity, getTrailerKey(data.key))
end

local function claimTrackedTrailer(data, entity)
    if not data or not data.key or not isNetworkedVehicle(entity) then
        return false
    end

    local trailerKey = getTrailerKey(data.key)
    local existingKey = Entity(entity).state.vehiclePersistKey

    if existingKey ~= nil and existingKey ~= trailerKey then
        return false
    end

    markManaged(entity, trailerKey)
    data.trailerEntity = entity
    return true
end

local function getDynamicKey(entity, plate, model)
    local state = Entity(entity).state
    local existing = state.vehiclePersistKey

    if type(existing) == 'string' and existing:sub(1, 8) == 'dynamic:' then
        return existing
    end

    local key = ('dynamic:%s:%s:%s:%s'):format(
        NetworkGetNetworkIdFromEntity(entity),
        model,
        plate:gsub('[^%w]', '_'),
        GetGameTimer()
    )

    state:set('vehiclePersistKey', key, true)
    return key
end

local function getVehiclePropertiesModel(properties)
    properties = safeDecode(properties)
    local model = properties and properties.model

    if type(model) == 'string' then
        model = tonumber(model) or joaat(model)
    end

    if validNumber(model) and model ~= 0 then
        return math.floor(model)
    end
end

local function updateRecordCache(plate, row, includesVehicle)
    local lifetime = tonumber(getConfig({ 'Tracking', 'StateCacheLifetime' }, 60000)) or 60000
    local previous = vehicleRecordCache[plate]
    local record =
    {
        exists = row ~= nil,
        expiresAt = GetGameTimer() + lifetime,
        stateEpoch = getStateEpoch(getOwnedKey(plate))
    }

    if row then
        record.owner = row.owner
        record.stored = isVehicleStored(row.stored)
        record.impounded = isVehicleImpounded(row.isTowedOut)

        if includesVehicle then
            record.model = getVehiclePropertiesModel(row.vehicle)
            record.modelKnown = true
        elseif previous and previous.modelKnown then
            record.model = previous.model
            record.modelKnown = true
        end
    end

    vehicleRecordCache[plate] = record
    return record
end

local function getOwnedRecord(plate, force)
    if clearingStates then
        return { exists = false, expiresAt = 0 }
    end

    local expectedPersistenceEpoch = persistenceEpoch
    local key = getOwnedKey(plate)
    local expectedStateEpoch = getStateEpoch(key)
    local cached = vehicleRecordCache[plate]

    if not force
        and cached
        and cached.expiresAt > GetGameTimer()
        and cached.stateEpoch == expectedStateEpoch
        and (not cached.exists or cached.modelKnown) then
        return cached
    end

    local row = MySQL.single.await(
        'SELECT `owner`, `stored`, `isTowedOut`, `vehicle` FROM `owned_vehicles` WHERE `plate` = ? LIMIT 1',
        { plate }
    )

    if not row then
        row = MySQL.single.await(
            'SELECT `owner`, `stored`, `isTowedOut`, `vehicle`, `plate` FROM `owned_vehicles` WHERE UPPER(TRIM(`plate`)) = ? LIMIT 1',
            { plate }
        )
    end

    if expectedPersistenceEpoch ~= persistenceEpoch
        or expectedStateEpoch ~= getStateEpoch(key)
        or clearingStates then
        return { exists = false, expiresAt = 0 }
    end

    return updateRecordCache(plate, row, true)
end

local function getOwnedVehicleModel(plate)
    local record = getOwnedRecord(plate)
    return record and record.model
end

local function isRegisteredVehicleModel(plate, entity)
    local expected = getOwnedVehicleModel(plate)

    return not expected or expected == GetEntityModel(entity)
end

local function setOwnedOutside(plate)
    if clearingStates then
        return false
    end

    lifecycleWriteCount = lifecycleWriteCount + 1
    local ok, updated = pcall(
        MySQL.update.await,
        'UPDATE `owned_vehicles` SET `stored` = 1, `isTowedOut` = 0 WHERE `plate` = ?',
        { plate }
    )

    if not ok or updated == false then
        lifecycleWriteCount = math.max(0, lifecycleWriteCount - 1)
        print(('[Vehicle Persist V2] Failed to mark %s outside: %s'):format(plate, tostring(updated)))
        return false
    end

    local cached = vehicleRecordCache[plate] or {}
    cached.exists = true
    cached.stored = false
    cached.impounded = false
    cached.expiresAt = GetGameTimer() + (tonumber(getConfig({ 'Tracking', 'StateCacheLifetime' }, 60000)) or 60000)
    cached.stateEpoch = getStateEpoch(getOwnedKey(plate))
    vehicleRecordCache[plate] = cached
    lifecycleWriteCount = math.max(0, lifecycleWriteCount - 1)
    return true
end

local function getSerializedValue(data, valueKey, cacheKey)
    local cached = data[cacheKey]

    if type(cached) == 'string' then
        return cached
    end

    local encoded = safeEncode(data[valueKey])

    if encoded then
        data[cacheKey] = encoded
    end

    return encoded
end

local function cacheSerializedProperties(data)
    if not data then
        return false
    end

    local runtime = type(data.runtime) == 'table' and data.runtime or {}
    runtime.engineOn = data.engineOn == true

    data.runtime = runtime
    data.serializedMods = safeEncode(data.mods)
    data.serializedStateBags = safeEncode(data.stateBags)
    data.serializedTrailer = safeEncode(data.trailer)
    data.serializedRuntime = safeEncode(runtime)
    return type(data.serializedMods) == 'string'
end

local function makeStateSnapshot(data)
    if not data or not data.key or not data.model or not data.coords then
        return nil
    end

    local coords = copyCoords(data.coords)
    local coordsJson = safeEncode(coords)
    local mods = getSerializedValue(data, 'mods', 'serializedMods')

    if not coords or not coordsJson or not mods then
        return nil
    end

    local runtime = data.serializedRuntime

    if type(runtime) ~= 'string' then
        local runtimeValues = type(data.runtime) == 'table' and data.runtime or {}
        runtimeValues.engineOn = data.engineOn == true
        data.runtime = runtimeValues
        runtime = safeEncode(runtimeValues)
        data.serializedRuntime = runtime
    end

    if not runtime then
        return nil
    end

    return
    {
        key = data.key,
        plate = data.plate,
        model = math.floor(data.model),
        vehicleClass = normalizeVehicleClass(data.vehicleClass),
        coords = coords,
        coordsJson = coordsJson,
        heading = tonumber(data.heading) or 0.0,
        mods = mods,
        stateBags = getSerializedValue(data, 'stateBags', 'serializedStateBags'),
        trailer = getSerializedValue(data, 'trailer', 'serializedTrailer'),
        runtime = runtime,
        revision = data.revision or 0,
        isOwned = data.isOwned == true,
        ownerIdentifier = data.ownerIdentifier,
        data = data
    }
end

local function appendValue(placeholders, parameters, value)
    if value == nil then
        placeholders[#placeholders + 1] = 'NULL'
        return
    end

    placeholders[#placeholders + 1] = '?'
    parameters[#parameters + 1] = value
end

local function appendSnapshotRow(rows, parameters, snapshot)
    local placeholders = {}

    appendValue(placeholders, parameters, snapshot.key)
    appendValue(placeholders, parameters, snapshot.plate)
    appendValue(placeholders, parameters, snapshot.model)
    appendValue(placeholders, parameters, snapshot.vehicleClass)
    appendValue(placeholders, parameters, snapshot.coordsJson)
    appendValue(placeholders, parameters, snapshot.heading)
    appendValue(placeholders, parameters, snapshot.mods)
    appendValue(placeholders, parameters, snapshot.stateBags)
    appendValue(placeholders, parameters, snapshot.trailer)
    appendValue(placeholders, parameters, snapshot.runtime)
    appendValue(placeholders, parameters, snapshot.revision)
    appendValue(placeholders, parameters, snapshot.isOwned and 1 or 0)
    appendValue(placeholders, parameters, snapshot.ownerIdentifier)

    rows[#rows + 1] = '(' .. table.concat(placeholders, ', ') .. ')'
end

local function enqueueDirtyKey(key)
    if not key or dirtyQueued[key] then
        return
    end

    dirtyQueued[key] = true
    dirtyQueue[#dirtyQueue + 1] = key
end

local function compactDirtyQueue()
    if dirtyQueueHead <= 128 or dirtyQueueHead * 2 <= #dirtyQueue then
        return
    end

    local compacted = {}

    for index = dirtyQueueHead, #dirtyQueue do
        local key = dirtyQueue[index]

        if key and dirtyQueued[key] then
            compacted[#compacted + 1] = key
        end
    end

    dirtyQueue = compacted
    dirtyQueueHead = 1
end

local function dequeueDirtySnapshot()
    local lastIndex = #dirtyQueue

    while dirtyQueueHead <= lastIndex do
        local key = dirtyQueue[dirtyQueueHead]
        dirtyQueueHead = dirtyQueueHead + 1

        if key and dirtyQueued[key] then
            dirtyQueued[key] = nil
            local snapshot = dirtyVehicles[key]

            if snapshot then
                if deleteTokens[key] or deleteInProgress[key] then
                    enqueueDirtyKey(key)
                else
                    return key, snapshot
                end
            end
        end
    end

    compactDirtyQueue()
end

local function beginInFlightWrite(key)
    inFlightWrites[key] = (inFlightWrites[key] or 0) + 1
end

local function executePendingDelete(key)
    if not deleteTokens[key] or inFlightWrites[key] or deleteInProgress[key] then
        return false
    end

    deleteInProgress[key] = true
    local ok, result = pcall(
        MySQL.update.await,
        ('DELETE FROM `%s` WHERE `storage_key` = ?'):format(STATE_TABLE),
        { key }
    )
    deleteInProgress[key] = nil

    if not ok or result == false then
        print(('[Vehicle Persist V2] Failed to delete persistent state %s: %s'):format(key, tostring(result)))
        return false
    end

    deleteTokens[key] = nil
    return true
end

local function processPendingDeletes(limit)
    local processed = 0

    for key in pairs(deleteTokens) do
        if processed >= limit then
            break
        end

        if not inFlightWrites[key] and not deleteInProgress[key] then
            executePendingDelete(key)
            processed = processed + 1
        end
    end
end

local function finishInFlightWrite(key)
    local count = (inFlightWrites[key] or 1) - 1

    if count > 0 then
        inFlightWrites[key] = count
        return false
    end

    inFlightWrites[key] = nil

    if deleteTokens[key] then
        return executePendingDelete(key)
    end

    return false
end

local function queuePersist(data)
    if clearingStates or not isCurrentTrackedVehicle(data) then
        return false
    end

    data.revision = (data.revision or 0) + 1
    local snapshot = makeStateSnapshot(data)

    if not snapshot then
        return false
    end

    dirtyVehicles[data.key] = snapshot
    enqueueDirtyKey(data.key)
    return true
end

local function releaseSnapshotData(snapshot)
    local data = snapshot.data

    if data and data.revision == snapshot.revision and (not data.entity or not DoesEntityExist(data.entity)) then
        data.mods = nil
        data.stateBags = nil
        data.trailer = nil
        data.runtime = nil
        data.serializedMods = nil
        data.serializedStateBags = nil
        data.serializedTrailer = nil
        data.serializedRuntime = nil
        data.hydrated = false
    end
end

local function releaseCachedProperties(data)
    if not data then
        return
    end

    data.mods = nil
    data.stateBags = nil
    data.trailer = nil
    data.runtime = nil
    data.serializedMods = nil
    data.serializedStateBags = nil
    data.serializedTrailer = nil
    data.serializedRuntime = nil
    data.hydrated = false
end

local function flushDirtyVehicles()
    if flushing or clearingStates then
        return false
    end

    local batchSize = math.max(1, tonumber(getConfig({ 'Persistence', 'BatchSize' }, 25)) or 25)
    flushing = true
    processPendingDeletes(batchSize)

    local selected = {}
    local rows = {}
    local parameters = {}

    while #rows < batchSize do
        local key, snapshot = dequeueDirtySnapshot()

        if not key then
            break
        end

        selected[#selected + 1] =
        {
            key = key,
            snapshot = snapshot
        }
        appendSnapshotRow(rows, parameters, snapshot)
        beginInFlightWrite(key)
    end

    if #rows == 0 then
        flushing = false
        return true
    end

    local query = UPSERT_PREFIX .. table.concat(rows, ', ') .. UPSERT_UPDATE
    local ok, result = pcall(MySQL.prepare.await, query, parameters)

    if not ok or result == false then
        for _, entry in ipairs(selected) do
            local deleted = finishInFlightWrite(entry.key)

            if not deleted and dirtyVehicles[entry.key] == entry.snapshot then
                enqueueDirtyKey(entry.key)
            end
        end

        flushing = false
        print(('[Vehicle Persist V2] Failed to flush %s vehicle snapshot(s): %s'):format(#rows, tostring(result)))
        return false
    end

    for _, entry in ipairs(selected) do
        if dirtyVehicles[entry.key] == entry.snapshot then
            dirtyVehicles[entry.key] = nil
            releaseSnapshotData(entry.snapshot)
        end

        finishInFlightWrite(entry.key)
    end

    flushing = false
    return true
end

local function persistNow(data)
    if clearingStates or not isCurrentTrackedVehicle(data) then
        return false
    end

    if deleteTokens[data.key] or deleteInProgress[data.key] then
        return queuePersist(data)
    end

    data.revision = (data.revision or 0) + 1
    local snapshot = makeStateSnapshot(data)

    if not snapshot then
        return false
    end

    dirtyVehicles[data.key] = nil
    dirtyQueued[data.key] = nil
    beginInFlightWrite(data.key)

    local rows = {}
    local parameters = {}
    appendSnapshotRow(rows, parameters, snapshot)

    local ok, result = pcall(MySQL.prepare.await, UPSERT_PREFIX .. rows[1] .. UPSERT_UPDATE, parameters)
    local deleted = finishInFlightWrite(data.key)

    if not ok or result == false then
        print(('[Vehicle Persist V2] Failed to persist %s: %s'):format(data.plate, tostring(result)))

        if not deleted and not deleteTokens[data.key] and not deleteInProgress[data.key] then
            queuePersist(data)
        end

        return false
    end

    if not deleted then
        releaseSnapshotData(snapshot)
    end

    return true
end

local function flushAllDirtyVehicles()
    if flushing or clearingStates then
        return false
    end

    local maxBatches = math.max(1, tonumber(getConfig({ 'Persistence', 'ShutdownFlushMaxBatches' }, 8)) or 8)

    for _ = 1, maxBatches do
        if not next(dirtyVehicles) and not next(deleteTokens) then
            return true
        end

        if not flushDirtyVehicles() then
            return false
        end
    end

    return not next(dirtyVehicles) and not next(deleteTokens)
end

local function removePersistedState(key)
    if not key then
        return
    end

    invalidatePersistedKey(key)
    dirtyVehicles[key] = nil
    dirtyQueued[key] = nil
    deleteTokens[key] = true

    if not inFlightWrites[key] then
        executePendingDelete(key)
    end
end

local function nextGeneration(key)
    local lifecycle = vehicleLifecycle[key]
    return lifecycle and lifecycle.generation + 1 or 1
end

local function setLifecycle(key, phase)
    local generation = nextGeneration(key)
    local lifecycle =
    {
        phase = phase,
        generation = generation,
        changedAt = os.time()
    }

    vehicleLifecycle[key] = lifecycle
    return lifecycle
end

local function removeTrackedVehicle(key, shouldDeleteEntity, shouldDeleteTrailer, deleteReason)
    local data = trackedVehicles[key]

    if not data then
        return nil
    end

    if shouldDeleteEntity then
        deleteManagedEntityForKey(data.entity or 0, key, deleteReason or 'remove_tracked')
    end

    if shouldDeleteTrailer == nil then
        shouldDeleteTrailer = shouldDeleteEntity
    end

    if shouldDeleteTrailer then
        deleteTrackedTrailer(data)
    end

    trackedVehicles[key] = nil

    if data.isOwned and ownedKeysByPlate[data.plate] == key then
        ownedKeysByPlate[data.plate] = nil
    end

    return data
end

local function hydrateTrackedVehicle(data)
    if not data or not isCurrentTrackedVehicle(data) then
        return false
    end

    if data.hydrated and type(data.mods) == 'table' then
        return true
    end

    local expectedPersistenceEpoch = persistenceEpoch
    local expectedStateEpoch = data.stateEpoch

    local row = MySQL.single.await(([[
        SELECT `plate`, `model`, `vehicle_class`, `coords`, `heading`, `mods`, `state_bags`, `trailer`, `runtime`, `revision`, `is_owned`, `owner_identifier`
        FROM `%s`
        WHERE `storage_key` = ?
        LIMIT 1
    ]]):format(STATE_TABLE), { data.key })

    if expectedPersistenceEpoch ~= persistenceEpoch
        or expectedStateEpoch ~= getStateEpoch(data.key)
        or not isCurrentTrackedVehicle(data)
        or not row then
        return false
    end

    local coords = safeDecode(row.coords)
    local mods = safeDecode(row.mods)

    if not copyCoords(coords) or type(mods) ~= 'table' then
        return false
    end

    data.plate = row.plate
    data.model = tonumber(row.model)
    data.vehicleClass = normalizeVehicleClass(row.vehicle_class)
    data.coords = copyCoords(coords)
    data.heading = tonumber(row.heading) or 0.0
    data.mods = mods
    data.stateBags = safeDecode(row.state_bags)
    data.trailer = safeDecode(row.trailer)
    local runtime = safeDecode(row.runtime)
    data.engineOn = type(runtime) == 'table' and runtime.engineOn == true or false
    data.runtime = runtime
    data.serializedMods = row.mods
    data.serializedStateBags = row.state_bags
    data.serializedTrailer = row.trailer
    data.serializedRuntime = row.runtime
    data.revision = tonumber(row.revision) or 0
    data.isOwned = tonumber(row.is_owned) == 1
    data.ownerIdentifier = row.owner_identifier
    data.hydrated = true
    return true
end

local function getCurrentTrackedVehicle(key)
    local existing = trackedVehicles[key]

    if existing and not isCurrentTrackedVehicle(existing) then
        trackedVehicles[key] = nil

        if existing.isOwned and ownedKeysByPlate[existing.plate] == key then
            ownedKeysByPlate[existing.plate] = nil
        end

        return nil
    end

    return existing
end

local function loadTrackedVehicle(key)
    local existing = getCurrentTrackedVehicle(key)

    if existing then
        return existing
    end

    if deleteTokens[key] or deleteInProgress[key] then
        return nil
    end

    local expectedPersistenceEpoch = persistenceEpoch
    local expectedStateEpoch = getStateEpoch(key)

    local row = MySQL.single.await(([[
        SELECT `plate`, `model`, `vehicle_class`, `coords`, `heading`, `revision`, `is_owned`, `owner_identifier`
        FROM `%s`
        WHERE `storage_key` = ?
        LIMIT 1
    ]]):format(STATE_TABLE), { key })

    if expectedPersistenceEpoch ~= persistenceEpoch
        or expectedStateEpoch ~= getStateEpoch(key)
        or clearingStates
        or deleteTokens[key]
        or deleteInProgress[key]
        or not row then
        return nil
    end

    local coords = safeDecode(row.coords)

    if not copyCoords(coords) then
        return nil
    end

    local data =
    {
        key = key,
        plate = row.plate,
        model = tonumber(row.model),
        vehicleClass = normalizeVehicleClass(row.vehicle_class),
        coords = copyCoords(coords),
        heading = tonumber(row.heading) or 0.0,
        isOwned = tonumber(row.is_owned) == 1,
        ownerIdentifier = row.owner_identifier,
        revision = tonumber(row.revision) or 0,
        entity = 0,
        missingSince = os.time()
    }

    stampTrackedVehicle(data)
    trackedVehicles[key] = data

    if data.isOwned then
        ownedKeysByPlate[data.plate] = key
    end

    setLifecycle(key, 'outside')
    return data
end

local function applyRestoration(entity, data)
    if not isNetworkedVehicle(entity) then
        return
    end

    local state = Entity(entity).state

    if type(data.mods) == 'table' then
        state:set('ox_lib:setVehicleProperties', data.mods, true)
    end

    local runtime = type(data.runtime) == 'table' and data.runtime or
    {
        engineOn = data.engineOn == true
    }

    if next(runtime) or type(data.stateBags) == 'table' then
        state:set('vehiclePersistRestore',
        {
            engineOn = runtime.engineOn,
            runtime = runtime,
            stateBags = data.stateBags
        }, true)
    end
end

local function markFadeIn(entity)
    if getConfig({ 'Visual', 'FadeIn' }, true) ~= true then
        return
    end

    local startAlpha = tonumber(getConfig({ 'Visual', 'FadeInStartAlpha' }, 190)) or 190

    pcall(SetEntityAlpha, entity, math.max(0, math.min(254, math.floor(startAlpha))), false)

    Entity(entity).state:set('vehiclePersistFadeIn',
    {
        duration = tonumber(getConfig({ 'Visual', 'FadeInDuration' }, 450)) or 450,
        startAlpha = startAlpha,
        step = tonumber(getConfig({ 'Visual', 'FadeInStep' }, 25)) or 25,
        token = GetGameTimer()
    }, true)
end

local function markFadeOutAndWait(entity)
    if getConfig({ 'Visual', 'FadeOut' }, true) ~= true or not isNetworkedVehicle(entity) then
        return
    end

    local duration = tonumber(getConfig({ 'Visual', 'FadeOutDuration' }, 700)) or 700

    Entity(entity).state:set('vehiclePersistFadeOut',
    {
        duration = duration,
        endAlpha = tonumber(getConfig({ 'Visual', 'FadeOutEndAlpha' }, 0)) or 0,
        step = tonumber(getConfig({ 'Visual', 'FadeOutStep' }, 35)) or 35,
        token = GetGameTimer()
    }, true)

    Wait(math.max(100, math.min(3000, math.floor(duration))))
end

local function spawnAttachedTrailer(root, data)
    local trailer = data.trailer

    if type(trailer) ~= 'table' or not validNumber(trailer.model) then
        releaseTrackedTrailer(data)
        return false
    end

    if isModelOrPlateBlacklisted(normalizePlate(trailer.plate), trailer.model) then
        deleteTrackedTrailer(data)
        return false
    end

    local expectedModel = math.floor(trailer.model)
    local entity = getTrackedTrailerEntity(data)

    if entity ~= 0 and GetEntityModel(entity) ~= expectedModel then
        deleteTrackedTrailer(data)
        entity = 0
    end

    local coords = copyCoords(trailer.coords) or data.coords
    local heading = tonumber(trailer.heading) or data.heading

    if entity == 0 then
        entity = CreateVehicle(expectedModel, coords.x, coords.y, coords.z, heading, true, true)
        local timeout = GetGameTimer() + 5000

        while entity ~= 0 and not DoesEntityExist(entity) and GetGameTimer() < timeout do
            Wait(0)
        end

        if entity == 0 or not DoesEntityExist(entity) then
            return false
        end

        while not isNetworkedVehicle(entity) and GetGameTimer() < timeout do
            Wait(0)
        end

        if not isNetworkedVehicle(entity) then
            DeleteEntity(entity)
            return false
        end

        if not claimTrackedTrailer(data, entity) then
            DeleteEntity(entity)
            return false
        end
    else
        data.trailerEntity = entity
    end

    if type(trailer.plate) == 'string' and trailer.plate ~= '' then
        SetVehicleNumberPlateText(entity, trailer.plate)
    end

    applyRestoration(entity,
    {
        mods = trailer.props,
        stateBags = trailer.stateBags,
        runtime = trailer.runtime,
        engineOn = trailer.engineOn
    })
    markFadeIn(entity)

    local rootNetId = NetworkGetNetworkIdFromEntity(root)

    if rootNetId ~= 0 then
        Entity(entity).state:set('vehiclePersistAttachTrailer', rootNetId, true)
    end

    return true
end

local function spawnTrackedVehicle(data)
    if not isCurrentTrackedVehicle(data)
        or clearingStates
        or data.spawning
        or not data.model
        or not data.coords then
        return false
    end

    local expectedPersistenceEpoch = persistenceEpoch
    local expectedStateEpoch = data.stateEpoch

    if isModelOrPlateBlacklisted(normalizePlate(data.plate), data.model) then
        deleteTrackedTrailer(data)
        return false
    end

    data.spawning = true

    if not hydrateTrackedVehicle(data) then
        data.spawning = false
        return false
    end

    local entity = CreateVehicle(math.floor(data.model), data.coords.x, data.coords.y, data.coords.z, data.heading, true, true)
    local timeout = GetGameTimer() + 5000

    while entity ~= 0 and not DoesEntityExist(entity) and GetGameTimer() < timeout do
        Wait(0)
    end

    if entity == 0 or not DoesEntityExist(entity) then
        data.spawning = false
        return false
    end

    while not isNetworkedVehicle(entity) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not isNetworkedVehicle(entity) then
        DeleteEntity(entity)
        data.spawning = false
        return false
    end

    if expectedPersistenceEpoch ~= persistenceEpoch
        or expectedStateEpoch ~= getStateEpoch(data.key)
        or clearingStates
        or not isCurrentTrackedVehicle(data) then
        DeleteEntity(entity)
        data.spawning = false
        return false
    end

    SetVehicleNumberPlateText(entity, data.plate)
    markManaged(entity, data.key)
    markFadeIn(entity)

    data.entity = entity
    data.missingSince = nil
    data.nextWorldProbe = nil
    data.nextSpawnAttempt = nil
    data.spawning = false

    applyRestoration(entity, data)
    spawnAttachedTrailer(entity, data)

    if expectedPersistenceEpoch ~= persistenceEpoch
        or expectedStateEpoch ~= getStateEpoch(data.key)
        or clearingStates
        or not isCurrentTrackedVehicle(data) then
        deleteManagedEntityForKey(entity, data.key)
        deleteTrackedTrailer(data)
        data.entity = 0
        data.spawning = false
        return false
    end

    debugLog(('Spawned %s at saved position'):format(data.plate))
    return true
end

local function adoptExistingVehicles()
    local wantedByPlate = {}
    local trailerOwners = {}

    for key, data in pairs(trackedVehicles) do
        if data.isOwned then
            wantedByPlate[data.plate] = key
        end

        trailerOwners[getTrailerKey(key)] = data
    end

    for _, entity in ipairs(GetAllVehicles() or {}) do
        if isNetworkedVehicle(entity)
            and not isVehiclePersistSpawning(entity)
            and not isVehiclePersistIgnored(entity) then
            local stateKey = Entity(entity).state.vehiclePersistKey
            local trailerOwner = type(stateKey) == 'string' and trailerOwners[stateKey] or nil

            if trailerOwner then
                trailerOwner.trailerEntity = entity
            else
                local data = type(stateKey) == 'string' and trackedVehicles[stateKey] or nil

                if not data then
                    local plate = normalizePlate(GetVehicleNumberPlateText(entity))
                    local key = plate and wantedByPlate[plate]
                    data = key and trackedVehicles[key] or nil
                end

                if data and doesEntityMatchTrackedModel(data, entity) and not isTrackedRootEntity(data) then
                    data.entity = entity
                    data.missingSince = nil
                    markManaged(entity, data.key)
                end
            end
        end
    end
end

MySQL.ready(function()
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `storage_key` varchar(96) NOT NULL,
            `plate` varchar(32) NOT NULL,
            `model` bigint NOT NULL,
            `vehicle_class` tinyint unsigned NULL,
            `coords` longtext NOT NULL,
            `heading` double NOT NULL DEFAULT 0,
            `mods` longtext NOT NULL,
            `state_bags` longtext NULL,
            `trailer` longtext NULL,
            `runtime` longtext NULL,
            `revision` bigint unsigned NOT NULL DEFAULT 0,
            `is_owned` tinyint(1) NOT NULL DEFAULT 1,
            `owner_identifier` varchar(100) NULL,
            `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`storage_key`),
            KEY `idx_plate_owned` (`plate`, `is_owned`),
            KEY `idx_updated_at` (`updated_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]]):format(STATE_TABLE))

    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `migration_key` varchar(64) NOT NULL,
            `completed_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`migration_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]]):format(META_TABLE))

    local existingColumns = MySQL.query.await(('SHOW COLUMNS FROM `%s`'):format(STATE_TABLE)) or {}
    local columnNames = {}

    for _, column in ipairs(existingColumns) do
        columnNames[column.Field] = true
    end

    if not columnNames.runtime then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `runtime` longtext NULL AFTER `trailer`'):format(STATE_TABLE))
    end

    if not columnNames.vehicle_class then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `vehicle_class` tinyint unsigned NULL AFTER `model`'):format(STATE_TABLE))
    end

    if not columnNames.revision then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `revision` bigint unsigned NOT NULL DEFAULT 0 AFTER `runtime`'):format(STATE_TABLE))
    end

    local legacyTable = MySQL.single.await([[
        SELECT 1 AS `exists`
        FROM `information_schema`.`tables`
        WHERE `table_schema` = DATABASE() AND `table_name` = 'vehicle_persist_state'
        LIMIT 1
    ]])

    local legacyMigrated = MySQL.scalar.await(
        ('SELECT 1 FROM `%s` WHERE `migration_key` = ? LIMIT 1'):format(META_TABLE),
        { 'legacy_v1' }
    )

    if legacyTable and not legacyMigrated then
        MySQL.update.await(([[
            INSERT IGNORE INTO `%s`
                (`storage_key`, `plate`, `model`, `coords`, `heading`, `mods`, `is_owned`, `updated_at`)
            SELECT CONCAT('owned:', `plate`), `plate`, `model`, `coords`, `heading`, `mods`, 1, `updated_at`
            FROM `vehicle_persist_state`
        ]]):format(STATE_TABLE))

        MySQL.insert.await(
            ('INSERT IGNORE INTO `%s` (`migration_key`) VALUES (?)'):format(META_TABLE),
            { 'legacy_v1' }
        )
    end

    MySQL.update.await(([[
        DELETE p FROM `%s` p
        LEFT JOIN `owned_vehicles` v ON v.`plate` = p.`plate`
        WHERE p.`is_owned` = 1
            AND (v.`plate` IS NULL OR v.`stored` = 0 OR COALESCE(v.`isTowedOut`, 0) = 1)
    ]]):format(STATE_TABLE))

    local rows = MySQL.query.await(([[
        SELECT p.`storage_key`, p.`plate`, p.`model`, p.`vehicle_class`, p.`coords`, p.`heading`, p.`revision`, p.`is_owned`, p.`owner_identifier`,
            v.`owner`, v.`stored`, v.`isTowedOut`
        FROM `%s` p
        LEFT JOIN `owned_vehicles` v ON v.`plate` = p.`plate` AND p.`is_owned` = 1
        WHERE p.`is_owned` = 0
            OR (v.`plate` IS NOT NULL AND v.`stored` = 1 AND COALESCE(v.`isTowedOut`, 0) = 0)
    ]]):format(STATE_TABLE)) or {}
    local saveOnlyOwned = getConfig({ 'Tracking', 'SaveOnlyOwnedVehicles' }, true) == true

    for _, row in ipairs(rows) do
        local coords = safeDecode(row.coords)
        local key = row.storage_key
        local isOwned = tonumber(row.is_owned) == 1

        if (isOwned or not saveOnlyOwned)
            and type(key) == 'string'
            and key ~= ''
            and copyCoords(coords)
            and validNumber(tonumber(row.model)) then
            local data =
            {
                key = key,
                plate = row.plate,
                model = tonumber(row.model),
                vehicleClass = normalizeVehicleClass(row.vehicle_class),
                coords = copyCoords(coords),
                heading = tonumber(row.heading) or 0.0,
                isOwned = isOwned,
                ownerIdentifier = row.owner_identifier or row.owner,
                revision = tonumber(row.revision) or 0,
                entity = 0,
                missingSince = os.time()
            }

            stampTrackedVehicle(data)
            trackedVehicles[key] = data
            setLifecycle(key, 'outside')

            if isOwned then
                ownedKeysByPlate[data.plate] = key
                updateRecordCache(data.plate, row)
            end
        end
    end

    adoptExistingVehicles()
    rebuildPlayerGrid()

    for _, playerSource in ipairs(GetPlayers()) do
        local identifier = getPlayerIdentifier(tonumber(playerSource))

        if identifier then
            onlineOwners[identifier] = true
            disconnectedOwners[identifier] = nil
        end
    end

    initialized = true
    print(('[Vehicle Persist V2] Loaded %s persistent vehicle state(s).'):format(#rows))
end)

local function getAllowedStateBagKeys()
    local configured = getConfig({ 'Tracking', 'PersistedStateBagKeys' }, {})
    local allowed = {}

    if type(configured) ~= 'table' then
        return allowed
    end

    for key, value in pairs(configured) do
        local stateKey = type(key) == 'number' and value or key
        local enabled = type(key) == 'number' or value == true

        if enabled and type(stateKey) == 'string' and stateKey ~= '' then
            allowed[stateKey] = true
        end
    end

    return allowed
end

local function sanitizeStateBags(input)
    if type(input) ~= 'table' then
        return nil
    end

    local allowed = getAllowedStateBagKeys()

    if not next(allowed) then
        return nil
    end

    local output = {}

    for key, value in pairs(input) do
        if allowed[key] then
            if key == 'deformation' then
                local normalized, encoded = VehiclePersistDeformation.Normalize(value)

                if normalized and #normalized > 0 and encoded then
                    output[key] = normalized
                end
            else
                local encoded = safeEncode(value)

                if encoded and #encoded <= 8192 then
                    output[key] = value
                end
            end
        end
    end

    return next(output) and output or nil
end

AddStateBagChangeHandler('deformation', '', function(bagName, _, value)
    local entity = GetEntityFromStateBagName(bagName)

    if not isNetworkedVehicle(entity) or isVehiclePersistIgnored(entity) then
        return
    end

    local key = Entity(entity).state.vehiclePersistKey

    if type(key) ~= 'string' or key == '' then
        return
    end

    local data = getCurrentTrackedVehicle(key) or loadTrackedVehicle(key)

    if not data or not isCurrentTrackedVehicle(data)
        or (data.entity and data.entity ~= 0 and data.entity ~= entity) then
        return
    end

    data.entity = entity

    local normalized = VehiclePersistDeformation.Normalize(value)

    if not normalized then
        return
    end

    if #normalized > 0 then
        data.stateBags = data.stateBags or {}
        data.stateBags.deformation = normalized
    elseif data.stateBags then
        data.stateBags.deformation = nil

        if not next(data.stateBags) then
            data.stateBags = nil
        end
    end

    data.serializedStateBags = nil
    queuePersist(data)
end)

local function sanitizeRuntime(input, fallbackEngineOn)
    local runtime =
    {
        engineOn = fallbackEngineOn == true
    }

    if type(input) ~= 'table' then
        return runtime
    end

    if input.engineOn ~= nil then
        runtime.engineOn = input.engineOn == true
    end

    local landingGear = tonumber(input.landingGear)

    if validNumber(landingGear) and landingGear >= 0 and landingGear <= 3 then
        runtime.landingGear = math.floor(landingGear)
    end

    local vtolPosition = tonumber(input.vtolPosition)

    if validNumber(vtolPosition) and vtolPosition >= -1.0 and vtolPosition <= 1.0 then
        runtime.vtolPosition = vtolPosition
    end

    if type(input.boatAnchored) == 'boolean' then
        runtime.boatAnchored = input.boatAnchored
    end

    local convertibleRoof = tonumber(input.convertibleRoof)

    if validNumber(convertibleRoof) and convertibleRoof >= 0 and convertibleRoof <= 3 then
        runtime.convertibleRoof = math.floor(convertibleRoof)
    end

    return runtime
end

local function getServerAttachedTrailer(root)
    if type(GetVehicleTrailer) ~= 'function' then
        return nil, false
    end

    local ok, hasTrailer, trailer = pcall(GetVehicleTrailer, root)

    if not ok then
        return nil, false
    end

    if hasTrailer == true and isNetworkedVehicle(trailer) then
        return trailer, true
    end

    if isNetworkedVehicle(hasTrailer) and trailer == nil then
        return hasTrailer, true
    end

    return 0, true
end

local function validateTrailerSnapshot(root, rawTrailer)
    if type(rawTrailer) ~= 'table' or type(rawTrailer.props) ~= 'table' then
        return nil, 0
    end

    local netId = tonumber(rawTrailer.netId)

    if not netId or netId <= 0 then
        return nil, 0
    end

    local trailer = NetworkGetEntityFromNetworkId(math.floor(netId))

    if not isNetworkedVehicle(trailer) or trailer == root then
        return nil, 0
    end

    local attachedTrailer, attachmentKnown = getServerAttachedTrailer(root)

    if attachmentKnown and attachedTrailer ~= trailer then
        return nil, 0
    end

    local rootCoords = GetEntityCoords(root)
    local trailerCoords = GetEntityCoords(trailer)

    if getEntityDistanceSquared(rootCoords, trailerCoords) > 4900.0 then
        return nil, 0
    end

    local model = GetEntityModel(trailer)
    local plate = getDisplayPlate(trailer)
    local vehicleClass = getServerVehicleClass(trailer) or normalizeVehicleClass(rawTrailer.vehicleClass)

    if isBlacklisted(trailer, normalizePlate(plate), model) then
        return nil, 0
    end

    local propsEncoded = safeEncode(rawTrailer.props)

    if not propsEncoded or #propsEncoded > (tonumber(getConfig({ 'Tracking', 'SnapshotMaxBytes' }, 60000)) or 60000) then
        return nil, 0
    end

    local runtime = sanitizeRuntime(rawTrailer.runtime, rawTrailer.engineOn)

    return
    {
        model = model,
        vehicleClass = vehicleClass,
        plate = plate,
        coords =
        {
            x = trailerCoords.x,
            y = trailerCoords.y,
            z = trailerCoords.z
        },
        heading = GetEntityHeading(trailer),
        props = rawTrailer.props,
        stateBags = sanitizeStateBags(rawTrailer.stateBags),
        runtime = runtime,
        engineOn = runtime.engineOn == true
    }, trailer
end

local function updateTrackedTrailerFromSnapshot(data, root, payload)
    local hasTrailer = payload.hasTrailer

    local function clearSavedTrailerState()
        releaseTrackedTrailer(data)
        data.trailer = nil
        data.serializedTrailer = nil
    end

    local function attachedTrailerIsBlacklisted(entity)
        return entity ~= 0
            and isBlacklisted(entity, normalizePlate(getDisplayPlate(entity)), GetEntityModel(entity))
    end

    if hasTrailer == false or payload.trailer == nil then
        local attachedTrailer, attachmentKnown = getServerAttachedTrailer(root)

        if attachmentKnown and attachedTrailer ~= 0 then
            if attachedTrailerIsBlacklisted(attachedTrailer) then
                clearSavedTrailerState()
            end

            return
        end

        clearSavedTrailerState()
        return
    end

    local trailer, entity = validateTrailerSnapshot(root, payload.trailer)

    if not trailer or entity == 0 then
        local attachedTrailer, attachmentKnown = getServerAttachedTrailer(root)

        if attachmentKnown and attachedTrailer ~= 0 then
            if attachedTrailerIsBlacklisted(attachedTrailer) then
                clearSavedTrailerState()
            end

            return
        end

        clearSavedTrailerState()
        return
    end

    releaseTrackedTrailer(data, entity)

    if not claimTrackedTrailer(data, entity) then
        clearSavedTrailerState()
        return
    end

    data.trailer = trailer
    data.serializedTrailer = nil
end

local function validateClientVehicle(playerSource, netId)
    if type(netId) ~= 'number' or netId <= 0 then
        return nil
    end

    local entity = NetworkGetEntityFromNetworkId(math.floor(netId))

    if not isNetworkedVehicle(entity) then
        return nil
    end

    local ped = GetPlayerPed(playerSource)

    if ped == 0 or not DoesEntityExist(ped) then
        return nil
    end

    local playerCoords = GetEntityCoords(ped)
    local vehicleCoords = GetEntityCoords(entity)

    if getEntityDistanceSquared(playerCoords, vehicleCoords) > 40000.0 then
        return nil
    end

    return entity, ped, playerCoords, vehicleCoords
end

RegisterNetEvent('vehicle_persist:server:fixDeformation', function(netId)
    local playerSource = source
    netId = math.floor(tonumber(netId) or 0)

    local entity, ped, playerCoords, vehicleCoords = validateClientVehicle(playerSource, netId)

    if not entity then
        return
    end

    local maxDistance = tonumber(getConfig({ 'Deformation', 'FixMaxDistance' }, 15.0)) or 15.0

    if getEntityDistanceSquared(playerCoords, vehicleCoords) > maxDistance * maxDistance
        or (NetworkGetEntityOwner(entity) ~= playerSource and GetPedInVehicleSeat(entity, -1) ~= ped) then
        return
    end

    local timeout = GetGameTimer()
        + math.max(0, tonumber(getConfig({ 'Deformation', 'FixValidationTimeout' }, 2000)) or 2000)

    while DoesEntityExist(entity) and GetVehicleBodyHealth(entity) < 995.0 and GetGameTimer() < timeout do
        Wait(100)
    end

    if not DoesEntityExist(entity) or GetVehicleBodyHealth(entity) < 995.0 then
        return
    end

    local plate = normalizePlate(GetVehicleNumberPlateText(entity))

    if not plate then
        return
    end

    local record = getOwnedRecord(plate, true)

    if not record.exists or (record.model ~= nil and record.model ~= GetEntityModel(entity)) then
        return
    end

    Entity(entity).state:set('deformation', nil, true)

    local key = Entity(entity).state.vehiclePersistKey or getOwnedKey(plate)
    local data = type(key) == 'string' and getCurrentTrackedVehicle(key) or nil

    if data and isCurrentTrackedVehicle(data) then
        if data.stateBags then
            data.stateBags.deformation = nil

            if not next(data.stateBags) then
                data.stateBags = nil
            end
        end

        data.serializedStateBags = nil
        queuePersist(data)
    end

    local ok, updated = pcall(
        MySQL.update.await,
        'UPDATE `owned_vehicles` SET `deformation` = ? WHERE UPPER(TRIM(`plate`)) = ? AND `owner` = ?',
        { '[]', plate, record.owner }
    )

    if not ok or updated == false then
        print(('[Vehicle Persist V2] Failed to clear deformation for %s: %s'):format(plate, tostring(updated)))
    end
end)

local function processVehicleSnapshot(playerSource, payload)
    if not initialized or clearingStates or type(payload) ~= 'table' then
        return false
    end

    local operationEpoch = persistenceEpoch

    local xPlayer = ESX.GetPlayerFromId(playerSource)

    if not xPlayer then
        return false
    end

    local entity, ped, _, vehicleCoords = validateClientVehicle(playerSource, payload.netId)

    if not entity or isVehiclePersistSpawning(entity) or isVehiclePersistIgnored(entity) then
        return false
    end

    local netId = NetworkGetNetworkIdFromEntity(entity)
    local model = GetEntityModel(entity)
    local normalizedPlate = normalizePlate(GetVehicleNumberPlateText(entity))
    local displayPlate = normalizedPlate or getDisplayPlate(entity)
    local ownedKey = normalizedPlate and getOwnedKey(normalizedPlate) or nil
    local expectedOwnedStateEpoch = ownedKey and getStateEpoch(ownedKey) or nil
    local existingPersistKey = Entity(entity).state.vehiclePersistKey
    local dynamicKey = type(existingPersistKey) == 'string'
        and existingPersistKey:sub(1, 8) == 'dynamic:'
        and existingPersistKey
        or nil
    local expectedDynamicStateEpoch = dynamicKey and getStateEpoch(dynamicKey) or nil
    local vehicleClass = getServerVehicleClass(entity) or normalizeVehicleClass(payload.vehicleClass)

    if isBlacklisted(entity, normalizedPlate, model) then
        return false
    end

    local now = GetGameTimer()
    local accessByEntity = recentVehicleAccess[playerSource] or {}
    recentVehicleAccess[playerSource] = accessByEntity
    local access = accessByEntity[netId] or {}
    local currentVehicle = GetVehiclePedIsIn(ped, false)
    local isOccupant = currentVehicle == entity
    local isDriver = GetPedInVehicleSeat(entity, -1) == ped
    local isNetworkOwner = NetworkGetEntityOwner(entity) == playerSource
    local grace = tonumber(getConfig({ 'Tracking', 'RecentAccessGrace' }, 12000)) or 12000

    if isOccupant then
        access.at = now
        access.wasDriver = isDriver
        access.wasNetworkOwner = isNetworkOwner
    elseif not access.at or now - access.at > grace then
        return false
    end

    if getConfig({ 'Tracking', 'RequireDriver' }, false) and not (isDriver or (not isOccupant and access.wasDriver)) then
        return false
    end

    local minimumInterval = tonumber(getConfig({ 'Tracking', 'SnapshotMinInterval' }, 1500)) or 1500
    local exitBypass = payload.reason == 'exit'
        and (not access.lastExitSnapshot or now - access.lastExitSnapshot >= minimumInterval)

    if not exitBypass and access.lastSnapshot and now - access.lastSnapshot < minimumInterval then
        return false
    end

    if payload.reason == 'exit' then
        access.lastExitSnapshot = now
    end

    access.lastSnapshot = now
    accessByEntity[netId] = access

    local canWriteFullState = isDriver
        or isNetworkOwner
        or (not isOccupant and (access.wasDriver == true or access.wasNetworkOwner == true))
    local isFullState = payload.fullState == true and canWriteFullState

    local record = normalizedPlate and getOwnedRecord(normalizedPlate) or { exists = false }

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or (record.exists and (not ownedKey or expectedOwnedStateEpoch ~= getStateEpoch(ownedKey))) then
        return false
    end

    if getConfig({ 'Tracking', 'SaveOnlyOwnedVehicles' }, true) and not record.exists then
        return false
    end

    if record.exists and record.model and record.model ~= model then
        return false
    end

    if getConfig({ 'Tracking', 'RequirePlayerOwnership' }, false) and record.exists and record.owner ~= xPlayer.identifier then
        return false
    end

    if isFullState then
        if type(payload.props) ~= 'table' then
            return false
        end

        local encoded = safeEncode(payload)
        local maxBytes = tonumber(getConfig({ 'Tracking', 'SnapshotMaxBytes' }, 60000)) or 60000

        if not encoded or #encoded > maxBytes then
            return false
        end
    end

    local isOwned = record.exists == true
    local key
    local expectedStateEpoch

    if isOwned then
        key = ownedKey
        expectedStateEpoch = expectedOwnedStateEpoch
    else
        key = dynamicKey or getDynamicKey(entity, displayPlate, model)
        expectedStateEpoch = dynamicKey and expectedDynamicStateEpoch or getStateEpoch(key)
    end

    if expectedStateEpoch ~= getStateEpoch(key) or deleteTokens[key] or deleteInProgress[key] then
        return false
    end

    local lifecycle = vehicleLifecycle[key]

    if lifecycle and (lifecycle.phase == 'storing' or lifecycle.phase == 'stored') then
        return false
    end

    local outsideGrace = lifecycle
        and lifecycle.phase == 'outside'
        and os.time() - lifecycle.changedAt < 30

    if isOwned and (record.impounded or (record.stored and not outsideGrace)) then
        return false
    end

    local data = getCurrentTrackedVehicle(key) or loadTrackedVehicle(key)

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key) then
        return false
    end

    if isOwned and data then
        if validNumber(tonumber(data.model)) and math.floor(tonumber(data.model)) ~= model then
            return false
        end

        if isTrackedRootEntity(data) and data.entity ~= entity then
            return false
        end
    end

    if not data then
        data =
        {
            key = key,
            plate = displayPlate,
            model = model,
            vehicleClass = vehicleClass,
            coords = {},
            heading = 0.0,
            isOwned = isOwned,
            ownerIdentifier = record.owner,
            entity = entity
        }

        stampTrackedVehicle(data)
        trackedVehicles[key] = data

        if isOwned then
            ownedKeysByPlate[displayPlate] = key
        end

        setLifecycle(key, 'outside')
    end

    data.entity = entity
    data.plate = displayPlate
    data.model = model
    data.vehicleClass = vehicleClass or data.vehicleClass
    data.coords =
    {
        x = vehicleCoords.x,
        y = vehicleCoords.y,
        z = vehicleCoords.z
    }
    data.heading = GetEntityHeading(entity)
    data.isOwned = isOwned
    data.ownerIdentifier = record.owner
    data.missingSince = nil
    data.nextWorldProbe = nil

    if isFullState then
        data.mods = payload.props
        data.stateBags = sanitizeStateBags(payload.stateBags)
        data.runtime = sanitizeRuntime(payload.runtime, payload.engineOn)
        data.engineOn = data.runtime.engineOn == true
        updateTrackedTrailerFromSnapshot(data, entity, payload)

        if not cacheSerializedProperties(data) then
            return false
        end

        data.hydrated = true
    elseif type(data.mods) ~= 'table' and not hydrateTrackedVehicle(data) then
        return false
    end

    if not isFullState and canWriteFullState and payload.hasTrailer == false then
        updateTrackedTrailerFromSnapshot(data, entity, payload)
    end

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key)
        or not isCurrentTrackedVehicle(data) then
        return false
    end

    markManaged(entity, key)
    local queued = queuePersist(data)

    if queued and isFullState then
        TriggerClientEvent('vehicle_persist:client:snapshotAccepted', playerSource, netId)
    end

    return queued
end

RegisterNetEvent('vehicle_persist:server:saveVehicleSnapshot', function(payload)
    processVehicleSnapshot(source, payload)
end)

RegisterNetEvent('vehicle_persist:server:saveVehicleCoords', function(_, _, _, _, mods, netId)
    local playerSource = source
    local ped = GetPlayerPed(playerSource)
    local entity = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0

    if entity == 0 or not isNetworkedVehicle(entity) then
        return
    end

    processVehicleSnapshot(playerSource,
    {
        netId = tonumber(netId) or NetworkGetNetworkIdFromEntity(entity),
        reason = 'legacy',
        fullState = type(mods) == 'table',
        props = mods
    })
end)

local function processGarageTransition(plate, record)
    local transition = garageTransitions[plate]

    if not transition then
        return
    end

    local key = transition.key

    if not record.exists or record.stored or record.impounded then
        deleteManagedEntityForKey(transition.pending and transition.pending.entity or 0, key, 'garage_transition_stored')
        deleteTrackedTrailer(transition.pending)
        removePersistedState(key)
        vehicleLifecycle[key] =
        {
            phase = 'stored',
            generation = nextGeneration(key),
            changedAt = os.time()
        }
        garageTransitions[plate] = nil
        return
    end

    local pending = transition.pending

    if pending and isCurrentTrackedVehicle(pending) and isManagedEntityForKey(pending.entity or 0, key) then
        pending.missingSince = nil
        trackedVehicles[key] = pending
        ownedKeysByPlate[plate] = key
        setLifecycle(key, 'outside')
        garageTransitions[plate] = nil
        debugLog(('Garage store rollback detected for %s'):format(plate))
        return
    end

    if transition.expiresAt <= os.time() then
        local data = transition.pending or loadTrackedVehicle(key)

        if data and isCurrentTrackedVehicle(data) then
            data.entity = data.entity or 0
            data.missingSince = data.missingSince or os.time()
            trackedVehicles[key] = data
            ownedKeysByPlate[plate] = key
            setLifecycle(key, 'outside')
        end

        garageTransitions[plate] = nil
    end
end

local function buildOwnedRecordMap(plates, expectedPersistenceEpoch)
    local result = {}

    for startIndex = 1, #plates, 100 do
        local parameters = {}
        local finishIndex = math.min(startIndex + 99, #plates)

        for index = startIndex, finishIndex do
            parameters[#parameters + 1] = plates[index]
        end

        local placeholders = string.rep('?,', #parameters):sub(1, -2)
        local rows = MySQL.query.await((
            'SELECT `plate`, `owner`, `stored`, `isTowedOut` FROM `owned_vehicles` WHERE `plate` IN (%s)'
        ):format(placeholders), parameters) or {}

        if #rows < #parameters then
            local normalizedRows = MySQL.query.await((
                'SELECT `plate`, `owner`, `stored`, `isTowedOut` FROM `owned_vehicles` WHERE UPPER(TRIM(`plate`)) IN (%s)'
            ):format(placeholders), parameters) or {}

            for _, row in ipairs(normalizedRows) do
                rows[#rows + 1] = row
            end
        end

        if expectedPersistenceEpoch ~= persistenceEpoch or clearingStates then
            return nil
        end

        for _, row in ipairs(rows) do
            local plate = normalizePlate(row.plate)

            if plate then
                result[plate] = updateRecordCache(plate, row)
            end
        end
    end

    return result
end

local function collectTrackedKeys(cursor, limit)
    if cursor and not trackedVehicles[cursor] then
        cursor = nil
    end

    local keys = {}
    local seen = {}
    local current = cursor

    while #keys < limit do
        local key = next(trackedVehicles, current)

        if not key then
            key = next(trackedVehicles)
        end

        if not key or seen[key] then
            break
        end

        seen[key] = true
        keys[#keys + 1] = key
        current = key
    end

    return keys, current
end

local function reconcileTrackedVehicles()
    if not initialized or clearingStates then
        return
    end

    local operationEpoch = persistenceEpoch

    rebuildPlayerGrid()
    local batchSize = math.max(1, math.floor(tonumber(getConfig({ 'Persistence', 'ReconcileBatchSize' }, 200)) or 200))
    local selectedKeys
    selectedKeys, reconcileCursor = collectTrackedKeys(reconcileCursor, batchSize)
    local ownedPlates = {}
    local seenPlates = {}

    for plate in pairs(garageTransitions) do
        if not seenPlates[plate] then
            seenPlates[plate] = true
            ownedPlates[#ownedPlates + 1] = plate
        end
    end

    for _, key in ipairs(selectedKeys) do
        local data = trackedVehicles[key]

        if data and data.isOwned and not seenPlates[data.plate] then
            seenPlates[data.plate] = true
            ownedPlates[#ownedPlates + 1] = data.plate
        end
    end

    local records = #ownedPlates > 0 and buildOwnedRecordMap(ownedPlates, operationEpoch) or {}

    if operationEpoch ~= persistenceEpoch or clearingStates then
        return
    end

    for plate in pairs(garageTransitions) do
        processGarageTransition(plate, records[plate] or { exists = false })
    end

    for _, key in ipairs(selectedKeys) do
        local data = trackedVehicles[key]

        if data and data.isOwned then
            local record = records[data.plate] or { exists = false }
            local lifecycle = vehicleLifecycle[key]

            if not isVehiclePersistSpawning(data.entity or 0)
                and (not record.exists or record.stored or record.impounded)
                and (not data.entity or data.entity == 0 or not DoesEntityExist(data.entity) or not vehicleHasOccupants(data.entity)) then
                debugLog(('Removing %s after garage/impound state reconciliation'):format(data.plate))
                removeTrackedVehicle(key, true, nil, 'reconcile_stored')
                removePersistedState(key)
                vehicleLifecycle[key] =
                {
                    phase = 'stored',
                    generation = lifecycle and lifecycle.generation + 1 or 1,
                    changedAt = os.time()
                }
            end
        elseif data and data.entity and DoesEntityExist(data.entity) then
            markManaged(data.entity, key)
        end
    end

    local now = os.time()

    for playerSource, entities in pairs(recentVehicleAccess) do
        if not GetPlayerName(playerSource) then
            recentVehicleAccess[playerSource] = nil
        else
            for netId, access in pairs(entities) do
                if not access.at or GetGameTimer() - access.at > 60000 then
                    entities[netId] = nil
                end
            end
        end
    end

    for key, lifecycle in pairs(vehicleLifecycle) do
        if lifecycle.phase == 'stored' and now - lifecycle.changedAt > 600 then
            vehicleLifecycle[key] = nil
        end
    end

    local cacheNow = GetGameTimer()

    for plate, cached in pairs(vehicleRecordCache) do
        if (not cached.expiresAt or cached.expiresAt <= cacheNow)
            and not ownedKeysByPlate[plate]
            and not garageTransitions[plate] then
            vehicleRecordCache[plate] = nil
        end
    end
end

local function syncGarageStoredStates()
    if not initialized or clearingStates then
        return
    end

    local operationEpoch = persistenceEpoch
    local batchSize = math.max(1, math.floor(tonumber(getConfig({ 'Persistence', 'GarageSyncBatchSize' }, 100)) or 100))
    local rows = MySQL.query.await(([[
        SELECT p.`storage_key`, p.`plate`, p.`is_owned`, v.`stored`, v.`isTowedOut`, v.`plate` AS `owned_plate`
        FROM `%s` p
        LEFT JOIN `owned_vehicles` v ON UPPER(TRIM(v.`plate`)) = UPPER(TRIM(p.`plate`))
        WHERE (v.`plate` IS NOT NULL AND (v.`stored` = 0 OR COALESCE(v.`isTowedOut`, 0) = 1))
            OR (p.`is_owned` = 1 AND v.`plate` IS NULL)
        LIMIT %s
    ]]):format(STATE_TABLE, batchSize)) or {}

    if operationEpoch ~= persistenceEpoch or clearingStates then
        return
    end

    for _, row in ipairs(rows) do
        local key = row.storage_key
        local plate = normalizePlate(row.plate)

        if key then
            local root = findManagedEntityForKey(key)
            local trailer = findManagedEntityForKey(getTrailerKey(key))

            if root ~= 0 and (isVehiclePersistSpawning(root) or vehicleHasOccupants(root)) then
                goto continue_garage_sync
            end

            removeTrackedVehicle(key, true, true, 'garage_sync_stored')

            if root ~= 0 then
                deleteManagedEntityForKey(root, key, 'garage_sync_stored')
            end

            if trailer ~= 0 then
                deleteManagedEntityForKey(trailer, getTrailerKey(key), 'garage_sync_trailer')
            end

            removePersistedState(key)
            setLifecycle(key, 'stored')
        end

        if plate then
            ownedKeysByPlate[plate] = nil
            garageTransitions[plate] = nil
            vehicleRecordCache[plate] = nil
        end

        ::continue_garage_sync::
    end
end

local function processRespawns()
    if not initialized or clearingStates then
        return
    end

    expireGarageSpawnLeases()
    local operationEpoch = persistenceEpoch

    rebuildPlayerGrid()
    local now = os.time()
    local respawnDistance = tonumber(getConfig({ 'Persistence', 'RespawnDistance' }, 250.0)) or 250.0
    local respawnDelay = tonumber(getConfig({ 'Persistence', 'RespawnDelay' }, 10)) or 10
    local scanBatch = math.max(1, math.floor(tonumber(getConfig({ 'Persistence', 'RespawnScanBatch' }, 250)) or 250))
    local selectedKeys
    selectedKeys, respawnCursor = collectTrackedKeys(respawnCursor, scanBatch)
    local candidates = {}
    local candidatesByKey = {}
    local trailerCandidatesByKey = {}
    local spawnCandidates = {}
    local ownedByPlate = {}

    for _, key in ipairs(selectedKeys) do
        local data = trackedVehicles[key]
        local lifecycle = vehicleLifecycle[key]

        if data and not (lifecycle and (lifecycle.phase == 'stored' or lifecycle.phase == 'storing')) then
            if isTrackedRootEntity(data) then
                if not isVehiclePersistSpawning(data.entity) then
                    markManaged(data.entity, key)
                end

                data.missingSince = nil
            else
                local previousEntity = data.entity or 0
                local externalDeleteDistance = tonumber(getConfig({ 'Persistence', 'ExternalDeleteDistance' }, 30.0)) or 30.0

                if data.isOwned
                    and previousEntity ~= 0
                    and data.coords
                    and not DoesEntityExist(previousEntity)
                    and playerIsNear(data.coords, externalDeleteDistance) then
                    removeTrackedVehicle(key, false, true)
                    removePersistedState(key)
                    setLifecycle(key, 'stored')
                    goto continue_respawn_scan
                end

                data.entity = 0

                if data.coords and playerIsNear(data.coords, respawnDistance) then
                    data.missingSince = data.missingSince or now
                    spawnCandidates[#spawnCandidates + 1] = data

                    if not data.nextWorldProbe or data.nextWorldProbe <= now then
                        candidates[#candidates + 1] = data
                        candidatesByKey[key] = data
                        trailerCandidatesByKey[getTrailerKey(key)] = data

                        if data.isOwned then
                            ownedByPlate[data.plate] = key
                        end
                    end
                end
            end
        end

        ::continue_respawn_scan::
    end

    if #candidates > 0 then
        for _, entity in ipairs(GetAllVehicles() or {}) do
            if isNetworkedVehicle(entity)
                and not isVehiclePersistSpawning(entity)
                and not isVehiclePersistIgnored(entity) then
                local stateKey = Entity(entity).state.vehiclePersistKey
                local trailerOwner = type(stateKey) == 'string' and trailerCandidatesByKey[stateKey] or nil
                local data = type(stateKey) == 'string' and candidatesByKey[stateKey] or nil

                if trailerOwner then
                    trailerOwner.trailerEntity = entity
                end

                if not data and not trailerOwner then
                    local plate = normalizePlate(GetVehicleNumberPlateText(entity))
                    local key = plate and ownedByPlate[plate]
                    data = key and candidatesByKey[key] or nil
                end

                if data and doesEntityMatchTrackedModel(data, entity) then
                    data.entity = entity
                    data.missingSince = nil
                    data.nextWorldProbe = nil
                    markManaged(entity, data.key)
                    candidatesByKey[data.key] = nil
                end
            end
        end

        for _, data in ipairs(candidates) do
            if candidatesByKey[data.key] == data then
                data.nextWorldProbe = now + 30
            end
        end
    end

    local verifyPlates = {}
    local seenVerifyPlates = {}

    for _, data in ipairs(spawnCandidates) do
        if data.isOwned and data.plate and not seenVerifyPlates[data.plate] then
            seenVerifyPlates[data.plate] = true
            verifyPlates[#verifyPlates + 1] = data.plate
        end
    end

    local verifiedRecords = #verifyPlates > 0 and buildOwnedRecordMap(verifyPlates, operationEpoch) or {}

    if operationEpoch ~= persistenceEpoch or clearingStates then
        return
    end

    if verifiedRecords == nil then
        return
    end

    local maxSpawns = math.max(1, tonumber(getConfig({ 'Persistence', 'MaxSpawnsPerTick' }, 2)) or 2)
    local spawned = 0

    for _, data in ipairs(spawnCandidates) do
        if spawned >= maxSpawns then
            break
        end

        local lifecycle = vehicleLifecycle[data.key]
        local record = data.isOwned and (verifiedRecords[data.plate] or { exists = false }) or nil

        if record and (not record.exists or record.stored or record.impounded) then
            removeTrackedVehicle(data.key, true, nil, 'respawn_record_stored')
            removePersistedState(data.key)
            vehicleLifecycle[data.key] =
            {
                phase = 'stored',
                generation = lifecycle and lifecycle.generation + 1 or 1,
                changedAt = now
            }
        elseif (not data.entity or data.entity == 0 or not DoesEntityExist(data.entity))
            and not data.spawning
            and not (lifecycle and (lifecycle.phase == 'stored' or lifecycle.phase == 'storing'))
            and data.missingSince
            and now - data.missingSince >= respawnDelay
            and data.coords
            and playerIsNear(data.coords, respawnDistance)
            and (not data.nextSpawnAttempt or data.nextSpawnAttempt <= now) then
            data.nextSpawnAttempt = now + 30

            if spawnTrackedVehicle(data) then
                spawned = spawned + 1
            end
        end
    end
end

local function sendOwnedVehicleToGarage(plate, ownerIdentifier)
    if clearingStates then
        return false
    end

    local query = [[
        UPDATE `owned_vehicles`
        SET `stored` = 0
        WHERE `plate` = ?
            AND `stored` = 1
            AND COALESCE(`isTowedOut`, 0) = 0
    ]]
    local parameters = { plate }

    if ownerIdentifier then
        query = query .. ' AND `owner` = ?'
        parameters[#parameters + 1] = ownerIdentifier
    end

    lifecycleWriteCount = lifecycleWriteCount + 1
    local ok, updated = pcall(MySQL.update.await, query, parameters)

    local affected = tonumber(updated) or 0

    if not ok or updated == false or affected <= 0 then
        lifecycleWriteCount = math.max(0, lifecycleWriteCount - 1)
        if not ok then
            print(('[Vehicle Persist V2] Failed to send %s to garage: %s'):format(plate, tostring(updated)))
        end

        return false
    end

    local cached = vehicleRecordCache[plate] or {}
    cached.exists = true
    cached.stored = true
    cached.impounded = false
    cached.expiresAt = GetGameTimer() + (tonumber(getConfig({ 'Tracking', 'StateCacheLifetime' }, 60000)) or 60000)
    cached.stateEpoch = getStateEpoch(getOwnedKey(plate))
    vehicleRecordCache[plate] = cached
    lifecycleWriteCount = math.max(0, lifecycleWriteCount - 1)
    return true
end

vehicleHasOccupants = function(entity)
    if entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    local ok, maxPassengers = pcall(GetVehicleMaxNumberOfPassengers, entity)
    maxPassengers = ok and tonumber(maxPassengers) or 0

    for seat = -1, maxPassengers do
        local ped = GetPedInVehicleSeat(entity, seat)

        if ped ~= 0 and DoesEntityExist(ped) then
            return true
        end
    end

    return false
end

local function returnDisconnectedOwnerVehicles()
    if not initialized or clearingStates or getConfig({ 'Cleanup', 'ReturnDisconnectedVehicles' }, true) ~= true then
        return
    end

    local now = os.time()
    local delay = math.max(60, math.floor((tonumber(getConfig({ 'Cleanup', 'ReturnDisconnectedAfterMinutes' }, 10)) or 10) * 60))
    local batchSize = math.max(1, math.floor(tonumber(getConfig({ 'Cleanup', 'ReturnDisconnectedBatchSize' }, 50)) or 50))
    local processed = 0

    for ownerIdentifier, droppedAt in pairs(disconnectedOwners) do
        if processed >= batchSize then
            break
        end

        if onlineOwners[ownerIdentifier] then
            disconnectedOwners[ownerIdentifier] = nil
        elseif now - droppedAt >= delay then
            for key, data in pairs(trackedVehicles) do
                if processed >= batchSize then
                    break
                end

                local entityExists = data.entity and data.entity ~= 0 and DoesEntityExist(data.entity)

                if data.isOwned
                    and data.ownerIdentifier == ownerIdentifier
                    and data.plate
                    and (not entityExists or not vehicleHasOccupants(data.entity)) then
                    if sendOwnedVehicleToGarage(data.plate, ownerIdentifier) then
                        removeTrackedVehicle(key, true, true, 'owner_disconnected')
                        removePersistedState(key)
                        setLifecycle(key, 'stored')
                        processed = processed + 1
                    end
                end
            end

            if processed < batchSize then
                local rows = MySQL.query.await(([[
                    SELECT p.`storage_key`, p.`plate`
                    FROM `%s` p
                    INNER JOIN `owned_vehicles` v ON UPPER(TRIM(v.`plate`)) = UPPER(TRIM(p.`plate`))
                    WHERE p.`is_owned` = 1
                        AND v.`owner` = ?
                        AND v.`stored` = 1
                        AND COALESCE(v.`isTowedOut`, 0) = 0
                    LIMIT %s
                ]]):format(STATE_TABLE, batchSize - processed), { ownerIdentifier }) or {}

                for _, row in ipairs(rows) do
                    if processed >= batchSize then
                        break
                    end

                    local key = row.storage_key
                    local plate = normalizePlate(row.plate)

                    if key and plate and sendOwnedVehicleToGarage(plate, ownerIdentifier) then
                        removeTrackedVehicle(key, true, true)
                        removePersistedState(key)
                        setLifecycle(key, 'stored')
                        processed = processed + 1
                    end
                end
            end

            disconnectedOwners[ownerIdentifier] = nil
        end
    end
end

local function runStateCleanup()
    if not initialized or clearingStates or not getConfig({ 'Cleanup', 'Enabled' }, true) then
        return
    end

    local operationEpoch = persistenceEpoch

    rebuildPlayerGrid()
    local threshold = math.max(60, math.floor(tonumber(getConfig({ 'Cleanup', 'MissingVehicleThreshold' }, 1800)) or 1800))
    local batchSize = math.max(1, math.floor(tonumber(getConfig({ 'Cleanup', 'BatchSize' }, 50)) or 50))
    local rows = MySQL.query.await(([[
        SELECT `storage_key`, `plate`, `coords`, `is_owned`
        FROM `%s`
        WHERE `updated_at` < DATE_SUB(NOW(), INTERVAL %s SECOND)
        ORDER BY `updated_at`
        LIMIT %s
    ]]):format(STATE_TABLE, threshold, batchSize)) or {}

    if operationEpoch ~= persistenceEpoch or clearingStates then
        return
    end

    local respawnDistance = tonumber(getConfig({ 'Persistence', 'RespawnDistance' }, 250.0)) or 250.0

    for _, row in ipairs(rows) do
        local key = row.storage_key
        local data = trackedVehicles[key]
        local coords = data and data.coords or safeDecode(row.coords)
        local entityExists = data and isTrackedRootEntity(data)

        if not dirtyVehicles[key] and not entityExists and coords and not playerIsNear(coords, respawnDistance) then
            local isOwned = tonumber(row.is_owned) == 1
            local canRemove = not isOwned

            if isOwned and getConfig({ 'Cleanup', 'SendToGarage' }, true) then
                canRemove = sendOwnedVehicleToGarage(row.plate)
            end

            if canRemove then
                removeTrackedVehicle(key, false, true)
                removePersistedState(key)
                setLifecycle(key, 'stored')
                debugLog(('Cleaned stale state %s'):format(row.plate))
            end
        end
    end
end

local function runDistantEntityCleanup()
    if not initialized or clearingStates or not getConfig({ 'Cleanup', 'DeleteDistantVehicles' }, false) then
        return
    end

    local now = os.time()
    local interval = math.max(1, math.floor((tonumber(getConfig({ 'Cleanup', 'DistantVehicleInterval' }, 900000)) or 900000) / 1000))

    if now - lastDistantCleanup < interval then
        return
    end

    lastDistantCleanup = now
    rebuildPlayerGrid()
    local distance = tonumber(getConfig({ 'Cleanup', 'DistantVehicleDistance' }, 1000.0)) or 1000.0

    for key, data in pairs(trackedVehicles) do
        if isTrackedRootEntity(data) then
            local coords = GetEntityCoords(data.entity)
            local currentCoords = { x = coords.x, y = coords.y, z = coords.z }

            if data.isOwned
                and not isVehiclePersistSpawning(data.entity)
                and not vehicleHasOccupants(data.entity)
                and not playerIsNear(currentCoords, distance) then
                data.coords = currentCoords
                data.heading = GetEntityHeading(data.entity)
                queuePersist(data)
                local rootEntity = data.entity
                local trailerEntity = getTrackedTrailerEntity(data)

                markFadeOutAndWait(rootEntity)

                if trailerEntity ~= 0 then
                    markFadeOutAndWait(trailerEntity)
                end

                deleteManagedEntityForKey(data.entity, key, 'distant_cleanup')
                deleteTrackedTrailer(data)
                data.entity = 0
                data.missingSince = now
                data.nextWorldProbe = now + 30

                if not dirtyVehicles[key] then
                    releaseCachedProperties(data)
                end

                debugLog(('Despawned distant vehicle %s'):format(key))
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(math.max(1000, tonumber(getConfig({ 'Persistence', 'FlushInterval' }, 15000)) or 15000))
        flushDirtyVehicles()
    end
end)

local isSuspiciousCreatesEnabled = nil
AddEventHandler('entityCreating', function(entity)
    if isSuspiciousCreatesEnabled == nil then
        isSuspiciousCreatesEnabled = (getConfig({ 'Diagnostics', 'SuspiciousCreates' }, false) == true)
    end
    if not isSuspiciousCreatesEnabled then
        return
    end

    local typeOk, entityType = pcall(GetEntityType, entity)
    local populationOk, populationType = pcall(GetEntityPopulationType, entity)

    if not typeOk or not populationOk or entityType ~= 2 or populationType ~= 7 then
        return
    end

    local ownerGetter = NetworkGetFirstEntityOwner or NetworkGetEntityOwner
    local ownerOk, firstOwner = pcall(ownerGetter, entity)

    if not ownerOk then
        firstOwner = 0
    end

    if tonumber(firstOwner) and firstOwner > 0 and GetPlayerName(firstOwner) then
        return
    end

    local modelOk, model = pcall(GetEntityModel, entity)
    local scriptOk = false
    local script

    if GetEntityScript then
        scriptOk, script = pcall(GetEntityScript, entity)
    end

    if not modelOk then
        model = 0
    end

    if not scriptOk then
        script = nil
    end

    print(('[vehicle_persist][entity-audit] suspicious_create entity=%s firstOwner=%s model=%s script=%s'):format(
        tostring(entity or 0),
        tostring(firstOwner or 0),
        tostring(model or 0),
        tostring(script or '')
    ))
end)

CreateThread(function()
    while true do
        Wait(math.max(5000, tonumber(getConfig({ 'Persistence', 'ReconcileInterval' }, 60000)) or 60000))
        reconcileTrackedVehicles()
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(500, tonumber(getConfig({ 'Persistence', 'GarageSyncInterval' }, 1000)) or 1000))
        syncGarageStoredStates()
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(1000, tonumber(getConfig({ 'Persistence', 'SpawnTickInterval' }, 5000)) or 5000))
        processRespawns()
        runDistantEntityCleanup()
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(60000, tonumber(getConfig({ 'Cleanup', 'CheckInterval' }, 300000)) or 300000))
        runStateCleanup()
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(10000, tonumber(getConfig({ 'Cleanup', 'ReturnDisconnectedCheckInterval' }, 60000)) or 60000))
        returnDisconnectedOwnerVehicles()
    end
end)

AddEventHandler('esx:playerLoaded', function(playerSource, xPlayer)
    local identifier = xPlayer and xPlayer.identifier or getPlayerIdentifier(playerSource)

    if identifier then
        onlineOwners[identifier] = true
        disconnectedOwners[identifier] = nil
    end
end)

AddEventHandler('playerDropped', function()
    local playerSource = source
    local identifier = getPlayerIdentifier(playerSource)

    if identifier then
        onlineOwners[identifier] = nil
        disconnectedOwners[identifier] = os.time()
    end

    for netId, lease in pairs(garageSpawnLeases) do
        if lease.source == playerSource then
            garageSpawnLeases[netId] = nil
            local entity = NetworkGetEntityFromNetworkId(netId)

            if isNetworkedVehicle(entity) and Entity(entity).state.vehiclePersistSpawning == true then
                Entity(entity).state:set('vehiclePersistSpawning', false, true)
            end
        end
    end

    recentVehicleAccess[playerSource] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == RESOURCE_NAME then
        if not flushAllDirtyVehicles() and (next(dirtyVehicles) or next(deleteTokens)) then
            print('[Vehicle Persist V2] Some persistence writes were left queued during resource stop.')
        end
    end
end)

local function validateGarageVehicle(playerSource, plate, netId)
    local normalizedPlate = normalizePlate(plate)
    local entity = validateClientVehicle(playerSource, netId)

    if not normalizedPlate
        or not entity
        or isVehiclePersistIgnored(entity)
        or normalizePlate(GetVehicleNumberPlateText(entity)) ~= normalizedPlate then
        return nil
    end

    return normalizedPlate, entity
end

lib.callback.register('vehicle_persist:server:garageSpawnStarted', function(source, netId)
    netId = tonumber(netId)

    local entity = netId and select(1, validateClientVehicle(source, netId)) or nil

    if not entity or NetworkGetEntityOwner(entity) ~= source then
        return false
    end

    netId = math.floor(netId)
    garageSpawnLeases[netId] =
    {
        source = source,
        expiresAt = GetGameTimer() + math.max(5000, tonumber(getConfig({ 'Persistence', 'SpawnTransitionLeaseMs' }, 30000)) or 30000)
    }
    Entity(entity).state:set('vehiclePersistSpawning', true, true)
    return true
end)

RegisterNetEvent('vehicle_persist:server:garageSpawnCancelled', function(netId)
    netId = math.floor(tonumber(netId) or 0)
    local lease = garageSpawnLeases[netId]

    if netId <= 0 or not lease or lease.source ~= source then
        return
    end

    garageSpawnLeases[netId] = nil
    local entity = NetworkGetEntityFromNetworkId(netId)

    if isNetworkedVehicle(entity) then
        Entity(entity).state:set('vehiclePersistSpawning', false, true)
    end
end)

lib.callback.register('vehicle_persist:server:garageStoreBegin', function(source, plate, netId, deformation)
    if clearingStates then
        return false
    end

    local operationEpoch = persistenceEpoch

    local normalizedPlate, entity = validateGarageVehicle(source, plate, netId)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not normalizedPlate or not xPlayer then
        return false
    end

    local key = getOwnedKey(normalizedPlate)
    local expectedStateEpoch = getStateEpoch(key)
    local record = getOwnedRecord(normalizedPlate, true)

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key) then
        return false
    end

    if not record.exists
        or record.stored
        or record.impounded
        or not isRegisteredVehicleModel(normalizedPlate, entity)
        or (getConfig({ 'Tracking', 'RequirePlayerOwnership' }, false) and record.owner ~= xPlayer.identifier) then
        return false
    end

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key) then
        return false
    end

    if garageTransitions[normalizedPlate] then
        return true
    end

    local storedDeformation

    if deformation ~= nil then
        storedDeformation = VehiclePersistDeformation.Normalize(deformation)

        if not storedDeformation then
            return false
        end

        local encoded = safeEncode(storedDeformation)
        local ok, updated = pcall(
            MySQL.update.await,
            'UPDATE `owned_vehicles` SET `deformation` = ? WHERE UPPER(TRIM(`plate`)) = ? AND `owner` = ?',
            { encoded, normalizedPlate, record.owner }
        )

        if not ok or updated == false then
            return false
        end

        Entity(entity).state:set('deformation', #storedDeformation > 0 and storedDeformation or nil, true)
    end

    local data = getCurrentTrackedVehicle(key) or loadTrackedVehicle(key)

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key) then
        return false
    end

    if data then
        data.entity = entity

        if storedDeformation then
            data.stateBags = data.stateBags or {}
            data.stateBags.deformation = #storedDeformation > 0 and storedDeformation or nil

            if not next(data.stateBags) then
                data.stateBags = nil
            end

            data.serializedStateBags = nil
        end
    end

    local lifecycle = setLifecycle(key, 'storing')
    lifecycle.pending = data
    removeTrackedVehicle(key, false, false)
    garageTransitions[normalizedPlate] =
    {
        key = key,
        pending = data,
        expiresAt = os.time() + 90
    }

    debugLog(('Garage store prepared for %s'):format(normalizedPlate))
    return true
end)

lib.callback.register('vehicle_persist:server:garageSpawnReady', function(source, plate, netId, mods, deformation)
    if clearingStates then
        return false
    end

    local operationEpoch = persistenceEpoch

    local normalizedPlate, entity = validateGarageVehicle(source, plate, netId)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not normalizedPlate or not xPlayer or type(mods) ~= 'table' then
        return false
    end

    local key = getOwnedKey(normalizedPlate)
    local expectedStateEpoch = getStateEpoch(key)

    local encodedMods = safeEncode(mods)
    local maxBytes = tonumber(getConfig({ 'Tracking', 'SnapshotMaxBytes' }, 60000)) or 60000

    if not encodedMods or #encodedMods > maxBytes then
        return false
    end

    local spawnDeformation = VehiclePersistDeformation.Normalize(deformation or Entity(entity).state.deformation)

    if not spawnDeformation then
        return false
    end

    local record = getOwnedRecord(normalizedPlate, true)

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key) then
        return false
    end

    if not record.exists
        or record.impounded
        or not isRegisteredVehicleModel(normalizedPlate, entity)
        or (getConfig({ 'Tracking', 'RequirePlayerOwnership' }, false) and record.owner ~= xPlayer.identifier) then
        return false
    end

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key) then
        return false
    end

    local coords = GetEntityCoords(entity)
    local previous = getCurrentTrackedVehicle(key)
        or (garageTransitions[normalizedPlate] and garageTransitions[normalizedPlate].pending)
        or loadTrackedVehicle(key)

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key) then
        return false
    end

    if previous and isTrackedRootEntity(previous) and previous.entity ~= entity then
        return false
    end

    if previous and isCurrentTrackedVehicle(previous) then
        deleteTrackedTrailer(previous)
    end

    local lifecycle = setLifecycle(key, 'outside')
    local data =
    {
        key = key,
        plate = normalizedPlate,
        model = GetEntityModel(entity),
        vehicleClass = getServerVehicleClass(entity) or (previous and previous.vehicleClass),
        coords =
        {
            x = coords.x,
            y = coords.y,
            z = coords.z
        },
        heading = GetEntityHeading(entity),
        mods = mods,
        serializedMods = encodedMods,
        stateBags = #spawnDeformation > 0 and { deformation = spawnDeformation } or nil,
        isOwned = true,
        ownerIdentifier = record.owner,
        entity = entity,
        engineOn = GetIsVehicleEngineRunning(entity),
        generation = lifecycle.generation,
        revision = previous and previous.revision or 0,
        hydrated = true
    }

    stampTrackedVehicle(data)
    trackedVehicles[key] = data
    ownedKeysByPlate[normalizedPlate] = key
    garageTransitions[normalizedPlate] = nil
    setOwnedOutside(normalizedPlate)

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key)
        or not isCurrentTrackedVehicle(data) then
        return false
    end

    markManaged(entity, key)
    garageSpawnLeases[NetworkGetNetworkIdFromEntity(entity)] = nil
    Entity(entity).state:set('vehiclePersistSpawning', false, true)
    persistNow(data)
    debugLog(('Garage spawn completed for %s'):format(normalizedPlate))
    return true
end)

local function rememberImpoundedEntities(plate, key, data)
    local root = getManagedEntityForKey(data and data.entity or 0, key)
    local trailer = getManagedEntityForKey(data and data.trailerEntity or 0, getTrailerKey(key))

    if root == 0 and trailer == 0 then
        impoundedEntities[plate] = nil
        return false
    end

    impoundedEntities[plate] =
    {
        key = key,
        root = root,
        trailer = trailer
    }
    return true
end

local function deleteImpoundedEntities(plate, key)
    local captured = impoundedEntities[plate]
    local root = getManagedEntityForKey(captured and captured.root or 0, key)
    local trailer = getManagedEntityForKey(captured and captured.trailer or 0, getTrailerKey(key))

    if root == 0 then
        root = findManagedEntityForKey(key)
    end

    if trailer == 0 then
        trailer = findManagedEntityForKey(getTrailerKey(key))
    end

    local deleted = false

    if root ~= 0 then
        deleted = deleteManagedEntityForKey(root, key) or deleted
    end

    if trailer ~= 0 then
        deleted = deleteManagedEntityForKey(trailer, getTrailerKey(key)) or deleted
    end

    impoundedEntities[plate] = nil
    return deleted
end

exports('untrackVehicle', function(plate, shouldDelete)
    if clearingStates then
        return false
    end

    local normalizedPlate = normalizePlate(plate)

    if not normalizedPlate then
        return false
    end

    local key = getOwnedKey(normalizedPlate)
    local deleteEntity = shouldDelete == true
    local data = getCurrentTrackedVehicle(key)
    local deleted = false

    if deleteEntity then
        data = removeTrackedVehicle(key, true, true, 'external_untrack')
        deleted = deleteImpoundedEntities(normalizedPlate, key)
    else
        rememberImpoundedEntities(normalizedPlate, key, data)
        data = removeTrackedVehicle(key, false, false)
    end

    garageTransitions[normalizedPlate] = nil
    vehicleRecordCache[normalizedPlate] = nil
    removePersistedState(key)
    setLifecycle(key, 'stored')
    debugLog(('Untracked %s (delete=%s)'):format(normalizedPlate, tostring(shouldDelete == true)))
    return data ~= nil or deleted
end)

local function findTrackedByPlate(plate)
    local owned = getCurrentTrackedVehicle(getOwnedKey(plate))

    if owned then
        return owned
    end

    for _, data in pairs(trackedVehicles) do
        if isCurrentTrackedVehicle(data) and data.plate == plate then
            return data
        end
    end
end

local function getStoredPosition(plateOrKey)
    local data = trackedVehicles[plateOrKey]
    local plate = normalizePlate(plateOrKey)

    if not data and plate then
        data = findTrackedByPlate(plate)
    end

    if data and data.coords then
        return copyCoords(data.coords), data.heading
    end

    local key = type(plateOrKey) == 'string' and plateOrKey:find(':', 1, true) and plateOrKey or nil

    if not key and plate then
        key = getOwnedKey(plate)
    end

    if not key then
        return nil
    end

    local row = MySQL.single.await(([[
        SELECT `coords`, `heading`
        FROM `%s`
        WHERE `storage_key` = ?
        LIMIT 1
    ]]):format(STATE_TABLE), { key })
    local coords = row and safeDecode(row.coords)

    if copyCoords(coords) then
        return copyCoords(coords), tonumber(row.heading) or 0.0
    end
end

exports('GetVehiclePosition', function(plate)
    local coords, heading = getStoredPosition(plate)

    if coords then
        coords.heading = heading
    end

    return coords
end)

exports('GetVehicleCoords', function(plate)
    local coords, heading = getStoredPosition(plate)

    if coords then
        coords.heading = heading
    end

    return coords
end)

exports('UpdateVehicle', function(plateOrEntity)
    local data
    local entity

    if type(plateOrEntity) == 'number' and isNetworkedVehicle(plateOrEntity) then
        entity = plateOrEntity
        local key = Entity(entity).state.vehiclePersistKey
        data = type(key) == 'string' and trackedVehicles[key] or nil
    elseif type(plateOrEntity) == 'string' then
        local plate = normalizePlate(plateOrEntity)
        data = plate and findTrackedByPlate(plate) or nil
        entity = data and data.entity or 0
    end

    if data and entity and isManagedEntityForKey(entity, data.key) then
        data.entity = entity
    end

    if not data or not isTrackedRootEntity(data) then
        return false
    end

    entity = data.entity

    if type(data.mods) ~= 'table' and not hydrateTrackedVehicle(data) then
        return false
    end

    local coords = GetEntityCoords(entity)
    data.coords = { x = coords.x, y = coords.y, z = coords.z }
    data.heading = GetEntityHeading(entity)
    data.engineOn = GetIsVehicleEngineRunning(entity)
    if type(data.runtime) == 'table' then
        data.runtime.engineOn = data.engineOn
    end
    data.serializedRuntime = nil
    queuePersist(data)
    return true
end)

local function notify(playerSource, notificationType, description)
    if playerSource == 0 then
        print(('[Vehicle Persist V2] %s'):format(description))
        return
    end

    TriggerClientEvent('ox_lib:notify', playerSource,
    {
        type = notificationType,
        description = description
    })
end

local function isAdmin(playerSource)
    if playerSource == 0 then
        return true
    end

    if GetResourceState('aCore') ~= 'started' then
        return false
    end

    local ok, allowed = pcall(function()
        return exports['aCore']:IsAdmin(playerSource)
    end)

    return ok and allowed == true
end

local function getGarageOrImpoundCoords(isStored, isImpounded, vehicleGarage, vehicleImpound)
    local query
    local index

    if isStored then
        query = 'SELECT `Coords` FROM `opgarages_garages2` WHERE `Index` = ? LIMIT 1'
        index = vehicleGarage
    elseif isImpounded then
        query = 'SELECT `Coords` FROM `opgarages_impounds` WHERE `Index` = ? LIMIT 1'
        index = vehicleImpound
    else
        return nil
    end

    local result = MySQL.single.await(query, { index })
    local data = result and safeDecode(result.Coords)

    if not data then
        return nil
    end

    if isStored then
        if data.AccessPoint and (data.AccessPoint.x ~= 0 or data.AccessPoint.y ~= 0) then
            return data.AccessPoint
        end

        if data.CenterOfZone and data.CenterOfZone[1] then
            return data.CenterOfZone[1]
        end
    end

    return data
end

local function findWorldVehicleByPlate(plate, expectedModel)
    for _, entity in ipairs(GetAllVehicles() or {}) do
        if isNetworkedVehicle(entity)
            and normalizePlate(GetVehicleNumberPlateText(entity)) == plate
            and (expectedModel == nil or GetEntityModel(entity) == expectedModel) then
            return entity
        end
    end

    return 0
end

local function loadOwnedVehicleFromDatabase(plate)
    local key = getOwnedKey(plate)
    local expectedPersistenceEpoch = persistenceEpoch
    local expectedStateEpoch = getStateEpoch(key)
    local row = MySQL.single.await(
        'SELECT `owner`, `vehicle` FROM `owned_vehicles` WHERE `plate` = ? LIMIT 1',
        { plate }
    )

    if expectedPersistenceEpoch ~= persistenceEpoch
        or expectedStateEpoch ~= getStateEpoch(key)
        or clearingStates
        or not row then
        return nil
    end

    local current = trackedVehicles[key]

    if current then
        return isCurrentTrackedVehicle(current) and current or nil
    end

    local mods = safeDecode(row.vehicle)
    local model = mods and mods.model

    if type(model) == 'string' then
        model = tonumber(model) or joaat(model)
    end

    if type(mods) ~= 'table' or not validNumber(model) or model == 0 then
        return nil
    end

    local data =
    {
        key = key,
        plate = plate,
        model = model,
        vehicleClass = normalizeVehicleClass(mods.vehicleClass),
        coords = { x = 0.0, y = 0.0, z = 0.0 },
        heading = 0.0,
        mods = mods,
        serializedMods = safeEncode(mods),
        isOwned = true,
        ownerIdentifier = row.owner,
        entity = 0,
        hydrated = true
    }

    stampTrackedVehicle(data)
    trackedVehicles[key] = data
    ownedKeysByPlate[plate] = key
    setLifecycle(key, 'outside')
    return data
end

local function showOwnedVehiclesMenu(playerSource, targetIdentifier, isForAdmin, targetPlayerId)
    local rows = MySQL.query.await(
        'SELECT `plate`, `vehicle`, `stored`, `isTowedOut` FROM `owned_vehicles` WHERE `owner` = ?',
        { targetIdentifier }
    ) or {}

    if #rows == 0 then
        notify(playerSource, 'error', isForAdmin and 'Người chơi này không sở hữu phương tiện nào' or 'Bạn không sở hữu phương tiện nào để tìm kiếm')
        return
    end

    local vehicles = {}

    for _, row in ipairs(rows) do
        local mods = safeDecode(row.vehicle) or {}
        local status = 'Bên Ngoài Garage'

        if isVehicleImpounded(row.isTowedOut) then
            status = 'Bị Giam Giữ'
        elseif isVehicleStored(row.stored) then
            status = 'Trong Garage'
        end

        vehicles[#vehicles + 1] =
        {
            plate = row.plate,
            model = mods.model,
            status = status
        }
    end

    TriggerClientEvent('vehicle_persist:client:showVehiclesMenu', playerSource, vehicles, isForAdmin, targetPlayerId)
end

local function waypointGarageOrImpound(playerSource, row)
    local stored = isVehicleStored(row.stored)
    local impounded = isVehicleImpounded(row.isTowedOut)

    if not stored and not impounded then
        return false
    end

    local coords = getGarageOrImpoundCoords(stored, impounded, row.vehicleGarage, row.vehicleImpound)

    if coords then
        TriggerClientEvent('vehicle_persist:client:setWaypoint', playerSource, coords)
        notify(playerSource, 'success', stored and 'Phương tiện đang trong Garage. Đã đánh dấu vị trí' or 'Phương tiện đang bị giam giữ. Đã đánh dấu vị trí')
    else
        notify(playerSource, 'error', stored and 'Phương tiện hiện đang trong Garage' or 'Phương tiện hiện đang bị giam giữ')
    end

    return true
end

local function locateOwnedVehicle(playerSource, plate, requireOwner)
    if clearingStates then
        return
    end

    local operationEpoch = persistenceEpoch
    local key = getOwnedKey(plate)
    local expectedStateEpoch = getStateEpoch(key)

    local xPlayer = ESX.GetPlayerFromId(playerSource)

    if not xPlayer then
        return
    end

    local row = MySQL.single.await(
        'SELECT `owner`, `stored`, `isTowedOut`, `vehicleGarage`, `vehicleImpound` FROM `owned_vehicles` WHERE `plate` = ? LIMIT 1',
        { plate }
    )

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key) then
        return
    end

    if not row or (requireOwner and row.owner ~= xPlayer.identifier) then
        notify(playerSource, 'error', requireOwner and 'Bạn không sở hữu phương tiện này' or 'Không tìm thấy phương tiện')
        return
    end

    if waypointGarageOrImpound(playerSource, row) then
        return
    end

    local entity = findWorldVehicleByPlate(plate)

    if entity ~= 0 then
        local coords = GetEntityCoords(entity)
        TriggerClientEvent('vehicle_persist:client:setWaypoint', playerSource, coords)
        notify(playerSource, 'success', 'Đã đánh dấu vị trí phương tiện')
        return
    end

    local coords = getStoredPosition(plate)

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key) then
        return
    end

    if coords then
        TriggerClientEvent('vehicle_persist:client:setWaypoint', playerSource, coords)
        notify(playerSource, 'success', 'Đã đánh dấu vị trí phương tiện')
        return
    end

    if sendOwnedVehicleToGarage(plate, requireOwner and xPlayer.identifier or nil) then
        if operationEpoch ~= persistenceEpoch
            or clearingStates
            or expectedStateEpoch ~= getStateEpoch(key) then
            return
        end

        removeTrackedVehicle(key, false, true)
        removePersistedState(key)
        setLifecycle(key, 'stored')
        notify(playerSource, 'warning', 'Phương tiện không còn tồn tại. Hệ thống đã đưa xe về Garage')
    else
        notify(playerSource, 'error', 'Không thể khôi phục trạng thái phương tiện')
    end
end

local function bringOwnedVehicle(playerSource, plate)
    if clearingStates or not isAdmin(playerSource) then
        return
    end

    local operationEpoch = persistenceEpoch

    local ped = GetPlayerPed(playerSource)

    if ped == 0 or not DoesEntityExist(ped) then
        return
    end

    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local key = getOwnedKey(plate)
    local expectedStateEpoch = getStateEpoch(key)
    local data = getCurrentTrackedVehicle(key) or loadTrackedVehicle(key)

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key) then
        return
    end

    if not data then
        data = loadOwnedVehicleFromDatabase(plate)

        if operationEpoch ~= persistenceEpoch
            or clearingStates
            or expectedStateEpoch ~= getStateEpoch(key) then
            return
        end
    end

    if not data then
        notify(playerSource, 'error', 'Không tồn tại biển số này trong DB')
        return
    end

    if type(data.mods) ~= 'table' and not hydrateTrackedVehicle(data) then
        notify(playerSource, 'error', 'Không thể đọc dữ liệu phương tiện')
        return
    end

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key)
        or not isCurrentTrackedVehicle(data) then
        return
    end

    local entity = isTrackedRootEntity(data) and data.entity or 0

    if entity == 0 then
        local worldEntity = findWorldVehicleByPlate(plate, data.model)

        if worldEntity ~= 0 then
            local stateKey = Entity(worldEntity).state.vehiclePersistKey

            if stateKey == nil or stateKey == key then
                entity = worldEntity
            end
        end
    end

    data.coords = { x = coords.x, y = coords.y, z = coords.z }
    data.heading = heading

    if entity and entity ~= 0 and DoesEntityExist(entity) then
        SetEntityCoords(entity, coords.x, coords.y, coords.z, false, false, false, true)
        SetEntityHeading(entity, heading)
        data.entity = entity
        markManaged(entity, key)
    elseif not spawnTrackedVehicle(data) then
        notify(playerSource, 'error', 'Không thể tạo lại phương tiện')
        return
    end

    setLifecycle(key, 'outside')
    setOwnedOutside(plate)

    if operationEpoch ~= persistenceEpoch
        or clearingStates
        or expectedStateEpoch ~= getStateEpoch(key)
        or not isCurrentTrackedVehicle(data) then
        return
    end

    persistNow(data)
    notify(playerSource, 'success', ('Đã đưa phương tiện %s đến vị trí của bạn'):format(plate))
end

RegisterCommand('vpersistdebug', function(source)
    if not isAdmin(source) then
        return
    end

    debugEnabled = not debugEnabled
    notify(source, 'info', 'Vehicle Persist Debug: ' .. (debugEnabled and 'ON' or 'OFF'))
end, true)

RegisterCommand('timxe', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then
        return
    end

    local input = normalizePlate(table.concat(args, ' '))

    if not input then
        showOwnedVehiclesMenu(source, xPlayer.identifier, false)
        return
    end

    locateOwnedVehicle(source, input, not isAdmin(source))
end, false)

RegisterCommand('atimxe', function(source, args)
    if not isAdmin(source) then
        return
    end

    local plate = normalizePlate(table.concat(args, ' '))

    if not plate then
        notify(source, 'error', 'Sử dụng: /atimxe [biển số]')
        return
    end

    locateOwnedVehicle(source, plate, false)
end, false)

RegisterCommand('agetcar', function(source, args)
    if not isAdmin(source) then
        return
    end

    local input = table.concat(args, ' ')

    if input == '' then
        notify(source, 'error', 'Sử dụng: /agetcar [biển số hoặc Player ID]')
        return
    end

    local targetPlayerId = tonumber(input)

    if targetPlayerId then
        local targetPlayer = ESX.GetPlayerFromId(targetPlayerId)

        if not targetPlayer then
            notify(source, 'error', 'Người chơi không hợp lệ')
            return
        end

        showOwnedVehiclesMenu(source, targetPlayer.identifier, true, targetPlayerId)
        return
    end

    local plate = normalizePlate(input)

    if not plate then
        notify(source, 'error', 'Biển số không hợp lệ')
        return
    end

    bringOwnedVehicle(source, plate)
end, false)

RegisterCommand('vpersistclear', function(source, args)
    if not isAdmin(source) then
        return
    end

    if args[1] ~= 'confirm' then
        notify(source, 'warning', 'Xác nhận bằng: /vpersistclear confirm')
        return
    end

    if not initialized then
        notify(source, 'error', 'Vehicle Persist chưa tải xong; hãy thử lại sau ít giây')
        return
    end

    if clearingStates then
        notify(source, 'warning', 'Vehicle Persist đang xóa trạng thái; hãy chờ hoàn tất')
        return
    end

    clearingStates = true

    while flushing or next(inFlightWrites) or next(deleteInProgress) or lifecycleWriteCount > 0 do
        Wait(0)
    end

    local recoverySet = {}

    for _, data in pairs(trackedVehicles) do
        if data.isOwned and type(data.plate) == 'string' then
            recoverySet[data.plate] = true
        end
    end

    local transitionSnapshots = {}

    for plate, transition in pairs(garageTransitions) do
        if type(plate) == 'string' then
            recoverySet[plate] = true
        end

        transitionSnapshots[#transitionSnapshots + 1] =
        {
            key = transition.key,
            data = transition.pending
        }
    end

    local recoveryPlates = {}

    for plate in pairs(recoverySet) do
        recoveryPlates[#recoveryPlates + 1] = plate
    end

    local clearQueries = {}

    clearQueries[#clearQueries + 1] =
    {
        query = ([[
            UPDATE `owned_vehicles` v
            INNER JOIN `%s` p ON p.`plate` = v.`plate`
            SET v.`stored` = 0
            WHERE p.`is_owned` = 1
                AND v.`stored` = 1
                AND COALESCE(v.`isTowedOut`, 0) = 0
        ]]):format(STATE_TABLE),
        values = {}
    }

    clearQueries[#clearQueries + 1] =
    {
        query = ('DELETE FROM `%s`'):format(STATE_TABLE),
        values = {}
    }
    local clearedOk, cleared = pcall(MySQL.transaction.await, clearQueries)

    if not clearedOk or cleared == false then
        clearingStates = false
        notify(source, 'error', 'Không thể xóa vehicle persistence state; transaction đã được hủy')
        return
    end

    persistenceEpoch = persistenceEpoch + 1

    local count = 0

    for key, data in pairs(trackedVehicles) do
        deleteManagedEntityForKey(data.entity or 0, key)
        deleteTrackedTrailer(data)

        trackedVehicles[key] = nil
        count = count + 1
    end

    for _, transition in ipairs(transitionSnapshots) do
        if transition.key then
            deleteManagedEntityForKey(transition.data and transition.data.entity or 0, transition.key)
            deleteTrackedTrailer(transition.data)
        end
    end

    ownedKeysByPlate = {}
    vehicleLifecycle = {}
    garageTransitions = {}
    garageSpawnLeases = {}
    vehicleRecordCache = {}
    impoundedEntities = {}
    recentVehicleAccess = {}
    dirtyVehicles = {}
    dirtyQueue = {}
    dirtyQueued = {}
    dirtyQueueHead = 1
    deleteTokens = {}
    deleteInProgress = {}
    inFlightWrites = {}
    reconcileCursor = nil
    respawnCursor = nil
    clearingStates = false
    notify(source, 'success', ('Đã xóa %s vehicle persistence state(s); %s xe sở hữu đã được đưa về Garage'):format(count, #recoveryPlates))
end, true)

RegisterNetEvent('vehicle_persist:server:locateVehicleByPlate', function(plate)
    local normalizedPlate = normalizePlate(plate)

    if normalizedPlate then
        locateOwnedVehicle(source, normalizedPlate, not isAdmin(source))
    end
end)

RegisterNetEvent('vehicle_persist:server:bringVehicleByPlate', function(plate)
    local normalizedPlate = normalizePlate(plate)

    if normalizedPlate then
        bringOwnedVehicle(source, normalizedPlate)
    end
end)
