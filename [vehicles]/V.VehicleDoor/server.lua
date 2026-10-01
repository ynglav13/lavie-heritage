RegisterNetEvent('vehdoor:sync')
AddEventHandler('vehdoor:sync', function(vehicleNetId, doorIndex, isOpening)
    TriggerClientEvent('vehdoor:sync', -1, vehicleNetId, doorIndex, isOpening, source)
end)
