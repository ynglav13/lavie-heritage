local ESX = exports['es_extended']:getSharedObject()

local Stations = {}
local ActiveByPlate = {}
local ActiveByIdentifier = {}
local OpenSessions = {}
local ExpiryWarnings = {}
local LockedSpawns = {}
local PendingRentals = {}
local ClientDeleteConfirmations = {}

local function asBool(value)
    if value == nil then return true end
    return value == true or value == 1 or value == '1' or value == 'true'
end

local function safeEntityExists(entity)
    if not entity or entity == 0 then
        return false
    end

    local ok, exists = pcall(DoesEntityExist, entity)
    return ok and exists == true
end

local function safeEntityCoords(entity)
    if not safeEntityExists(entity) then
        return nil
    end

    local ok, coords = pcall(GetEntityCoords, entity)

    if ok then
        return coords
    end
end

local function safeEntityHeading(entity)
    if not safeEntityExists(entity) then
        return nil
    end

    local ok, heading = pcall(GetEntityHeading, entity)

    if ok then
        return heading
    end
end

local function safeNetworkEntity(netId)
    netId = tonumber(netId) or 0

    if netId <= 0 then
        return nil
    end

    local ok, entity = pcall(NetworkGetEntityFromNetworkId, netId)

    if ok and entity and entity ~= 0 and safeEntityExists(entity) then
        return entity
    end
end

local function rentalDebug(message, data)
    local suffix = ''

    if data then
        suffix = (' | %s'):format(json.encode(data))
    end

    print(('[lv_rentals] %s%s'):format(message, suffix))
end

local function safeVehiclePlate(entity)
    if not safeEntityExists(entity) then
        return nil, 'entity_not_found'
    end

    local ok, plate = pcall(GetVehicleNumberPlateText, entity)

    if not ok then
        return nil, ('native_error: %s'):format(tostring(plate))
    end

    if type(plate) ~= 'string' then
        return nil, ('invalid_type: %s'):format(type(plate))
    end

    plate = Rental.trim(plate:gsub('%z', '')):upper()

    if plate == '' then
        return nil, 'empty_plate'
    end

    return plate, 'ok'
end

local function safeDeleteEntity(entity)
    if not safeEntityExists(entity) then
        return true
    end

    local retries = Config.DeleteVehicleRetries or 8
    local delay = Config.DeleteVehicleRetryDelayMs or 350

    for _ = 1, retries do
        if not safeEntityExists(entity) then
            return true
        end

        pcall(SetEntityAsMissionEntity, entity, true, true)
        pcall(DeleteVehicle, entity)

        if safeEntityExists(entity) then
            pcall(DeleteEntity, entity)
        end

        if not safeEntityExists(entity) then
            return true
        end

        Wait(delay)
    end
    return not safeEntityExists(entity)
end

local function spawnRentalVehicleServer(row, spawn)
    local plate = Rental.trim(row.plate):upper()
    local coords = vec3(spawn.x, spawn.y, spawn.z)
    local heading = spawn.w or 0.0

    -- set plate khi spawn
    local okSpawn, netId = pcall(ESX.OneSync.SpawnVehicle, row.model, coords, heading,
    {
        plate = plate
    })

    if not okSpawn or not netId or netId == 0 then
        rentalDebug('ESX.OneSync.SpawnVehicle failed',
        {
            model = row.model,
            reason = tostring(netId)
        })
        return false, 0, 'spawn_failed'
    end

    local entity = NetworkGetEntityFromNetworkId(netId)

    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false, 0, 'entity_not_found'
    end

    local plateDeadline = GetGameTimer() + (tonumber(Config.ServerPlateVerifyTimeoutMs) or 1000)
    local actualPlate, plateReadReason
    local plateVerified = false
    local plateSetRequested = false

    while GetGameTimer() < plateDeadline do
        local okSet = pcall(SetVehicleNumberPlateText, entity, plate)
        plateSetRequested = plateSetRequested or okSet
        actualPlate, plateReadReason = safeVehiclePlate(entity)

        if actualPlate == plate then
            plateVerified = true
            break
        end


        if plateReadReason and plateReadReason:sub(1, 12) == 'native_error' then
            break
        end

        Wait(100)
    end

    if not plateVerified and Config.PlateVerificationDebug then
        rentalDebug('server plate verification deferred',
        {
            model = row.model,
            expected = plate,
            actual = actualPlate,
            readReason = plateReadReason,
            setRequested = plateSetRequested,
            netId = netId
        })
    end

    pcall(function()
        Entity(entity).state.lvRental = true
        Entity(entity).state.lvRentalOwner = row.identifier
        Entity(entity).state.lvRentalExpires = tonumber(row.expires_at) or 0
    end)
    pcall(SetVehicleDoorsLocked, entity, 1)

    return true, netId, 'server'
end

local function vecToData(vec)
    return
    {
        x = vec.x,
        y = vec.y,
        z = vec.z,
        w = vec.w
    }
end

local function encodeCoords(coords)
    return json.encode(
    {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = coords.w or 0.0
    })
end

local function dataToVec3(data)
    if type(data) == 'string' then
        data = json.decode(data)
    end
    return vec3(tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0)
end

local function dataToVec4(data, heading)
    if type(data) == 'string' then
        data = json.decode(data)
    end
    return vec4(tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0, tonumber(data.w or heading) or 0.0)
end

