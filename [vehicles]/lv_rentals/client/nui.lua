local function closeUi()
    SetNuiFocus(false, false)
    SendNUIMessage(
    {
        action = 'close'
    })
end

local function awaitServerCallback(name, ...)
    local ok, response = pcall(lib.callback.await, name, false, ...)
    
    if ok then
        return response or
        {
            ok = false,
            message = Config.Text.invalidRequest
        }
    end

    return
    {
        ok = false,
        message = ('Không Thể Xử Lý Yêu Cầu: %s'):format(tostring(response))
    }
end

local function notify(message, notifyType)
    TriggerEvent('lv_notify:client:notify',
    {
        title = 'Thuê Phương Tiện',
        message = message,
        type = notifyType or 'info',
        duration = 4200
    })
end

CreateThread(function()
    Wait(500)

    closeUi()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    
    SetNuiFocus(false, false)
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    
    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('rentVehicle', function(data, cb)
    local response = awaitServerCallback('lv_rentals:server:rentVehicle', data.stationId, data.vehicleId, data.hours)
    
    if response and response.ok then
        closeUi()
        
        notify(response.message, 'success')
        notify(Config.Text.rentalWarning, 'warning')
        
        TriggerEvent('lv_rentals:client:syncRentalVehicle', response.netId or 0, response.plate, response.expiresAt, response.spawn, response.model)
        
       
        CreateThread(function()
            local ped = PlayerPedId()
            local vehicle = 0
            local rentPlate = Rental.trim(response.plate):upper()
            local deadline = GetGameTimer() + 25000 

            while GetGameTimer() < deadline do
                if response.netId and response.netId ~= 0 then
                    if NetworkDoesEntityExistWithNetworkId(response.netId) then
                        local ok, result = pcall(NetworkGetEntityFromNetworkId, response.netId)

                        if ok and result and result ~= 0 and DoesEntityExist(result) then
                            vehicle = result
                            pcall(SetVehicleNumberPlateText, vehicle, rentPlate)
                        end
                    end
                end

                if vehicle == 0 and response.spawn then
                    local targetCoords = vector3(
                        tonumber(response.spawn.x) or 0.0,
                        tonumber(response.spawn.y) or 0.0,
                        tonumber(response.spawn.z) or 0.0
                    )

                    for _, veh in ipairs(GetGamePool('CVehicle')) do
                        if DoesEntityExist(veh) then
                            local okPlate, plate = pcall(GetVehicleNumberPlateText, veh)
                            if okPlate and plate and Rental.trim(plate):upper() == rentPlate then
                                vehicle = veh
                                break
                            end
                        end
                    end

                    if vehicle == 0 then
                        local modelHash = response.model and joaat(response.model) or nil
                        for _, veh in ipairs(GetGamePool('CVehicle')) do
                            if DoesEntityExist(veh) and modelHash and GetEntityModel(veh) == modelHash then
                                local dist = #(GetEntityCoords(veh) - targetCoords)
                                if dist <= 12.0 then 
                                    vehicle = veh
                                    pcall(SetVehicleNumberPlateText, vehicle, rentPlate)
                                    break
                                end
                            end
                        end
                    end
                end

                if vehicle ~= 0 and DoesEntityExist(vehicle) then
                    local controlTimeout = GetGameTimer() + 2000
                    while DoesEntityExist(vehicle) and not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < controlTimeout do
                        NetworkRequestControlOfEntity(vehicle)
                        Wait(50)
                    end

        
                    if DoesEntityExist(vehicle) then
                        pcall(SetPedIntoVehicle, ped, vehicle, -1)
                        Wait(300)
                        if GetVehiclePedIsIn(ped, false) ~= vehicle then
                            local warpAttempt = 0
                            while DoesEntityExist(vehicle) and GetVehiclePedIsIn(ped, false) ~= vehicle and warpAttempt < 8 do
                                TaskWarpPedIntoVehicle(ped, vehicle, -1)
                                Wait(250)
                                
                                warpAttempt = warpAttempt + 1
                            end
                        end
                    end

                    break
                end

                Wait(200)
            end
        end)
    end

    cb(response or
    {
        ok = false
    })
end)

RegisterNUICallback('notify', function(data, cb)
    notify(data.message or Config.Text.invalidRequest, data.type or 'info')
    
    cb(
    {
        ok = true
    })
end)

RegisterNUICallback('getAdminData', function(_, cb)
    cb(awaitServerCallback('lv_rentals:server:adminData'))
end)

RegisterNUICallback('saveStation', function(data, cb)
    cb(awaitServerCallback('lv_rentals:server:saveStation', data))
end)

RegisterNUICallback('deleteStation', function(data, cb)
    cb(awaitServerCallback('lv_rentals:server:deleteStation', data.id))
end)

RegisterNUICallback('saveSpawn', function(data, cb)
    cb(awaitServerCallback('lv_rentals:server:saveSpawn', data))
end)

RegisterNUICallback('deleteSpawn', function(data, cb)
    cb(awaitServerCallback('lv_rentals:server:deleteSpawn', data.id))
end)

RegisterNUICallback('saveVehicle', function(data, cb)
    cb(awaitServerCallback('lv_rentals:server:saveVehicle', data))
end)

RegisterNUICallback('deleteVehicle', function(data, cb)
    cb(awaitServerCallback('lv_rentals:server:deleteVehicle', data.id))
end)

RegisterNUICallback('usePlayerCoords', function(_, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    
    cb({
        x = Rental.round(coords.x * 100) / 100,
        y = Rental.round(coords.y * 100) / 100,
        z = Rental.round(coords.z * 100) / 100,
        w = Rental.round(GetEntityHeading(ped) * 100) / 100
    })
end)

RegisterCommand(Config.AdminCommand, function()
    local allowed = lib.callback.await('lv_rentals:server:isAdmin', false)
    
    if not allowed then
        notify(Config.Text.noPermission, 'error')
        return
    end

    TriggerEvent('lv_rentals:client:openAdmin')
end, false)
