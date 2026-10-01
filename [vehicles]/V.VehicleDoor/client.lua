RegisterCommand('vehdoor', function(source, args, rawCommand)
    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        TriggerEvent('custom-chat:addMessage', "{FFFFFF}Bạn {FF6347}không ở trên phương tiện{FFFFFF} để có thể sử dụng lệnh này")
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    local doorArg = tonumber(args[1])

    if not doorArg or doorArg < 1 then
        TriggerEvent('custom-chat:addMessage', "{FF6347}Sử Dụng:{FFFFFF} /vehdoor [1-6]")
        return
    end

    local doorIndex = doorArg - 1
    local vehicleNetId = VehToNet(vehicle)
    local isOpening

    if GetVehicleDoorAngleRatio(vehicle, doorIndex) > 0.0 then
        SetVehicleDoorShut(vehicle, doorIndex, false)

        isOpening = false
    else
        SetVehicleDoorOpen(vehicle, doorIndex, false, false)

        isOpening = true
    end

    TriggerServerEvent('vehdoor:sync', vehicleNetId, doorIndex, isOpening)
end, false)

RegisterNetEvent('vehdoor:sync')
AddEventHandler('vehdoor:sync', function(vehicleNetId, doorIndex, isOpening, originalPlayerServerId)
    if originalPlayerServerId ~= GetPlayerServerId(PlayerId()) then
        local vehicle = NetToVeh(vehicleNetId)

        if DoesEntityExist(vehicle) then
            if isOpening then
                SetVehicleDoorOpen(vehicle, doorIndex, false, false)
            else
                SetVehicleDoorShut(vehicle, doorIndex, false)
            end
        end
    end
end)
