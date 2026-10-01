local ESX = exports['es_extended']:getSharedObject()

local function getIdentifier(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    return xPlayer and xPlayer.identifier or nil
end

local function loadAnimsForPlayer(src, identifier)
    local result = MySQL.query.await('SELECT weapongroup, animkey FROM player_weapon_anims WHERE identifier = ?',
    {
        identifier
    })
    local anims = {}

    if result and #result > 0 then
        for _, row in ipairs(result) do
            anims[row.weapongroup] = row.animkey
        end
    end

    TriggerClientEvent('lavie_animdraw:client:loadAnims', src, anims)
end

RegisterNetEvent('lavie_animdraw:server:loadAnims', function()
    local src = source
    local identifier = getIdentifier(src)

    if identifier then
        loadAnimsForPlayer(src, identifier)
    end
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    if xPlayer and xPlayer.identifier then
        loadAnimsForPlayer(playerId, xPlayer.identifier)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    Wait(1000)

    local xPlayers = ESX.GetExtendedPlayers()

    for _, xPlayer in ipairs(xPlayers) do
        if xPlayer and xPlayer.identifier then
            loadAnimsForPlayer(xPlayer.source, xPlayer.identifier)
        end
    end
end)

RegisterNetEvent('lavie_animdraw:server:saveAnim', function(group, animKey)
    local src = source
    local identifier = getIdentifier(src)

    if not identifier then
        return
    end

    MySQL.insert.await('INSERT INTO player_weapon_anims (identifier, weapongroup, animkey) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE animkey = ?',
    {
        identifier,
        group,
        animKey,
        animKey
    })
end)

RegisterNetEvent('lavie_animdraw:server:clearAnims', function()
    local src = source
    local identifier = getIdentifier(src)

    if not identifier then
        return
    end

    MySQL.query.await('DELETE FROM player_weapon_anims WHERE identifier = ?',
    {
        identifier
    })
end)

AddStateBagChangeHandler('isPrime', nil, function(bagName, key, value, _reserved, replicated)
    if value == false then
        local playerId = string.match(bagName, '^player:(%d+)')

        if playerId then
            playerId = tonumber(playerId)

            local identifier = getIdentifier(playerId)

            if identifier then
                MySQL.query.await('DELETE FROM player_weapon_anims WHERE identifier = ?',
                {
                    identifier
                })

                TriggerClientEvent('lavie_animdraw:client:loadAnims', playerId, {})
            end
        end
    end
end)