local function publicStation(station)
    local vehicles = {}

    for i = 1, #station.vehicles do
        local vehicle = station.vehicles[i]

        if vehicle.enabled then
            vehicles[#vehicles + 1] = vehicle
        end
    end
    return
    {
        id = station.id,
        code = station.code,
        label = station.label,
        coords =
        {
            x = station.coords.x,
            y = station.coords.y,
            z = station.coords.z,
            w = station.heading
        },
        heading = station.heading,
        enabled = station.enabled,
        blip = station.blip,
        maxHours = station.maxHours,
        deposit = station.deposit,
        vehicles = vehicles
    }
end

local function broadcastStations()
    local payload = {}

    for _, station in pairs(Stations) do
        payload[#payload + 1] = publicStation(station)
    end

    TriggerClientEvent('lv_rentals:client:setStations', -1, payload)
end

local function broadcastRentalPlates(target)
    local plates = {}

    for plate, row in pairs(ActiveByPlate) do
        plates[#plates + 1] =
        {
            plate = plate,
            owner = row.identifier
        }
    end

    TriggerClientEvent('lv_rentals:client:setRentalPlates', target or -1, plates)
end

local function loadStations()
    Stations = {}

    local rows = MySQL.query.await('SELECT * FROM lv_rental_stations ORDER BY id ASC') or {}
    local spawns = MySQL.query.await('SELECT * FROM lv_rental_spawns ORDER BY id ASC') or {}
    local vehicles = MySQL.query.await('SELECT * FROM lv_rental_vehicles ORDER BY id ASC') or {}

    for i = 1, #rows do
        local row = rows[i]

        Stations[row.id] =
        {
            id = row.id,
            code = row.code,
            label = row.label,
            coords = dataToVec3(row.coords),
            heading = tonumber(row.heading) or 0.0,
            enabled = asBool(row.enabled),
            blip = asBool(row.blip),
            maxHours = tonumber(row.max_hours) or Config.DefaultMaxHours,
            deposit = tonumber(row.deposit) or 0,
            spawns = {},
            vehicles = {}
        }
    end

    for i = 1, #spawns do
        local spawn = spawns[i]

        if Stations[spawn.station_id] then
            Stations[spawn.station_id].spawns[#Stations[spawn.station_id].spawns + 1] =
            {
                id = spawn.id,
                coords = dataToVec4(spawn.coords, spawn.heading)
            }
        end
    end

    for i = 1, #vehicles do
        local vehicle = vehicles[i]

        if Stations[vehicle.station_id] then
            Stations[vehicle.station_id].vehicles[#Stations[vehicle.station_id].vehicles + 1] =
            {
                id = vehicle.id,
                model = vehicle.model,
                label = vehicle.label,
                pricePerHour = tonumber(vehicle.price_per_hour) or 0,
                deposit = tonumber(vehicle.deposit) or 0,
                image = vehicle.image or '',
                enabled = asBool(vehicle.enabled)
            }
        end
    end
end

local function seedDefaults()
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM lv_rental_stations') or 0

    if count > 0 then
        return
    end

    for i = 1, #Config.DefaultStations do
        local station = Config.DefaultStations[i]
        local stationId = MySQL.insert.await('INSERT INTO lv_rental_stations (code, label, coords, heading, enabled, blip, max_hours, deposit) VALUES (?, ?, ?, ?, 1, ?, ?, ?)',
        {
            station.code,
            station.label,
            json.encode(vecToData(station.coords)),
            station.heading or 0.0,
            station.blip and 1 or 0,
            station.maxHours or Config.DefaultMaxHours,
            station.deposit or 0
        })

        for _, spawn in ipairs(station.spawnPoints or {}) do
            MySQL.insert.await('INSERT INTO lv_rental_spawns (station_id, coords, heading) VALUES (?, ?, ?)',
            {
                stationId,
                json.encode(vecToData(spawn)),
                spawn.w or 0.0
            })
        end

        for _, vehicle in ipairs(station.vehicles or {}) do
            MySQL.insert.await('INSERT INTO lv_rental_vehicles (station_id, model, label, price_per_hour, deposit, image, enabled) VALUES (?, ?, ?, ?, ?, ?, 1)',
            {
                stationId,
                vehicle.model,
                vehicle.label,
                vehicle.pricePerHour,
                vehicle.deposit,
                vehicle.image or ''
            })
        end
    end
end

local function normalizeEpoch(value)
    value = tonumber(value) or 0

    if value > 100000000000 then
        value = math.floor(value / 1000)
    end
    return value
end

local cacheActiveRow

local function loadActive()
    ActiveByPlate = {}
    ActiveByIdentifier = {}

    local rows = MySQL.query.await('SELECT * FROM lv_rental_active') or {}

    for i = 1, #rows do
        cacheActiveRow(rows[i])
    end
end

cacheActiveRow = function(row, source)
    if not row then
        return nil
    end

    if source then
        row.source = source
    end

    row.plate = Rental.trim(row.plate):upper()
    row.rented_at = normalizeEpoch(row.rented_at)
    row.expires_at = normalizeEpoch(row.expires_at)
    row.hours = tonumber(row.hours) or 0
    row.price_paid = tonumber(row.price_paid) or 0
    row.deposit_paid = tonumber(row.deposit_paid) or 0
    row.net_id = tonumber(row.net_id) or 0

    if row.expires_at <= 0 and row.rented_at > 0 and row.hours > 0 then
        row.expires_at = row.rented_at + (row.hours * 3600)
    end

    ActiveByPlate[row.plate] = row
    ActiveByIdentifier[row.identifier] = row
    return row
end

local function clearCachedRental(identifier)
    local cached = identifier and ActiveByIdentifier[identifier] or nil

    if cached and cached.plate then
        ActiveByPlate[cached.plate] = nil
    end

    if identifier then
        ActiveByIdentifier[identifier] = nil
    end
end

local function getActiveRentalForPlayer(xPlayer, source)
    if not xPlayer then
        return nil
    end

    local row = MySQL.single.await('SELECT * FROM lv_rental_active WHERE identifier = ? ORDER BY rented_at DESC LIMIT 1',
    {
        xPlayer.identifier
    })

    if row then
        return cacheActiveRow(row, source)
    end

    clearCachedRental(xPlayer.identifier)
end

local function findVehicle(station, vehicleId)
    vehicleId = tonumber(vehicleId)

    for i = 1, #station.vehicles do
        if station.vehicles[i].id == vehicleId then
            return station.vehicles[i]
        end
    end
end

local function spawnLockKey(coords)
    if not coords then return nil end
    return ('%.1f:%.1f:%.1f'):format(coords.x, coords.y, coords.z)
end

local function lockSpawn(coords)
    if not coords then return nil end
    local key = spawnLockKey(coords)
    LockedSpawns[key] = os.time()
    return key
end

local function unlockSpawn(key)
    if key then LockedSpawns[key] = nil end
end

local function chooseSpawn(station)
    if not station.spawns or #station.spawns == 0 then
        return nil
    end

    local clearSpawns = {}
    local allVehicles = GetAllVehicles()

    for i = 1, #station.spawns do
        local spawn = station.spawns[i]
        local spawnCoords = spawn.coords
        local isClear = true

        -- Skip spawn points that are currently locked by another rental in progress
        local sKey = spawnLockKey(spawnCoords)
        if sKey and LockedSpawns[sKey] then
            isClear = false
        end

        if isClear and spawnCoords then
            local sVec = vector3(spawnCoords.x, spawnCoords.y, spawnCoords.z)
            for j = 1, #allVehicles do
                local veh = allVehicles[j]
                if DoesEntityExist(veh) then
                    local vCoords = GetEntityCoords(veh)
                    if #(vCoords - sVec) < 3.5 then
                        isClear = false
                        break
                    end
                end
            end
        end

        if isClear then
            clearSpawns[#clearSpawns + 1] = spawn
        end
    end

    if #clearSpawns > 0 then
        return clearSpawns[math.random(1, #clearSpawns)].coords
    end

    return nil
end

local function rowSpawnCoords(row)
    if row.spawn_coords and row.spawn_coords ~= '' then
        return dataToVec4(row.spawn_coords, 0.0)
    end

    local station = Stations[tonumber(row.station_id)]
    return station and chooseSpawn(station) or nil
end

local function formatRemaining(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)

    local hours = math.floor(seconds / 3600)
    local minutes = math.ceil((seconds % 3600) / 60)

    if hours > 0 and minutes > 0 then
        return ('%s giờ %s phút'):format(hours, minutes)
    end

    if hours > 0 then
        return ('%s giờ'):format(hours)
    end

    return ('%s phút'):format(math.max(1, minutes))
end

local function generatePlate()
    for _ = 1, 30 do
        local plate = ('%s%04d'):format(Config.PlatePrefix, math.random(0, 9999))
        local activeExists = MySQL.scalar.await('SELECT plate FROM lv_rental_active WHERE plate = ?',
        {
            plate
        })
        local ownedExists = MySQL.scalar.await('SELECT plate FROM owned_vehicles WHERE plate = ?',
        {
            plate
        })

        if not activeExists and not ownedExists then
            return plate
        end
    end
    return ('%s%04d'):format(Config.PlatePrefix, math.random(0, 9999))
end

local function getIcName(source, xPlayer)
    if xPlayer then
        local okName, name = pcall(function()
            return xPlayer.getName and xPlayer.getName()
        end)

        if okName and name and name ~= '' then
            return name
        end

        local firstName = xPlayer.get and (xPlayer.get('firstName') or xPlayer.get('firstname')) or nil
        local lastName = xPlayer.get and (xPlayer.get('lastName') or xPlayer.get('lastname')) or nil

        if (not firstName or firstName == '') and xPlayer.variables then
            firstName = xPlayer.variables.firstName or xPlayer.variables.firstname
            lastName = xPlayer.variables.lastName or xPlayer.variables.lastname
        end

        local fullName = Rental.trim(('%s %s'):format(firstName or '', lastName or ''))

        if fullName ~= '' then
            return fullName
        end
    end
    return GetPlayerName(source) or ('Player %s'):format(source)
end

local function getRentalKeySlots(source, plate)
    plate = Rental.trim(plate):upper()

    if GetResourceState('ox_inventory') ~= 'started' then
        return nil, 'ox_inventory_not_started'
    end

    local ok, items = pcall(function()
        return exports.ox_inventory:Search(source, 'slots', 'vehicle_key')
    end)

    if not ok or not items then
        return nil, tostring(items or 'inventory_search_failed')
    end

    local slots = {}

    for _, item in pairs(items) do
        local itemPlate = item.metadata and item.metadata.plate and Rental.trim(item.metadata.plate):upper()

        if itemPlate == plate then
            slots[#slots + 1] = item.slot
        end
    end

    return slots
end

local function hasRentalKey(source, plate)
    local slots = getRentalKeySlots(source, plate)
    return slots and #slots > 0
end

local function giveRentalKey(source, plate)
    plate = Rental.trim(plate):upper()

    if plate == '' then
        return false, 'invalid_plate'
    end

    if hasRentalKey(source, plate) then
        return true
    end

    if GetResourceState('ox_inventory') == 'started' then
        local okCarry, canCarry = pcall(function()
            return exports.ox_inventory:CanCarryItem(source, 'vehicle_key', 1)
        end)

        if okCarry and canCarry == false then
            return false, 'inventory_full'
        end
    end

    local okGive, giveResult = pcall(function()
        return exports['vehicleCore']:GiveVehicleKey(source, plate)
    end)

    if not okGive then
        return false, tostring(giveResult)
    end

    local deadline = GetGameTimer() + 2500

    while GetGameTimer() < deadline do
        if hasRentalKey(source, plate) then
            return true
        end

        Wait(100)
    end

    return false, 'key_verify_failed'
end

local function removeRentalKey(source, plate)
    plate = Rental.trim(plate):upper()

    pcall(function()
        exports['vehicleCore']:RemoveVehicleKey(source, plate)
    end)

    local slots = getRentalKeySlots(source, plate)

    if not slots then
        return false
    end

    for i = 1, #slots do
        pcall(function()
            exports.ox_inventory:RemoveItem(source, 'vehicle_key', 1, nil, slots[i])
        end)
    end

    local deadline = GetGameTimer() + 1500

    while GetGameTimer() < deadline do
        local remaining = getRentalKeySlots(source, plate)

        if not remaining or #remaining == 0 then
            return true
        end

        for i = 1, #remaining do
            pcall(function()
                exports.ox_inventory:RemoveItem(source, 'vehicle_key', 1, nil, remaining[i])
            end)
        end

        Wait(100)
    end

    return not hasRentalKey(source, plate)
end

local function removeStaleRentalKeys(source, identifier)
    if GetResourceState('ox_inventory') ~= 'started' then
        return
    end

    local ok, items = pcall(function()
        return exports.ox_inventory:Search(source, 'slots', 'vehicle_key')
    end)

    if not ok or not items then
        return
    end

    for _, item in pairs(items) do
        local plate = item.metadata and item.metadata.plate and Rental.trim(item.metadata.plate):upper() or ''

        if plate:sub(1, #Config.PlatePrefix) == Config.PlatePrefix then
            local active = ActiveByPlate[plate]

            if not active or active.identifier ~= identifier then
                pcall(function()
                    exports.ox_inventory:RemoveItem(source, 'vehicle_key', 1, nil, item.slot)
                end)
            end
        end
    end
end



local function findRentalEntity(row, preferredNetId)
    local preferred = safeNetworkEntity(preferredNetId)

    if preferred then
        return preferred
    end

    preferred = safeNetworkEntity(row and row.delete_net_id)

    if preferred then
        return preferred
    end

    preferred = safeNetworkEntity(row and row.net_id)

    if preferred then
        return preferred
    end

    local plate = row and Rental.trim(row.plate):upper() or ''

    if plate == '' then
        return nil
    end

    local allVehicles = GetAllVehicles()

    for i = 1, #allVehicles do
        local entity = allVehicles[i]

        if safeVehiclePlate(entity) == plate then
            return entity
        end
    end
end

RegisterNetEvent('lv_rentals:server:clientVehicleDeleted', function(plate)
    plate = Rental.trim(plate):upper()

    if ClientDeleteConfirmations[plate] ~= nil then
        ClientDeleteConfirmations[plate] = true
    end
end)

local function requestClientDeleteRental(row)
    local src = row.source

    if not src or GetPlayerPing(src) <= 0 then
        return false
    end

    local plate = Rental.trim(row.plate):upper()
    ClientDeleteConfirmations[plate] = false

    TriggerClientEvent('lv_rentals:client:forceExitRental', src, plate, true)

    local deadline = GetGameTimer() + (Config.ExpiredClearTimeoutMs or 45000)

    while ClientDeleteConfirmations[plate] ~= true and GetGameTimer() < deadline do
        Wait(250)
    end

    local confirmed = ClientDeleteConfirmations[plate] == true
    ClientDeleteConfirmations[plate] = nil

    return confirmed
end

local function deleteRentalVehicle(row, reason)
    local plate = Rental.trim(row.plate):upper()

    if reason == 'expired' then
        if requestClientDeleteRental(row) then
            return true
        end

        Wait(Config.ExpireForceExitDelayMs or 2500)
    elseif reason == 'disconnect' or reason == 'cleanup' then
        requestClientDeleteRental(row)
    end

    local entity = findRentalEntity(row)

    if not entity then
        return true
    end

    local deadline = GetGameTimer() + (Config.ExpiredClearTimeoutMs or 45000)

    while safeEntityExists(entity) and GetGameTimer() < deadline do
        local occupants = false
        local okSeats, maxPassengers = pcall(GetVehicleMaxNumberOfPassengers, entity)
        maxPassengers = okSeats and (tonumber(maxPassengers) or 0) or 0

        for seat = -1, maxPassengers - 1 do
            local ped = GetPedInVehicleSeat(entity, seat)

            if ped and ped ~= 0 then
                occupants = true
                break
            end
        end

        local speed = 0.0
        local okSpeed, currentSpeed = pcall(GetEntitySpeed, entity)

        if okSpeed then
            speed = currentSpeed or 0.0
        end

        if not occupants and speed <= (Config.ExpiredDeleteMaxSpeed or 1.5) then
            break
        end

        pcall(SetVehicleEngineOn, entity, false, true, true)
        pcall(SetVehicleHandbrake, entity, true)

        Wait(500)
    end

    if not safeEntityExists(entity) then
        return true
    end

    local okDelete = safeDeleteEntity(entity)

    if not okDelete then
        rentalDebug('failed to delete rental vehicle',
        {
            plate = plate,
            reason = reason,
            netId = row.net_id
        })
    end

    return okDelete
end

local function deleteRental(row, reason, refund)
    local src = row.source
    row.plate = Rental.trim(row.plate):upper()

    if not deleteRentalVehicle(row, reason) then
        return false
    end

    if src then
        removeRentalKey(src, row.plate)
    end

    if src and GetPlayerPing(src) > 0 then
        if refund and refund > 0 then
            local xPlayer = ESX.GetPlayerFromId(src)

            if xPlayer then
                xPlayer.addAccountMoney(Config.CurrencyAccount, refund)
            end
        end
    end

    MySQL.query.await('DELETE FROM lv_rental_active WHERE plate = ?',
    {
        row.plate
    })

    ActiveByPlate[row.plate] = nil
    ActiveByIdentifier[row.identifier] = nil

    broadcastRentalPlates()

    for i = 1, #(Config.ExpiryWarningMinutes or {}) do
        ExpiryWarnings[('%s:%s'):format(row.plate, Config.ExpiryWarningMinutes[i])] = nil
    end

    local logPayload =
    {
        identifier = row.identifier,
        playerName = row.player_name,
        plate = row.plate,
        stationId = row.station_id,
        model = row.model,
        amount = refund or 0
    }

    Rental.log(reason, src, logPayload)
    return true
end

local function isPlayerNearCoords(source, coords, maxDistance)
    local ped = GetPlayerPed(source)

    if not ped or ped == 0 then
        return false
    end

    local pedCoords = safeEntityCoords(ped)
    return pedCoords and #(pedCoords - vec3(coords.x, coords.y, coords.z)) <= maxDistance
end

local function coordsFromClient(data)
    if type(data) ~= 'table' then
        return nil
    end

    if type(data.player) == 'table' then
        data = data.player
    end

    local x = tonumber(data.x)
    local y = tonumber(data.y)
    local z = tonumber(data.z)

    if not x or not y or not z then
        return nil
    end
    return vec3(x, y, z)
end

local function vehicleCoordsFromClient(data)
    if type(data) ~= 'table' or type(data.vehicle) ~= 'table' then
        return nil
    end

    local x = tonumber(data.vehicle.x)
    local y = tonumber(data.vehicle.y)
    local z = tonumber(data.vehicle.z)

    if not x or not y or not z then
        return nil
    end
    return vec3(x, y, z)
end

local function isCoordsNearStation(coords, station, maxDistance)
    if not coords or not station or not station.coords then
        return false
    end
    return #(coords - vec3(station.coords.x, station.coords.y, station.coords.z)) <= maxDistance
end

local function isNearReturnStation(source, row, clientCoords)
    local maxDistance = Config.ReturnStationDistance or 18.0
    local station = Stations[tonumber(row.station_id)]
    local serverNear = station and isPlayerNearCoords(source, station.coords, maxDistance)
    local clientNear = isCoordsNearStation(clientCoords, station, maxDistance)

    if serverNear or clientNear then
        return true
    end

    for _, otherStation in pairs(Stations) do
        if otherStation.enabled and isCoordsNearStation(clientCoords, otherStation, maxDistance) then
            return true
        end
    end
    return false
end

local function hydrateSource(row)
    local players = ESX.GetExtendedPlayers()

    for i = 1, #players do
        if players[i].identifier == row.identifier then
            row.source = players[i].source
            return row
        end
    end
    return row
end

local function processExpiredRentals(notifyOnline)
    local now = os.time()
    local expired = MySQL.query.await('SELECT * FROM lv_rental_active WHERE expires_at <= ?',
    {
        now
    }) or {}

    for i = 1, #expired do
        local row = hydrateSource(expired[i])
        local deleted = deleteRental(row, 'expired', 0)

        if deleted and notifyOnline and row.source then
            Rental.notify(row.source, Config.Text.expiredAutoReturn:format(row.plate), 'warning')
        end
    end
end

local function clearStoredRentals(reason)
    local rows = MySQL.query.await('SELECT * FROM lv_rental_active') or {}

    for i = 1, #rows do
        deleteRental(hydrateSource(rows[i]), reason or 'cleanup', 0)
    end
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lv_rental_stations` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `code` VARCHAR(64) NOT NULL,
            `label` VARCHAR(100) NOT NULL,
            `coords` LONGTEXT NOT NULL,
            `heading` FLOAT NOT NULL DEFAULT 0,
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `blip` TINYINT(1) NOT NULL DEFAULT 1,
            `max_hours` INT NOT NULL DEFAULT 6,
            `deposit` INT NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_code` (`code`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lv_rental_spawns` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `station_id` INT UNSIGNED NOT NULL,
            `coords` LONGTEXT NOT NULL,
            `heading` FLOAT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_station_id` (`station_id`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lv_rental_vehicles` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `station_id` INT UNSIGNED NOT NULL,
            `model` VARCHAR(60) NOT NULL,
            `label` VARCHAR(100) NOT NULL,
            `price_per_hour` INT NOT NULL DEFAULT 0,
            `deposit` INT NOT NULL DEFAULT 0,
            `image` VARCHAR(255) DEFAULT '',
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`),
            KEY `idx_station_id` (`station_id`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lv_rental_active` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(80) NOT NULL,
            `player_name` VARCHAR(100) NOT NULL,
            `station_id` INT UNSIGNED NOT NULL,
            `vehicle_id` INT UNSIGNED NOT NULL,
            `model` VARCHAR(60) NOT NULL,
            `plate` VARCHAR(12) NOT NULL,
            `net_id` INT DEFAULT NULL,
            `entity` INT DEFAULT NULL,
            `spawn_coords` LONGTEXT DEFAULT NULL,
            `hours` INT NOT NULL,
            `price_paid` INT NOT NULL,
            `deposit_paid` INT NOT NULL,
            `rented_at` INT NOT NULL,
            `expires_at` INT NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_plate` (`plate`),
            KEY `idx_identifier` (`identifier`),
            KEY `idx_expires_at` (`expires_at`)
        )
    ]])

    pcall(MySQL.query.await, 'ALTER TABLE `lv_rental_active` ADD COLUMN IF NOT EXISTS `net_id` INT DEFAULT NULL')
    pcall(MySQL.query.await, 'ALTER TABLE `lv_rental_active` ADD COLUMN IF NOT EXISTS `entity` INT DEFAULT NULL')
    pcall(MySQL.query.await, 'ALTER TABLE `lv_rental_active` ADD COLUMN IF NOT EXISTS `spawn_coords` LONGTEXT DEFAULT NULL')
    pcall(MySQL.query.await, 'ALTER TABLE `lv_rental_active` ADD COLUMN IF NOT EXISTS `price_paid` INT NOT NULL DEFAULT 0')
    pcall(MySQL.query.await, 'ALTER TABLE `lv_rental_active` ADD COLUMN IF NOT EXISTS `deposit_paid` INT NOT NULL DEFAULT 0')
    
    MySQL.query.await('DROP TABLE IF EXISTS `lv_rental_logs`')

    seedDefaults()

    loadStations()

    loadActive()



    broadcastStations()

    broadcastRentalPlates()
end)

AddEventHandler('playerDropped', function()
    local src = source

    OpenSessions[src] = nil
    PendingRentals[src] = nil

    local xPlayer = ESX.GetPlayerFromId(src)
    local row = xPlayer and getActiveRentalForPlayer(xPlayer, source) or nil

    if not row then
        for _, activeRow in pairs(ActiveByPlate) do
            if tonumber(activeRow.source) == tonumber(src) then
                row = activeRow
                break
            end
        end
    end

    if row then
        local remainingTime = (tonumber(row.expires_at) or 0) - os.time()

        if remainingTime > 0 then
            row.source = nil
            rentalDebug('player disconnected, keeping rental vehicle',
            {
                plate = row.plate,
                remaining = ('%d phut'):format(math.ceil(remainingTime / 60))
            })
        else
            row.source = src
            deleteRental(row, 'disconnect', 0)
        end
    end
end)

RegisterNetEvent('lv_rentals:server:openedStation', function(stationId)
    local src = source

    stationId = tonumber(stationId)

    local station = stationId and Stations[stationId]

    if not station or not station.enabled then
        return
    end

    -- Client can only open this through our NPC/nearest command, but keep a loose
    -- distance check when server coords are available.
    local near = isPlayerNearCoords(src, station.coords, 60.0)

    OpenSessions[src] =
    {
        stationId = stationId,
        expiresAt = os.time() + 90,
        near = near == true
    }
end)

AddEventHandler('esx:playerLoaded', function(source, xPlayer)
    TriggerClientEvent('lv_rentals:client:setIdentifier', source, xPlayer.identifier)

    removeStaleRentalKeys(source, xPlayer.identifier)

    local row = getActiveRentalForPlayer(xPlayer, source)

    if row then
        row.source = source

        if (tonumber(row.expires_at) or 0) <= os.time() then
            deleteRental(row, 'expired', 0)
        else
            local okKey, keyReason = giveRentalKey(source, row.plate)

            if not okKey then
                rentalDebug('failed to restore rental key on player load',
                {
                    source = source,
                    plate = row.plate,
                    reason = keyReason
                })
            end

            Rental.notify(source, Config.Text.activeRental:format(row.plate, formatRemaining((tonumber(row.expires_at) or os.time()) - os.time()), tonumber(row.deposit_paid) or 0), 'info')
        end
    end

    local payload = {}

    for _, station in pairs(Stations) do
        payload[#payload + 1] = publicStation(station)
    end

    TriggerClientEvent('lv_rentals:client:setStations', source, payload)

    broadcastRentalPlates(source)
end)

CreateThread(function()
    while true do
        Wait((Config.DeleteExpiredEveryMinutes or 5) * 60000)

        processExpiredRentals(true)
    end
end)

-- Cleanup stale spawn locks (safety net for server errors / edge cases)
CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for key, lockedAt in pairs(LockedSpawns) do
            if now - lockedAt > 30 then
                LockedSpawns[key] = nil
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        for src, _ in pairs(PendingRentals) do
            if GetPlayerPing(src) <= 0 then
                PendingRentals[src] = nil
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(60000)

        local now = os.time()

        for plate, row in pairs(ActiveByPlate) do
            local expiresAt = tonumber(row.expires_at) or 0
            local remaining = expiresAt - now

            if remaining > 0 then
                for i = 1, #(Config.ExpiryWarningMinutes or {}) do
                    local minutes = tonumber(Config.ExpiryWarningMinutes[i]) or 0
                    local key = ('%s:%s'):format(plate, minutes)

                    if minutes > 0 and remaining <= minutes * 60 and not ExpiryWarnings[key] then
                        local hydrated = hydrateSource(row)

                        if hydrated.source then
                            Rental.notify(hydrated.source, Config.Text.expiresSoon:format(plate, formatRemaining(remaining)), 'warning')
                        end

                        ExpiryWarnings[key] = true
                    end
                end
            end
        end
    end
end)

lib.callback.register('lv_rentals:server:getStations', function()
    local payload = {}
    
    for _, station in pairs(Stations) do
        payload[#payload + 1] = publicStation(station)
    end
    return payload
end)

lib.callback.register('lv_rentals:server:isRentalPlate', function(source, plate)
    plate = Rental.trim(plate):upper()

    if not Rental.isPlate(plate) then
        return false
    end

    return MySQL.scalar.await('SELECT plate FROM lv_rental_active WHERE plate = ?',
    {
        plate
    }) ~= nil
end)

lib.callback.register('lv_rentals:server:getRentalPlates', function()
    local plates = {}

    for plate, row in pairs(ActiveByPlate) do
        plates[#plates + 1] =
        {
            plate = plate,
            owner = row.identifier
        }
    end
    return plates
end)

lib.callback.register('lv_rentals:server:getIdentifier', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    return xPlayer and xPlayer.identifier or nil
end)

lib.callback.register('lv_rentals:server:rentVehicle', function(source, stationId, vehicleId, hours)
    if PendingRentals[source] then
        return
        {
            ok = false,
            message = 'Yeu cau thue xe dang duoc xu ly, vui long cho trong giay lat.'
        }
    end

    PendingRentals[source] = true

    local ok, response = pcall(function()
        local xPlayer = ESX.GetPlayerFromId(source)

        if not xPlayer then
            return
            {
                ok = false,
                message = 'Khong the tai du lieu nguoi choi'
            }
        end

        hours = tonumber(hours)
        if not hours or hours < 1 or hours ~= math.floor(hours) then
            return
            {
                ok = false,
                message = 'So gio thue khong hop le.'
            }
        end

        stationId = tonumber(stationId)

        local station = stationId and Stations[stationId]

        if not station then
            return
            {
                ok = false,
                message = 'Khong tim thay diem thue phuong tien'
            }
        end

        if not station.enabled then
            return
            {
                ok = false,
                message = Config.Text.stationDisabled
            }
        end

        local session = OpenSessions[source]
        local hasOpenSession = session
            and session.stationId == stationId
            and session.expiresAt >= os.time()

        if not hasOpenSession and not isPlayerNearCoords(source, station.coords, Config.RentDistance or 25.0) then
            return
            {
                ok = false,
                message = Config.Text.tooFar
            }
        end

        if getActiveRentalForPlayer(xPlayer, source) then
            return
            {
                ok = false,
                message = Config.Text.alreadyRenting
            }
        end

        local vehicle = findVehicle(station, vehicleId)

        if not vehicle or not vehicle.enabled then
            return
            {
                ok = false,
                message = Config.Text.vehicleUnavailable,
                debug =
                {
                    stationId = stationId,
                    vehicleId = vehicleId
                }
            }
        end

        hours = Rental.clamp(hours, Config.MinHours, math.min(station.maxHours, Config.HardMaxHours))

        local rentalPrice = Rental.round(vehicle.pricePerHour * hours)
        local deposit = Rental.round((station.deposit or 0) + (vehicle.deposit or 0))
        local total = rentalPrice + deposit

        if xPlayer.getAccount(Config.CurrencyAccount).money < total then
            return
            {
                ok = false,
                message = Config.Text.notEnoughMoney
            }
        end

        local spawn = chooseSpawn(station)

        if not spawn then
            return
            {
                ok = false,
                message = Config.Text.noSpawn
            }
        end

        local currentSpawnLockKey = lockSpawn(spawn)
        local plate = Rental.trim(generatePlate()):upper()
        local now = os.time()
        local playerName = getIcName(source, xPlayer)
        local row =
        {
            identifier = xPlayer.identifier,
            player_name = playerName,
            station_id = station.id,
            vehicle_id = vehicle.id,
            model = vehicle.model,
            plate = plate,
            net_id = 0,
            hours = hours,
            price_paid = rentalPrice,
            deposit_paid = deposit,
            rented_at = now,
            expires_at = now + (hours * 3600),
            spawn_coords = encodeCoords(spawn),
            source = source
        }

        local okCharge = pcall(function()
            xPlayer.removeAccountMoney(Config.CurrencyAccount, total)
        end)

        if not okCharge then
            unlockSpawn(currentSpawnLockKey)
            return
            {
                ok = false,
                message = Config.Text.notEnoughMoney
            }
        end

        local okSpawn, netId, spawnReason = spawnRentalVehicleServer(row, spawn)

        if not okSpawn then
            pcall(function() xPlayer.addAccountMoney(Config.CurrencyAccount, total) end)
            unlockSpawn(currentSpawnLockKey)
            rentalDebug('server spawn failed',
            {
                source = source,
                model = vehicle.model,
                plate = plate,
                reason = spawnReason
            })
            return
            {
                ok = false,
                message = Config.Text.spawnFailed
            }
        end

        row.net_id = tonumber(netId) or 0

        if row.net_id <= 0 then
            pcall(function() xPlayer.addAccountMoney(Config.CurrencyAccount, total) end)
            unlockSpawn(currentSpawnLockKey)
            return
            {
                ok = false,
                message = Config.Text.vehicleNetFailed
            }
        end

        local okInsert, insertResult = pcall(MySQL.insert.await, 'INSERT INTO lv_rental_active (identifier, player_name, station_id, vehicle_id, model, plate, net_id, entity, spawn_coords, hours, price_paid, deposit_paid, rented_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {
            xPlayer.identifier,
            playerName,
            station.id,
            vehicle.id,
            vehicle.model,
            plate,
            row.net_id,
            0,
            row.spawn_coords,
            hours,
            rentalPrice,
            deposit,
            now,
            now + (hours * 3600)
        })

        if not okInsert then
            pcall(function() xPlayer.addAccountMoney(Config.CurrencyAccount, total) end)
            safeDeleteEntity(findRentalEntity(row))
            unlockSpawn(currentSpawnLockKey)
            rentalDebug('rental db insert failed',
            {
                source = source,
                plate = plate,
                reason = tostring(insertResult)
            })
            return
            {
                ok = false,
                message = 'Rental database insert failed.'
            }
        end

        local okKey, keyReason = giveRentalKey(source, plate)

        if not okKey then
            pcall(function() xPlayer.addAccountMoney(Config.CurrencyAccount, total) end)
            MySQL.query.await('DELETE FROM lv_rental_active WHERE plate = ?',
            {
                plate
            })
            safeDeleteEntity(findRentalEntity(row))
            unlockSpawn(currentSpawnLockKey)
            rentalDebug('rental key give failed',
            {
                source = source,
                plate = plate,
                reason = keyReason
            })
            return
            {
                ok = false,
                message = 'Khong the phat chia khoa xe, giao dich da duoc huy.'
            }
        end

        unlockSpawn(currentSpawnLockKey)

        ActiveByPlate[plate] = row
        ActiveByIdentifier[xPlayer.identifier] = row

        broadcastRentalPlates()

        OpenSessions[source] = nil

        Rental.log('rent', source,
        {
            plate = plate,
            stationId = station.id,
            model = vehicle.model,
            playerName = playerName,
            amount = total,
            metadata =
            {
                hours = hours,
                rent = rentalPrice,
                deposit = deposit,
                spawnType = 'server',
                netId = row.net_id
            }
        })

        if GetResourceState('lv_tutorial') == 'started' then
            if exports.lv_tutorial:AdvanceStep(source, 1) then
                TriggerClientEvent('lv_notify:client:notify', source, {
                    title = 'Huong dan',
                    message = 'Ban da hoan thanh thue xe. Diem tiep theo: Tap hoa (mua dien thoai/sim).',
                    type = 'success',
                    duration = 5000
                })
            end
        end

        return
        {
            ok = true,
            message = Config.Text.rented,
            plate = plate,
            model = row.model,
            netId = row.net_id,
            spawn =
            {
                x = spawn.x,
                y = spawn.y,
                z = spawn.z
            },
            expiresAt = row.expires_at
        }
    end)

    PendingRentals[source] = nil

    if not ok then
        rentalDebug('rent callback crashed',
        {
            source = source,
            reason = tostring(response)
        })
        return
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    return response
end)
lib.callback.register('lv_rentals:server:returnVehicle', function(source, plate, clientNetId, clientCoordsData)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then
        return
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    plate = Rental.trim(plate):upper()

    if not Rental.isPlate(plate) then
        return
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    local row = ActiveByPlate[plate]

    if not row then
        local result = MySQL.single.await('SELECT * FROM lv_rental_active WHERE plate = ?',
        {
            plate
        })

        row = result and cacheActiveRow(result, source) or nil
    end

    if not row or row.identifier ~= xPlayer.identifier then
        return
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    local clientCoords = coordsFromClient(clientCoordsData)
    local clientVehicleCoords = vehicleCoordsFromClient(clientCoordsData)

    if not isNearReturnStation(source, row, clientCoords) then
        return
        {
            ok = false,
            message = Config.Text.tooFarReturn
        }
    end

    clientNetId = tonumber(clientNetId) or 0

    local entity = findRentalEntity(row, clientNetId)

    local ped = GetPlayerPed(source)
    local pedCoords = clientCoords or safeEntityCoords(ped)
    local entityCoords = entity and safeEntityCoords(entity) or clientVehicleCoords

    if not pedCoords or not entityCoords or #(pedCoords - entityCoords) > (Config.ReturnVehicleDistance or 8.0) then
        return
        {
            ok = false,
            message = Config.Text.tooFarVehicle
        }
    end

    if not entity then
        rentalDebug('return accepted using client vehicle coords',
        {
            source = source,
            plate = plate,
            netId = clientNetId
        })
    end

    row.source = source

    if clientNetId > 0 then
        row.delete_net_id = clientNetId
    end

    if not deleteRental(row, 'return', tonumber(row.deposit_paid) or 0) then
        return
        {
            ok = false,
            message = 'Khong the xoa xe thue an toan, vui long thu lai sau.'
        }
    end

    return
    {
        ok = true,
        message = Config.Text.returned:format(tonumber(row.deposit_paid) or 0)
    }
end)

RegisterCommand(Config.MemberCommand, function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    local row = xPlayer and getActiveRentalForPlayer(xPlayer, source) or nil

    if row then
        if (tonumber(row.expires_at) or 0) <= os.time() then
            row.source = source

            if deleteRental(row, 'expired', 0) then
                Rental.notify(source, Config.Text.expiredAutoReturn:format(row.plate), 'warning')
            end
            return
        end

        Rental.notify(source, Config.Text.activeRental:format(row.plate, formatRemaining((tonumber(row.expires_at) or os.time()) - os.time()), tonumber(row.deposit_paid) or 0), 'info')
        return
    end

    TriggerClientEvent('lv_rentals:client:openNearest', source)
end, false)

RegisterCommand(Config.StatusCommand, function(source)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then
        return
    end

    local row = getActiveRentalForPlayer(xPlayer, source)

    if not row then
        Rental.notify(source, Config.Text.noActiveRental, 'info')
        return
    end

    if (tonumber(row.expires_at) or 0) <= os.time() then
        row.source = source

        if deleteRental(row, 'expired', 0) then
            Rental.notify(source, Config.Text.expiredAutoReturn:format(row.plate), 'warning')
        end
        return
    end

    Rental.notify(source, Config.Text.activeRental:format(row.plate, formatRemaining((tonumber(row.expires_at) or os.time()) - os.time()), tonumber(row.deposit_paid) or 0), 'info')
end, false)

Rental.ReloadStations = function()
    loadStations()
    
    broadcastStations()
end

Rental.GetStations = function()
    return Stations
end
