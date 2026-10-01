local Stations = {}
local TargetZones = {}
local StationPeds = {}
local Blips = {}
local CurrentStation = nil
local RentalPlates = {}
local MyIdentifier = nil
local openRental

local function notify(message, notifyType)
    local nType = notifyType == 'inform' and 'info' or (notifyType or 'info')

    if GetResourceState('lv_notify') == 'started' then
        exports['lv_notify']:Notify(
        {
            title = 'Thuê Phương Tiện',
            message = message,
            type = nType,
            duration = 4200
        })
        return
    end

    TriggerEvent('lv_notify:client:notify',
    {
        title = 'Thuê Phương Tiện',
        message = message,
        type = nType,
        duration = 4200
    })
end

local function safeVehiclePlate(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return nil
    end

    local ok, plate = pcall(GetVehicleNumberPlateText, entity)
    
    if not ok or not plate then
        return nil
    end
    return Rental.trim(plate):upper()
end

local function setRentalPlate(plate, enabled)
    plate = Rental.trim(plate):upper()

    if plate == '' then
        return
    end
    RentalPlates[plate] = enabled and true or nil
end

local function findVehicleByPlate(plate)
    plate = Rental.trim(plate):upper()

    local current = GetVehiclePedIsIn(PlayerPedId(), false)

    if current ~= 0 and safeVehiclePlate(current) == plate then
        return current
    end

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if safeVehiclePlate(vehicle) == plate then
            return vehicle
        end
    end
end

local function findVehicleNearSpawn(spawn, model)
    if type(spawn) ~= 'table' then
        return nil
    end

    local targetCoords = vector3(tonumber(spawn.x) or 0.0, tonumber(spawn.y) or 0.0, tonumber(spawn.z) or 0.0)
    local modelHash = model and joaat(model) or nil
    local bestVehicle, bestDistance

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and (not modelHash or GetEntityModel(vehicle) == modelHash) then
            local coords = GetEntityCoords(vehicle)
            local distance = #(coords - targetCoords)

            if distance <= 12.0 and (not bestDistance or distance < bestDistance) then
                bestVehicle = vehicle
                bestDistance = distance
            end
        end
    end

    return bestVehicle
end

local function vehicleHasOccupants(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    local maxPassengers = GetVehicleMaxNumberOfPassengers(vehicle) or 0

    for seat = -1, maxPassengers - 1 do
        local occupant = GetPedInVehicleSeat(vehicle, seat)

        if occupant and occupant ~= 0 then
            return true
        end
    end
    return false
end

local function requestVehicleControl(vehicle, timeoutMs)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    if NetworkHasControlOfEntity(vehicle) then
        return true
    end

    NetworkRequestControlOfEntity(vehicle)

    local timeout = GetGameTimer() + (timeoutMs or 2500)

    while DoesEntityExist(vehicle) and not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(vehicle)

        Wait(50)
    end
    return DoesEntityExist(vehicle) and NetworkHasControlOfEntity(vehicle)
end

local function clearTargets()
    for _, zone in pairs(TargetZones) do
        exports.ox_target:removeZone(zone)
    end

    TargetZones = {}

    for _, actorId in pairs(StationPeds) do
        exports.legacyCore:DeleteActor(actorId)
    end

    StationPeds = {}

    for _, blip in pairs(Blips) do
        RemoveBlip(blip)
    end

    Blips = {}
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)

    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        return nil
    end

    RequestModel(hash)

    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(hash) do
        Wait(10)

        if GetGameTimer() > timeout then
            return nil
        end
    end
    return hash
end

local function createStationPed(station)
    if not Config.Npc.enabled then
        return nil
    end

    local coords = station.coords
    local heading = tonumber(station.heading or coords.w) or 0.0

    local actorId = exports.legacyCore:CreateActor({
        name = 'lv_rentals_station_' .. station.id,
        model = Config.Npc.model,
        coords = coords,
        heading = heading,
        scenario = (Config.Npc.scenario and Config.Npc.scenario ~= '') and Config.Npc.scenario or nil,
        renderDistance = Config.PointRenderDistance or 30.0,
        options = {
            {
                name = 'lv_rentals_open_station',
                icon = 'fa-solid fa-car-side',
                label = Config.Text.openRental,
                distance = Config.TargetDistance + 0.5,
                onSelect = function()
                    openRental(station.id)
                end
            }
        }
    })

    if actorId then
        StationPeds[#StationPeds + 1] = actorId
    end

    return actorId
end

local function createBlip(station)
    if station.blip == false or station.blip == 0 or station.blip == '0' or station.blip == 'false' then
        return
    end

    local coords = station.coords
    if not coords or not coords.x then
        return
    end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    SetBlipSprite(blip, tonumber(station.blipSprite) or 225)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, tonumber(station.blipColor) or 3)
    SetBlipAsShortRange(blip, false)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(station.label or Config.Text.openRental or 'Vehicle Rental')
    EndTextCommandSetBlipName(blip)

    Blips[#Blips + 1] = blip
end

openRental = function(stationId)
    local station

    for i = 1, #Stations do
        if Stations[i].id == stationId then
            station = Stations[i]
            break
        end
    end

    if not station then
        return
    end

    CurrentStation = station

    TriggerServerEvent('lv_rentals:server:openedStation', station.id)

    SetNuiFocus(true, true)

    SendNUIMessage(
    {
        action = 'openRental',
        station = station
    })
end

local function refreshTargets()
    clearTargets()

    for i = 1, #Stations do
        local station = Stations[i]

        if station.enabled then
            local ped = createStationPed(station)

            if not ped then
                local zone = exports.ox_target:addSphereZone(
                {
                    coords = vec3(station.coords.x, station.coords.y, station.coords.z),
                    radius = Config.TargetDistance,
                    debug = false,
                    options =
                    {
                        {
                            name = ('lv_rentals_station_%s'):format(station.id),
                            icon = 'fa-solid fa-car-side',
                            label = Config.Text.openRental,
                            distance = Config.TargetDistance,
                            onSelect = function()
                                openRental(station.id)
                            end
                        }
                    }
                })

                TargetZones[#TargetZones + 1] = zone
            end

            createBlip(station)
        end
    end
end

RegisterNetEvent('lv_rentals:client:setStations', function(stations)
    Stations = stations or {}
    
    refreshTargets()
end)

RegisterNetEvent('lv_rentals:client:setRentalPlates', function(plates)
    RentalPlates = {}
    
    for i = 1, #(plates or {}) do
        local entry = plates[i]

        if type(entry) == 'table' then
            local plate = Rental.trim(entry.plate):upper()

            if plate ~= '' then
                RentalPlates[plate] =
                {
                    owner = entry.owner
                }
            end
        else
            setRentalPlate(entry, true)
        end
    end
end)

RegisterNetEvent('lv_rentals:client:setIdentifier', function(identifier)
    MyIdentifier = identifier
end)

local function isMyRentalPlate(plate)
    plate = Rental.trim(plate):upper()

    local entry = RentalPlates[plate]

    if not entry then
        return false
    end

    if entry == true then
        return true
    end

    return entry.owner ~= nil and MyIdentifier ~= nil and entry.owner == MyIdentifier
end

RegisterNetEvent('lv_rentals:client:openNearest', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local bestStation, bestDistance

    for i = 1, #Stations do
        local station = Stations[i]
        local distance = #(coords - vector3(station.coords.x, station.coords.y, station.coords.z))
        
        if not bestDistance or distance < bestDistance then
            bestStation = station
            bestDistance = distance
        end
    end

    if bestStation and bestDistance <= 8.0 then
        openRental(bestStation.id)
    else
        notify('Bạn không ở gần điểm thuê phương tiện', 'error')
    end
end)

RegisterNetEvent('lv_rentals:client:openAdmin', function()
    SetNuiFocus(true, true)
    
    SendNUIMessage(
    {
        action = 'openAdmin',
        loading = true
    })

    local data = lib.callback.await('lv_rentals:server:adminData', false)
    
    SendNUIMessage(
    {
        action = 'adminData',
        data = data
    })
end)

RegisterNetEvent('lv_rentals:client:forceExitRental', function(plate, shouldDelete)
    plate = Rental.trim(plate):upper()

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 and safeVehiclePlate(vehicle) == plate then
        CreateThread(function()
            local currentVehicle = vehicle
            local slowDeadline = GetGameTimer() + 8000

            while DoesEntityExist(currentVehicle)
                and safeVehiclePlate(currentVehicle) == plate
                and GetEntitySpeed(currentVehicle) > (Config.ExpiredExitMaxSpeed or 2.2)
                and GetGameTimer() < slowDeadline do
                if requestVehicleControl(currentVehicle, 300) then
                    local speed = GetEntitySpeed(currentVehicle)

                    pcall(SetVehicleEngineOn, currentVehicle, false, true, true)
                    pcall(SetVehicleForwardSpeed, currentVehicle, speed * (Config.ExpiredSlowdownStep or 0.92))
                    pcall(SetVehicleMaxSpeed, currentVehicle, math.max(Config.ExpiredExitMaxSpeed or 2.2, speed * 0.95))
                end

                Wait(250)
            end

            if DoesEntityExist(currentVehicle) and requestVehicleControl(currentVehicle, 300) then
                pcall(SetVehicleHandbrake, currentVehicle, true)
            end

            local exitDeadline = GetGameTimer() + (Config.ExpiredMaxExitWaitMs or 30000)

            while GetVehiclePedIsIn(PlayerPedId(), false) ~= 0
                and safeVehiclePlate(GetVehiclePedIsIn(PlayerPedId(), false)) == plate
                and GetGameTimer() < exitDeadline do
                TaskLeaveVehicle(PlayerPedId(), GetVehiclePedIsIn(PlayerPedId(), false), 0)

                Wait(Config.ExpiredExitRetryMs or 2000)
            end
        end)
    end

    if shouldDelete then
        CreateThread(function()
            local target = findVehicleByPlate(plate)

            if not target or target == 0 or not DoesEntityExist(target) then
                return
            end

            local deadline = GetGameTimer() + (Config.ExpiredClearTimeoutMs or 45000)

            while DoesEntityExist(target) and GetGameTimer() < deadline do
                requestVehicleControl(target, 400)

                if NetworkHasControlOfEntity(target) then
                    local speed = GetEntitySpeed(target)

                    pcall(SetVehicleEngineOn, target, false, true, true)

                    if speed > (Config.ExpiredExitMaxSpeed or 2.2) then
                        pcall(SetVehicleForwardSpeed, target, speed * (Config.ExpiredSlowdownStep or 0.92))
                        pcall(SetVehicleMaxSpeed, target, math.max(Config.ExpiredExitMaxSpeed or 2.2, speed * 0.95))
                    else
                        pcall(SetVehicleHandbrake, target, true)
                    end
                end

                if not vehicleHasOccupants(target) and GetEntitySpeed(target) <= (Config.ExpiredDeleteMaxSpeed or 1.5) then
                    break
                end

                Wait(250)
            end

            if DoesEntityExist(target) then
                local deleteDeadline = GetGameTimer() + 6000

                while DoesEntityExist(target) and GetGameTimer() < deleteDeadline do
                    requestVehicleControl(target, 750)

                    pcall(SetEntityAsMissionEntity, target, true, true)

                    if not vehicleHasOccupants(target) or GetGameTimer() >= deadline then
                        pcall(DeleteVehicle, target)

                        if DoesEntityExist(target) then
                            pcall(DeleteEntity, target)
                        end
                    end

                    if not DoesEntityExist(target) then
                        break
                    end

                    Wait(250)
                end
            end

            if not DoesEntityExist(target) then
                setRentalPlate(plate, false)
                TriggerServerEvent('lv_rentals:server:clientVehicleDeleted', plate)
            end

        end)
    end
end)

RegisterNetEvent('lv_rentals:client:rentalWaypoint', function(netId, spawn)
    local entity = 0

    if netId and netId ~= 0 and NetworkDoesEntityExistWithNetworkId(netId) then
        local ok, result = pcall(NetworkGetEntityFromNetworkId, netId)

        if ok then
            entity = result or 0
        end
    end

    if entity ~= 0 and DoesEntityExist(entity) then
        local coords = GetEntityCoords(entity)

        SetNewWaypoint(coords.x, coords.y)
        return
    end

    if spawn then
        SetNewWaypoint(spawn.x, spawn.y)
    end
end)

RegisterNetEvent('lv_rentals:client:syncRentalVehicle', function(netId, plate, expiresAt, spawn, model)
    local cleanPlate = Rental.trim(plate):upper()

    setRentalPlate(cleanPlate, true)

    local timeout = GetGameTimer() + 20000
    local entity = 0

    while GetGameTimer() < timeout do
        entity = 0

        if netId and netId ~= 0 and NetworkDoesEntityExistWithNetworkId(netId) then
            local ok, result = pcall(NetworkGetEntityFromNetworkId, netId)

            if ok and result and result ~= 0 and DoesEntityExist(result) then
                entity = result
            end
        end

        if entity == 0 and (not netId or netId == 0) then
            entity = findVehicleNearSpawn(spawn, model) or 0
        end

        if entity ~= 0 and DoesEntityExist(entity) then
            if requestVehicleControl(entity, 500) then
                pcall(SetVehicleNumberPlateText, entity, cleanPlate)

                pcall(function()
                    Entity(entity).state.lvRental = true
                    Entity(entity).state.lvRentalExpires = expiresAt or 0
                end)

                Wait(250)

                if safeVehiclePlate(entity) == cleanPlate then
                    return
                end
            end
        end

        Wait(250)
    end

    if entity ~= 0 and DoesEntityExist(entity) then
        pcall(SetVehicleNumberPlateText, entity, cleanPlate)
    end
end)

lib.callback.register('lv_rentals:client:spawnRentalVehicle', function(data)
    data = data or {}

    local spawn = data.spawn or {}
    local plate = Rental.trim(data.plate):upper()
    local hash = loadModel(data.model)

    if not hash or plate == '' then
        return
        {
            ok = false,
            reason = 'invalid_model_or_plate'
        }
    end

    local x = tonumber(spawn.x) or 0.0
    local y = tonumber(spawn.y) or 0.0
    local z = tonumber(spawn.z) or 0.0
    local w = tonumber(spawn.w) or 0.0

    RequestCollisionAtCoord(x, y, z)

    local vehicle = CreateVehicle(hash, x, y, z, w, true, true)

    SetModelAsNoLongerNeeded(hash)

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
        {
            ok = false,
            reason = 'create_vehicle_failed'
        }
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetEntityHeading(vehicle, w)

    local plateDeadline = GetGameTimer() + 4000

    while DoesEntityExist(vehicle) and GetGameTimer() < plateDeadline do
        SetVehicleNumberPlateText(vehicle, plate)

        if safeVehiclePlate(vehicle) == plate then
            break
        end

        Wait(100)
    end

    if safeVehiclePlate(vehicle) ~= plate then
        DeleteVehicle(vehicle)

        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end

        return
        {
            ok = false,
            reason = 'plate_verify_failed'
        }
    end

    local netId = 0
    local netDeadline = GetGameTimer() + 5000

    NetworkRegisterEntityAsNetworked(vehicle)

    while DoesEntityExist(vehicle) and GetGameTimer() < netDeadline do
        netId = NetworkGetNetworkIdFromEntity(vehicle)

        if netId and netId ~= 0 then
            SetNetworkIdCanMigrate(netId, true)
            SetNetworkIdExistsOnAllMachines(netId, true)
            break
        end

        Wait(100)
    end

    if not netId or netId == 0 then
        DeleteVehicle(vehicle)

        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end

        return
        {
            ok = false,
            reason = 'netid_timeout'
        }
    end

    pcall(function()
        Entity(vehicle).state.lvRental = true
        Entity(vehicle).state.lvRentalExpires = data.expiresAt or 0
    end)

    local coords = GetEntityCoords(vehicle)

    return
    {
        ok = true,
        netId = netId,
        plate = safeVehiclePlate(vehicle),
        coords =
        {
            x = coords.x,
            y = coords.y,
            z = coords.z
        }
    }
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    clearTargets()
end)

CreateThread(function()
    local stations = lib.callback.await('lv_rentals:server:getStations', false)

    Stations = stations or {}

    refreshTargets()

    MyIdentifier = lib.callback.await('lv_rentals:server:getIdentifier', false)

    TriggerEvent('lv_rentals:client:setRentalPlates', lib.callback.await('lv_rentals:server:getRentalPlates', false) or {})

    exports.ox_target:addGlobalVehicle(
    {
        {
            name = 'lv_rentals_return_vehicle',
            icon = 'fa-solid fa-rotate-left',
            label = 'Trả Phương Tiện Thuê',
            distance = 2.5,
            canInteract = function(entity)
                if not entity or entity == 0 or not DoesEntityExist(entity) then
                    return false
                end

                local okState, state = pcall(function()
                    return Entity(entity).state.lvRental
                end)

                local plate = safeVehiclePlate(entity)
                
                if not plate then
                    return false
                end

                local okOwner, owner = pcall(function()
                    return Entity(entity).state.lvRentalOwner
                end)

                if okState and state == true and okOwner and owner and MyIdentifier and owner == MyIdentifier then
                    return true
                end

                if isMyRentalPlate(plate) then
                    return true
                end

                return false
            end,
            onSelect = function(data)
                local entity = data.entity
                local plate = safeVehiclePlate(entity)

                if not plate then
                    notify(Config.Text.invalidRequest, 'error')
                    return
                end

                local netId = 0

                if entity and entity ~= 0 and DoesEntityExist(entity) then
                    local okNet, result = pcall(NetworkGetNetworkIdFromEntity, entity)

                    if okNet then
                        netId = result or 0
                    end
                end

                local playerCoords = GetEntityCoords(PlayerPedId())
                local vehicleCoords = GetEntityCoords(entity)
                local response = lib.callback.await('lv_rentals:server:returnVehicle', false, plate, netId,
                {
                    player =
                    {
                        x = playerCoords.x,
                        y = playerCoords.y,
                        z = playerCoords.z
                    },
                    vehicle =
                    {
                        x = vehicleCoords.x,
                        y = vehicleCoords.y,
                        z = vehicleCoords.z
                    }
                })

                if response.ok then
                    setRentalPlate(plate, false)
                end

                if response.ok and DoesEntityExist(entity) then
                    requestVehicleControl(entity, 1500)

                    pcall(SetEntityAsMissionEntity, entity, true, true)
                    pcall(DeleteVehicle, entity)

                    if DoesEntityExist(entity) then
                        pcall(DeleteEntity, entity)
                    end
                end
                
                notify(response.message or Config.Text.invalidRequest, response.ok and 'success' or 'error')
            end
        }
    })
end)
