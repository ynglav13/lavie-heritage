local seatSelectionOpen = false
local vehicleOptionNames = {'put_in_injured_nui'}
local playerOptionNames = {'injury_carry', 'injury_drag', 'injury_helpup', 'injury_damages'}

local function isDownedState(state)
    return type(state) == 'table' and state.Status == true
end

local function isTargetDowned(serverId)
    if not serverId then
        return false
    end

    local state = Player(serverId).state

    return isDownedState(state.Helpup) or isDownedState(state.Injured) or isDownedState(state.Dead)
end

local function getClosestValidTarget()
    local carryTarget = exports['lavie_injury']:GetCarryDragTarget()
    if carryTarget then
        return carryTarget
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local closestId
    local closestDistance

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local serverId = GetPlayerServerId(player)
            local ped = GetPlayerPed(player)

            if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) and isTargetDowned(serverId) then
                local distance = #(playerCoords - GetEntityCoords(ped))

                if distance <= 5.0 and (not closestDistance or distance < closestDistance) then
                    closestId = serverId
                    closestDistance = distance
                end
            end
        end
    end

    return closestId
end

local function notifyError(message)
    lib.notify(
    {
        type = 'error',
        description = message,
    })
end

function CloseInjurySeatSelection(keepFocus)
    if not seatSelectionOpen then
        return
    end

    seatSelectionOpen = false
    if not keepFocus then
        SetNuiFocus(false, false)
    end

    SendNUIMessage({action = 'closeSeatSelection'})
end

local function openSeatSelection(vehicle, targetId)
    if type(CloseDamageReport) == 'function' then
        CloseDamageReport(true)
    end

    local model = GetEntityModel(vehicle)
    local totalSeats = GetVehicleModelNumberOfSeats(model)
    local maxPassengers = totalSeats > 1 and (totalSeats - 1) or GetVehicleMaxNumberOfPassengers(vehicle)
    if maxPassengers < 1 then maxPassengers = 1 end
    local seats = {}

    for seat = 0, maxPassengers - 1 do
        seats[tostring(seat)] = IsVehicleSeatFree(vehicle, seat) and true or false
    end

    if maxPassengers <= 0 then
        return notifyError('Phương tiện này không có ghế hành khách phù hợp')
    end

    local vehicleNetworkId = NetworkGetNetworkIdFromEntity(vehicle)

    if vehicleNetworkId == 0 then
        return notifyError('Không thể đồng bộ phương tiện này')
    end

    seatSelectionOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage(
    {
        action = 'openSeatSelection',
        targetId = targetId,
        vehNet = vehicleNetworkId,
        maxPassengers = maxPassengers,
        seats = seats,
        isDragging = exports['lavie_injury']:IsCarryDragActive(),
    })
end

CreateThread(function()
    local vehicleOptions =
    {
        {
            name = 'put_in_injured_nui',
            icon = 'fa-solid fa-truck-medical',
            label = 'Đưa Người Bị Thương Lên Phương Tiện',
            canInteract = function()
                return exports['lavie_injury']:IsCarryDragActive() or getClosestValidTarget() ~= nil
            end,
            onSelect = function(data)
                local targetId = getClosestValidTarget()

                if not targetId then
                    return notifyError('Không tìm thấy người bị thương ở gần')
                end

                openSeatSelection(data.entity, targetId)
            end,
        }
    }

    for index = -1, 14 do
        local seat = index
        local optionName = 'pull_out_injured_' .. seat
        local seatLabel = seat == -1 and 'Ghế Lái' or ('Ghế ' .. seat)

        vehicleOptionNames[#vehicleOptionNames + 1] = optionName
        vehicleOptions[#vehicleOptions + 1] =
        {
            name = optionName,
            icon = 'fa-solid fa-person-arrow-down-to-line',
            label = 'Đưa người bị thương xuống (' .. seatLabel .. ')',
            canInteract = function(vehicle)
                if seat ~= -1 and seat >= GetVehicleMaxNumberOfPassengers(vehicle) then
                    return false
                end

                local ped = GetPedInVehicleSeat(vehicle, seat)

                if ped == 0 or not IsPedAPlayer(ped) then
                    return false
                end

                return isTargetDowned(GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped)))
            end,
            onSelect = function(data)
                local ped = GetPedInVehicleSeat(data.entity, seat)

                if ped == 0 or not IsPedAPlayer(ped) then
                    return
                end

                local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))

                if isTargetDowned(serverId) then
                    TriggerNetEvent('Injury:server:PullOutVehicle', serverId)
                end
            end,
        }
    end

    exports.ox_target:addGlobalVehicle(vehicleOptions)
    exports.ox_target:addGlobalPlayer(
    {
        {
            name = 'injury_carry',
            icon = 'fas fa-people-carry-box',
            label = 'Vác Người Bị Thương',
            canInteract = function(entity, distance)
                if distance > 3.0 or IsPedInAnyVehicle(PlayerPedId(), false) then
                    return false
                end

                local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))

                return isTargetDowned(serverId) and not exports['lavie_injury']:IsCarryDragActive()
            end,
            onSelect = function(data)
                local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(data.entity))

                ExecuteCommand('carry ' .. serverId)
            end,
        },
        {
            name = 'injury_drag',
            icon = 'fa-solid fa-person-walking-luggage',
            label = 'Kéo Người Bị Thương',
            canInteract = function(entity, distance)
                if distance > 3.0 or IsPedInAnyVehicle(PlayerPedId(), false) then
                    return false
                end

                local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))

                return isTargetDowned(serverId) and not exports['lavie_injury']:IsCarryDragActive()
            end,
            onSelect = function(data)
                local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(data.entity))

                ExecuteCommand('drag ' .. serverId)
            end,
        },
        {
            name = 'injury_helpup',
            icon = 'fa-solid fa-hand-holding-hand',
            label = 'Kéo Dậy',
            canInteract = function(entity, distance)
                if distance > 3.0 then
                    return false
                end

                local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
                local state = Player(serverId).state

                return isDownedState(state.Helpup) and not isDownedState(state.Injured) and not isDownedState(state.Dead)
            end,
            onSelect = function(data)
                local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(data.entity))

                ExecuteCommand('helpup ' .. serverId)
            end,
        },
        {
            name = 'injury_damages',
            icon = 'fa-solid fa-notes-medical',
            label = 'Kiểm tra thương tích',
            canInteract = function(entity, distance)
                if distance > 3.0 then
                    return false
                end

                return isTargetDowned(GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity)))
            end,
            onSelect = function(data)
                local serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(data.entity))

                ExecuteCommand('damages ' .. serverId)
            end,
        }
    })
