local requestTimes = {}
local REQUEST_COOLDOWN = 400
local PLAYER_DISTANCE = 5.0
local VEHICLE_DISTANCE = 7.0

local function notify(playerId, message)
    if not InjuryServer.PlayerExists(playerId) then
        return
    end

    TriggerClientEvent('lv_notify:client:notify', playerId,
    {
        title = 'Người Bị Thương',
        message = message,
        type = 'error',
    })
end

local function consumeRequest(playerId)
    local now = GetGameTimer()
    local previous = requestTimes[playerId]

    if previous and now - previous < REQUEST_COOLDOWN then
        return false
    end

    requestTimes[playerId] = now
    return true
end

local function validatePlayers(requesterId, targetId)
    targetId = tonumber(targetId)

    if not targetId or targetId % 1 ~= 0 or targetId == requesterId then
        return nil
    end

    if not ESX.GetPlayerFromId(requesterId) or not ESX.GetPlayerFromId(targetId) then
        return nil
    end

    if not InjuryServer.IsPlayerReady(requesterId) or not InjuryServer.IsPlayerReady(targetId) then
        return nil
    end

    if InjuryServer.GetPlayerStatus(requesterId) ~= 0 or InjuryServer.GetPlayerStatus(targetId) == 0 then
        return nil
    end

    if not InjuryServer.ArePlayersNear(requesterId, targetId, PLAYER_DISTANCE) then
        return nil
    end

    local requesterPed = GetPlayerPed(requesterId)
    local targetPed = GetPlayerPed(targetId)

    if requesterPed == 0 or targetPed == 0 then
        return nil
    end

    return targetId, requesterPed, targetPed
end

local function resolveVehicle(networkId, routingBucket)
    networkId = tonumber(networkId)

    if not networkId or networkId % 1 ~= 0 or networkId <= 0 then
        return nil
    end

    local vehicle = NetworkGetEntityFromNetworkId(networkId)

    if vehicle == 0
        or not DoesEntityExist(vehicle)
        or GetEntityType(vehicle) ~= 2
        or GetEntityRoutingBucket(vehicle) ~= routingBucket then
        return nil
    end

    return vehicle
end

local function isNearVehicle(ped, vehicle)
    return #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= VEHICLE_DISTANCE
end

RegisterNetEvent('Injury:server:PutInVehicle', function(targetId, vehicleNetworkId, seatIndex)
    local requesterId = source

    if not consumeRequest(requesterId) then
        return
    end

    local validTarget, requesterPed, targetPed = validatePlayers(requesterId, targetId)

    if not validTarget then
        notify(requesterId, 'Người chơi, khoảng cách hoặc trạng thái không hợp lệ')
        return
    end

    if GetVehiclePedIsIn(requesterPed, false) ~= 0 or GetVehiclePedIsIn(targetPed, false) ~= 0 then
        notify(requesterId, 'Một trong hai người đang ở trên phương tiện')
        return
    end

    local routingBucket = GetPlayerRoutingBucket(requesterId)
    local vehicle = resolveVehicle(vehicleNetworkId, routingBucket)

    if not vehicle or not isNearVehicle(requesterPed, vehicle) or not isNearVehicle(targetPed, vehicle) then
        notify(requesterId, 'Phương tiện không hợp lệ hoặc ở quá xa')
        return
    end

    seatIndex = tonumber(seatIndex)

    if not seatIndex or seatIndex % 1 ~= 0 then
        return
    end

    local maximumPassengers = 7

    if type(GetVehicleMaxNumberOfPassengers) == 'function' then
        local ok, nativeMaxPassengers = pcall(GetVehicleMaxNumberOfPassengers, vehicle)
        if ok and type(nativeMaxPassengers) == 'number' and nativeMaxPassengers > 0 then
            maximumPassengers = nativeMaxPassengers
        end
    end

    if seatIndex < 0 or seatIndex >= maximumPassengers then
        notify(requesterId, 'Ghế hành khách không hợp lệ')
        return
    end

    local seatOk, occupant = pcall(GetPedInVehicleSeat, vehicle, seatIndex)

    if not seatOk or occupant ~= 0 then
        notify(requesterId, 'Ghế này hiện không còn trống')
        return
    end

    if type(InjuryCarryDragStopPlayer) == 'function' then
        InjuryCarryDragStopPlayer(requesterId)
        InjuryCarryDragStopPlayer(validTarget)
    end

    TriggerClientEvent('Injury:client:PutInVehicle', validTarget, tonumber(vehicleNetworkId), seatIndex)
end)

RegisterNetEvent('Injury:server:PullOutVehicle', function(targetId)
    local requesterId = source

    if not consumeRequest(requesterId) then
        return
    end

    local validTarget, requesterPed, targetPed = validatePlayers(requesterId, targetId)

    if not validTarget then
        notify(requesterId, 'Người chơi, khoảng cách hoặc trạng thái không hợp lệ')
        return
    end

    if GetVehiclePedIsIn(requesterPed, false) ~= 0 then
        notify(requesterId, 'Bạn phải ra khỏi phương tiện để đưa người bị thương xuống')
        return
    end

    local vehicle = GetVehiclePedIsIn(targetPed, false)

    if vehicle == 0
        or not DoesEntityExist(vehicle)
        or GetEntityType(vehicle) ~= 2
        or GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(requesterId)
        or not isNearVehicle(requesterPed, vehicle) then
        notify(requesterId, 'Người chơi không ở trong phương tiện hợp lệ gần bạn')
        return
    end

    if type(InjuryCarryDragStopPlayer) == 'function' then
        InjuryCarryDragStopPlayer(requesterId)
        InjuryCarryDragStopPlayer(validTarget)
    end

    TriggerClientEvent('Injury:client:PullOutVehicle', validTarget)
end)

AddEventHandler('playerDropped', function()
    requestTimes[source] = nil
end)
