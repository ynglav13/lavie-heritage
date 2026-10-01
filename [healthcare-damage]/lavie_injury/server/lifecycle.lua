local function loadMedicalPlayer(playerId, xPlayer)
    playerId = tonumber(playerId)
    xPlayer = xPlayer or (playerId and ESX.GetPlayerFromId(playerId))

    if not playerId or not xPlayer then
        return
    end

    InjuryServer.LoadPlayer(playerId, xPlayer)
    DamageServer.LoadPlayer(playerId, xPlayer)
end

local function releaseMedicalPlayer(playerId)
    InjuryServer.ReleasePlayer(playerId)
    DamageServer.ReleasePlayer(playerId)
end

AddEventHandler('esx:playerLoaded', loadMedicalPlayer)

AddEventHandler('playerDropped', function()
    releaseMedicalPlayer(source)
end)

AddEventHandler('esx:playerDropped', function(playerId)
    releaseMedicalPlayer(playerId)
end)

CreateThread(function()
    Wait(0)

    for _, playerId in ipairs(GetPlayers()) do
        loadMedicalPlayer(tonumber(playerId))
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        DamageServer.FlushAll()
    end
end)