end)

RegisterNetEvent('Injury:client:PutInVehicle', function(vehicleNetworkId, seat)
    if not IsPlayerInjuryDowned() then
        return
    end

    vehicleNetworkId = tonumber(vehicleNetworkId)
    seat = tonumber(seat)

    if not vehicleNetworkId or not seat or seat < 0 or not NetworkDoesNetworkIdExist(vehicleNetworkId) then
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetworkId)

    if vehicle == 0 or not DoesEntityExist(vehicle) or not IsVehicleSeatFree(vehicle, seat) then
        return
    end

    if type(StopInjuryCarryDrag) == 'function' then
        StopInjuryCarryDrag(true, true)
    end

    local ped = PlayerPedId()

    ClearPedTasksImmediately(ped)
    SetPedIntoVehicle(ped, vehicle, seat)
end)

RegisterNetEvent('Injury:client:PullOutVehicle', function()
    if not IsPlayerInjuryDowned() then
        return
    end

    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    local coords = GetOffsetFromEntityInWorldCoords(vehicle, 1.5, 0.0, 0.0)

    ClearPedTasksImmediately(ped)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    EffectUpdate()
end)

RegisterNUICallback('selectSeat', function(data, callback)
    callback('ok')
    CloseInjurySeatSelection()

    local targetId = tonumber(data.targetId)
    local vehicleNetworkId = tonumber(data.vehNet)
    local seat = tonumber(data.seatIndex)

    if not targetId or not vehicleNetworkId or not seat or seat < 0 then
        return
    end

    if not NetworkDoesNetworkIdExist(vehicleNetworkId) then
        return notifyError('Phương tiện không còn tồn tại')
    end

    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetworkId)
    local model = (vehicle ~= 0 and DoesEntityExist(vehicle)) and GetEntityModel(vehicle) or 0
    local totalSeats = model ~= 0 and GetVehicleModelNumberOfSeats(model) or 0
    local maximumPassengers = totalSeats > 1 and (totalSeats - 1) or (vehicle ~= 0 and GetVehicleMaxNumberOfPassengers(vehicle) or 7)
    if maximumPassengers < 1 then maximumPassengers = 7 end

    if vehicle == 0 or not DoesEntityExist(vehicle) or seat >= maximumPassengers then
        return notifyError('Ghế hành khách không hợp lệ')
    end

    if not IsVehicleSeatFree(vehicle, seat) then
        return notifyError('Ghế hành khách này vừa có người ngồi')
    end

    if data.isDragging and type(StopInjuryCarryDrag) == 'function' then
        StopInjuryCarryDrag(true, true)
    end

    TriggerNetEvent('Injury:server:PutInVehicle', targetId, vehicleNetworkId, seat)
end)

RegisterNUICallback('closeUI', function(_, callback)
    callback('ok')
    CloseInjurySeatSelection()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    CloseInjurySeatSelection()

    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:removeGlobalVehicle(vehicleOptionNames)
        exports.ox_target:removeGlobalPlayer(playerOptionNames)
    end
end)
